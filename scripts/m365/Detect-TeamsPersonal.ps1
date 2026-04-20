<#
.SYNOPSIS
    Detection script for Microsoft Teams Personal installation using AppX commands.

.DESCRIPTION
    This script checks whether Microsoft Teams Personal is installed on a Windows 11 device
    by searching for the MicrosoftTeams AppX package across all user profiles. It returns a
    non-zero exit code if the package is detected, indicating non-compliance.

.AUTHOR
    Marius A. Skovli
    Spirhed Group
    https://spirhed.com

.DATE
    2024-10-9

.VERSION
    1.1

#>

# Function to check if Microsoft Teams Personal is installed
try {
 
    $TeamsApp = Get-AppxPackage "*Teams*" -AllUsers  -ErrorAction SilentlyContinue
    if ($TeamsApp.Name -eq "MicrosoftTeams")
        {
            Write-Host "Built-in Teams Chat App Detected"
            Exit 1
        }
    ELSE
        {
            Write-Host "Built-in Teams Chat App Not Detected"
            Exit  0
               }
}
catch {
    $errMsg = $_.Exception.Message
    return $errMsg
    Exit 1
}