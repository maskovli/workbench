Connect-MgGraph -Scopes "Group.ReadWrite.All, PrivilegedAccess.ReadWrite.AzureAD, PrivilegedAccess.ReadWrite.AzureADGroup, PrivilegedAccess.ReadWrite.AzureResources, RoleManagement.ReadWrite.Directory"

# Define the base name
$approvegroupName = "AZIC-NU-PIM-AM-Approvers"

    # Parameters for the resource group
    $approvegroupParams = @{
        DisplayName = $approvegroupName
        Description = $approvegroupName
        MailNickname = $approvegroupName
        SecurityEnabled = $true
        MailEnabled = $false
        
    }

    # Create the resource group
    New-MgGroup -BodyParameter $approvegroupParams


# Define the base name
$reviewgroupName = "AZIC-NU-PIM-AM-Reviewers"

    # Parameters for the resource group
    $reivewgroupParams = @{
        DisplayName = $reviewgroupName
        Description = $reviewgroupName
        MailNickname = $reviewgroupName
        SecurityEnabled = $true
        MailEnabled = $false
        
    }

    # Create the resource group
    New-MgGroup -BodyParameter $reivewgroupParams