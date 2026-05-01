<#
Disbles Autoupdate in Aodbe Reader DC
Created: 20.03.2020
Last Modified: 20.03.2020
#>


New-ItemProperty -path 'HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown' -Name bUpdater -Value 0 -PropertyType "DWORD" -Verbose
Set-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Adobe\Adobe ARM\Legacy\Reader\{AC76BA86-7AD7-1033-7B44-AC0F074E4100}' -Name "Mode" -Value 0 -Verbose

$StartType = (Get-Service AdobeARMservice).StartType
if($StartType -eq 'Disabled')
    {Write-host 'Compliant'}
    else
    {get-service AdobeARMservice | Set-Service -StartupType Disabled -verbose}
  
$Status = (Get-Service AdobeARMservice).Status
if($Status -eq 'Stopped')
    {Write-host 'Compliant'}
    else
    {Stop-service -Name 'AdobeARMservice' -Force -Verbose}