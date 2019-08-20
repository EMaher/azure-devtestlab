[CmdletBinding()]
param(
    
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

function Get-RunningAsAdministrator {
    [CmdletBinding()]
    param(    )
    
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”)
    Write-Verbose "Running with Administrator privileges (t/f): $isAdministrator"
    return $isAdministrator

}

<#
       .SYNOPSIS
       Short description
       
       .DESCRIPTION
       Long description
       
       .EXAMPLE
       An example
       
       .NOTES
       General notes
       #>
function Install-HypervAndTools {
    [CmdletBinding()]
    param()
    ##Check to see if Hyper-V role is installed, if running on a server os

    if ($(Get-Module -ListAvailable -Name 'servermanager') -ne $null) {        
        #server os
        #install Hyper-V roll
        $hyperVRoleInstalled = $(Get-WindowsFeature -Name 'Hyper-V' | Select -ExpandProperty 'Installed')
        if ($hyperVRoleInstalled -eq $null) {
            Write-Error "This script only applies to machines that can run Hyper-V."
        }
        elseif ( $hyperVRoleInstalled -eq $false) {
            $roleInstallStatus = Install-WindowsFeature -Name Hyper-V -IncludeManagementTools
            if ($roleInstallStatus.RestartNeeded -eq 'Yes') {
                Write-Error "Restart required to finish installing the Hyper-V role .  Please restart and re-run this script."
            }  
        } 

        #install PowerShell cmdlets
        #if ($(Get-Module -ListAvailable -Name 'hyper-v' | measure | select -Expand 'Count') -ne 1) {
        #    Write-Verbose 'Installing PowerShell module for Hyper-V'
        $featureStatus = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell
        if ($featureStatus.RestartNeeded -eq $true) {
            Write-Error "Restart required to finish installing the Hyper-V PowerShell Module.  Please restart and re-run this script."
        }
        #}
    }
    else {      
        #client os
        #install service
        # if ($(Get-Module -ListAvailable -Name 'Microsoft-Hyper-V-All' | Select-Object -ExpandProperty State) -eq 'Enabled') {
        $installStatus = Enable-WindowsOptionalFeature -Online -FeatureName:Microsoft-Hyper-V-All -NoRestart
        if ($installStatus.RestartNeeded -eq $true) {
            Write-Error "Restart required to finish installing Hyper-V.  Please restart and re-run this script."
        }
        #}
    }
}

function Select-ResourceByProperty {
    [CmdletBinding()]
    param(
         [Parameter(Mandatory=$true)][string]$PropertyName ,
         [Parameter(Mandatory=$true)][string]$ExpectedPropertyValue,
                                     [bool]$ExactMatch = $true,
         [Parameter(Mandatory=$true)][array]$List,
         [Parameter(Mandatory=$true)][scriptblock]$NewObjectScriptBlock
        )
    
        $returnValue = $null
       # if ($ExactMatch){
        #$items = @($List | where $PropertyName -EQ $ExpectedPropertyValue)
        #}else {
            $items = @($List | where $PropertyName -Like $ExpectedPropertyValue)
        #}
        if ($items.Count -eq 0) {
            Write-Verbose "Creating new item with $PropertyName =  $ExpectedPropertyValue."
            #$returnValue = New-VMSwitch -Name $ExpectedPropertyValue -SwitchType Internal
            $returnValue = & $NewObjectScriptBlock
        }
        elseif ($items.Count -eq 1) {
            $returnValue = $items[0]
        }
        else {
            Write-Host "Found multiple items with name $ExpectedPropertyValue.  Available items are:"
            $choice = -1
            $choiceTable = New-Object System.Data.DataTable
            $choiceTable.Columns.Add($(new-object System.Data.DataColumn("Option Number")))
            $choiceTable.Columns[0].AutoIncrement = $true
            $choiceTable.Columns[0].ReadOnly = $true
            $choiceTable.Columns.Add($(New-Object System.Data.DataColumn($ExpectedPropertyValue)))
           
            $choiceTable.Rows.Add($null, "< Choose this option exit. >", "") | Out-Null
            $items | ForEach-Object { $choiceTable.Rows.Add($null, $($_ | select -ExpandProperty $PropertyName)) } | Out-Null
            $choiceTable | Format-Table 
            while ( -not (($choice -ge 0 ) -and ($choice -le $items.Count))) {     
                $choice = Read-Host "Please enter option number. (Between 0 and $($choiceTable.Rows.Count -1))"           
            }
    
            if ($choice -eq 0) {
                Write-Error "User cancelled script."
            }
            else {
                $returnValue = $items[$($choice - 1)]
            }
          
        }
        return $returnValue
}

###################################################################################################
#
# Main execution block.
#

try {

    ##Check that script is being run with Administrator privilege.
    if (-NOT (Get-RunningAsAdministrator)) { Write-Error "Please re-run this script as Administrator." }

    #Install HyperV service and client tools
    Install-HypervAndTools

    #Pin Hyper-V to the user's desktop.
    $Shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($(Join-Path "$env:UserProfile\Desktop" "Hyper-V Manager.lnk"))
    $Shortcut.TargetPath = "$env:SystemRoot\System32\virtmgmt.msc"
    $Shortcut.Save()


    #Create Switch
    $switchName = "LabServicesSwitch"
    $vmSwitch = Select-ResourceByProperty -PropertyName 'Name' -ExpectedPropertyValue $switchName -List (Get-VMSwitch -SwitchType Internal) -NewObjectScriptBlock {New-VMSwitch -Name $switchName -SwitchType Internal}
    Write-Host "Using $vmSwitch"

    
    $netAdapter = Select-ResourceByProperty -PropertyName "Name" -ExpectedPropertyValue "*$switchName*" -ExactMatch $false -List @(Get-NetAdapter) -NewObjectScriptBlock {Write-Error "No Net Adapters found"}
    Write-Host "Use  $netAdapter"
  
    $ifIndex = $netAdapter.ifIndex
    $ipAddress = "192.168.0.1"
    $natName = "LabServicesNat"
  
###RESUME HERE####
#return

#todo make this section idempotent
    Write-Output "Adapter found is $($netAdapter.ifAlias) and Interface Index is $ifIndex"
    New-NetIPAddress -IPAddress $ipAddress -PrefixLength 24 -InterfaceIndex $ifIndex
    New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix "192.168.0.0/24"          
    #todo: make subnet mask 255.255.255.0

}
finally {
    # Restore system to state prior to execution of this script.
    Pop-Location
}


