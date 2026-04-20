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


#Shift + F10 To open CMD
#type powrshell ise--> enter
#run the following:
PowerShell.exe Set-ExecutionPolicy -ExecutionPolicy Bypass -Force -Verbose
PowerShell.exe Find-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies -verbose
PowerShell.exe Install-Script -Name Get-WindowsAutopilotInfo -Force -Verbose
PowerShell.exe -file "C:\Program Files\WindowsPowerShell\Scripts\Get-WindowsAutoPilotInfo.ps1" -Online -Verbose