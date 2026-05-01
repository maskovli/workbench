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

# Get the list of available roles associated with the signed-in account
$roles = Get-AzureADDirectoryRole | Select-Object DisplayName, ObjectId

# Display available roles
Write-Host "Available Roles:`n"
$roles | ForEach-Object { Write-Host "- $($_.DisplayName)" }

# Prompt the user to select one or more roles to activate
$selectedRoles = (Read-Host "`nEnter the roles you want to activate (comma-separated)").Split(',')
$roleIds = @()
foreach ($selectedRole in $selectedRoles) {
    $roleId = $roles | Where-Object { $_.DisplayName -eq $selectedRole.Trim() } | Select-Object -ExpandProperty ObjectId
    if ($roleId) {
        $roleIds += $roleId
    }
}

# If no roles were selected, exit the script
if ($roleIds.Count -eq 0) {
    Write-Warning "No roles were selected. Exiting script."
    Disconnect-AzureAD
    return
}

# Prompt for duration and justification
$duration = Read-Host "Enter the duration (in hours) for which the selected roles should be activated"
$justification = Read-Host "Enter the justification for activating the selected roles"

# Loop through the selected role IDs and activate each role with the specified justification and duration
foreach ($roleId in $roleIds) {
    # Get the role by ID
    $role = Get-AzureADDirectoryRole -ObjectId $roleId

    # Create a new role assignment with the specified duration and justification
    $assignment = @{
        "roleId" = $roleId
        "reason" = $justification
        "duration" = $duration
    }
    $result = New-AzureADMSPrivilegedRoleAssignment -RoleAssignmentProperties $assignment

    # Check the result of the activation request
    if ($result.Status -eq "PendingApproval") {
        Write-Verbose "Activation request for role $($role.DisplayName) submitted. Waiting for approval."
    }
    elseif ($result.Status -eq "Denied") {
        Write-Verbose "Activation request for role $($role.DisplayName) denied."
    }
    else {
        Write-Verbose "Role $($role.DisplayName) activated until $($result.EndTime) with justification '$justification'."
    }
}

# Disconnect from Azure AD
Disconnect-AzureAD
