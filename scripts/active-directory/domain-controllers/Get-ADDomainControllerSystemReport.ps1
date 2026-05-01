# Import Active Directory module
Import-Module ActiveDirectory

# Specify the domain controller
$DCName = 'DC01'

# Get the domain controller
$DC = Get-ADDomainController -Identity $DCName

# Get the system information
$systemInfo = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $DC.Hostname

# Get the operating system information
$osInfo = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $DC.Hostname

# Get network adapter configuration
$netInfo = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $DC.Hostname | Where-Object { $_.IPAddress -ne $null }

# Get roles
$roles = (Get-WmiObject -Class Win32_ServerFeature -ComputerName $DC.Hostname).Name

# Check if machine is physical or virtual
if ($systemInfo.Model -like "*Virtual*") {
    $machineType = "Virtual"
}
else {
    $machineType = "Physical"
}

# Create a PSObject for this DC
$properties = @{
    'Name' = $DC.Hostname
    'MachineType' = $machineType
    'OperatingSystem' = $osInfo.Caption
    'OperatingSystemVersion' = $osInfo.Version
    'Roles' = $roles -join ', '
    'CPU' = $systemInfo.NumberOfLogicalProcessors
    'MemoryGB' = [math]::Round($systemInfo.TotalPhysicalMemory / 1GB, 2)
    'IPAddress' = $netInfo.IPAddress -join ', '
    'DNSAddress' = $netInfo.DNSServerSearchOrder -join ', '
}

$result = New-Object PSObject -Property $properties

# Output the result in table format
$result | Format-Table -AutoSize
