<#
.SYNOPSIS
Activates selected Azure AD Privileged Identity Management (PIM) roles for a specified duration.

.DESCRIPTION
This PowerShell script connects to Azure AD and prompts the user to select one or more PIM roles to activate. The selected roles are then activated with a specified duration and justification.

.NOTES
Author: Marius A. Skovli
Date: April 3, 2023
#>

# Check if all required modules are installed and install them if necessary
$requiredModules = @('AzureADPreview', 'Az.Accounts')
$missingModules = @()
foreach ($module in $requiredModules) {
    if (-not(Get-Module -Name $module -ErrorAction SilentlyContinue)) {
        $missingModules += $module
    }
}
if ($missingModules.Count -gt 0) {
    Write-Host "The following modules are missing: $($missingModules -join ', '). Installing modules..."
    Install-Module -Name $missingModules -Scope CurrentUser -Force
}

# Import required modules
Import-Module -Name AzureADPreview, Az.Accounts -ErrorAction Stop


Connect-AzureAD -AccountId $currentUser.Account.Id -TenantId $currentUser.Tenant.Id -Credential $currentUser.Account.Context.Credentials


# Read the CSV file
$groups = Import-Csv -Path "C:\Temp\CreateGroups\PIM-Groups.csv"

# Loop through the groups and create each one
foreach ($group in $groups) {
    # Create a new group
    $newGroup = New-AzureADGroup -DisplayName $group.GroupName -Description $group.GroupDescription -MailEnabled $false -SecurityEnabled $true -MailNickName "NotSet" -Verbose
}