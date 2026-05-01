<#  
    .NOTES 
    =========================================================================== 
    Created on:    28.09.2020 09.31 
    Created by:    Marius A. Skovli
    Filename:      CreateBoundaries.
    =========================================================================== 
    .DESCRIPTION 
    Creates boundaries in SCCM Based on DHCP Scope. 
#>

#----
# On DHCP Server run this to get CSV File:
# Get-DhcpServerv4Scope | select Name,StartRange,Endrange | Export-Csv C:\DhcpServerv4Scope.csv
#----

# Import Module
Import-Module $env:SMS_ADMIN_UI_PATH.Replace("\bin\i386","\bin\configurationmanager.psd1")$SiteCode = Get-PSDrive -PSProvider CMSITESet-Location "CAS:\"# Import Boundaries from CSV file$Boundaries = Import-Csv `    -Path "D:\Tools\CreateBoundaries\DhcpServerv4Scope.csv"$SiteCode = Get-PSDrive -PSProvider CMSITESet-Location "$($SiteCode.Name):\"foreach($Boundary in $Boundaries){    Write-Output -InputObject "Creating $($Boundary.Name)"        #Create the Boundary    New-CMBoundary `        -Name $Boundary.Name `        -Type IPRange `        -Value "$($Boundary.'StartRange')-$($Boundary.'EndRange')" |             Out-Null}