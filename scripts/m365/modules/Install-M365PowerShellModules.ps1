<#
.SYNOPSIS
Installs PowerShell modules for Microsoft 365 services.

.DESCRIPTION
This script installs PowerShell modules for Microsoft 365 services, including Microsoft Defender for Endpoint, Defender for Office, Defender for Apps, Graph API, Intune, Azure AD, Exchange Online, Teams, PowerApps, and Office.

.PARAMETER Services
A comma-separated list of Microsoft 365 services to install PowerShell modules for.

.PARAMETER Verbose
Indicates that verbose output should be displayed.

.EXAMPLE
Install-M365Modules.ps1 -Services "Defender for Endpoint, Intune, Azure AD" -Verbose

This example installs PowerShell modules for Defender for Endpoint, Intune, and Azure AD, and displays verbose output.

.NOTES
Author: ChatGPT
Date: 2023-04-03
#>


# Define an array of services to install
$services = @(
    "Office"
    "Graph API"
    "Intune"
    "Azure AD"
    "Exchange Online"
    "Teams"
    "PowerApps"
    "SharePoint Online"
    "Identity"
)

# Loop through the array and install the corresponding PowerShell module
foreach ($service in $services) {
    Write-Host "Installing PowerShell module for $service..."

    switch ($service) {
        "Office" {
            Install-Module -Name MSCommerce -Scope AllUsers -Force -Verbose
        }
        "Graph API" {
            Install-Module -Name Microsoft.Graph -Scope AllUsers -Force -Verbose
        }
        "Intune" {
            Install-Module -Name Microsoft.Graph.Intune -Scope AllUsers -Force -Verbose
        }
        "Azure AD" {
            Install-Module -Name AzureAD -Scope AllUsers -AllowClobber -Force -Verbose
        }
        "Exchange Online" {
            Install-Module -Name ExchangeOnlineManagement -Scope AllUsers -Force -Verbose
        }
        "Teams" {
            Install-Module -Name MicrosoftTeams -Scope AllUsers -Force -Verbose
        }
        "PowerApps" {
            Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope AllUsers -Force -Verbose
        }
        "SharePoint Online" {
            Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Scope AllUsers -Force -Verbose
}
        "Identity" {
            Install-Module -Name Microsoft.Graph.Identity.Authentication -Scope AllUsers -Force -Verbose            
        }
        default {
            Write-Warning "No PowerShell module available for $service."
        }
    }
}

# Output a message when installation is complete
Write-Host "PowerShell module installation complete."
