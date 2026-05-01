$registryPath = "HKLM:\Software\Microsoft\Cryptography\MSCEP"
$Name = "GeneralPurposeTemplate"
$value = "NDESClientCertificate"
Set-ItemProperty -Path $registryPath -Name $name -Value $value | Out-Null