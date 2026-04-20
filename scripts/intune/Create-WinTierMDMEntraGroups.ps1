#Requires -Version 5.1
<#
.SYNOPSIS
    Oppretter MDM-grupper i Entra ID med dynamic membership rules og Autopilot Group Tags.

.DESCRIPTION
    Navnestandard:
    Grupper:    [T0/T1/T2]-MDM-[Platform]-[DPO/UPO]-[Miljø/Spesial]
    Group Tags: [T0/T1/T2]-[Platform]-[Miljø/Spesial]

    Tier-mapping:
      T0  Privileged  — PAW  — IT Ops, Global Admins, ALZ/AD T0-kontoer
      T1  Specialized — SAW  — High-impact users, devs, service desk admins
      T2  Enterprise  — Alle øvrige — Win11, W365, AVD, Kiosk, Shared

    Kjøres av en bruker med Group Administrator-rollen i Entra ID.

.NOTES
    Krever: Microsoft.Graph PowerShell-modul
    Installer: Install-Module Microsoft.Graph -Scope CurrentUser
#>

# ============================================================
# KONFIGURASJON
# ============================================================

$TenantId = "" # Valgfritt — fyll inn din Tenant ID

$Scopes = @(
    "Group.ReadWrite.All"
    "Directory.ReadWrite.All"
)

# ============================================================
# GRUPPE-DEFINISJONER
# ============================================================

$Groups = @(

    # ----------------------------------------------------------
    # T0 — PRIVILEGED
    # PAW: Privileged Access Workstation
    # Brukes av: IT Ops, Global Admins, ALZ/AD T0-kontoer
    # ----------------------------------------------------------

    @{
        Name           = "T0-MDM-W11-DPO-PAW"
        Description    = "T0 Privileged — Privileged Access Workstation. IT Ops, Global Admins og ALZ/AD T0-kontoer. Maksimal herding, dedikert admin-konto, LAPS påkrevd. Eksklusiv gruppe — kombineres ikke med andre device-grupper."
        GroupTag       = "T0-W11-PAW"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T0-W11-PAW")'
        Tier           = "T0"
        Platform       = "W11"
        Type           = "DPO"
        Environment    = "PAW"
    }

    # ----------------------------------------------------------
    # T1 — SPECIALIZED
    # SAW: Secure Admin Workstation
    # Brukes av: High-impact users, devs, service desk med admin-rettigheter
    # ----------------------------------------------------------

    @{
        Name           = "T1-MDM-W11-DPO-SAW"
        Description    = "T1 Specialized — Secure Admin Workstation. High-impact users, utviklere og service desk med admin-rettigheter. Herdet baseline, begrenset app-tilgang, egen Conditional Access. Eksklusiv gruppe."
        GroupTag       = "T1-W11-SAW"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T1-W11-SAW")'
        Tier           = "T1"
        Platform       = "W11"
        Type           = "DPO"
        Environment    = "SAW"
    }

    # ----------------------------------------------------------
    # T2 — ENTERPRISE
    # Standard enheter: Win11, W365, AVD, Kiosk, Shared
    # ----------------------------------------------------------

    @{
        Name           = "T2-MDM-W11-DPO-DEV"
        Description    = "T2 Enterprise — Fysiske Windows 11-enheter i testmiljø. Nye policies testes her før PROD."
        GroupTag       = "T2-W11-DEV"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-W11-DEV")'
        Tier           = "T2"
        Platform       = "W11"
        Type           = "DPO"
        Environment    = "DEV"
    }
    @{
        Name           = "T2-MDM-W11-DPO-PROD"
        Description    = "T2 Enterprise — Fysiske Windows 11-enheter i produksjon. Alle standard ansatte."
        GroupTag       = "T2-W11-PROD"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-W11-PROD")'
        Tier           = "T2"
        Platform       = "W11"
        Type           = "DPO"
        Environment    = "PROD"
    }
    @{
        Name           = "T2-MDM-W365-DPO-DEV"
        Description    = "T2 Enterprise — Windows 365 Cloud PC i testmiljø."
        GroupTag       = "T2-W365-DEV"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-W365-DEV")'
        Tier           = "T2"
        Platform       = "W365"
        Type           = "DPO"
        Environment    = "DEV"
    }
    @{
        Name           = "T2-MDM-W365-DPO-PROD"
        Description    = "T2 Enterprise — Windows 365 Cloud PC i produksjon."
        GroupTag       = "T2-W365-PROD"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-W365-PROD")'
        Tier           = "T2"
        Platform       = "W365"
        Type           = "DPO"
        Environment    = "PROD"
    }
    @{
        Name           = "T2-MDM-AVD-DPO-DEV"
        Description    = "T2 Enterprise — Azure Virtual Desktop session hosts i testmiljø."
        GroupTag       = "T2-AVD-DEV"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-AVD-DEV")'
        Tier           = "T2"
        Platform       = "AVD"
        Type           = "DPO"
        Environment    = "DEV"
    }
    @{
        Name           = "T2-MDM-AVD-DPO-PROD"
        Description    = "T2 Enterprise — Azure Virtual Desktop session hosts i produksjon."
        GroupTag       = "T2-AVD-PROD"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-AVD-PROD")'
        Tier           = "T2"
        Platform       = "AVD"
        Type           = "DPO"
        Environment    = "PROD"
    }
    @{
        Name           = "T2-MDM-W11-DPO-KIOSK"
        Description    = "T2 Enterprise — Kiosk og fellesmaskiner. Single App eller Multi App kiosk-modus. Eksklusiv gruppe."
        GroupTag       = "T2-W11-KIOSK"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-W11-KIOSK")'
        Tier           = "T2"
        Platform       = "W11"
        Type           = "DPO"
        Environment    = "KIOSK"
    }
    @{
        Name           = "T2-MDM-W11-DPO-SHARED"
        Description    = "T2 Enterprise — Delte enheter med Shared PC mode. Flere brukere på samme maskin. Eksklusiv gruppe."
        GroupTag       = "T2-W11-SHARED"
        MembershipRule = '(device.devicePhysicalIds -any _ -eq "[OrderID]:T2-W11-SHARED")'
        Tier           = "T2"
        Platform       = "W11"
        Type           = "DPO"
        Environment    = "SHARED"
    }

    # ----------------------------------------------------------
    # BRUKERGRUPPER (UPO)
    # Ingen tier-prefix — tier på brukernivå styres av
    # Conditional Access og kontotype, ikke gruppenavn
    # ----------------------------------------------------------

    @{
        Name           = "MDM-GLB-UPO-DEV"
        Description    = "IT-avdelingen og testbrukere. Mottar dev-policies på tvers av alle plattformer. Sett extensionAttribute1 = MDM-Dev for å legge til bruker."
        GroupTag       = "N/A"
        MembershipRule = '(user.extensionAttribute1 -eq "MDM-Dev") -and (user.accountEnabled -eq true)'
        Tier           = "N/A"
        Platform       = "GLB"
        Type           = "UPO"
        Environment    = "DEV"
    }
    @{
        Name           = "MDM-GLB-UPO-PROD"
        Description    = "Alle aktive medlemsbrukere. Mottar globale bruker-policies på tvers av plattformer."
        GroupTag       = "N/A"
        MembershipRule = '(user.userType -eq "Member") -and (user.accountEnabled -eq true)'
        Tier           = "N/A"
        Platform       = "GLB"
        Type           = "UPO"
        Environment    = "PROD"
    }
)

# ============================================================
# FUNKSJONER
# ============================================================

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

function Write-Step    { param([string]$Text); Write-Host "  --> $Text" -ForegroundColor Gray }
function Write-Success { param([string]$Text); Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn    { param([string]$Text); Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Text); Write-Host "  [X]  $Text" -ForegroundColor Red }

function Get-TierColor {
    param([string]$Tier)
    switch ($Tier) {
        "T0"    { return "DarkGray" }
        "T1"    { return "Cyan" }
        "T2"    { return "Green" }
        default { return "Gray" }
    }
}

function Test-GraphModule {
    Write-Header "Sjekker Microsoft.Graph-modul"
    $module = Get-Module -ListAvailable -Name "Microsoft.Graph.Groups" | Select-Object -First 1
    if (-not $module) {
        Write-Fail "Microsoft.Graph er ikke installert."
        Write-Host ""
        Write-Host "  Installer med:" -ForegroundColor Yellow
        Write-Host "  Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor White
        return $false
    }
    Write-Success "Microsoft.Graph v$($module.Version) funnet"
    return $true
}

function Connect-ToGraph {
    Write-Header "Kobler til Microsoft Graph"
    try {
        $connectParams = @{ Scopes = $Scopes }
        if ($TenantId -ne "") { $connectParams.TenantId = $TenantId }
        Connect-MgGraph @connectParams -ErrorAction Stop
        $context = Get-MgContext
        Write-Success "Koblet til som: $($context.Account)"
        Write-Success "Tenant: $($context.TenantId)"
        return $true
    }
    catch {
        Write-Fail "Tilkobling feilet: $($_.Exception.Message)"
        return $false
    }
}

function New-MDMGroup {
    param($GroupDef)

    $existing = Get-MgGroup -Filter "displayName eq '$($GroupDef.Name)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "Finnes allerede: $($GroupDef.Name) — hopper over"
        return [PSCustomObject]@{
            Name   = $GroupDef.Name
            Status = "Eksisterer allerede"
            Id     = $existing.Id
            Tier   = $GroupDef.Tier
        }
    }

    try {
        Write-Step "Oppretter: $($GroupDef.Name)"
        $params = @{
            DisplayName                   = $GroupDef.Name
            Description                   = $GroupDef.Description
            MailEnabled                   = $false
            MailNickname                  = $GroupDef.Name.Replace("-", "").ToLower()
            SecurityEnabled               = $true
            GroupTypes                    = @("DynamicMembership")
            MembershipRule                = $GroupDef.MembershipRule
            MembershipRuleProcessingState = "On"
        }
        $newGroup = New-MgGroup -BodyParameter $params -ErrorAction Stop
        Write-Success "Opprettet: $($GroupDef.Name) [$($newGroup.Id)]"
        return [PSCustomObject]@{
            Name   = $GroupDef.Name
            Status = "Opprettet"
            Id     = $newGroup.Id
            Tier   = $GroupDef.Tier
        }
    }
    catch {
        Write-Fail "Feilet: $($GroupDef.Name) — $($_.Exception.Message)"
        return [PSCustomObject]@{
            Name   = $GroupDef.Name
            Status = "FEIL: $($_.Exception.Message)"
            Id     = ""
            Tier   = $GroupDef.Tier
        }
    }
}

function Show-GroupTagReference {
    Write-Header "Autopilot Group Tag-referanse"
    Write-Host ""
    Write-Host "  Sett Group Tag ved Autopilot-import (CSV), Autopilot-profil eller OEM-leveranse." -ForegroundColor Gray
    Write-Host "  En enhet skal kun ha EN Group Tag." -ForegroundColor Gray
    Write-Host "  T0 og T1 er eksklusive — kombineres aldri med T2-grupper." -ForegroundColor Yellow
    Write-Host ""
    Write-Host ("  {0,-35} {1,-20} {2}" -f "GRUPPE", "GROUP TAG", "TIER") -ForegroundColor DarkGray
    Write-Host ("  {0,-35} {1,-20} {2}" -f ("-" * 34), ("-" * 19), ("-" * 14)) -ForegroundColor DarkGray

    foreach ($g in $Groups | Where-Object { $_.Type -eq "DPO" }) {
        $color = Get-TierColor -Tier $g.Tier
        Write-Host ("  {0,-35} " -f $g.Name) -NoNewline -ForegroundColor White
        Write-Host ("{0,-20} " -f $g.GroupTag) -NoNewline -ForegroundColor $color
        Write-Host $g.Tier -ForegroundColor $color
    }

    Write-Host ""
    Write-Host ("  {0,-12} {1,-14} {2}" -f "TIER", "ENHET", "TYPISKE BRUKERE") -ForegroundColor DarkGray
    Write-Host ("  {0,-12} {1,-14} {2}" -f ("-" * 11), ("-" * 13), ("-" * 30)) -ForegroundColor DarkGray
    Write-Host ("  {0,-12} {1,-14} {2}" -f "T0 Privileged", "PAW", "IT Ops, Global Admins, ALZ T0") -ForegroundColor DarkGray
    Write-Host ("  {0,-12} {1,-14} {2}" -f "T1 Specialized", "SAW", "High-impact users, devs, service desk") -ForegroundColor Cyan
    Write-Host ("  {0,-12} {1,-14} {2}" -f "T2 Enterprise", "W11/W365/AVD", "Standard ansatte") -ForegroundColor Green
}

function Show-Summary {
    param($Results)
    Write-Header "Oppsummering"

    $created  = $Results | Where-Object { $_.Status -eq "Opprettet" }
    $existing = $Results | Where-Object { $_.Status -eq "Eksisterer allerede" }
    $failed   = $Results | Where-Object { $_.Status -like "FEIL*" }

    Write-Host "  Opprettet:       $($created.Count)" -ForegroundColor Green
    Write-Host "  Fantes fra for:  $($existing.Count)" -ForegroundColor Yellow
    Write-Host "  Feilet:          $($failed.Count)" -ForegroundColor $(if ($failed.Count -gt 0) { "Red" } else { "Gray" })

    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "  Feilede grupper:" -ForegroundColor Red
        foreach ($f in $failed) {
            Write-Host "    - $($f.Name): $($f.Status)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  NB: Dynamic membership kan ta 5-10 min aa prosessere." -ForegroundColor DarkGray
    Write-Host "  Enheter dukker ikke opp umiddelbart etter opprettelse." -ForegroundColor DarkGray
}

# ============================================================
# HOVEDFLYT
# ============================================================

Write-Host ""
Write-Host "  MDM Entra ID Group Setup" -ForegroundColor Cyan
Write-Host "  Grupper:    [T0/T1/T2]-MDM-[Platform]-[DPO/UPO]-[Miljo]" -ForegroundColor DarkGray
Write-Host "  Group Tags: [T0/T1/T2]-[Platform]-[Miljo]" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-GraphModule)) { exit 1 }
if (-not (Connect-ToGraph))  { exit 1 }

Write-Header "Oppretter grupper ($($Groups.Count) totalt)"
$results = @()
foreach ($group in $Groups) {
    $results += New-MDMGroup -GroupDef $group
}

Show-GroupTagReference
Show-Summary -Results $results

Disconnect-MgGraph | Out-Null
Write-Host ""
Write-Host "  Ferdig. Graph-tilkobling avsluttet." -ForegroundColor DarkGray
Write-Host ""