
param(
[string]
$ConfigJSONPath = '.\LabServicesAADGroupMapping.json',

[string]
$clientId = '',

[string]
$clientSecret = '',

[string]
$tenantId = ''
)

Add-Type -LiteralPath "$PSScriptRoot\ADAL\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"

function New-AuthenticationHeader {
    param (
        # Parameter help description
        [Parameter(Mandatory=$True)]
        [string]
        $clientId,
        [Parameter(Mandatory=$True)]
        [string]
        $clientSecret,
        [Parameter(Mandatory=$True)]
        [string]
        $tenantId,
        [Parameter(Mandatory=$True)]
        [string]
        $resourceId
    )


    $login = "https://login.microsoftonline.com"

    # Get an Access Token with ADAL

    $clientCredential = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential($clientId,$clientSecret)

    $authContext = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext("{0}/{1}" -f $login,$tenantId)
    $authenticationResult = $authContext.AcquireTokenAsync($resourceId, $clientcredential).GetAwaiter().GetResult()
    $token = $authenticationResult.AccessToken

    $headers = @{ 
        "Authorization" = ("Bearer {0}" -f $token);
        "Content-Type" = "application/json";
    }
return $headers
}

function Get-ADALTokenFromCache {
    $resource = 'https://management.core.windows.net/'
    $ctx = Get-AzContext
    $token = $null

    $tenantId = $ctx.Tenant.Id
    $tokenCacheItems = $ctx.TokenCache.ReadItems()
    if ($tokenCacheItems.count -gt 1) {
        $token = $tokenCacheItems | Where-Object {($_.TenantId -eq $tenantId)  -and ($_.Resource -eq $resource)}
    } else {
        $token = $tokenCacheItems
    }
    $authorisationHeader = @{
        Authorization = ('Bearer {0}' -f $token.AccessToken)
    }
    
    return $authorisationHeader
    
    }

function New-LabServicesUserAssignment {
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]
        $subscriptionId,
        [Parameter(Mandatory=$true)]
        [string]
        $resourceGroupName,
        [Parameter(Mandatory=$true)]
        [string]
        $labName,
        [Parameter(Mandatory=$true)]
        [string]
        $labAccountName,
        [Parameter(Mandatory=$true)]
        [string[]] $users,
        [Parameter(Mandatory=$true)]
        $authHeader

    )
    #subscriptions/51d06b2f-9c98-4502-9329-1ec41fed64c7/resourceGroups/ntazlabs/providers/Microsoft.LabServices/labaccounts/ntlabs01/labs/scriptinglab/addUsers?api-version=2019-01-01-preview 
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.LabServices/labaccounts/$labAccountName/labs/$labName/addUsers?api-version=2019-01-01-preview"
    if ($users.count -gt 1) {
    $usersJson = $users | ConvertTo-Json -Depth 9
    }
    else {
        $usersJson = "['$users']"
    }
    $body = @"
        {
        "emailAddresses":$usersJson
    }
"@
    
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $authHeader -Body $body
    return $response
}

function Get-Users {
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]
        $subscriptionId,
        [Parameter(Mandatory=$true)]
        [string]
        $resourceGroupName,
        [Parameter(Mandatory=$true)]
        [string]
        $labAccountName,
        [Parameter(Mandatory=$true)]
        [string]
        $labName,
        [Parameter(Mandatory=$true)]
        [string]
        $userName,
        [Parameter(Mandatory=$true)]
        [string]
        $authHeader

    )
    $VerbosePreference = $true
    $DebugPreference = $true
    $uri = $null
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.LabServices/labaccounts/$labAccountName/labs/$labName/users/$userName`?api-version=2018-10-15"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $auth
    return $response
}


function Get-AADGroupMembers {
    param (
        # Parameter help description
        [Parameter(Mandatory=$True)]
        [string]
        $GroupId,
        [Parameter(Mandatory=$True)]
        [Hashtable]
        $AuthHeader
    )
    $apiUrl = "https://graph.microsoft.com/v1.0/Groups/$GroupId/members"
    $Data = Invoke-RestMethod -Headers $AuthHeader -Uri $apiUrl -Method Get
    $groupMembers = ($Data | select-object Value).Value
    [string[]] $emails = $null
    foreach ($groupMember in $groupMembers){
        $email = $groupMember.mail
        $emails += $email
    }
    # $groupMembershipEmails = 
    return $emails
}

function Get-AADGroupId {
    param (
        # Parameter help description

        [Parameter(Mandatory=$True)]
        [string]
        $GroupName,

        [Parameter(Mandatory=$True)]
        [Hashtable]
        $AuthHeader
    )
    $apiUrl = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'$GroupName')"
    # $apiUrl = "https://graph.microsoft.com/v1.0/groups"
    $data = Invoke-RestMethod -Headers $AuthHeader -Uri $apiUrl -Method Get
    $groupId = (($data | select-object Value).Value)[0].Id
    return $groupId
}

$authLabServices = New-AuthenticationHeader -clientId $clientId -clientSecret $clientSecret -tenantId $tenantId -resourceId 'https://management.azure.com'
$authGraph = New-AuthenticationHeader -clientId $clientId -clientSecret $clientSecret -tenantId $tenantId -resourceId 'https://graph.microsoft.com/'

#Read in the JSON Config and loop through / apply the relevant changes to LabServices User Membership

$config = Get-Content -Path $ConfigJSONPath | ConvertFrom-Json -Depth 9
foreach ($labService in $config.LabServices) {
    $labServiceAccountName = $labService.LabServiceAccountName
    $subscriptionId = $labService.SubscriptionId
    $labServicesResourceGroupName = $labService.LabServicesResourceGroupName
    $labName = $labService.LabName
    $AADGroups = $labService.AADGroups
    [string[]]$groupMembers = $null

    foreach ($AADGroup in $AADGroups){
        $groupDisplayName = $AADGroup.GroupDisplayName
        $groupId = Get-AADGroupId -GroupName $groupDisplayName -AuthHeader $authGraph
        $groupMembers += Get-AADGroupMembers -GroupId $groupId -AuthHeader $authGraph

    }

    #remove empty users from the array
    $groupMembers = $groupMembers | Where({ $_ -ne "" })
    if ($groupMembers.count -gt 0) {
    $newUser = New-LabServicesUserAssignment -subscriptionId $subscriptionId -resourceGroupName $labServicesResourceGroupName -labName $labName -authHeader $authLabServices -labAccountName $labServiceAccountName -users $groupMembers
    }
}
