<#
.SYNOPSIS
Sets 100% display scaling (DPI) for all loaded user hives and the Default profile.

.DESCRIPTION
This script enforces standardized DPI settings (100% / LogPixels = 96) across
all currently loaded user hives as well as the Default user profile.  
It removes any Per-Monitor DPI overrides to ensure a consistent experience,
which is crucial for shared devices, kiosk scenarios and Intune-managed devices
where UI scaling must remain predictable and supportable.

The script is designed for Intune and must be executed as SYSTEM in 64-bit
PowerShell. A sign-out/in is required for users before changes fully apply.

.AUTHOR
Marius A. Skovli – Principal Consultant, Microsoft MVP  
Spirhed Advisory – Security & Compliance

.COMPANY
Spirhed Group AS

.VERSION
2.0  
2025-11-19

.CHANGELOG
v2.0 – Added cleanup of PerMonitorSettings, improved hive handling,  
       added robust default-profile loading logic, clarified output.

v1.0 – Initial implementation.

.NOTES
- Secure-by-default approach for consistent Windows experience.  
- Suitable for Assigned Access / Kiosk, shared devices og generelle enterprise-scenarier.  
- Returns exit code 0 for Intune compliance.
#>
$ErrorActionPreference = 'Stop'

$LogPixels = 96         # 100%
$Win8DpiScaling = 1
$Changed = $false

function Set-DpiForHive {
    param(
        [Parameter(Mandatory)][string]$HiveRoot  # e.g. 'Registry::HKEY_USERS\S-1-5-21-...'
    )
    $desk = Join-Path $HiveRoot 'Control Panel\Desktop'
    if (-not (Test-Path $desk)) { New-Item -Path $desk -Force | Out-Null }

    $curLP = (Get-ItemProperty -Path $desk -Name 'LogPixels' -ErrorAction SilentlyContinue).LogPixels
    $curW8 = (Get-ItemProperty -Path $desk -Name 'Win8DpiScaling' -ErrorAction SilentlyContinue).Win8DpiScaling

    if ($curLP -ne $LogPixels) {
        New-ItemProperty -Path $desk -Name 'LogPixels' -PropertyType DWord -Value $LogPixels -Force | Out-Null
        $script:Changed = $true
    }
    if ($curW8 -ne $Win8DpiScaling) {
        New-ItemProperty -Path $desk -Name 'Win8DpiScaling' -PropertyType DWord -Value $Win8DpiScaling -Force | Out-Null
        $script:Changed = $true
    }

    # Fjern per-monitor overrides (ellers kan Windows "huske" en annen skalering)
    $perMon = Join-Path $desk 'PerMonitorSettings'
    if (Test-Path $perMon) {
        Remove-Item -Path $perMon -Recurse -Force
        $script:Changed = $true
    }
}

# 1) Alle innlastede bruker-hives (aktive brukere)
Get-ChildItem 'Registry::HKEY_USERS' |
    Where-Object {
        # Inkluder vanlige bruker-SIDer (domene/lokal) og AAD (S-1-12-1-...),
        # ekskluder SYSTEM/Service-hiver
        $_.PSChildName -match '^S-1-5-21-' -or $_.PSChildName -match '^S-1-12-1-'
    } |
    ForEach-Object {
        Set-DpiForHive -HiveRoot ("Registry::HKEY_USERS\{0}" -f $_.PSChildName)
    }

# 2) Default-profil (for nye brukere)
$defaultDat = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
if (Test-Path $defaultDat) {
    $mountName = "TempDefault_$([guid]::NewGuid().ToString('N'))"
    $mountKeyHKU = "HKU\$mountName"
    $mountKeyPS  = "Registry::HKEY_USERS\$mountName"

    & reg.exe load $mountKeyHKU "$defaultDat" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        try {
            Set-DpiForHive -HiveRoot $mountKeyPS
        } finally {
            & reg.exe unload $mountKeyHKU | Out-Null
        }
    } else {
        Write-Warning "Kunne ikke laste Default hive (exit $LASTEXITCODE). Hopper over Default."
    }
} else {
    Write-Warning "Fant ikke $defaultDat. Hopper over Default."
}

if ($Changed) {
    Write-Output 'DPI set to 100% for loaded users and Default profile. Sign out/in required.'
} else {
    Write-Output 'No changes needed.'
}
exit 0   # Viktig: Intune markerer alt annet enn 0 som "Error"