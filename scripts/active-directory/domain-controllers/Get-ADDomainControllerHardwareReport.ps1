# Define an array to hold the DC hardware information
$dcHardware = @()

# Get the list of domain controllers
$domainControllers = Get-ADDomainController -Filter *

# Iterate through each domain controller
foreach ($dc in $domainControllers) {
    $dcName = $dc.HostName

    # Get hardware information using WMI
    $hardwareInfo = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $dcName

    # Extract relevant hardware details
    $cpuCores = (Get-WmiObject -Class Win32_Processor -ComputerName $dcName | Measure-Object -Property NumberOfCores -Sum).Sum
    $memory = "{0:N2} GB" -f ($hardwareInfo.TotalPhysicalMemory / 1GB)
    $drives = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $dcName | Select-Object -ExpandProperty DeviceID
    $make = $hardwareInfo.Manufacturer
    $model = $hardwareInfo.Model

    # Create a custom PSObject for each DC's hardware information
    $dcHardwareInfo = [PSCustomObject]@{
        'DC Name' = $dcName
        'CPU Cores' = $cpuCores
        'Memory' = $memory
        'Drives' = ($drives -join ", ")
        'Make' = $make
        'Model' = $model
    }

    # Add the DC hardware info to the array
    $dcHardware += $dcHardwareInfo
}

# Output the DC hardware information in markdown table format
"|DC Name|CPU Cores|Memory|Drives|Make|Model|"
"|-------|---------|------|------|----|-----|"
foreach ($dc in $dcHardware) {
    "|$($dc.'DC Name')|$($dc.'CPU Cores')|$($dc.Memory)|$($dc.Drives)|$($dc.Make)|$($dc.Model)|"
}
