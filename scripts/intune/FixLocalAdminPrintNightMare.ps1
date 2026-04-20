# PowerShell script to set the RestrictDriverInstallationToAdministrators value to 0

# Define the base registry path and value information
$registryPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Printers"
$keyName = "PointAndPrint"
$valueName = "RestrictDriverInstallationToAdministrators"
$valueData = 0

# Ensure the parent registry key exists
if (-not (Test-Path -Path $registryPath)) {
    # Create the parent registry key if it doesn't exist
    New-Item -Path $registryPath -Force | Out-Null
}

# Ensure the PointAndPrint subkey exists
if (-not (Test-Path -Path "$registryPath\$keyName")) {
    New-Item -Path "$registryPath" -Name $keyName -Force | Out-Null
}

# Set the registry value
Set-ItemProperty -Path "$registryPath\$keyName" -Name $valueName -Type DWord -Value $valueData

Write-Host "Successfully set $valueName to $valueData in $registryPath\$keyName."
