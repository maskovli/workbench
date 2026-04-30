#Requires -Version 5.1
<#
.SYNOPSIS
    Deteksjonsskript for AutopilotWindowsUpdate Win32-app.
.NOTES
    Brukes som "Custom script" i Intune-deteksjonsregelen.
    Returnerer exit 0 + output dersom Status = "Completed" i registeret.
#>

$regKey = 'HKLM:\SOFTWARE\AutopilotWindowsUpdate'
$prop   = 'Status'

try {
    $val = Get-ItemPropertyValue -Path $regKey -Name $prop -ErrorAction Stop
    if ($val -eq 'Completed') {
        Write-Output "Detected: $val"
        exit 0
    }
    exit 1
}
catch {
    exit 1
}
