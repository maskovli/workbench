<#
    .NOTES
    ===========================================================================
     Created on:       26.11.2019
     Created by:       Marius A. Skovli
     Filename:         UninstallAppsWithWMI.ps1
    ===========================================================================
    .DESCRIPTION
        This Script will search for the software defined as ProductName in the 
        SMS_InstalledSoftware WMI Class store it in a variable ($Product) and uninstall
        the software. In this Example Java has been Used. 
#>

#-----------------
#Define Variables
#-----------------
$Software = "Java"
 
#-----------------
#Search software
#-----------------
$Product = Get-WmiObject -class SMS_InstalledSoftware -Namespace "root\cimv2\sms" | 
Where-Object {$PSItem.ProductName -like "*$Software*"}
 
#-----------------
#Uninstall software
#-----------------
 
    ForEach ($ObjItem in $Product) 
    {
 
    #-----------------
    #Define Variables
    #-----------------
    $ID = $ObjItem.SoftwareCode
    $SoftwareName = $ObjItem.ProductName
 
        #-----------------
        #Uninstall 
        #-----------------
        $Uninstall = "/x" + "$ID /qn" 
        $SP = (Start-Process -FilePath "msiexec.exe" $Uninstall -Wait -Passthru).ExitCode
 
    Write-Output "Uninstalled $SoftwareName"
    }
 
Write-Output "Done!"