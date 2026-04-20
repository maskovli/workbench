Connect-MgGraph -Scopes "Group.ReadWrite.All, PrivilegedAccess.ReadWrite.AzureAD, PrivilegedAccess.ReadWrite.AzureADGroup, PrivilegedAccess.ReadWrite.AzureResources, RoleManagement.ReadWrite.Directory, Policy.ReadWrite.AccessReview"

# Define the base name
$baseName = "AZIC-NU-PIM-AM-Infrastructure"

# Define the tiers
$tiers = 0..3

# Create the groups for each tier
foreach ($tier in $tiers) {
    $rgroupName = "$baseName-TL$tier"

    # Parameters for the resource group
    $groupParams = @{
        DisplayName = $rgroupName
        Description = $rgroupName
        MailNickname = $rgroupName
        SecurityEnabled = $true
        MailEnabled = $false
        IsAssignableToRole = $true
        
    }

    # Create the resource group
    New-MgGroup -BodyParameter $groupParams

    }


    foreach ($tier in $tiers) {
    $memberGroupName = "$baseName-TL$tier-Member" 

    # Parameters for the requestor group
    $memberGroupParams = @{
        DisplayName = $memberGroupName
        Description = $memberGroupName
        MailNickname = $memberGroupName
        SecurityEnabled = $true
        MailEnabled = $false
    }

    # Create the requestor group
    New-MgGroup -BodyParameter $memberGroupParams
}

