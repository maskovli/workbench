# Get a list of all installed PowerShell modules
$modules = Get-Module -ListAvailable

# Iterate through each module and uninstall it
foreach ($module in $modules) {
    $moduleName = $module.Name
    Write-Host "Removing module: $moduleName"
    Uninstall-Module -Name $moduleName -Force
}

# Remove any remaining module files and folders
$modulePaths = $env:PSModulePath -split ';'
foreach ($modulePath in $modulePaths) {
    if (Test-Path $modulePath) {
        $moduleFiles = Get-ChildItem -Path $modulePath -Include *.psd1, *.dll, *.exe -Recurse
        if ($moduleFiles.Count -eq 0) {
            Write-Host "Removing empty module path: $modulePath"
            Remove-Item -Path $modulePath -Force -Recurse
        }
    }
}

Write-Host "Module cleanup completed."
