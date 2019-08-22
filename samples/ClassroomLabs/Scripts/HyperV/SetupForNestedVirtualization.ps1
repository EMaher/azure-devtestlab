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


function Get-RunningServerOperatingSystem {
    [CmdletBinding()]
    param()

    return ($null -ne $(Get-Module -ListAvailable -Name 'servermanager') )
}

function Install-HypervAndTools {
    [CmdletBinding()]
    param()
   

    if ($null -eq $(Get-WindowsFeature -Name 'Hyper-V')) {
        Write-Error "This script only applies to machines that can run Hyper-V."
    }
    else 
    {
        $roleInstallStatus = Install-WindowsFeature -Name Hyper-V -IncludeManagementTools
        if ($roleInstallStatus.RestartNeeded -eq 'Yes') {
            Write-Error "Restart required to finish installing the Hyper-V role .  Please restart and re-run this script."
        }  
    } 

    #install PowerShell cmdlets
    $featureStatus = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell
    if ($featureStatus.RestartNeeded -eq $true) {
        Write-Error "Restart required to finish installing the Hyper-V PowerShell Module.  Please restart and re-run this script."
    }
    

}

function Install-DHCP {
    [CmdletBinding()]
    param(    )
   
    if ($null -eq $(Get-WindowsFeature -Name 'DHCP')) {
        Write-Error "This script only applies to machines that can run DHCP."
    }
    else
    {
        $roleInstallStatus = Install-WindowsFeature -Name DHCP -IncludeManagementTools
        if ($roleInstallStatus.RestartNeeded -eq 'Yes') {
            Write-Error "Restart required to finish installing the DHCP role .  Please restart and re-run this script."
        }  
    } 

    #Tell Windows we are done installing DHCP
    Set-ItemProperty –Path registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager\Roles\12 –Name ConfigurationState –Value 2
}


function Select-ResourceByProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PropertyName ,
        [Parameter(Mandatory = $true)][string]$ExpectedPropertyValue,
        [Parameter(Mandatory = $false)][array]$List = @(),
        [Parameter(Mandatory = $true)][scriptblock]$NewObjectScriptBlock
    )
    
    $returnValue = $null
    $items = @($List | Where-Object $PropertyName -Like $ExpectedPropertyValue)
    
    if ($items.Count -eq 0) {
        Write-Verbose "Creating new item with $PropertyName =  $ExpectedPropertyValue."
        $returnValue = & $NewObjectScriptBlock
    }
    elseif ($items.Count -eq 1) {
        $returnValue = $items[0]
    }
    else {
        $choice = -1
        $choiceTable = New-Object System.Data.DataTable
        $choiceTable.Columns.Add($(new-object System.Data.DataColumn("Option Number")))
        $choiceTable.Columns[0].AutoIncrement = $true
        $choiceTable.Columns[0].ReadOnly = $true
        $choiceTable.Columns.Add($(New-Object System.Data.DataColumn($PropertyName)))
        $choiceTable.Columns.Add($(New-Object System.Data.DataColumn("Details")))
           
        $choiceTable.Rows.Add($null, "< Exit >", "Choose this option to exit the script.") | Out-Null
        $items | ForEach-Object { $choiceTable.Rows.Add($null, $($_ | Select-Object -ExpandProperty $PropertyName), $_.ToString()) } | Out-Null


        Write-Host "Found multiple items with $PropertyName = $ExpectedPropertyValue.  Please choose on of the following options."
        $choiceTable | ForEach-Object {Write-Host "$($_[0]): $($_[1]) ($($_[2]))"}
        
        #$choiceTable.Rows | ForEach-Object {Write-Host $_}

        
while ( -not (($choice -ge 0 ) -and ($choice -le $choiceTable.Rows.Count -1 ))) {     
            $choice = Read-Host "Please enter option number. (Between 0 and $($choiceTable.Rows.Count - 1))"           
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
    #Verify that we are on a server os, not a client os
    if (-Not (Get-RunningServerOperatingSystem)) { Write-Error "This script is designed to run on Windows Server." }

    #Check that script is being run with Administrator privilege.
    if (-NOT (Get-RunningAsAdministrator)) { Write-Error "Please re-run this script as Administrator." }

    #Install HyperV service and client tools
    Install-HypervAndTools

    #Pin Hyper-V to the user's desktop.
    $Shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($(Join-Path "$env:UserProfile\Desktop" "Hyper-V Manager.lnk"))
    $Shortcut.TargetPath = "$env:SystemRoot\System32\virtmgmt.msc"
    $Shortcut.Save()


    $ipAddress = "192.168.0.1"
    $ipAddressPrefix = "192.168.0.0/24"
    $startRangeForClientIps = "192.168.0.100"
    $endRangeForClientIps = "192.168.0.200"
    $subnetMaskForClientIps = "255.255.255.0"

    Install-DHCP 

    #Add scope for client vm ip address
    $scopeName = "LabServicesDhcpScope"
    $dhcpScope = Select-ResourceByProperty -PropertyName 'Name' -ExpectedPropertyValue $scopeName -List @(Get-DhcpServerV4Scope) -NewObjectScriptBlock { Add-DhcpServerv4Scope -name $scopeName -StartRange $startRangeForClientIps -EndRange $endRangeForClientIps -SubnetMask $subnetMaskForClientIps -State Active }
    Write-Host"Using $dhcpScope"

    #Create Switch
    $switchName = "LabServicesSwitch"
    $vmSwitch = Select-ResourceByProperty -PropertyName 'Name' -ExpectedPropertyValue $switchName -List (Get-VMSwitch -SwitchType Internal) -NewObjectScriptBlock { New-VMSwitch -Name $switchName -SwitchType Internal }
    Write-Host "Using $vmSwitch"

    #Get network adapter information
    $netAdapter = Select-ResourceByProperty -PropertyName "Name" -ExpectedPropertyValue "*$switchName*"  -List @(Get-NetAdapter) -NewObjectScriptBlock { Write-Error "No Net Adapters found" } 
    Write-Host "Using  $netAdapter"
    Write-Output "Adapter found is $($netAdapter.ifAlias) and Interface Index is $($netAdapter.ifIndex)"

    ##TODO: Set default gateway on netAdapter???
  
    #Create IP Address 
    $netIpAddr = Select-ResourceByProperty  -PropertyName 'IPAddress' -ExpectedPropertyValue $ipAddress -List @(Get-NetIPAddress) -NewObjectScriptBlock { New-NetIPAddress -IPAddress $ipAddress -PrefixLength 24 -InterfaceIndex $netAdapter.ifIndex }
    if (($netIpAddr.PrefixLength -ne 24) -or ($netIpAddr.InterfaceIndex -ne $netAdapter.ifIndex)) {
        Write-Error "Found Net IP Address $netIpAddr, but prefix $ipAddressPrefix ifIndex not $($netAdapter.ifIndex)."
    }
    Write-Output "Net ip address found is $ipAddress"

    #Create NAT
    $natName = "LabServicesNat"
    $netNat = Select-ResourceByProperty -PropertyName 'Name' -ExpectedPropertyValue $natName -List @(Get-NetNat) -NewObjectScriptBlock { New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $ipAddressPrefix }
    if ($netNat.InternalIPInterfaceAddressPrefix -ne $ipAddressPrefix) {
        Write-Error "Found nat with name $natName, but InternalIPInterfaceAddressPrefix is not $ipAddressPrefix."
    }
    Write-Output "Nat found is $netNat"
}
finally {
    # Restore system to state prior to execution of this script.
    Pop-Location
}