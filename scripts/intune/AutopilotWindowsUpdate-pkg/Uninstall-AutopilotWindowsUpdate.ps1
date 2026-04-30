#Requires -Version 5.1
<#
.SYNOPSIS
    Avinstallasjon — fjerner deteksjonsnøkkelen slik at Win32-appen kan reinstalleres.
#>

$regKey = 'HKLM:\SOFTWARE\AutopilotWindowsUpdate'

if (Test-Path $regKey) {
    Remove-Item -Path $regKey -Recurse -Force
}
exit 0
