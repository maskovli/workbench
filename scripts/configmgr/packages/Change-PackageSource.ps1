<#	
	.NOTES
	===========================================================================
	 Created on:   	20.08.2019 00.05
	 Created by:   	Marius A. Skovli
	 Organization: 	Coretech
	 Filename:     	
	===========================================================================
	.DESCRIPTION
        Changes the Source folder for packages in ConfigMgr. 
#>
Import-Module $env:SMS_ADMIN_UI_PATH.Replace("\bin\i386","\bin\configurationmanager.psd1")$SiteCode = Get-PSDrive -PSProvider CMSITESet-Location "$($SiteCode.Name):\"
 

    $Packages = Get-CMPackage 
    $OldPath = "\CMSRV01\SCCMSource$\SD\Packages\Physical.Packages"
    $NewPath = "\CMSRV02\source$\sd\packages" 

ForEach ($Package in $Packages) 
 { 
 $ChangePath = $Package.PkgSourcePath.Replace($OldPath, $NewPath) 
 Set-CMPackage -Name $Package.Name -Path $ChangePath 
 Write-Host $Package.Name ” has been changed to ” $ChangePath 
 }
