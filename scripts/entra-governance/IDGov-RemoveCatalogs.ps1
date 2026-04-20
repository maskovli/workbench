$catalogsToDelete = Get-MgEntitlementManagementCatalog | Where-Object { $_.DisplayName -like 'Catalog*' }

foreach ($catalog in $catalogsToDelete) {
    if ($catalog.Id) {
        Remove-MgEntitlementManagementCatalog -AccessPackageCatalogId $catalog.Id -Confirm:$false -verbose
        Write-Host "Removed catalog with ID: $($catalog.Id) and Name: $($catalog.DisplayName)"
    } else {
        Write-Host "Skipped catalog with Name: $($catalog.DisplayName) due to missing ID"
    }
}
