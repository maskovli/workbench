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
# Connect to Azure AD
Connect-AzureAD

# Get the user's roles
$roles = Get-AzureADMSPrivilegedRole -Filter "AssignedTo eq '$($env:USERNAME)'" -All $true | Select-Object -Property DisplayName, Id

# Check if there are any roles assigned to the user
if ($roles) {
    # Display the available roles
    Write-Host "Available Roles:"
    $roles | Format-Table -AutoSize

    # Prompt the user to select one or more roles
    $selectedRoles = Read-Host "Enter the ID(s) of the role(s) you want to activate, separated by a comma."

    # Split the selected roles into an array
    $selectedRoles = $selectedRoles -split ','

    # Prompt the user to enter a justification for activating the role(s)
    $justification = Read-Host "Enter a justification for activating the role(s)."

    # Prompt the user to enter the duration for the activation
    $duration = Read-Host "Enter the duration for the activation in minutes."

    # Loop through the selected roles and activate them
    foreach ($roleId in $selectedRoles) {
        # Activate the role
        $result = Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId 'aadRoles' -ResourceId $roleId -RoleDefinitionId $roleId -SubjectId $env:USERNAME -Type 'adminAdd' -AssignmentState 'Active' -Duration ($duration * 60) -Reason $justification

        # Display the result
        Write-Host "Activated role $($roleId)"
    }
}
else {
    Write-Host "You do not have any roles assigned to you in Privileged Identity Management."
}

# Disconnect from Azure AD
Disconnect-AzureAD