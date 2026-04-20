<#
.SYNOPSIS
  Detect-AzurePermissions.ps1
  Map RBAC roles in use from selected Management Groups / Subscriptions.
  Supports recursive traversal of TRG/MG (-Recurse).
  Exports CSV/JSON including identities and resource details (name, type, tags).

.PARAMETER TenantId
  Tenant (ID eller verified domain) å logge mot.

.PARAMETER ExportPath
  Katalog for eksport (opprettes). Default: .\output

.PARAMETER IncludeClassicAdmins
  Inkluderer Classic Administrators i uttrekk.

.PARAMETER AutoUpdateModules
  Forsøker å oppdatere Az-moduler automatisk hvis versjon er for lav.

.PARAMETER OutputJson
  I tillegg til CSV, skriv også JSON-filer.

.PARAMETER NoLog
  Deaktiver fil-logg (Transcript).

.PARAMETER Recurse
  Når valgt, og du velger TRG/MG, hentes alle underliggende MG-er og Subscriptions rekursivt.

.NOTES
  Requires Microsoft.Graph PowerShell SDK (PS 7+ recommended).
  First time: Install-Module Microsoft.Graph -Scope CurrentUser -Force
  Author: Marius A. Skovli - Spirhed Group - https://spirhed.com
  Date: 7.10.2025
#>

[CmdletBinding()]
param(
  [string]$TenantId,
  [string]$ExportPath = ".\output",
  [switch]$IncludeClassicAdmins,
  [switch]$AutoUpdateModules,
  [switch]$OutputJson,
  [switch]$NoLog,
  [switch]$Recurse
)

$ErrorActionPreference = 'Stop'
Write-Host "`n=== Detect-AzurePermissions.ps1 ===" -ForegroundColor Cyan

# --- 0) Paths & logging -------------------------------------------------------
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath | Out-Null }
$rolesCsv   = Join-Path $ExportPath 'roles_in_use.csv'
$assignCsv  = Join-Path $ExportPath 'role_assignments.csv'
$rolesJson  = Join-Path $ExportPath 'roles_in_use.json'
$assignJson = Join-Path $ExportPath 'role_assignments.json'
$logPath    = Join-Path $ExportPath 'detect-azurepermissions.log'
if (-not $NoLog) { try { Start-Transcript -Path $logPath -Append -ErrorAction Stop | Out-Null } catch { Write-Host "Advarsel: kunne ikke starte logg ($logPath)." -ForegroundColor Yellow } }

# --- 1) Moduler ---------------------------------------------------------------
$RequiredModules = @(
  @{ Name="Az.Accounts";  MinVersion="2.15.0" },
  @{ Name="Az.Resources"; MinVersion="6.17.0" }
)
foreach ($m in $RequiredModules) {
  $installed = Get-Module -ListAvailable -Name $m.Name | Sort-Object Version -Descending | Select-Object -First 1
  if (-not $installed) { Write-Host ("Installerer {0}..." -f $m.Name) -ForegroundColor Yellow; Install-Module -Name $m.Name -Scope CurrentUser -Force }
  elseif ([version]$installed.Version -lt [version]$m.MinVersion) {
    Write-Host ("Modul {0} er {1}, anbefalt >= {2}." -f $m.Name, $installed.Version, $m.MinVersion) -ForegroundColor Yellow
    if ($AutoUpdateModules) { try { Update-Module -Name $m.Name -Force -ErrorAction Stop } catch { Write-Host "Advarsel: kunne ikke oppdatere $($m.Name)." -ForegroundColor Yellow } }
    else { Write-Host "Tips: Kjør 'Update-Module $($m.Name) -Force' for å oppdatere." -ForegroundColor Yellow }
  }
  Import-Module $m.Name -ErrorAction Stop
}

# --- 2) Innlogging / gjenbruk av sesjon ---------------------------------------
$ctx = Get-AzContext -ErrorAction SilentlyContinue
$needLogin = $true
if ($ctx -and $ctx.Account) {
  Write-Host "Eksisterende Azure-kontekst:" -ForegroundColor Cyan
  Write-Host ("  Account : {0}" -f $ctx.Account)
  Write-Host ("  Tenant  : {0}" -f $ctx.Tenant.Id)
  if ($TenantId -and ($TenantId -ne $ctx.Tenant.Id)) { Write-Host ("Merk: Requested tenant '{0}' != current '{1}'" -f $TenantId, $ctx.Tenant.Id) -ForegroundColor Yellow }
  $ans = Read-Host "Bruke denne sesjonen? [Y]es / [S]witch account"
  if ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(y|yes)$') {
    $needLogin = $false
    if ($TenantId -and ($TenantId -ne $ctx.Tenant.Id)) {
      Write-Host "Bytter tenant (uten ny innlogging hvis mulig)..." -ForegroundColor Yellow
      try { Set-AzContext -Tenant $TenantId -ErrorAction Stop | Out-Null }
      catch { Connect-AzAccount -Tenant $TenantId -AccountId $ctx.Account -Force | Out-Null }
    }
  }
}
if ($needLogin) { if ($TenantId) { Connect-AzAccount -Tenant $TenantId | Out-Null } else { Connect-AzAccount | Out-Null } }
$ctx = Get-AzContext
Write-Host ("Pålogget: {0} (Tenant {1})" -f $ctx.Account, $ctx.Tenant.Id) -ForegroundColor Green

# --- 3) Finn Tenant Root Group ------------------------------------------------
Write-Host "`nLeter etter Tenant Root Group..." -ForegroundColor Cyan
$rootMg = $null
try { $rootMg = Get-AzManagementGroup -GroupName $ctx.Tenant.Id -Expand -ErrorAction Stop }
catch {
  try { $allTop = Get-AzManagementGroup -Expand -ErrorAction Stop; $rootMg = $allTop | Where-Object { $_.DisplayName -eq "Tenant Root Group" } | Select-Object -First 1 }
  catch { Write-Host "Advarsel: kunne ikke enumerere Management Groups." -ForegroundColor Yellow }
}
if (-not $rootMg) { throw "Fant ikke Tenant Root Group. Sjekk MG-tilgang." }
Write-Host ("Root MG: {0} ({1})" -f $rootMg.DisplayName, $rootMg.Name) -ForegroundColor Cyan

# --- 4) Valgbar scope-meny ----------------------------------------------------
Write-Host "`nVelg scope du vil hente roller fra:" -ForegroundColor Cyan
$subsAll = @(); try { $subsAll = Get-AzSubscription -TenantId $ctx.Tenant.Id | Sort-Object Name } catch { Write-Host "Advarsel: kunne ikke hente subscriptions." -ForegroundColor Yellow }
$mgListForMenu = @()
try { $mgListForMenu = Get-AzManagementGroup -GroupName $rootMg.Name -Expand -Recurse -ErrorAction Stop }
catch { Write-Host "Advarsel: kunne ikke hente hele MG-treet, viser kun Root." -ForegroundColor Yellow; $mgListForMenu = @($rootMg) }
$mgListForMenu = @($rootMg) + ($mgListForMenu | Where-Object { $_.Name -ne $rootMg.Name })
$mgListForMenu = $mgListForMenu | Sort-Object DisplayName, Name | Select-Object -Unique Name, DisplayName

$choices = @()
Write-Host "TRG: Tenant Root Group" -ForegroundColor Yellow
$choices += [pscustomobject]@{ Key="TRG"; Type="ManagementGroup"; Name=$rootMg.Name; Label=$rootMg.DisplayName }
$idx = 1
foreach ($mg in $mgListForMenu) { $key = "MG$idx"; Write-Host ("{0}: {1} ({2})" -f $key, $mg.DisplayName, $mg.Name); $choices += [pscustomobject]@{ Key=$key; Type="ManagementGroup"; Name=$mg.Name; Label=$mg.DisplayName }; $idx++ }
$idx = 1
foreach ($s in $subsAll) { $key = "S$idx"; Write-Host ("{0}: {1}" -f $key, $s.Name); $choices += [pscustomobject]@{ Key=$key; Type="Subscription"; Name=$s.Id; Label=$s.Name }; $idx++ }

$sel = Read-Host "`nAngi valg (f.eks. TRG, MG2, S1 — kommaseparert). Tomt = TRG"
$scopeSelection = if ([string]::IsNullOrWhiteSpace($sel)) { @("TRG") } else { $sel.Split(',') | ForEach-Object { $_.Trim().ToUpper() } }
$selectedMenuItems = $choices | Where-Object { $scopeSelection -contains $_.Key }
if (-not $selectedMenuItems) { Write-Host "Ingen gyldige valg. Kjører mot TRG." -ForegroundColor Yellow; $selectedMenuItems = $choices | Where-Object { $_.Key -eq "TRG" } }

# --- Recurse-hjelpere ---------------------------------------------------------
function Get-DescendantMGs {
  param([string]$MgName)
  $queue = New-Object System.Collections.ArrayList; [void]$queue.Add($MgName)
  $seen = @{}; $result=@()
  while ($queue.Count -gt 0) {
    $name = $queue[0]; $null = $queue.RemoveAt(0)
    if ($seen.ContainsKey($name)) { continue }
    $seen[$name] = $true
    try {
      $mg = Get-AzManagementGroup -GroupName $name -Expand -ErrorAction Stop
      if ($mg) { $result += $mg }
      foreach ($c in ($mg.Children | Where-Object { $_.Type -like "*managementGroups*" })) { [void]$queue.Add($c.Name) }
    } catch { Write-Host ("Advarsel: kunne ikke expand MG {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Yellow }
  }
  return ($result | Sort-Object Name | Select-Object -Unique Name, DisplayName)
}
function Get-SubscriptionsUnderMGs {
  param([object[]]$MgEntries)
  $subSet = @{}
  foreach ($mg in $MgEntries) {
    try {
      $subs = Get-AzManagementGroupSubscription -GroupName $mg.Name -ErrorAction Stop
      foreach ($s in $subs) { if (-not $subSet.ContainsKey($s.Id)) { $subSet[$s.Id] = $s } }
    } catch { }
  }
  return $subSet.GetEnumerator() | ForEach-Object { $_.Value }
}

# Endelig arbeidsliste
$finalMGs=@(); $finalSubs=@()
foreach ($itm in $selectedMenuItems) {
  if ($itm.Type -eq "ManagementGroup") {
    if ($Recurse) {
      Write-Host ("Rekursiv traversering fra MG: {0}" -f $itm.Label) -ForegroundColor Cyan
      $allMgsUnder = Get-DescendantMGs -MgName $itm.Name
      $finalMGs += $allMgsUnder
      $finalSubs += Get-SubscriptionsUnderMGs -MgEntries $allMgsUnder
    } else { $finalMGs += [pscustomobject]@{ Name=$itm.Name; DisplayName=$itm.Label } }
  } else { $finalSubs += [pscustomobject]@{ Id=$itm.Name; Name=$itm.Label } }
}
$finalMGs  = $finalMGs  | Sort-Object Name | Select-Object -Unique Name, DisplayName
$finalSubs = $finalSubs | Sort-Object Id   | Select-Object -Unique Id, Name
if ((-not $finalMGs) -and (-not $finalSubs)) { $finalMGs = @([pscustomobject]@{ Name=$rootMg.Name; DisplayName=$rootMg.DisplayName }) }

# --- 5) Hent role assignments -------------------------------------------------
$allAssignments = @()
$raParams = @{}; if ($IncludeClassicAdmins) { $raParams['IncludeClassicAdministrators'] = $true }
foreach ($mg in $finalMGs) {
  $scope = "/providers/Microsoft.Management/managementGroups/$($mg.Name)"
  Write-Host ("Henter MG: {0}" -f $mg.DisplayName) -ForegroundColor Cyan
  try { $allAssignments += Get-AzRoleAssignment -Scope $scope @raParams -ErrorAction Stop }
  catch { Write-Host ("Advarsel: kunne ikke hente MG {0}: {1}" -f $mg.DisplayName, $_.Exception.Message) -ForegroundColor Yellow }
}
foreach ($sub in $finalSubs) {
  Write-Host ("Henter Subscription: {0}" -f $sub.Name) -ForegroundColor Cyan
  try { Set-AzContext -SubscriptionId $sub.Id -Tenant $ctx.Tenant.Id | Out-Null; $allAssignments += Get-AzRoleAssignment @raParams -ErrorAction Stop }
  catch { Write-Host ("Advarsel: kunne ikke hente Sub {0}: {1}" -f $sub.Name, $_.Exception.Message) -ForegroundColor Yellow }
}

# --- 6) Cacher & hjelpefunksjoner (principal + scope-detaljer) ----------------
$principalCache = @{}
function Resolve-Principal {
  param([string]$ObjectId,[string]$ObjectType,[string]$SignInName,[string]$DisplayName)
  if ([string]::IsNullOrWhiteSpace($ObjectId)) { return @{ FriendlyName=$DisplayName; PrincipalName=$SignInName } }
  if ($principalCache.ContainsKey($ObjectId)) { return $principalCache[$ObjectId] }
  $result = @{ FriendlyName=$DisplayName; PrincipalName=$SignInName }
  try {
    switch ($ObjectType) {
      'User' { $u = Get-AzADUser -ObjectId $ObjectId -ErrorAction Stop; $result.FriendlyName = $u.DisplayName; if ($u.UserPrincipalName) { $result.PrincipalName = $u.UserPrincipalName } }
      'Group' { $g = Get-AzADGroup -ObjectId $ObjectId -ErrorAction Stop; $result.FriendlyName = $g.DisplayName; if (-not $result.PrincipalName) { $result.PrincipalName = $g.DisplayName } }
      'ServicePrincipal' { $sp = Get-AzADServicePrincipal -ObjectId $ObjectId -ErrorAction Stop; $result.FriendlyName = $sp.AppDisplayName; if (-not $result.PrincipalName) { $result.PrincipalName = ($sp.ServicePrincipalNames | Select-Object -First 1) } }
      default { try { $obj = Get-AzADObject -ObjectId $ObjectId -ErrorAction Stop; if ($obj.DisplayName) { $result.FriendlyName = $obj.DisplayName }; if (-not $result.PrincipalName) { $result.PrincipalName = $obj.AdditionalProperties.userPrincipalName } } catch { } }
    }
  } catch { }
  $principalCache[$ObjectId] = $result; return $result
}

function Get-ScopeType { param([string]$Scope)
  if ($Scope -match "/providers/Microsoft.Management/managementGroups/") { "ManagementGroup" }
  elseif ($Scope -match "^/subscriptions/[^/]+$") { "Subscription" }
  elseif ($Scope -match "^/subscriptions/[^/]+/resourceGroups/[^/]+$") { "ResourceGroup" }
  else { "Resource" }
}

# Sub-id -> navn map (for raskt oppslag)
$subNameMap = @{}; foreach ($s in $subsAll) { $subNameMap[$s.Id] = $s.Name }

# Scope-cache: detaljer per scope (navn, type, rg, sub, tags)
$scopeCache = @{}
function Format-Tags { param($TagHash) if (-not $TagHash) { return "" } ($TagHash.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }) -join '; ' }

function Resolve-ScopeDetails {
  param([string]$Scope)
  if ($scopeCache.ContainsKey($Scope)) { return $scopeCache[$Scope] }

  $stype = Get-ScopeType -Scope $Scope
  $det = @{
    ResourceName      = $null
    ResourceType      = $null
    ResourceGroup     = $null
    SubscriptionId    = $null
    SubscriptionName  = $null
    Tags              = ""
  }

  try {
    if ($stype -eq "ManagementGroup") {
      $mgName = ($Scope -split "/")[-1]
      $det.ResourceName = $mgName
      $det.ResourceType = "Microsoft.Management/managementGroups"
    }
    elseif ($stype -eq "Subscription") {
      if ($Scope -match "^/subscriptions/([^/]+)$") { $det.SubscriptionId = $Matches[1] }
      $det.SubscriptionName = $subNameMap[$det.SubscriptionId]
      $det.ResourceName = $det.SubscriptionId
      $det.ResourceType = "Microsoft.Resources/subscriptions"
    }
    elseif ($stype -eq "ResourceGroup") {
      if ($Scope -match "^/subscriptions/([^/]+)/resourceGroups/([^/]+)$") {
        $det.SubscriptionId = $Matches[1]; $det.ResourceGroup = $Matches[2]; $det.SubscriptionName = $subNameMap[$det.SubscriptionId]
        try {
          Set-AzContext -SubscriptionId $det.SubscriptionId -Tenant $ctx.Tenant.Id | Out-Null
          $rg = Get-AzResourceGroup -Name $det.ResourceGroup -ErrorAction Stop
          $det.ResourceName = $rg.ResourceGroupName
          $det.ResourceType = "Microsoft.Resources/resourceGroups"
          $det.Tags = Format-Tags $rg.Tags
        } catch { $det.ResourceName = $det.ResourceGroup; $det.ResourceType = "Microsoft.Resources/resourceGroups" }
      }
    }
    else {
      # Resource
      if ($Scope -match "^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/.+$") {
        $det.SubscriptionId = $Matches[1]; $det.ResourceGroup = $Matches[2]; $det.SubscriptionName = $subNameMap[$det.SubscriptionId]
      }
      try {
        if ($det.SubscriptionId) { Set-AzContext -SubscriptionId $det.SubscriptionId -Tenant $ctx.Tenant.Id | Out-Null }
        $res = Get-AzResource -ResourceId $Scope -ErrorAction Stop
        $det.ResourceName = $res.Name
        $det.ResourceType = $res.ResourceType
        if (-not $det.ResourceGroup) { $det.ResourceGroup = $res.ResourceGroupName }
        $det.Tags = Format-Tags $res.Tags
      } catch {
        # fallback hvis Get-AzResource ikke treffer (child resources etc.)
        $parts = $Scope -split "/"
        $det.ResourceName = $parts[-1]
        $det.ResourceType = ($parts[6..($parts.Length-2)] -join "/") # providers/<ns>/<type>/...
      }
    }
  } catch { }

  $scopeCache[$Scope] = $det
  return $det
}

# --- 7) Normaliser assignments (med FriendlyName + ressurskolonner) -----------
$assignOut = $allAssignments | ForEach-Object {
  $resolved = Resolve-Principal -ObjectId $_.ObjectId -ObjectType $_.ObjectType -SignInName $_.SignInName -DisplayName $_.DisplayName
  $sd = Resolve-ScopeDetails -Scope $_.Scope
  [pscustomobject]@{
    FriendlyName      = $resolved.FriendlyName
    PrincipalName     = $resolved.PrincipalName
    PrincipalId       = $_.ObjectId
    PrincipalType     = $_.ObjectType
    RoleName          = $_.RoleDefinitionName
    RoleDefinitionId  = $_.RoleDefinitionId
    Scope             = $_.Scope
    ScopeType         = Get-ScopeType -Scope $_.Scope
    ResourceName      = $sd.ResourceName
    ResourceType      = $sd.ResourceType
    ResourceGroup     = $sd.ResourceGroup
    SubscriptionId    = $sd.SubscriptionId
    SubscriptionName  = $sd.SubscriptionName
    Tags              = $sd.Tags
  }
}

# --- 8) Rolledefinisjoner (inkl. custom pr. sub) ------------------------------
Write-Host "`nHenter rolledefinisjoner..." -ForegroundColor Cyan
$roleDefs = @{}
foreach ($sub in $subsAll) {
  try {
    Set-AzContext -SubscriptionId $sub.Id -Tenant $ctx.Tenant.Id | Out-Null
    Get-AzRoleDefinition | ForEach-Object { if (-not $roleDefs.ContainsKey($_.Id)) { $roleDefs[$_.Id] = $_ } }
  } catch { Write-Host ("Advarsel: kunne ikke hente rolledefinisjoner for {0}" -f $sub.Name) -ForegroundColor Yellow }
}
try { Get-AzRoleDefinition | ForEach-Object { if (-not $roleDefs.ContainsKey($_.Id)) { $roleDefs[$_.Id] = $_ } } } catch { }

# --- 9) Rolle-aggregat --------------------------------------------------------
$rolesOut = @()
$grpByRole = $assignOut | Group-Object RoleDefinitionId
foreach ($g in $grpByRole) {
  $rid = $g.Name; $def = $roleDefs[$rid]
  $actions=@(); $dataActions=@(); $notActions=@(); $notDataActions=@()
  if ($def) {
    $actions        = $def.Actions        | Sort-Object -Unique
    $dataActions    = $def.DataActions    | Sort-Object -Unique
    $notActions     = $def.NotActions     | Sort-Object -Unique
    $notDataActions = $def.NotDataActions | Sort-Object -Unique
  } else { Write-Host ("Advarsel: fant ikke role definition for {0}" -f $rid) -ForegroundColor Yellow }
  $scopesUsed = $g.Group | Select-Object -ExpandProperty Scope -Unique
  $scopeTypes = $g.Group | Select-Object -ExpandProperty ScopeType -Unique

  $rolesOut += [pscustomobject]@{
    RoleName         = $def?.RoleName ?? ($g.Group | Select-Object -First 1).RoleName
    RoleDefinitionId = $rid
    IsCustom         = $def?.IsCustom
    Assignments      = $g.Count
    ScopesCount      = $scopesUsed.Count
    ScopeTypesUsed   = ($scopeTypes -join '; ')
    ExampleScopes    = ($scopesUsed | Select-Object -First 5) -join '; '
    Actions          = ($actions -join '; ')
    DataActions      = ($dataActions -join '; ')
    NotActions       = ($notActions -join '; ')
    NotDataActions   = ($notDataActions -join '; ')
  }
}

# --- 10) Eksport --------------------------------------------------------------
$assignOut | Sort-Object ScopeType, RoleName, FriendlyName, PrincipalName | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $assignCsv
$rolesOut  | Sort-Object -Property @{Expression="Assignments";Descending=$true} | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $rolesCsv
if ($OutputJson) {
  $assignOut | ConvertTo-Json -Depth 8 | Out-File -FilePath $assignJson -Encoding UTF8
  $rolesOut  | ConvertTo-Json -Depth 6 | Out-File -FilePath $rolesJson  -Encoding UTF8
}

Write-Host "`nFerdig!" -ForegroundColor Green
Write-Host ("  Roller (unike): {0}" -f ($rolesOut.Count))
Write-Host ("  Tildelinger:     {0}" -f ($assignOut.Count))
Write-Host ("  Eksport:         {0}" -f (Resolve-Path $ExportPath))
Write-Host ("    - {0}" -f $rolesCsv)
Write-Host ("    - {0}" -f $assignCsv)
if ($OutputJson) { Write-Host ("    - {0}" -f $rolesJson); Write-Host ("    - {0}" -f $assignJson) }
if (-not $NoLog) { try { Stop-Transcript | Out-Null } catch { } }
