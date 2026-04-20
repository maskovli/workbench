$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection\DeviceTagging'
$Name         = 'Group'
$Value        = 'FOCO-PC'
New-Item -Path $RegistryPath
New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType STRING -Force