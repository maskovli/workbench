# Connect to your Azure AD tenant
Connect-AzureAD

# Retrieve all Azure AD roles
$roles = Get-AzureADDirectoryRole | Where-Object { $_.DisplayName -ne "Company Administrator" }

# Loop through the roles and display their information
foreach ($role in $roles) {
    Write-Host "Role Name: $($role.DisplayName)"
    Write-Host "Role Description: $($role.Description)"
    Write-Host "Role Object ID: $($role.ObjectId)"
    Write-Host ""
}