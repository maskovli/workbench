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

    # Prompt the user to enter the duration for the role activation
    $duration = Read-Host "Enter the duration for the role activation in minutes (e.g. 60)"

    # Prompt the user to enter a justification for the role activation
    $justification = Read-Host "Enter a justification for the role activation"

    # Iterate through the selected roles and activate each one
    foreach ($role in $selectedRoles) {
        # Get the role details
        $roleDetails = Get-AzureADMSPrivilegedRole -ObjectId $role

        # Create a new role assignment
        $assignment = New-Object Microsoft.Open.MSGraphBeta.PowerShell.Models.OpenAzureADMSPrivilegedRoleAssignmentRequest

        # Set the assignment properties
        $assignment.ProviderId = "aadRoles"
        $assignment.SubjectId = (Get-AzureADUser -ObjectId $env:USERPrincipalName).ObjectID
        $assignment.Type = "adminAdd"
        $assignment.RoleId = $roleDetails.Id

        # Create a schedule object for the assignment
        $startTime = (Get-Date).ToUniversalTime().ToString("o")
        $endTime = ((Get-Date).AddMinutes([int]$duration)).ToUniversalTime().ToString("o")
        $schedule = New-Object Microsoft.Open.MSGraphBeta.PowerShell.Models.OpenAzureADMSPrivilegedRoleSchedule
        $schedule.StartDateTime = $startTime
        $schedule.EndDateTime = $endTime

        # Set the assignment schedule and justification
        $assignment.Schedule = $schedule
        $assignment.Justification = $justification

        # Activate the role assignment
        Open-AzureADMSPrivilegedRoleAssignmentRequest -RoleAssignment $assignment
    }

    Write-Host "Role activation complete."
}
else {
    Write-Host "No roles available for activation."
}
