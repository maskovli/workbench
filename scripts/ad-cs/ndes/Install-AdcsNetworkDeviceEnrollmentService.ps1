<#	
	.NOTES
	===========================================================================
	 Created on:   	20.05.2019
	 Created by:   	Marius A. Skovli
	 Filename:     	
	===========================================================================
	.DESCRIPTION
        Change the variables to fit your need.
        This will Install NDES. 
#>



#Run this Section first:
Install-WindowsFeature ADCS-Device-Enrollment,
Web-Server,
Web-WebServer,
Web-Common-Http,
Web-Default-Doc,
Web-Dir-Browsing,
Web-Http-Errors,
Web-Static-Content,
Web-Http-Redirect,
Web-Http-Logging,
Web-Log-Libraries,
Web-Request-Monitor,
Web-Http-Tracing,
Web-Stat-Compression,
Web-Filtering,
Web-Windows-Auth,
Web-Net-Ext,
Web-Net-Ext45,
Web-Asp-Net,
Web-Asp-Net45,
Web-ISAPI-Ext,
Web-ISAPI-Filter,
Web-Mgmt-Console,
Web-Mgmt-Compat,
Web-Lgcy-Scripting,
Web-Metabase,
Web-WMI,
NET-HTTP-Activation,
NET-WCF-HTTP-Activation45 -Verbose 

#Run this section next:

$ServiceAccount = "Domain\ServiceAccount"
$IssuingCA = "Domain\IssuingCA"
$RAName = "SERVERNAME-MSCEP-RA"
$CompanyName = "COMPANAYNAME"


Install-AdcsNetworkDeviceEnrollmentService -ServiceAccountName $ServiceAccount -ServiceAccountPassword (read-host "Set user password" -assecurestring) -CAConfig $IssuingCA 
-RAName $RAName -RACountry "NO" -RACompany $CompanyName -SigningProviderName "Microsoft Strong Cryptographic Provider" -SigningKeyLength 2048 
-EncryptionProviderName "Microsoft Strong Cryptographic Provider" -EncryptionKeyLength 2048