# Connect to Entra with the required permissions
Connect-MgGraph -Scopes "RoleManagement.Read.Directory","User.Read"

# Retrieve the current logged-in user's details from the active session context
$currentContext = Get-MgContext
$currentUserId = $currentContext.Account

# Get current user object using UPN from context
$currentUser = Get-MgUser -UserId $currentUserId


# Get eligible PIM roles assigned to yourself
$eligibleAssignments = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance `
    -Filter "principalId eq '$($currentUser.Id)'" `
    -ExpandProperty "RoleDefinition" `
    -All

# Format roles for display
$report = $eligibleAssignments | ForEach-Object {
    # Calculate Activation Limit
    if($_.EndDateTime -and $_.StartDateTime){
        $activationHours = ([DateTime]$_.EndDateTime - [DateTime]$_.StartDateTime).TotalHours
        $activationLimit = "$activationHours hours"
    }
    else {
        $activationLimit = "No Limit"
    }

    # Determine if approval is required (simplified as MemberType 'Direct' usually indicates no approval)
    $approvalRequired = if ($_.MemberType -eq "Direct") { "No" } else { "Yes" }

    # Categorize roles
    $category = if ($_.DirectoryScopeId -eq "/") {
                    "Entra Built-in Roles"
                } elseif ($_.AppScopeId) {
                    "Azure Roles"
                } else {
                    "Group Roles"
                }

    [PSCustomObject]@{
        RoleName         = $_.RoleDefinition.DisplayName
        Description      = $_.RoleDefinition.Description
        ActivationLimit  = $activationLimit
        ApprovalRequired = $approvalRequired
        Category         = $category
    }
}

# Display roles sorted by category and name in GridView
$report | Sort-Object Category, RoleName | Out-GridView -Title "My Eligible Roles in Entra ID"
