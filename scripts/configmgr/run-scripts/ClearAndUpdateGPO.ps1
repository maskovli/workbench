<#
Clear GPO Cache and Update policy
Created: 20.03.2020
Last Modified: 20.03.2020
#>

<#
ConfigMgr: Run Script
#>

$Verify = (Get-ItemProperty C:\System\GPOCheck.txt).Name
if($Verify -eq 'GPOCheck.txt')
    {Write-host 'Compliant'}
    else
    {
    Remove-Item -Path "C:\Windows\System32\GroupPolicyUsers" -Recurse -Force -Verbose
    GPUPDATE /force
    New-Item -Path C:\System -Name GPOCheck.txt -ItemType File -Force
    }