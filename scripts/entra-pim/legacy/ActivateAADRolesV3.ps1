<#
.SYNOPSIS
Activates selected Azure AD Privileged Identity Management (PIM) roles for a specified duration.

.DESCRIPTION
This PowerShell script connects to Azure AD and prompts the user to select one or more PIM roles to activate. The selected roles are then activated with a specified duration and justification.

.NOTES
Author: Marius A. Skovli
Date: April 3, 2023
#>

# Check if AzureADPreview module is installed and install if not
if (-not (Get-Module -Name AzureADPreview -ListAvailable)) {
    Write-Verbose "AzureADPreview module is not installed. Installing..."
    Install-Module -Name AzureADPreview -AllowClobber -Force
}

# Import AzureADPreview module
Write-Verbose "Importing AzureADPreview module..."
Import-Module -Name AzureADPreview

# Connect to Azure AD
Connect-AzureAD

# Get available roles for the signed-in user
$availableRoles = Get-AzureADMSPrivilegedRole -All $true | Where-Object { $_.IsElevatableByMyself -eq $true }

Write-Host "Available roles:"
foreach ($role in $availableRoles) {
    Write-Host "$($role.DisplayName) ($($role.Id))"
}

# Prompt user to select role(s) to activate
$selectedRoles = Read-Host "Enter the role IDs to activate, separated by commas"
$selectedRoles = $selectedRoles -split ","

# Prompt user to provide justification
$justification = Read-Host "Enter justification for the role assignment"

# Prompt user to provide duration in minutes
$duration = Read-Host "Enter the duration (in minutes) for the role assignment"

foreach ($roleId in $selectedRoles) {
    $result = Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId 'aadRoles' -ResourceId $roleId -RoleDefinitionId $roleId -SubjectId (Get-AzureADSignedInUser).ObjectId -Type 'adminAdd' -AssignmentState 'Active' -DurationInMinutes $duration -Reason $justification
    Write-Host "Activated role $($roleId)"
}
