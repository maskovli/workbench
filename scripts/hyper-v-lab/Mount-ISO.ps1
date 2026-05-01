
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


#1
$ISO = "C:\LAb\Image\ISO\Windows\Win10_1909\en_windows_10_business_editions_version_1909_x64_dvd_ada535d0.iso"
$ISOPath = "C:\LAb\Image\ISO\Windows\Win10_1909"
$Time = Get-Date
$MountDirLocation = "C:\Lab\Image"
$UnattedFile = "C:\Lab\Image\ISO\Windows\autounattend.xml"
New-Item -path $MountDirLocation -Name "MointPoint" -ItemType "Directory"
$MountDir = "$MountDirLocation\MointPoint"
Mount-DiskImage -ImagePath $ISO


#2
$DiskImage = "D:\"
Copy-Item "$DiskImage\*" -Recurse -Destination "$MountDir" -Verbose -Force
Copy-Item $UnattedFile -Recurse -Destination "$MountDir" -Verbose -Force

#3
powershell.exe "C:\LAB\Scripts\_PowerShell\New-ISO.ps1"
Get-ChildItem $ISOPath\Win10_Custom.iso | Remove-Item -Force -Verbose
get-childitem "$MountDir" | New-ISOFile -path $ISOPath\Win10_Custom.iso -BootFile "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\efisys.bin" -Title "Custom Win10"

<#4
Dismount-DiskImage -ImagePath $ISO
Remove-Item $MountDir -Force
#>