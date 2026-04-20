# Sets HKLM\SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowYourAccount value=0 (DWORD)
# Kjør som SYSTEM og i 64-bit PowerShell (Intune: "Run script in 64-bit PowerShell" = Yes)

$ErrorActionPreference = 'Stop'

$regSubPath = 'SOFTWARE\Microsoft\PolicyManager\default\Settings\AllowYourAccount'
$regName    = 'value'
$regData    = 0
$changed    = $false

# Åpne 64-bit registry view eksplisitt
$base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    [Microsoft.Win32.RegistryView]::Registry64
)

$key = $base.OpenSubKey($regSubPath, $true)
if (-not $key) { $key = $base.CreateSubKey($regSubPath) }

$current = $key.GetValue($regName, $null, 'DoNotExpandEnvironmentNames')

if ($null -eq $current -or $current -ne $regData) {
    $key.SetValue($regName, $regData, [Microsoft.Win32.RegistryValueKind]::DWord)
    $changed = $true
}

$key.Close(); $base.Close()

if ($changed) {
    Write-Output "Set $regName=$regData at HKLM:\$regSubPath (64-bit view)."
    exit 3010
} else {
    Write-Output "Already set. No changes."
    exit 0
}