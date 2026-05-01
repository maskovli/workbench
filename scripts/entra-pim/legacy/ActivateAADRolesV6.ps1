<#
.SYNOPSIS
Activates selected Azure AD Privileged Identity Management (PIM) roles for a specified duration.

.DESCRIPTION
This PowerShell script connects to Azure AD and prompts the user to select one or more PIM roles to activate. The selected roles are then activated with a specified duration and justification.

.NOTES
Author: Marius A. Skovli
Date: April 3, 2023
#>

# Import the required modules
Import-Module -Name AzureADPreview
Import-Module -Name Microsoft.Graph.Authentication
Import-Module -Name Microsoft.Graph.Identity.SignIns
Import-Module -Name Microsoft.Graph.IdentityPrivilegedAccessManagement

# Check if the current user is logged on to Azure
$currentUser = Get-AzContext

if ($currentUser) {
    # If the user is logged on, ask if they want to proceed or terminate
    $response = Read-Host "Current user $($currentUser.Account.Id) is logged on to Azure. Do you want to proceed (P) or terminate (T)?"

    if ($response -eq "P") {
        Write-Host "Proceeding with current user $($currentUser.Account.Id)"
    }
    elseif ($response -eq "T") {
        # If the user wants to terminate, clear the current context and prompt for new login
        Clear-AzContext
        Write-Host "Current context has been cleared. Please log in again."
        Connect-AzAccount
        Connect-AzureAD -AccountId $currentUser.Account.Id -TenantId $currentUser.Tenant.Id -Credential $currentUser.Account.Context.Credentials
    }
    else {
        Write-Host "Invalid response. Please enter 'P' to proceed or 'T' to terminate."
    }
}
else {
    # If the user is not logged on, prompt for login
    Write-Host "No user is logged on to Azure. Please log in."
    Connect-AzAccount
    Connect-AzureAD -AccountId $currentUser.Account.Id -TenantId $currentUser.Tenant.Id -Credential $currentUser.Account.Context.Credentials
}

# Get the user's roles
$roles = Get-AzureADDirectoryRole | Select-Object -Property DisplayName, ObjectId, Description

# Check if there are any roles assigned to the user
if ($roles) {
    # Display the available roles
    Write-Host "Available Roles:"
    $roles | Format-Table -AutoSize

    # Prompt the user to select one or more roles
    $selectedRoles = Read-Host "Enter the ID(s) of the role(s) you want to activate, separated by a comma."

    # Split the selected roles into an array
    $selectedRoles = $selectedRoles -split ','

    # Prompt the user to enter the duration for the role activation
    $duration = Read-Host "Enter the duration for the role activation in minutes (e.g. 60)"

    # Prompt the user to enter a justification for the role activation
    $justification = Read-Host "Enter a justification for the role activation"

    # Iterate through the selected roles and activate each one
    foreach ($role in $selectedRoles) {
        # Get the role details
        $roleDetails = Get-AzureADDirectoryRole -ObjectId $role

        # Create a new role assignment request
        $assignment = [Microsoft.Graph.IdentityPrivilegedAccessManagement.OpenShiftPrivilegedRoleAssignmentRequest]::new()
        $assignment.Provider = "aadRoles"
        $assignment.Type = "adminAdd"
        $assignment.RoleId = $roleDetails.ObjectId

        # Create a schedule object for the assignment
        $startTime = (Get-Date).ToUniversalTime()
        $endTime = $startTime.AddMinutes([int]$duration)
        $schedule = [Microsoft.Graph.IdentityPrivilegedAccessManagement.OpenShiftRoleSchedule]::new($startTime, $endTime)

        # Set the assignment schedule and justification
        $assignment.Schedule = $schedule
        $assignment.Justification = $justification

        # Activate the role assignment
        $result = New-AzureADMSPrivilegedRoleAssignmentRequest -RoleAssignment $assignment

        Write-Host "Role $($roleDetails.DisplayName) activated until $($endTime.ToLocalTime()) with justification '$justification'."
    }

    Write-Host "Role activation complete."
}
else {
    Write-Host "No roles available for activation."
}
