<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
This script installs Office
#>

[CmdletBinding()]
param( 
    [string]$TenantId
)

###################################################################################################
#
# PowerShell configurations
#

# NOTE: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.
#       This is necessary to ensure we capture errors inside the try-catch-finally block.
$ErrorActionPreference = "Stop"

# Hide any progress bars, due to downloads and installs of remote components.
$ProgressPreference = "SilentlyContinue"

# Ensure we set the working directory to that of the script.
Push-Location $PSScriptRoot

# Discard any collected errors from a previous execution.
$Error.Clear()

# Configure strict debugging.
Set-PSDebug -Strict

###################################################################################################
#
# Handle all errors in this script.
#

trap {
    # NOTE: This trap will handle all errors. There should be no need to use a catch below in this
    #       script, unless you want to ignore a specific error.
    $message = $Error[0].Exception.Message
    if ($message) {
        Write-Host -Object "`nERROR: $message" -ForegroundColor Red
    }

    Write-Host "`nThe script failed to run.`n"

    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

###################################################################################################
#
# Functions used in this script.
#             

<#
.SYNOPSIS
Returns true is script is running with administrator privileges and false otherwise.
#>
function Get-RunningAsAdministrator {
    [CmdletBinding()]
    param()
    
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    Write-Verbose "Running with Administrator privileges (t/f): $isAdministrator"
    return $isAdministrator
}

<#
.SYNOPSIS
Funtion will download file from specified url.
.PARAMETER DownloadUrl
Url where to get file.
.PARAMETER TargetFilePath
Path where download file will be saved.
.PARAMETER SkipIfAlreadyExists
Skip download if TargetFilePath already exists.
#>
function Get-WebFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DownloadUrl ,
        [Parameter(Mandatory = $true)][string]$TargetFilePath,
        [Parameter(Mandatory = $false)][bool]$SkipIfAlreadyExists = $true
    )

    Write-Verbose ("Downloading installation files from URL: $DownloadUrl to $TargetFilePath")
    $targetFolder = Split-Path $TargetFilePath

    #See if file already exists and skip download if told to do so
    if ($SkipIfAlreadyExists -and (Test-Path $TargetFilePath)) {
        Write-Verbose "File $TargetFilePath already exists.  Skipping download."
        return $TargetFilePath
        
    }

    #Make destination folder, if it doesn't already exist
    if ((Test-Path -path $targetFolder) -eq $false) {
        Write-Verbose "Creating folder $targetFolder"
        New-Item -ItemType Directory -Force -Path $targetFolder | Out-Null
    }

    #Download the file
    for ($i = 1; $i -le 5; $i++) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ; # Enable TLS 1.2 as Security Protocol
            $WebClient = New-Object System.Net.WebClient
            $WebClient.DownloadFile($DownloadUrl, $TargetFilePath)
            Write-Verbose "File $TargetFilePath download."
            return $TargetFilePath
        }
        catch [Exception] {
            Write-Verbose "Caught exception during download..."
            if ($_.Exception.InnerException) {
                $exceptionMessage = $_.InnerException.Message
                Write-Verbose "InnerException: $exceptionMessage"
            }
            else {
                $exceptionMessage = $_.Message
                Write-Verbose "Exception: $exceptionMessage"
            }
        }
    }
    Write-Error "Download of $DownloadUrl failed $i times. Aborting download."
}

<#
.SYNOPSIS
Invokes process and waits for process to exit.
.PARAMETER FileName
Name of executable file to run.  This can be full path to file or file available through the system paths.
.PARAMETER Arguments
Arguments to pass to executable file.
.PARAMETER ValidExitCodes
List of valid exit code when process ends.  By default 0 and 3010 (restart needed) are accepted.
#>
function Invoke-Process {
    [CmdletBinding()]
    param (
        [string] $FileName = $(throw 'The FileName must be provided'),
        [string] $Arguments = '',
        [Array] $ValidExitCodes = @()
    )

    Write-Host "Running command '$FileName $Arguments'"

    # Prepare specifics for starting the process that will install the component.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo -Property @{
        Arguments              = $Arguments
        CreateNoWindow         = $true
        ErrorDialog            = $false
        FileName               = $FileName
        RedirectStandardError  = $true
        RedirectStandardInput  = $true
        RedirectStandardOutput = $true
        UseShellExecute        = $false
        Verb                   = 'runas'
        WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
        WorkingDirectory       = $PSScriptRoot
    }

    # Initialize a new process.
    $process = New-Object System.Diagnostics.Process
    try {
        # Configure the process so we can capture all its output.
        $process.EnableRaisingEvents = $true
        # Hook into the standard output and error stream events
        $errEvent = Register-ObjectEvent -SourceIdentifier OnErrorDataReceived $process "ErrorDataReceived" `
            `
        {
            param
            (
                [System.Object] $sender,
                [System.Diagnostics.DataReceivedEventArgs] $e
            )
            foreach ($s in $e.Data) { if ($s) { Write-Host $err $s -ForegroundColor Red } }
        }
        $outEvent = Register-ObjectEvent -SourceIdentifier OnOutputDataReceived $process "OutputDataReceived" `
            `
        {
            param
            (
                [System.Object] $sender,
                [System.Diagnostics.DataReceivedEventArgs] $e
            )
            foreach ($s in $e.Data) { if ($s -and $s.Trim('. ').Length -gt 0) { Write-Host $s } }
        }
        $process.StartInfo = $startInfo;
        # Attempt to start the process.
        if ($process.Start()) {
            # Read from all redirected streams before waiting to prevent deadlock.
            $process.BeginErrorReadLine()
            $process.BeginOutputReadLine()
            # Wait for the application to exit for no more than 5 minutes.
            $process.WaitForExit(300000) | Out-Null
        }
        # Ensure we extract an exit code, if not from the process itself.
        $exitCode = $process.ExitCode
        # Determine if process requires a reboot.
        if ($exitCode -eq 3010) {
            Write-Host 'The recent changes indicate a reboot is necessary. Please reboot at your earliest convenience.'
        }
        elseif ($ValidExitCodes.Contains($exitCode)) {
            Write-Host "$FileName exited with expected valid exit code: $exitCode"
            # Override to ensure the overall script doesn't fail.
            $LASTEXITCODE = 0
        }
        # Determine if process failed to execute.
        elseif ($exitCode -gt 0) {
            # Throwing an exception at this point will stop any subsequent
            # attempts for deployment.
            throw "$FileName exited with code: $exitCode"
        }
    }
    finally {
        # Free all resources associated to the process.
        $process.Close();
        # Remove any previous event handlers.
        Unregister-Event OnErrorDataReceived -Force | Out-Null
        Unregister-Event OnOutputDataReceived -Force | Out-Null
    }
}

function Install-Office{
    param{
        [Parameter(Mandatory=$true)][string]$PathToConfig
    }

    $resolvedPathToConfig = Resolve-Path $PathToConfig
    
    Write-Host "Downloading Office Deployment Tool"
    $odtExe = "$env:userprofile/Downloads/OfficeDeploymentToole.exe"
    Get-WebFile -DownloadFile "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_11901-20022.exe" -TargetFilePath $onedriveSetupExePath -SkipIfAlreadyExists $true
    
    Write-Host "Downloading Office components specified by configuration file"
    Invoke-Process -FileName $odtExe -Arguments "/download $resolvedPathToConfig"
    
    Write-Host "Installing Office components specified by configuration file"
    Invoke-Process -FileName $odtExe -Arguments "/configure $resolvedPathToConfig"
}

function Get-OfficeUpdateChannels{
    #https://docs.microsoft.com/en-us/sccm/sum/deploy-use/manage-office-365-proplus-updates#change-the-update-channel-after-you-enable-office-365-clients-to-receive-updates-from-configuration-manager
    $updateChannels = @{
        "Monthly Channel" = "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60";
        "Semi-Annual Channel" = "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114";
        "Monthly Channel (Targeted)" = "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be";
        "Semi-Annual Channel (Targeted)" = "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf"
    }
    return $updateChannels
}

function Set-OfficeUpdateChanel{
    param(
        [Parameter(Mandatory=$true)][string]$CdnUrl
    )
    # Update to the Office 365 Monthly Channel 
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration\CDNBaseUrl" -Name "CDNBaseUrl" -Value $CdnUrl -Force | Out-Null

}

###################################################################################################
#
# Main execution block.
#

try {
    Write-Host "Verifying running as administrator."
    if (-not (Get-RunningAsAdministrator)) { 
        Write-Error "Please re-run this script as Administrator." 
    }

    Install-Office


    $cdnUrlChoice = $()
    while ([array]$CdnUrl.Count -ne 1){
        $cdnUrlChoice Sort-Object -Property Name  | Out-Gridview -Title "Select Update Channel to use." -PassThru
    }

    Write-Host -Object "Script completed." -ForegroundColor Green
}
finally {
    # Restore system to state prior to execution of this script.
    Pop-Location
}
