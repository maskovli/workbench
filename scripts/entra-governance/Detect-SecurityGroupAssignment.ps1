#requires -Version 7.0
#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Export group memberships for one or more users (security, M365/Unified, mail-enabled security, distribution),
  including flags for cloud-only vs on-prem-synced and dynamic membership.

.DESCRIPTION
  - Search users by displayName / UPN / mail (full-text).
  - Optional GridView picker for multiple matches (ConsoleGuiTools).
  - Exports one CSV row per (user × group).
  - Classifies groups:
      * M365 Group (Unified)
      * Security
      * Mail-enabled Security
      * Distribution
    And flags:
      * Source: CloudOnly / OnPremSync
      * Dynamic: True/False

.PARAMETER UserQuery
  Free-text terms to find users (e.g., "Roger Johansen"). You can pass multiple values.

.PARAMETER SelectWithGrid
  Show a GridView picker if multiple matches. If omitted, all matches are used.

.PARAMETER TenantId
  Tenant GUID or verified domain (e.g., spirhed.onmicrosoft.com).

.PARAMETER OutputDir
  Output directory for CSV export (default: current directory). Supports ~ and relative paths.

.NOTES
  Requires Microsoft.Graph PowerShell SDK (PS 7+ recommended).
  First time: Install-Module Microsoft.Graph -Scope CurrentUser -Force
  Author: Marius A. Skovli – Spirhed Group – https://spirhed.com
#>

[CmdletBinding()]
param(
  [string[]]$UserQuery,
  [switch]  $SelectWithGrid,
  [string]  $TenantId,
  [ValidateNotNullOrEmpty()][string]$OutputDir = "."
)

# ---------------- Utilities ----------------
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Ensure-Module {
  param([Parameter(Mandatory)][string]$Name,[string]$MinVersion='0.0.1')
  if (-not (Get-Module -ListAvailable -Name $Name | Where-Object { $_.Version -ge [version]$MinVersion })) {
    Write-Host "Installing module $Name (CurrentUser)..." -ForegroundColor Yellow
    Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }
  Import-Module $Name -ErrorAction Stop | Out-Null
}

function Ensure-Grid {
  if (-not $SelectWithGrid) { return $false }
  try { Ensure-Module Microsoft.PowerShell.ConsoleGuiTools | Out-Null; return $true } catch { return $false }
}

function Resolve-OutputDir([string]$Path){
  try { return (Resolve-Path -Path $Path -ErrorAction Stop).Path }
  catch {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    return (Resolve-Path -Path $Path).Path
  }
}

# ---------------- Auth (Interactive-first, fallback → Device Code; reuse prompt) ----------------
$RequiredGraphScopes = @('Directory.Read.All','Group.Read.All')

function Ensure-GraphWithScopes {
  Ensure-Module Microsoft.Graph -MinVersion '2.15.0'
  Ensure-Module Microsoft.Graph.Users
  Ensure-Module Microsoft.Graph.Groups

  $ctx = Get-MgContext -ErrorAction SilentlyContinue
  $needLogin = $true
  if ($ctx -and $ctx.Account){
    $missing = if ($ctx.Scopes) { $RequiredGraphScopes | Where-Object { $ctx.Scopes -notcontains $_ } } else { $RequiredGraphScopes }
    Write-Host "Existing Microsoft Graph session:" -ForegroundColor Cyan
    Write-Host ("  Account : {0}" -f $ctx.Account)
    Write-Host ("  Tenant  : {0}" -f $ctx.TenantId)
    if ($TenantId -and ($TenantId -ne $ctx.TenantId)){
      Write-Host ("Note: Requested tenant '{0}' differs from current session." -f $TenantId) -ForegroundColor Yellow
    }
    $ans = Read-Host "Use this session? [Y]es / [S]witch account"
    if ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(y|yes)$'){
      if (-not $missing -or $missing.Count -eq 0){
        try { Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null; $needLogin=$false } catch { $needLogin=$true }
      }
    }
  }

  if ($needLogin){
    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue){ Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    if (Get-Command Clear-MgContext    -ErrorAction SilentlyContinue){ Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue }

    $argsBase = @{ Scopes = $RequiredGraphScopes; NoWelcome = $true }
    if ($TenantId){ $argsBase.TenantId = $TenantId }

    Write-Host "Connecting to Microsoft Graph (Interactive browser)..." -ForegroundColor Yellow
    try {
      Connect-MgGraph @argsBase | Out-Null
      Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
    } catch {
      Write-Warning ("Interactive sign-in failed ('{0}'). Falling back to Device Code..." -f $_.Exception.Message)
      if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue){ Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
      if (Get-Command Clear-MgContext    -ErrorAction SilentlyContinue){ Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue }
      $argsDev = $argsBase.Clone(); $argsDev.UseDeviceCode = $true
      Connect-MgGraph @argsDev | Out-Null
      Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
    }

    if (Get-Command Select-MgProfile -ErrorAction SilentlyContinue) { Select-MgProfile -Name 'v1.0' }
  }
}

# ---------------- Robust user search (ALWAYS returns an array) ----------------
function Find-Users {
  param([string[]]$Queries)

  if (-not $Queries -or $Queries.Count -eq 0){
    throw "Please provide -UserQuery (e.g., -UserQuery 'Roger Johansen')."
  }

  $all = New-Object System.Collections.Generic.List[object]

  foreach($q in $Queries){
    $s = $q.Trim()
    if (-not $s){ continue }

    # 1) $search requires property:value — try several properties
    $searchTerms = @(
      ('"displayName:{0}"'       -f $s),
      ('"userPrincipalName:{0}"' -f $s),
      ('"mail:{0}"'              -f $s)
    )
    foreach($st in $searchTerms){
      try {
        $hits = Get-MgUser -Search $st -ConsistencyLevel eventual -All `
                -Property "id,displayName,userPrincipalName,mail,jobTitle,department"
        foreach($u in $hits){ $all.Add($u) }
      } catch { }
    }

    # 2) Fallback: filters
    try {
      $filterName = "startsWith(displayName,'{0}')" -f $s.Replace("'","''")
      $hits2 = Get-MgUser -Filter $filterName -All -Property "id,displayName,userPrincipalName,mail,jobTitle,department"
      foreach($u in $hits2){ $all.Add($u) }
    } catch { }

    # 3) Direct lookups (UPN/email/GUID)
    try {
      if ($s -match '@' -or $s -match '^[0-9a-fA-F-]{36}$') {
        $u3 = Get-MgUser -UserId $s -Property "id,displayName,userPrincipalName,mail,jobTitle,department" -ErrorAction SilentlyContinue
        if ($u3){ $all.Add($u3) }
      }
    } catch { }
  }

  # De-dup and FORCE array output
  $uniq = $all | Group-Object id | ForEach-Object { $_.Group | Select-Object -First 1 }
  return @($uniq)
}

function Pick-Users([array]$Users,[switch]$AllowMulti){
  $Users = @($Users)
  if ($Users.Count -eq 0){ return @() }
  if ($Users.Count -eq 1 -or -not (Ensure-Grid)){ return ,$Users[0] }

  $proj = foreach($u in $Users){
    [pscustomobject]@{
      DisplayName       = $u.DisplayName
      UserPrincipalName = $u.UserPrincipalName
      Mail              = $u.Mail
      JobTitle          = $u.JobTitle
      Department        = $u.Department
      __Ref             = $u
    }
  }
  $mode = $AllowMulti ? 'Multiple' : 'Single'
  $sel  = $proj | Out-ConsoleGridView -Title "Select user(s)" -OutputMode $mode
  if (-not $sel){ return @() }
  if ($AllowMulti){ return @($sel | ForEach-Object { $_.__Ref }) } else { return ,$sel.__Ref }
}

# ---------------- Group helpers ----------------
function Classify-Group {
  param($g)
  $groupTypes = @(); if ($g.groupTypes){ $groupTypes = @($g.groupTypes) } elseif ($g.GroupTypes){ $groupTypes = @($g.GroupTypes) }
  $security    = $g.securityEnabled ?? $g.SecurityEnabled
  $mailEnabled = $g.mailEnabled     ?? $g.MailEnabled
  $syncOnPrem  = $g.onPremisesSyncEnabled ?? $g.OnPremisesSyncEnabled
  $dyn         = ($groupTypes -contains 'DynamicMembership') -or ($null -ne ($g.membershipRule ?? $g.MembershipRule))

  if ($groupTypes -contains 'Unified')                 { $kind = 'M365 Group' }
  elseif ($mailEnabled -and $security)                 { $kind = 'Mail-enabled Security' }
  elseif ($mailEnabled -and -not $security)            { $kind = 'Distribution' }
  else                                                 { $kind = 'Security' }

  $source = $syncOnPrem ? 'OnPremSync' : 'CloudOnly'
  [pscustomobject]@{ Kind=$kind; Source=$source; IsDynamic=[bool]$dyn }
}

function Get-UserGroups {
  param([Parameter(Mandatory)][string]$UserId)

  # Preferred: return groups already typed as groups (no @odata.type poking)
  try {
    return Get-MgUserTransitiveMemberOfAsGroup -UserId $UserId -All `
           -Property "id,displayName,groupTypes,securityEnabled,mailEnabled,mail,visibility,onPremisesSyncEnabled,membershipRule,createdDateTime"
  } catch {
    # Fallback for older SDKs: fetch everything, then filter SAFELY without tripping StrictMode
    $items = Get-MgUserTransitiveMemberOf -UserId $UserId -All `
             -Property "id,displayName,groupTypes,securityEnabled,mailEnabled,mail,visibility,onPremisesSyncEnabled,membershipRule,createdDateTime"

    return $items | Where-Object {
      $_ -is [Microsoft.Graph.PowerShell.Models.MicrosoftGraphGroup] -or
      ($_.PSObject.TypeNames -match 'MicrosoftGraphGroup') -or
      ($_.PSObject.Properties['@odata.type'] -and $_.PSObject.Properties['@odata.type'].Value -eq '#microsoft.graph.group') -or
      ($_.AdditionalProperties -and $_.AdditionalProperties.ContainsKey('@odata.type') -and $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group')
    }
  }
}

# ---------------- Main ----------------
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Ensure-GraphWithScopes
$resolvedOutputDir = (Resolve-OutputDir $OutputDir)

if (-not $UserQuery -or $UserQuery.Count -eq 0){
  Write-Host "Tip: use -UserQuery 'Roger Johansen' or -UserQuery 'displayName:Roger','mail:roger@contoso.com'." -ForegroundColor Yellow
}

$found = @(Find-Users -Queries $UserQuery)
if ($found.Count -eq 0){ throw "No users matched your query." }

$users = @(Pick-Users -Users $found -AllowMulti:$true)
if ($users.Count -eq 0){ Write-Host "No selection. Exiting."; return }

Write-Host ("Selected {0} user(s)." -f $users.Count) -ForegroundColor Cyan

$rows = New-Object System.Collections.Generic.List[object]
$uIdx = 0
foreach($u in $users){
  $uIdx++
  Write-Progress -Activity "Fetching groups" -Status ("{0}/{1} {2}" -f $uIdx,$users.Count,$u.DisplayName) -PercentComplete ([int](100*$uIdx/$users.Count))

  $groups = Get-UserGroups -UserId $u.Id
  foreach($g in $groups){
    $class = Classify-Group -g $g
    $rows.Add([pscustomobject]@{
      UserDisplayName       = $u.DisplayName
      UserPrincipalName     = $u.UserPrincipalName
      UserId                = $u.Id
      GroupDisplayName      = $g.DisplayName
      GroupId               = $g.Id
      GroupKind             = $class.Kind
      GroupSource           = $class.Source
      GroupIsDynamic        = $class.IsDynamic
      GroupMail             = $g.Mail
      GroupVisibility       = $g.Visibility
      GroupCreatedDateTime  = $g.CreatedDateTime
    })
  }
}

$ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
$out = Join-Path $resolvedOutputDir ("UserGroups_{0}.csv" -f $ts)
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $out

$sw.Stop()
Write-Host ("Done in {0}s" -f [int]$sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host ("CSV: {0}" -f $out)
