# Install the Microsoft Graph PowerShell Module (if not already installed)
# Uncomment the line below if you haven't installed the module yet
# Install-Module Microsoft.Graph.Identity.Governance -AllowClobber -Scope CurrentUser -Force

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "EntitlementManagement.ReadWrite.All", "EntitlementMgmt-SubjectAccess.ReadWrite"

# Define the catalogs with their names and descriptions
$catalogsToCreate = @(
    @{Name = "NU-PIM-Infrastructure"; Description = "Description: Manages and governs access to critical infrastructure resources and tools. Ensures seamless and secure operations of foundational IT systems."},
    @{Name = "NU-PIM-Security"; Description = "Description: Focuses on cybersecurity and access to security-related tools and resources. Provides monitoring and protective measures against potential threats."},
    @{Name = "NU-PIM-UserSupport"; Description = "Description: Dedicated to user assistance and IT support. Manages tools and resources related to helpdesk, ticketing, and user assistance operations."},
    @{Name = "NU-PIM-Development"; Description = "Description: Overviews access for developers and associated tools. Ensures secure coding practices and manages developer permissions and tools."},
    @{Name = "NU-PIM-Productivity"; Description = "Description: Facilitates access to productivity tools and software. Encompasses office suite tools, collaboration software, and other user-centric applications."},
    @{Name = "NU-PIM-Compliance"; Description = "Description: Manages access to resources related to IT compliance, legal requirements, and regulatory mandates. Ensures the organization meets its statutory obligations."},
    @{Name = "NU-PIM-Executives"; Description = "Description: A specialized catalog for high-level management. Ensures secure and prioritized access to essential executive resources and tools."}
)

# Loop through and create each catalog
foreach ($catalog in $catalogsToCreate) {
    New-MgEntitlementManagementCatalog -DisplayName $catalog.Name -Description $catalog.Description -verbose
}