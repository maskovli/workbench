# Check if Global Secure Access client is installed
$GSAClient = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Global Secure Access*" }

# Check if the service related to GSA is running (example, replace with actual service name if needed)
$GSAService = Get-Service -Name "GSAClientService" -ErrorAction SilentlyContinue

$hash = @{
    GSAClientInstalled = $GSAClient -ne $null
    GSAServiceRunning = $GSAService.Status -eq "Running"
}

# Return the results as JSON
return $hash | ConvertTo-Json -Compress