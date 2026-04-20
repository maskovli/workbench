
## Create Tier level Groups, member groups only

    # Import the module
    Import-Module AzureADPreview

    # Connect to your Azure AD
    Connect-AzureAD -Credential $credential

    # List of Group Names
    $groupNames = @(

    'AZIC-AM-PIM-INT-AP-NORD-Infrastructure-TL1-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Infrastructure-TL2-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Infrastructure-TL3-Member',

    'AZIC-AM-PIM-INT-AP-NORD-Development-TL1-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Development-TL2-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Development-TL3-Member',

    'AZIC-AM-PIM-INT-AP-NORD-Security-TL1-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Security-TL2-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Security-TL3-Member',

    'AZIC-AM-PIM-INT-AP-NORD-UserSupport-TL1-Member',
    'AZIC-AM-PIM-INT-AP-NORD-UserSupport-TL2-Member',
    'AZIC-AM-PIM-INT-AP-NORD-UserSupport-TL3-Member',

    'AZIC-AM-PIM-INT-AP-NORD-Productivity-TL1-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Productivity-TL2-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Productivity-TL3-Member',

    'AZIC-AM-PIM-INT-AP-NORD-Compliance-TL1-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Compliance-TL2-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Compliance-TL3-Member',

    'AZIC-AM-PIM-INT-AP-NORD-Executives-TL1-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Executives-TL2-Member',
    'AZIC-AM-PIM-INT-AP-NORD-Executives-TL3-Member'

    )

    foreach($name in $groupNames) {
    # Create the group
    New-AzureADGroup -DisplayName $name -MailEnabled $false -SecurityEnabled $true -MailNickName "NotSet"
    }

```


## THis section creates the Tier Groups that has the ability to assign Roles:

```powershell
# Import the module
Import-Module AzureAD

# Connect to your Azure AD
$credential = Get-Credential
Connect-AzureAD -Credential $credential

# List of Group Names
$groupNames = @(

        'AZIC-AM-PIM-INT-AP-NORD-Infrastructure-TL1',
    'AZIC-AM-PIM-INT-AP-NORD-Infrastructure-TL2',
    'AZIC-AM-PIM-INT-AP-NORD-Infrastructure-TL3',

    'AZIC-AM-PIM-INT-AP-NORD-Development-TL1',
    'AZIC-AM-PIM-INT-AP-NORD-Development-TL2',
    'AZIC-AM-PIM-INT-AP-NORD-Development-TL3',

    'AZIC-AM-PIM-INT-AP-NORD-Security-TL1',
    'AZIC-AM-PIM-INT-AP-NORD-Security-TL2',
    'AZIC-AM-PIM-INT-AP-NORD-Security-TL3',

    'AZIC-AM-PIM-INT-AP-NORD-UserSupport-TL1',
    'AZIC-AM-PIM-INT-AP-NORD-UserSupport-TL2',
    'AZIC-AM-PIM-INT-AP-NORD-UserSupport-TL3',

    'AZIC-AM-PIM-INT-AP-NORD-Productivity-TL1',
    'AZIC-AM-PIM-INT-AP-NORD-Productivity-TL2',
    'AZIC-AM-PIM-INT-AP-NORD-Productivity-TL3',

    'AZIC-AM-PIM-INT-AP-NORD-Compliance-TL1',
    'AZIC-AM-PIM-INT-AP-NORD-Compliance-TL2',
    'AZIC-AM-PIM-INT-AP-NORD-Compliance-TL3',

    'AZIC-AM-PIM-INT-AP-NORD-Executives-TL1',
    'AZIC-AM-PIM-INT-AP-NORD-Executives-TL2',
    'AZIC-AM-PIM-INT-AP-NORD-Executives-TL3'

)

foreach($name in $groupNames) {
    # Create the group
    New-AzureADMSGroup -DisplayName $name -Description "$name Description" -MailEnabled $false -SecurityEnabled $true -MailNickName $name -IsAssignableToRole $true
}


## Create Azure IAM Groups, for management groups only

```powershell
# Import the module
Import-Module AzureAD

# Connect to your Azure AD
$credential = Get-Credential
Connect-AzureAD -Credential $credential

# List of Group Names
$groupNames = @(
  
    
'AZIC-AM-PIM-MG-NORD-Owner',
'AZIC-AM-PIM-MG-NORD-Contributor',
'AZIC-AM-PIM-MG-NORD-Reader',

'AZIC-AM-PIM-MG-NORD-DevTest-Owner',
'AZIC-AM-PIM-MG-NORD-DevTest-Contributor',
'AZIC-AM-PIM-MG-NORD-DevTest-Reader',

'AZIC-AM-PIM-MG-NORD-DevTest-Dev-Owner',
'AZIC-AM-PIM-MG-NORD-DevTest-Dev-Contributor',
'AZIC-AM-PIM-MG-NORD-DevTest-Dev-Reader',

'AZIC-AM-PIM-MG-NORD-DevTest-Dev-DevSub-Owner',
'AZIC-AM-PIM-MG-NORD-DevTest-Dev-DevSub-Contributor',
'AZIC-AM-PIM-MG-NORD-DevTest-Dev-DevSub-Reader',

'AZIC-AM-PIM-MG-NORD-Platform-Owner',
'AZIC-AM-PIM-MG-NORD-Platform-Contributor',
'AZIC-AM-PIM-MG-NORD-Platform-Reader',

'AZIC-AM-PIM-MG-NORD-Platform-Connectivity-Owner',
'AZIC-AM-PIM-MG-NORD-Platform-Connectivity-Contributor',
'AZIC-AM-PIM-MG-NORD-Platform-Connectivity-Reader',

'AZIC-AM-PIM-MG-NORD-Platform-Identity-Owner',
'AZIC-AM-PIM-MG-NORD-Platform-Identity-Contributor',
'AZIC-AM-PIM-MG-NORD-Platform-Identity-Reader',

'AZIC-AM-PIM-MG-NORD-Platform-Management-Owner',
'AZIC-AM-PIM-MG-NORD-Platform-Management-Contributor',
'AZIC-AM-PIM-MG-NORD-Platform-Management-Reader',

'AZIC-AM-PIM-MG-NORD-Production-Owner',
'AZIC-AM-PIM-MG-NORD-Production-Contributor',
'AZIC-AM-PIM-MG-NORD-Production-Reader'

)

foreach($name in $groupNames) {
    # Create the group
    New-AzureADMSGroup -DisplayName $name -Description "$name Description" -MailEnabled $false -SecurityEnabled $true -MailNickName $name -GroupTypes "Unified" -IsAssignableToRole $true
}