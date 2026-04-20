# Connect to Microsoft Graph
Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory", "RoleManagement.ReadWrite.CloudPC", "Directory.AccessAsUser.All"
Write-Host "Connected to Microsoft Graph."

# Get the current user's ID
$userId = (Get-MgContext).Account.ObjectId
Write-Host "User ID: $userId"

# Retrieve eligible Azure AD roles
Write-Host "Retrieving Azure AD eligible roles..."
$aadEligibleRoles = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$userId'"
Write-Host "Retrieved Azure AD eligible roles: $($aadEligibleRoles.Count)"

# Initialize the array to store all roles
$allRoles = @()

foreach ($role in $aadEligibleRoles) {
    $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -RoleDefinitionId $role.RoleDefinitionId
    $allRoles += [PSCustomObject]@{
        RoleName             = $roleDefinition.DisplayName
        Description          = $roleDefinition.Description
        RequiresJustification= $null
        RequiresApproval     = $null
        Approvers            = $null
        RoleType             = "Entra Role"
        AssignmentId         = $role.Id
        RoleDefinitionId     = $role.RoleDefinitionId
        ResourceId           = $role.DirectoryScopeId
    }
}

# Display roles in GridView
$selectedRoles = $allRoles | Out-GridView -Title "Select Roles to Activate" -OutputMode Multiple

# Prompt for Justification and Duration
$justification = Read-Host "Enter Justification"
$durationHours = Read-Host "Enter Duration in Hours (e.g., 4)"
$duration = "PT${durationHours}H"

# Activate Selected Roles
foreach ($role in $selectedRoles) {
    $bodyParams = @{
        PrincipalId        = $userId
        RoleDefinitionId   = $role.RoleDefinitionId
        DirectoryScopeId   = $role.ResourceId
        Justification      = $justification
        Schedule           = @{
            StartDateTime = (Get-Date).ToUniversalTime().ToString("o")
            Duration      = $duration
        }
    }

    switch ($role.RoleType) {
        "Entra Role" {
            New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $bodyParams | Out-Null
        }
        # Add cases for other role types if necessary
    }
}

Write-Host "Activation requests submitted."
