## THis section creates the Tier Groups that has the ability to assign Roles:


# Import the module
#Import-Module AzureADPreview

# Connect to your Azure AD
#Connect-AzureAD

# List of Group Names
$groupNames = @(
    
    'SPV-AZIC-AM-PIM-INT-AP-DigitalArbeidsflate-TL0',
    'SPV-AZIC-AM-PIM-INT-AP-DigitalArbeidsflate-TL1',
    'SPV-AZIC-AM-PIM-INT-AP-DigitalArbeidsflate-TL2',
    'SPV-AZIC-AM-PIM-INT-AP-DigitalArbeidsflate-TL3'
    

)

foreach($name in $groupNames) {
    # Create the group
    New-AzureADMSGroup -DisplayName $name -Description "$name Description" -MailEnabled $false -SecurityEnabled $true -MailNickname $Name -IsAssignableToRole $true
}