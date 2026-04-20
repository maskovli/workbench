1.  Create new VMP Operation role

## 1.1. Contents

- [1.1. Contents](#11-contents)
- [1.2. Description](#12-description)
- [1.3. Groups](#13-groups)

## 1.2. Description

Vinmonpolet has

## 1.3. Groups

```powershell
    # Import the module
    Import-Module AzureAD

    # Connect to your Azure AD
    Connect-AzureAD -Credential $credential

    # List of Group Names
    $groupNames = @(
    'AZIC-AM-PIM-MG-VMP-Owner',
    'AZIC-AM-PIM-MG-VMP-Contributor',
    'AZIC-AM-PIM-MG-VMP-Reader'
    )

    foreach($name in $groupNames) {
    # Create the group
    New-AzureADGroup -DisplayName $name -MailEnabled $false -SecurityEnabled $true -MailNickName "NotSet"
    }

```
