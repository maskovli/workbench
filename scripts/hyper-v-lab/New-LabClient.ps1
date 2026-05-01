<#	
	.NOTES
	===========================================================================
	 Created on:   	13.05.2019
	 Created by:   	Marius A. Skovli
	 Filename:     	
	===========================================================================
	.DESCRIPTION
        Run script section by section.
        TIP: Add the autounattend.xml to the ISO in order to automate the process entierly. 
#>

# Define variables
$LabVMName = "TB-CLIENT-01"
$LabVMPath = "C:\VMs\$LabVMName"
$Time = Get-Date
$ISO = "C:\VMS\iso\en-us_windows_10_business_editions_version_22h2_updated_june_2023_x64_dvd_ac6658bf.iso"
$Switch = "Default Switch"

# Create the VM
try {
    New-VM -Name $LabVMName -MemoryStartupBytes 4GB -BootDevice VHD -NewVHDPath "$LabVMPath\Virtual Hard Disks\$LabVMName.vhdx" -Path "C:\VMs\$LabVMName\Virtual Machines" -NewVHDSizeBytes 80GB -Generation 2 -Switch "Default switch" -Verbose
    Set-VM -Name $LabVMName -ProcessorCount 4 -AutomaticCheckpointsEnabled $False -SnapshotFileLocation "$LabVMPath\Snapshots" -Verbose
    Add-VMDvdDrive -Path $ISO -VMName $LabVMName -Verbose
    Get-VMNetworkAdapter -VMName $LabVMName | Connect-VMNetworkAdapter -SwitchName $Switch
} catch {
    Write-Error "Error creating VM: $_"
    exit 1
}

# Enable security features and other settings
try {
    Set-VMKeyProtector -VMName $LabVMName -NewLocalKeyProtector -Verbose
    Enable-VMTPM -VMName $LabVMName -Verbose
} catch {
    Write-Error "Error enabling security features: $_"
    exit 1
}

# Set boot order to DVD drive
try {
    $vmFirmware = Get-VMFirmware $LabVMName
    $bootOrder = $vmFirmware.BootOrder
    $hddrive = $bootOrder[0]
    $pxe = $bootOrder[1]
    $dvddrive = $bootOrder[2]
    Set-VMFirmware -VMName $LabVMName -BootOrder $dvddrive,$hddrive,$pxe -Verbose
} catch {
    Write-Error "Error setting boot order: $_"
    exit 1
}

# Start the VM and connect to the console
try {
    vmconnect.exe localhost $LabVMName
    Start-VM -VMName $LabVMName -Verbose
} catch {
    Write-Error "Error starting VM: $_"
    exit 1
}

#Checkpoint-VM -VMName $LabVMName -SnapshotName "$LabVMName-$Time"