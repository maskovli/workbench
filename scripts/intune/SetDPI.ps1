# Set 100% display scaling for all loaded user hives + Default profile (Shared devices friendly)
$ErrorActionPreference = 'Stop'

$LogPixels = 96            # 100%
$Win8DpiScaling = 1
$Changed = $false

function Set-DpiForHive {
    param([string]$HiveRoot) # e.g. 'Registry::HKEY_USERS\S-1-5-21-...'
    $desk = Join-Path $HiveRoot 'Control Panel\Desktop'
    if (-not (Test-Path $desk)) { New-Item -Path $desk -Force | Out-Null }

    $curLP  = (Get-ItemProperty -Path $desk -Name 'LogPixels' -ErrorAction SilentlyContinue).LogPixels
    $curW8  = (Get-ItemProperty -Path $desk -Name 'Win8DpiScaling' -ErrorAction SilentlyContinue).Win8DpiScaling

    if ($curLP -ne $LogPixels) {
        New-ItemProperty -Path $desk -Name 'LogPixels' -PropertyType DWord -Value $LogPixels -Force | Out-Null
        $script:Changed = $true
    }
    if ($curW8 -ne $Win8DpiScaling) {
        New-ItemProperty -Path $desk -Name 'Win8DpiScaling' -PropertyType DWord -Value $Win8DpiScaling -Force | Out-Null
        $script:Changed = $true
    }

    # Nuke per-monitor overrides so the above actually wins
    $perMon = Join-Path $desk 'PerMonitorSettings'
    if (Test-Path $perMon) {
        Remove-Item -Path $perMon -Recurse -Force
        $script:Changed = $true
    }
}

# 1) Apply to all loaded user hives (interactive users)
$LoadedUserHives = Get-ChildItem Registry::HKEY_USERS |
    Where-Object {
        # Include AzureAD and local/domain users; exclude built-in service SIDs
        $_.PSChildName -match '^S-1-(5|12)-' -and
        $_.PSChildName -notmatch '^(S-1-5-18|S-1-5-19|S-1-5-20)$'
    }

foreach ($h in $LoadedUserHives) {
    Set-DpiForHive -HiveRoot ("Registry::HKEY_USERS\{0}" -f $h.PSChildName)
}

# 2) Apply to the Default user profile so NEW users get 100%
$mountPoint = 'HKU\TempDefault'
$needUnload = $false
if (-not (Test-Path "Registry::$mountPoint")) {
    # Load C:\Users\Default\NTUSER.DAT under a temp hive
    & reg.exe load $mountPoint "$env:SystemDrive\Users\Default\NTUSER.DAT" | Out-Null
    $needUnload = $LASTEXITCODE -eq 0
}
try {
    Set-DpiForHive -HiveRoot ("Registry::$mountPoint")
} finally {
    if ($needUnload) { & reg.exe unload $mountPoint | Out-Null }
}

if ($Changed) {
    Write-Output 'DPI set to 100% for current users and Default profile. Sign out/in required.'
    exit 3010
} else {
    Write-Output 'No changes needed.'
    exit 0
}