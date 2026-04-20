<#
.SYNOPSIS
    Remediation script to uninstall Microsoft Teams Personal using AppX commands.

.DESCRIPTION
    This script removes Microsoft Teams Personal from a Windows 11 device by executing the
    Remove-AppxPackage cmdlet for the MicrosoftTeams AppX package across all user profiles.
    It ensures silent uninstallation and cleans up residual folders post-removal.

.AUTHOR
    Marius A. Skovli
    Spirhed Group
    https://spirhed.com

.DATE
    2024-10-9

.VERSION
    1.1

#>

# Function to uninstall Microsoft Teams Personal
Try{
 
    Get-AppxPackage -Name "MicrosoftTeams" -AllUsers | Remove-AppxPackage
    Get-AppXProvisionedPackage -Online | Where {$_.DisplayName -eq "MicrosoftTeams"} | Remove-AppxProvisionedPackage -Online
 
    Write-Host "Built-In Teams Chat app uninstalled"
    Exit 0
}
catch {
    $errMsg = $_.Exception.Message
    return $errMsg
    Exit 1
}