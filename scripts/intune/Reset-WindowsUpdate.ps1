#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Tilbakestiller Windows Update fullstendig på Windows 11-klienter.

.DESCRIPTION
    Dette skriptet utforer en fullstendig tilbakestilling av Windows Update ved a:
    - Stoppe alle relevante Windows Update-tjenester
    - Slette midlertidige filer og cache tilknyttet Windows Update
    - Tilbakestille BITS- og Windows Update-komponenter
    - Registrere Windows Update DLL-filer pa nytt
    - Fjerne eventuelle feilaktige registernokler
    - Starte tjenestene pa nytt

    Krev administrator-rettigheter. Anbefalt a starte maskinen pa nytt etter kjoring.

.PARAMETER NoRestart
    Undertrykker den valgfrie omstarten pa slutten av skriptet.

.EXAMPLE
    .\Reset-WindowsUpdate.ps1

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -NoRestart

.NOTES
    Forfatter  : Marius
    Versjon    : 1.0
    Dato       : 2026-04-13
    Testet pa  : Windows 11 23H2 / 24H2
    Krever     : PowerShell 5.1 eller nyere, Administrator-rettigheter
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [switch]$NoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helpers

function Write-Step {
    param([string]$Message)
    Write-Host "`n[*] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    [!]  $Message" -ForegroundColor Yellow
}

function Stop-WUService {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Write-OK "Stoppet tjeneste: $Name"
    }
}

function Start-WUService {
    param([string]$Name, [string]$StartupType = 'Manual')
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name $Name -StartupType $StartupType -ErrorAction SilentlyContinue
        Start-Service -Name $Name -ErrorAction SilentlyContinue
        Write-OK "Startet tjeneste: $Name"
    }
}

#endregion

#region Verifiser administrator

Write-Step "Verifiserer administrator-rettigheter"
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Skriptet ma kjores som Administrator. Start PowerShell med 'Kjor som administrator'."
}
Write-OK "Administrator-rettigheter bekreftet"

#endregion

#region Stopp tjenester

Write-Step "Stopper Windows Update-relaterte tjenester"

$servicesToStop = @(
    'wuauserv',   # Windows Update
    'cryptsvc',   # Cryptographic Services
    'bits',       # Background Intelligent Transfer Service
    'msiserver',  # Windows Installer
    'usosvc',     # Update Orchestrator Service
    'uhssvc',     # Microsoft Update Health Service
    'WaaSMedicSvc' # Windows Update Medic Service (blokkeres midlertidig)
)

foreach ($svc in $servicesToStop) {
    Stop-WUService -Name $svc
}

# Forsok a deaktivere WaaSMedicSvc midlertidig via registeret
$medicKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc'
if (Test-Path $medicKey) {
    try {
        Set-ItemProperty -Path $medicKey -Name 'Start' -Value 4 -ErrorAction SilentlyContinue
        Write-OK "Deaktiverte WaaSMedicSvc midlertidig"
    } catch {
        Write-Warn "Kunne ikke deaktivere WaaSMedicSvc (beskyttet av TrustedInstaller) - fortsetter"
    }
}

#endregion

#region Gi nytt navn til / slett cache-mapper

Write-Step "Sletter Windows Update-cache og midlertidige filer"

$foldersToReset = @(
    "$env:SystemRoot\SoftwareDistribution",
    "$env:SystemRoot\System32\catroot2"
)

foreach ($folder in $foldersToReset) {
    if (Test-Path $folder) {
        $backup = "${folder}_bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        try {
            Rename-Item -Path $folder -NewName $backup -Force -ErrorAction Stop
            Write-OK "Omdopte: $folder -> $backup"
        } catch {
            Write-Warn "Kunne ikke omdope $folder, forsok a slette innhold direkte"
            Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Slett BITS-kofiler
$bitsFolder = "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader"
if (Test-Path $bitsFolder) {
    Get-ChildItem -Path $bitsFolder -Filter 'qmgr*.dat' -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-OK "Slettet BITS-kofiler"
}

#endregion

#region Tilbakestill nettverkskonfigurasjon

Write-Step "Tilbakestiller Winsock og nettverksproxy"

$netCommands = @(
    'netsh winsock reset',
    'netsh winhttp reset proxy'
)

foreach ($cmd in $netCommands) {
    try {
        $result = Invoke-Expression $cmd 2>&1
        Write-OK "$cmd"
    } catch {
        Write-Warn "Feil ved: $cmd"
    }
}

#endregion

#region Registrer DLL-filer pa nytt

Write-Step "Registrerer Windows Update DLL-filer pa nytt"

$dllsToRegister = @(
    'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll',
    'browseui.dll', 'jscript.dll', 'vbscript.dll', 'scrrun.dll',
    'msxml.dll', 'msxml3.dll', 'msxml6.dll', 'actxprxy.dll',
    'softpub.dll', 'wintrust.dll', 'dssenh.dll', 'rsaenh.dll',
    'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
    'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll',
    'wuapi.dll', 'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll',
    'wups.dll', 'wups2.dll', 'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll',
    'wucltux.dll', 'muweb.dll', 'wuwebv.dll'
)

foreach ($dll in $dllsToRegister) {
    $path = "$env:SystemRoot\System32\$dll"
    if (Test-Path $path) {
        try {
            $null = & regsvr32.exe /s $path
            Write-OK "Registrert: $dll"
        } catch {
            Write-Warn "Kunne ikke registrere: $dll"
        }
    }
}

#endregion

#region Tilbakestill registernokler

Write-Step "Tilbakestiller Windows Update-registernokler"

$regKeysToRemove = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RequestedAppCategories',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect'
)

foreach ($key in $regKeysToRemove) {
    if (Test-Path $key) {
        try {
            Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
            Write-OK "Slettet registernokkel: $key"
        } catch {
            Write-Warn "Kunne ikke slette: $key"
        }
    }
}

# Sett WU-tjenesteurl tilbake til standard (fjern eventuelle proxy-overstyringer)
$wuPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
if (Test-Path $wuPolicyKey) {
    @('WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate') | ForEach-Object {
        Remove-ItemProperty -Path $wuPolicyKey -Name $_ -ErrorAction SilentlyContinue
    }
    Write-OK "Fjernet eventuelle WSUS-overstyringer fra gruppepolicy-nokler"
}

#endregion

#region Start tjenester pa nytt

Write-Step "Starter Windows Update-tjenester pa nytt"

# Reaktiver WaaSMedicSvc
if (Test-Path $medicKey) {
    Set-ItemProperty -Path $medicKey -Name 'Start' -Value 3 -ErrorAction SilentlyContinue
}

$servicesToStart = @(
    @{ Name = 'bits';      StartupType = 'Automatic' },
    @{ Name = 'cryptsvc';  StartupType = 'Automatic' },
    @{ Name = 'wuauserv';  StartupType = 'Manual'    },
    @{ Name = 'usosvc';    StartupType = 'Manual'    }
)

foreach ($svc in $servicesToStart) {
    Start-WUService -Name $svc.Name -StartupType $svc.StartupType
}

#endregion

#region Tving Windows Update til a se etter oppdateringer

Write-Step "Tvinger Windows Update-skanning"

try {
    $updateSession   = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher  = $updateSession.CreateUpdateSearcher()
    $null            = $updateSearcher.Search("IsInstalled=0")
    Write-OK "Windows Update-skanning startet"
} catch {
    Write-Warn "Kunne ikke starte skanning via COM-objekt (vanlig etter reset) - start Windows Update manuelt"
}

# Alternativ: usoclient
try {
    & usoclient StartScan
    Write-OK "usoclient StartScan kjoert"
} catch {
    Write-Warn "usoclient ikke tilgjengelig"
}

#endregion

#region Ferdig

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Windows Update er tilbakestilt." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

if (-not $NoRestart) {
    $restart = Read-Host "`nOmstart anbefales for at endringene skal tre i kraft.`nStart maskinen pa nytt na? (j/N)"
    if ($restart -match '^[jJ]$') {
        Write-Host "Starter pa nytt om 15 sekunder. Trykk Ctrl+C for a avbryte." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
        Restart-Computer -Force
    } else {
        Write-Host "Husk a starte pa nytt manuelt." -ForegroundColor Yellow
    }
} else {
    Write-Host "(-NoRestart angitt - omstart hoppes over)" -ForegroundColor Yellow
}

#endregion
