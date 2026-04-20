#Requires -Version 5.1
<#
.SYNOPSIS
    Oppretter Entra ID-gruppe for macOS MDM-enheter.

.DESCRIPTION
    Oppretter T2-MDM-MAC-DPO-PROD med dynamic membership rule
    som matcher alle macOS-enheter enrolled via Intune/ABM.

.NOTES
    Krever: Microsoft.Graph PowerShell-modul
    Installer: Install-Module Microsoft.Graph -Scope CurrentUser
#>

$Scopes = @(
    "Group.ReadWrite.All"
    "Directory.ReadWrite.All"
)

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

function Write-Success { param([string]$Text); Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Fail    { param([string]$Text); Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-Warn    { param([string]$Text); Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Step    { param([string]$Text); Write-Host "  --> $Text" -ForegroundColor Gray }

# ============================================================
# GRUPPE-DEFINISJON
# ============================================================

$Group = @{
    Name           = "T2-MDM-MAC-DPO-PROD"
    Description    = "T2 Enterprise — macOS-enheter enrolled via Apple Business Manager og Intune. Alle produksjon Mac-enheter. Dynamic rule basert på OS-type."
    MembershipRule = '(device.deviceOSType -eq "MacMDM") -and (device.accountEnabled -eq true)'
}

# ============================================================
# HOVEDFLYT
# ============================================================

Write-Host ""
Write-Host "  macOS Entra ID Group Setup" -ForegroundColor Cyan
Write-Host "  Gruppe: $($Group.Name)" -ForegroundColor DarkGray
Write-Host "  Rule:   $($Group.MembershipRule)" -ForegroundColor DarkGray
Write-Host ""

# 1. Sjekk modul
Write-Header "Sjekker Microsoft.Graph-modul"
$module = Get-Module -ListAvailable -Name "Microsoft.Graph.Groups" | Select-Object -First 1
if (-not $module) {
    Write-Fail "Microsoft.Graph er ikke installert."
    Write-Host ""
    Write-Host "  Installer med:" -ForegroundColor Yellow
    Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor White
    exit 1
}
Write-Success "Microsoft.Graph v$($module.Version) funnet"

# 2. Koble til
Write-Header "Kobler til Microsoft Graph"
try {
    Connect-MgGraph -Scopes $Scopes -ErrorAction Stop
    $context = Get-MgContext
    Write-Success "Koblet til som: $($context.Account)"
    Write-Success "Tenant: $($context.TenantId)"
}
catch {
    Write-Fail "Tilkobling feilet: $($_.Exception.Message)"
    exit 1
}

# 3. Sjekk om gruppen allerede eksisterer
Write-Header "Oppretter gruppe"
$existing = Get-MgGroup -Filter "displayName eq '$($Group.Name)'" -ErrorAction SilentlyContinue

if ($existing) {
    Write-Warn "Gruppen finnes allerede: $($Group.Name)"
    Write-Host "  ID: $($existing.Id)" -ForegroundColor DarkGray
}
else {
    try {
        Write-Step "Oppretter: $($Group.Name)"

        $params = @{
            DisplayName                   = $Group.Name
            Description                   = $Group.Description
            MailEnabled                   = $false
            MailNickname                  = $Group.Name.Replace("-", "").ToLower()
            SecurityEnabled               = $true
            GroupTypes                    = @("DynamicMembership")
            MembershipRule                = $Group.MembershipRule
            MembershipRuleProcessingState = "On"
        }

        $newGroup = New-MgGroup -BodyParameter $params -ErrorAction Stop
        Write-Success "Opprettet: $($Group.Name)"
        Write-Host "  ID: $($newGroup.Id)" -ForegroundColor DarkGray
    }
    catch {
        Write-Fail "Feilet: $($_.Exception.Message)"
        Disconnect-MgGraph | Out-Null
        exit 1
    }
}

# 4. Oppsummering
Write-Header "Gruppedetaljer"
Write-Host "  Navn:      $($Group.Name)" -ForegroundColor White
Write-Host "  Platform:  macOS (MacMDM)" -ForegroundColor White
Write-Host "  Tier:      T2 Enterprise" -ForegroundColor Green
Write-Host "  Type:      DPO — Device Policy Object" -ForegroundColor White
Write-Host "  Miljø:     PROD" -ForegroundColor White
Write-Host ""
Write-Host "  Dynamic rule:" -ForegroundColor DarkGray
Write-Host "  $($Group.MembershipRule)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  NB: Dynamic membership kan ta 5-10 min aa prosessere." -ForegroundColor DarkGray
Write-Host "  Mac-enheter dukker opp naar de er enrolled via ABM + Intune." -ForegroundColor DarkGray

# 5. Koble fra
Disconnect-MgGraph | Out-Null
Write-Host ""
Write-Host "  Ferdig. Graph-tilkobling avsluttet." -ForegroundColor DarkGray
Write-Host ""