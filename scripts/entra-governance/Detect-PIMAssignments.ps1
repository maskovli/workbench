#requires -Version 7.0
#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Export PIM (Privileged Access) role assignments per user:
  - Entra Directory roles (eligible + active)
  - PIM for Groups (eligible + active; member/owner)
  Includes users with no assignments (placeholder row).

.PARAMETER UserQuery
  One or more terms to find users (e.g., "Roger Johansen").

.PARAMETER SelectWithGrid
  Show GridView to pick one/many when multiple hits.

.PARAMETER TenantId
  Tenant GUID or verified domain (e.g., spirhed.onmicrosoft.com).

.PARAMETER OutputDir
  Output directory for CSV export (default: current directory).

.NOTES
  Requires Microsoft.Graph PowerShell SDK (PS 7+).
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

# ---------------- Common setup ----------------
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
  catch { New-Item -ItemType Directory -Path $Path -Force | Out-Null; return (Resolve-Path -Path $Path).Path }
}

# ---------------- Auth (interactive → device code; reuse session) ----------------
$RequiredGraphScopes = @(
  'User.Read',
  'Directory.Read.All',
  'RoleManagement.Read.Directory',
  'RoleEligibilitySchedule.Read.Directory',
  'RoleAssignmentSchedule.Read.Directory',
  'Group.Read.All',
  'PrivilegedAccess.Read.AzureADGroup'  # best effort; may 403 if feature disabled
)

function Ensure-GraphWithScopes {
  Ensure-Module Microsoft.Graph -MinVersion '2.15.0'
  Ensure-Module Microsoft.Graph.Authentication
  Ensure-Module Microsoft.Graph.Users
  Ensure-Module Microsoft.Graph.Groups
  Ensure-Module Microsoft.Graph.Identity.Governance
  Ensure-Module Microsoft.Graph.DirectoryObjects

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

# ---------------- Robust user search (always returns array) ----------------
function Find-Users {
  param([string[]]$Queries)
  if (-not $Queries -or $Queries.Count -eq 0){ throw "Please provide -UserQuery (e.g., -UserQuery 'Roger Johansen')." }

  $all = New-Object System.Collections.Generic.List[object]
  foreach($q in $Queries){
    $s = $q.Trim(); if (-not $s){ continue }

    $searchTerms = @(
      ('"displayName:{0}"'       -f $s),
      ('"userPrincipalName:{0}"' -f $s),
      ('"mail:{0}"'              -f $s)
    )
    foreach($st in $searchTerms){
      try { (Get-MgUser -Search $st -ConsistencyLevel eventual -All -Property "id,displayName,userPrincipalName,mail") | ForEach-Object { $all.Add($_) } } catch {}
    }
    try {
      $filterName = "startsWith(displayName,'{0}')" -f $s.Replace("'","''")
      (Get-MgUser -Filter $filterName -All -Property "id,displayName,userPrincipalName,mail") | ForEach-Object { $all.Add($_) }
    } catch {}
    try {
      if ($s -match '@' -or $s -match '^[0-9a-fA-F-]{36}$') {
        $u3 = Get-MgUser -UserId $s -Property "id,displayName,userPrincipalName,mail" -ErrorAction SilentlyContinue
        if ($u3){ $all.Add($u3) }
      }
    } catch {}
  }
  $uniq = $all | Group-Object id | ForEach-Object { $_.Group | Select-Object -First 1 }
  return @($uniq)
}
function Pick-Users([array]$Users,[switch]$AllowMulti){
  $Users=@($Users); if ($Users.Count -eq 0){ return @() }
  if ($Users.Count -eq 1 -or -not (Ensure-Grid)){ return ,$Users[0] }
  $proj = foreach($u in $Users){ [pscustomobject]@{DisplayName=$u.DisplayName;UserPrincipalName=$u.UserPrincipalName;Mail=$u.Mail;__Ref=$u} }
  $mode = $AllowMulti ? 'Multiple' : 'Single'
  $sel  = $proj | Out-ConsoleGridView -Title "Select user(s)" -OutputMode $mode
  if (-not $sel){ return @() }
  if ($AllowMulti){ return @($sel | ForEach-Object { $_.__Ref }) } else { return ,$sel.__Ref }
}

# ---------------- Caches / resolvers ----------------
$script:DirRoleDefById = @{}
function Get-DirRoleName([string]$RoleDefinitionId){
  if ($DirRoleDefById.ContainsKey($RoleDefinitionId)){ return $DirRoleDefById[$RoleDefinitionId] }
  try {
    $def = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $RoleDefinitionId -ErrorAction Stop
    $name = $def.DisplayName
  } catch {
    try { $name = (Get-MgRoleManagementDirectoryRoleDefinition -Filter ("id eq '{0}'" -f $RoleDefinitionId)).DisplayName } catch { $name = $RoleDefinitionId }
  }
  $DirRoleDefById[$RoleDefinitionId] = $name
  return $name
}
$script:GroupNameById = @{}
function Get-GroupName([string]$GroupId){
  if ($GroupNameById.ContainsKey($GroupId)){ return $GroupNameById[$GroupId] }
  try { $name=(Get-MgGroup -GroupId $GroupId -Property DisplayName -ErrorAction Stop).DisplayName } catch { $name=$GroupId }
  $GroupNameById[$GroupId]=$name; return $name
}

# ---------------- Feature flags (for graceful 403 handling) ----------------
$script:PimGroupsAvailable = $true
$script:PimGroupsWarned = $false
function Warn-PimGroupsOnce([string]$msg){
  if (-not $script:PimGroupsWarned){
    Write-Warning "PIM for Groups not accessible: $msg (skipping group assignments for remaining users)."
    $script:PimGroupsWarned = $true
  }
}

# ---------------- Fetchers ----------------
function Get-DirectoryEligible([string]$UserId){
  try { Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter ("principalId eq '{0}'" -f $UserId) -All -ErrorAction Stop }
  catch { @() }
}
function Get-DirectoryActive([string]$UserId){
  try { Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter ("principalId eq '{0}'" -f $UserId) -All -ErrorAction Stop }
  catch { @() }
}
function Get-GroupEligible([string]$UserId){
  if (-not $script:PimGroupsAvailable){ return @() }
  try {
    Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance -Filter ("principalId eq '{0}'" -f $UserId) -All -ErrorAction Stop
  } catch {
    if ($_.Exception.Message -match 'Forbidden|Unauthorized'){
      $script:PimGroupsAvailable = $false; Warn-PimGroupsOnce $_.Exception.Message; return @()
    }
    @()
  }
}
function Get-GroupActive([string]$UserId){
  if (-not $script:PimGroupsAvailable){ return @() }
  try {
    Get-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleInstance -Filter ("principalId eq '{0}'" -f $UserId) -All -ErrorAction Stop
  } catch {
    if ($_.Exception.Message -match 'Forbidden|Unauthorized'){
      $script:PimGroupsAvailable = $false; Warn-PimGroupsOnce $_.Exception.Message; return @()
    }
    @()
  }
}

# ---------------- Row builders ----------------
function Add-DirRows([System.Collections.Generic.List[object]]$rows,[object[]]$eligible,[object[]]$active,[string]$userDn,[string]$userUpn,[string]$userId){
  $activeSet=@{}
  foreach($a in $active){
    $key="$($a.RoleDefinitionId)|$([string]::IsNullOrEmpty($a.DirectoryScopeId) ? '/' : $a.DirectoryScopeId)"
    $activeSet[$key]=1
  }

  foreach($e in $eligible){
    $scope = if ([string]::IsNullOrEmpty($e.DirectoryScopeId)) { '/' } else { $e.DirectoryScopeId }
    $key="$($e.RoleDefinitionId)|$scope"
    $rows.Add([pscustomobject]@{
      UserDisplayName      = $userDn
      UserPrincipalName    = $userUpn
      UserId               = $userId
      Category             = 'Directory'
      RoleOrAccess         = (Get-DirRoleName $e.RoleDefinitionId)
      Scope                = $scope
      AssignmentType       = 'Eligible'
      ActiveNow            = [bool]$activeSet.ContainsKey($key)
      StartDateTimeUtc     = $e.StartDateTime
      EndDateTimeUtc       = $e.EndDateTime
      ScheduleInstanceId   = $e.Id
    })
  }

  foreach($a in $active){
    $scope = if ([string]::IsNullOrEmpty($a.DirectoryScopeId)) { '/' } else { $a.DirectoryScopeId }
    $rows.Add([pscustomobject]@{
      UserDisplayName      = $userDn
      UserPrincipalName    = $userUpn
      UserId               = $userId
      Category             = 'Directory'
      RoleOrAccess         = (Get-DirRoleName $a.RoleDefinitionId)
      Scope                = $scope
      AssignmentType       = 'Active'
      ActiveNow            = $true
      StartDateTimeUtc     = $a.StartDateTime
      EndDateTimeUtc       = $a.EndDateTime
      ScheduleInstanceId   = $a.Id
    })
  }
}

function Add-GroupRows([System.Collections.Generic.List[object]]$rows,[object[]]$eligible,[object[]]$active,[string]$userDn,[string]$userUpn,[string]$userId){
  $activeSet=@{}
  foreach($a in $active){ $activeSet["$($a.GroupId)|$($a.AccessId)"]=1 }

  foreach($e in $eligible){
    $access = switch ($e.AccessId) { 'member' {'member'} 'owner' {'owner'} default {$e.AccessId} }
    $rows.Add([pscustomobject]@{
      UserDisplayName      = $userDn
      UserPrincipalName    = $userUpn
      UserId               = $userId
      Category             = 'Group'
      RoleOrAccess         = "$(Get-GroupName $e.GroupId) / $access"
      Scope                = $e.GroupId
      AssignmentType       = 'Eligible'
      ActiveNow            = [bool]$activeSet.ContainsKey("$($e.GroupId)|$($e.AccessId)")
      StartDateTimeUtc     = $e.StartDateTime
      EndDateTimeUtc       = $e.EndDateTime
      ScheduleInstanceId   = $e.Id
    })
  }

  foreach($a in $active){
    $access = switch ($a.AccessId) { 'member' {'member'} 'owner' {'owner'} default {$a.AccessId} }
    $rows.Add([pscustomobject]@{
      UserDisplayName      = $userDn
      UserPrincipalName    = $userUpn
      UserId               = $userId
      Category             = 'Group'
      RoleOrAccess         = "$(Get-GroupName $a.GroupId) / $access"
      Scope                = $a.GroupId
      AssignmentType       = 'Active'
      ActiveNow            = $true
      StartDateTimeUtc     = $a.StartDateTime
      EndDateTimeUtc       = $a.EndDateTime
      ScheduleInstanceId   = $a.Id
    })
  }
}

# ---------------- MAIN ----------------
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
  Write-Progress -Activity "Fetching PIM assignments" -Status ("{0}/{1} {2}" -f $uIdx,$users.Count,$u.DisplayName) -PercentComplete ([int](100*$uIdx/$users.Count))

  # Directory roles
  $dirElig = @(Get-DirectoryEligible -UserId $u.Id)
  $dirAct  = @(Get-DirectoryActive   -UserId $u.Id)
  Add-DirRows -rows $rows -eligible $dirElig -active $dirAct -userDn $u.DisplayName -userUpn $u.UserPrincipalName -userId $u.Id

  # PIM for Groups (graceful skip if 403)
  $grpElig = @(Get-GroupEligible -UserId $u.Id)
  $grpAct  = @(Get-GroupActive   -UserId $u.Id)
  if ($script:PimGroupsAvailable){
    Add-GroupRows -rows $rows -eligible $grpElig -active $grpAct -userDn $u.DisplayName -userUpn $u.UserPrincipalName -userId $u.Id
  }

  # Ensure users without any assignments are represented
  if ($dirElig.Count -eq 0 -and $dirAct.Count -eq 0 -and ($script:PimGroupsAvailable -eq $false -or ($grpElig.Count -eq 0 -and $grpAct.Count -eq 0))) {
    $rows.Add([pscustomobject]@{
      UserDisplayName      = $u.DisplayName
      UserPrincipalName    = $u.UserPrincipalName
      UserId               = $u.Id
      Category             = 'None'
      RoleOrAccess         = ''
      Scope                = ''
      AssignmentType       = 'None'
      ActiveNow            = $false
      StartDateTimeUtc     = $null
      EndDateTimeUtc       = $null
      ScheduleInstanceId   = ''
    })
  }
}

# Export
$ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
$out = Join-Path $resolvedOutputDir ("PIMAssignments_{0}.csv" -f $ts)
$rows | Sort-Object UserDisplayName, Category, RoleOrAccess, AssignmentType | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $out

$sw.Stop()
Write-Host ("Done in {0}s" -f [int]$sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host ("CSV: {0}" -f $out)