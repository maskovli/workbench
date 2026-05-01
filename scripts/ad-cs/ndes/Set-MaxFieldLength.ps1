$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters"
$Name = "MaxFieldLength"
$value = "65534"
New-ItemProperty -Path $registryPath -Name $name -Value $value `
 -PropertyType DWORD -Force | Out-Null
