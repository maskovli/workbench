# Import Partner Center module
Install-Module PartnerCenter -force -Verbose
Install-Module WindowsAutopilotPartnerCenter -force -Verbose

# Authenticate to Partner Center
Connect-PartnerCenter

# Specify the customer Id, group Tag and csv-path.
$customerId = "TENANT ID"
$GroupTag = "GROUP TAG"
$CSVPath = "C:\Temp\Upload.csv"

# Read the CSV file with serial numbers and models
$deviceList = Import-Csv -Path $CSVPath

# Loop through each device
foreach ($device in $deviceList) {

    # Upload the device to the autopilot profile
    Import-AutoPilotPartnerCenterCSV -csvFile $CSVPath -CustomerId $customerId -BatchID $GroupTag -Verbose

    }


# Import Partner Center module
Install-Module PartnerCenter -Force -Verbose
Install-Module WindowsAutopilotPartnerCenter -Force -Verbose

# Authenticate to Partner Center
Connect-PartnerCenter

# Prompt for customer ID and group Tag
$customerId = Read-Host -Prompt "Enter the customer Id"
$groupTag = Read-Host -Prompt "Enter the group Tag"

# Prompt for the CSV path or if they want to manually input device info
$choice = Read-Host -Prompt "Enter '1' to upload via CSV or '2' to manually enter device information"

if ($choice -eq '1') {
    $CSVPath = Read-Host -Prompt "Enter the path to the CSV file"

    # Read the CSV file with serial numbers and models
    $deviceList = Import-Csv -Path $CSVPath

    # Loop through each device
    foreach ($device in $deviceList) {
        # Assuming the CSV has columns for SerialNumber, Make, and Model
        # Upload the device to the autopilot profile
        Import-AutoPilotPartnerCenterCSV -csvFile $CSVPath -CustomerId $customerId -BatchID $groupTag
    }
} elseif ($choice -eq '2') {
    $serialNumber = Read-Host -Prompt "Enter the device's Serial Number"
    $make = Read-Host -Prompt "Enter the device's Make"
    $model = Read-Host -Prompt "Enter the device's Model"

    # Since there's no native cmdlet shown for a single device upload, assuming a hypothetical function or cmdlet
    # Replace 'Upload-DeviceToAutoPilotProfile' with the actual cmdlet or function to upload a single device
    Upload-DeviceToAutoPilotProfile -SerialNumber $serialNumber -Make $make -Model $model -CustomerId $customerId -GroupTag $groupTag
} else {
    Write-Host "Invalid choice entered. Exiting script."
}
