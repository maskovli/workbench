# Connect to Microsoft G
Connect-MgBetaGraph -Scopes "Group.ReadWrite.All, PrivilegedAccess.ReadWrite.AzureAD, PrivilegedAccess.ReadWrite.AzureADGroup, PrivilegedAccess.ReadWrite.AzureResources, RoleManagement.ReadWrite.Directory, EntitlementManagement.ReadWrite.All, EntitlementMgmt-SubjectAccess.ReadWrite"
Install-Module Microsoft.Graph.Beta -AllowClobber -Force

Connect-MgBetaGraph -Scopes 'EntitlementManagement.ReadWrite.All'
Import-Module Microsoft.Graph.Beta.Identity.Governance

# Defined Catalogs
$catalogs = @('NU-PIM-Infrastructure')

# Reviewers and Approvers groups
$reviewersGroup = 'SH-PIM-Reviewers'
$approversGroup = 'SH-PIM-Approvers'

# Life cycle for each tier
$lifecycle = @{
    TL0 = 365
    TL1 = 180
    TL2 = 90
    TL3 = 30
}

# Loop through each catalog and create access packages for each tier
foreach ($catalog in $catalogs) {
    for ($tier = 3; $tier -ge 0; $tier--) {
        $tierName = "TL$tier"
        
        $params = @{
            accessPackageId = "${catalog}-${tierName}"  # Assuming this format for IDs
            displayName = "$catalog $tierName"
            description = "$catalog $tierName Access Package"
            canExtend = $false
            durationInDays = $lifecycle[$tierName]
            expirationDateTime = $null
            requestorSettings = @{
                scopeType = "SpecificDirectorySubjects"
                acceptRequests = $true
                allowedRequestors = @("${catalog}-${tierName}-Member")
            }
            requestApprovalSettings = @{
                isApprovalRequired = $true
                isApprovalRequiredForExtension = $true
                isRequestorJustificationRequired = $true
                approvalMode = "Everyone"
                approvalStages = @(
                    @{
                        approvalStageTimeOutInDays = 14
                        isApproverJustificationRequired = $true
                        isEscalationEnabled = $true
                        escalationTimeInMinutes = 11520
                        primaryApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.groupMembers"
                                isBackup = $true
                                id = "${catalog}-${tierName}"  # Assuming this format for group IDs
                                description = "group for users from connected organizations which have no external sponsor"
                            }
                            @{
                                "@odata.type" = "#microsoft.graph.externalSponsors"
                                isBackup = $false
                            }
                        )
                        escalationApprovers = @(
                            @{
                                "@odata.type" = "#microsoft.graph.singleUser"
                                isBackup = $true
                                id = "backup-identifier"  # You'll need to replace this with the correct ID
                                description = "user if the external sponsor does not respond"
                            }
                        )
                    }
                )
            }
            accessReviewSettings = @{
                isEnabled = $true
                recurrenceType = "quarterly"
                reviewerType = "Self"
                startDateTime = [System.DateTime]::UtcNow.AddDays(-1).ToString("o")  # Setting to the previous day to make sure it's always in the past
                durationInDays = 25
                reviewers = @($reviewersGroup)
            }
        }

        New-MgBetaEntitlementManagementAccessPackageAssignmentPolicy -BodyParameter $params
    }
}
