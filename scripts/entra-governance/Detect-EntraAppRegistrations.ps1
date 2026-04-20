#requires -Version 7.0
#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Export all Entra ID App Registrations and their permissions
  (configured and granted — delegated & application).

.DESCRIPTION
  Produces two CSV files:
    1) AppRegistrations_Summary.csv – one row per app (owners, secrets/certs, expirations, permissions, etc.)
    2) AppRegistrations_Permissions.csv – one row per (app × permission) with type (Configured/Granted)

.PARAMETER TenantId
  (Optional) Tenant GUID or a verified domain.

.PARAMETER ExpiringDays
  (Optional) Number of days used to flag secrets/certs approaching expiry (default: 30).

.PARAMETER OutputDir
  (Optional) Output directory for CSV export (default: current directory). Supports ~ and relative paths.

.NOTES
  Requires Microsoft.Graph PowerShell SDK (PS 7+ recommended).
  First time: Install-Module Microsoft.Graph -Scope CurrentUser -Force
  Author: Marius A. Skovli - Spirhed Group - https://spirhed.com
  Date: 7.10.2025
#>

[CmdletBinding()]
param(
  [string]$TenantId,
  [ValidateRange(1,365)][int]$ExpiringDays = 30,
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

# ---------------- Auth (Interactive-first, catch → Device Code) ----------------
$RequiredGraphScopes = @(
  'User.Read',
  'Directory.Read.All',
  'RoleManagementPolicy.Read.Directory',
  'RoleEligibilitySchedule.Read.Directory',
  'RoleAssignmentSchedule.Read.Directory',
  'RoleAssignmentSchedule.ReadWrite.Directory',
  'RoleManagement.Read.Directory',
  'RoleManagement.Read.All',
  'RoleManagement.ReadWrite.Directory',
  'Group.Read.All',
  'PrivilegedAccess.Read.AzureADGroup',
  'PrivilegedAccess.ReadWrite.AzureADGroup',
  'PrivilegedEligibilitySchedule.Read.AzureADGroup',
  'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup',
  'Application.Read.All',
  'DelegatedPermissionGrant.Read.All'
)

function Ensure-GraphWithScopes {
  Ensure-Module Microsoft.Graph -MinVersion '2.15.0'
  Ensure-Module Microsoft.Graph.Authentication
  Ensure-Module Microsoft.Graph.Identity.Governance
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
        try {
          Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
          $needLogin = $false
        } catch { $needLogin = $true }
      }
    }
  }

  if ($needLogin){
    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue){ Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    if (Get-Command Clear-MgContext    -ErrorAction SilentlyContinue){ Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue }

    $argsBase = @{ Scopes = $RequiredGraphScopes; NoWelcome = $true }
    if ($TenantId){ $argsBase.TenantId = $TenantId }

    # Try Interactive first (same process)
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

    if (Get-Command Select-MgProfile -ErrorAction SilentlyContinue) {
      Select-MgProfile -Name 'v1.0'
    } else {
      Write-Host "Select-MgProfile not available; continuing with default profile." -ForegroundColor DarkYellow
    }
  }
}

# ---------------- Helpers ----------------

$script:SpByAppId = @{}
$script:SpByObjectId = @{}

function Get-SpByAppId {
  param([Parameter(Mandatory)][string]$AppId)
  if ($SpByAppId.ContainsKey($AppId)) { return $SpByAppId[$AppId] }
  $sp = $null
  try {
    $sp = Get-MgServicePrincipal -Filter ("appId eq '{0}'" -f $AppId) -All -Property Id,AppId,DisplayName,AppRoles,Oauth2PermissionScopes | Select-Object -First 1
  } catch {}
  $SpByAppId[$AppId] = $sp
  return $sp
}

function Get-SpByObjectId {
  param([Parameter(Mandatory)][string]$ObjectId)
  if ($SpByObjectId.ContainsKey($ObjectId)) { return $SpByObjectId[$ObjectId] }
  $sp = $null
  try {
    $sp = Get-MgServicePrincipal -ServicePrincipalId $ObjectId -Property Id,AppId,DisplayName,AppRoles,Oauth2PermissionScopes
  } catch {}
  $SpByObjectId[$ObjectId] = $sp
  return $sp
}

# Returns value from direct property or from AdditionalProperties bag (Graph SDK varies)
function Get-AnyProp {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string[]]$Names
  )
  foreach ($n in $Names) {
    if ($Object.PSObject.Properties[$n]) { return $Object.$n }
    if ($Object.AdditionalProperties -and $Object.AdditionalProperties.ContainsKey($n)) {
      return $Object.AdditionalProperties[$n]
    }
  }
  return $null
}

# Convert owner objects to readable labels (robust and always returns an array)
function Convert-OwnerObjectsToLabels {
  param([Parameter(Mandatory)][object[]]$Objects)

  if (-not $Objects) { return @() }

  $labels = foreach ($o in $Objects) {
    # Pull common fields (works for both SDK models and raw REST objects)
    $id    = Get-AnyProp -Object $o -Names @('id','Id')
    $dn    = Get-AnyProp -Object $o -Names @('displayName','DisplayName')
    $upn   = Get-AnyProp -Object $o -Names @('userPrincipalName','UserPrincipalName')
    $mail  = Get-AnyProp -Object $o -Names @('mail','Mail')
    $appId = Get-AnyProp -Object $o -Names @('appId','AppId')
    $grpClues = @( Get-AnyProp -Object $o -Names @('groupTypes','securityEnabled','mailEnabled') ) -ne $null

    # Detect kind via strongest clues first (properties), then type names
    $isUser  = ($upn -or $mail) -or ($o.PSObject.TypeNames -match 'User')
    $isSp    = $appId -or ($o.PSObject.TypeNames -match 'ServicePrincipal')
    $isGroup = ($grpClues -contains $true) -or ($o.PSObject.TypeNames -match 'Group')

    if     ($isUser)  { if ($upn) { $upn } elseif ($mail) { $mail } elseif ($dn) { $dn } else { $id } }
    elseif ($isSp)    { if ($dn)  { "SP:$dn" } elseif ($appId) { "SP:$appId" } else { "SP:$id" } }
    elseif ($isGroup) { if ($dn)  { "Group:$dn" } else { "Group:$id" } }
    else              { if ($dn)  { $dn } else { $id } }
  }

  # Unary comma ensures an array is returned even when single item
  return ,($labels | Where-Object { $_ -and $_ -ne '' })
}

function Get-AppOwnersInfo {
  param([Parameter(Mandatory)][string]$ApplicationObjectId)

  # 1) Cmdlet path first
  $cmdletErr = $null
  try {
    $owners = @( Get-MgApplicationOwner -ApplicationId $ApplicationObjectId -All -ErrorAction Stop )
  } catch {
    $cmdletErr = $_.Exception.Message
    $owners = @()
  }

  if ($owners.Count -gt 0) {
    $labels = @( Convert-OwnerObjectsToLabels -Objects $owners )
    return [pscustomobject]@{
      Owners      = ($labels -join ';')
      OwnersCount = $labels.Count
      OwnersNote  = ''
    }
  }

  # 2) Fallback: raw REST (handles both wrapped {value=...} and plain arrays)
  try {
    $uri = "https://graph.microsoft.com/v1.0/applications/$ApplicationObjectId/owners?`$select=id,displayName,userPrincipalName,mail,appId,appDisplayName"
    $all = New-Object System.Collections.Generic.List[object]

    do {
      $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop

      $hasValue = ($resp -isnot [System.Array]) -and ($resp.PSObject.Properties.Name -contains 'value')
      if ($hasValue) {
        foreach($it in $resp.value){ $all.Add($it) }
      } else {
        # Some SDKs return the array directly when no paging
        foreach($it in @($resp)){ $all.Add($it) }
      }

      $hasNextLink = ($resp -isnot [System.Array]) -and ($resp.PSObject.Properties.Name -contains '@odata.nextLink')
      $uri = if ($hasNextLink) { $resp.'@odata.nextLink' } else { $null }
    } while ($uri)

    $labels = @( Convert-OwnerObjectsToLabels -Objects $all.ToArray() )
    return [pscustomobject]@{
      Owners      = ($labels -join ';')
      OwnersCount = $labels.Count
      OwnersNote  = ($cmdletErr ? "Cmdlet failed: $cmdletErr" : '')
    }
  } catch {
    $msg = $_.Exception.Message
    return [pscustomobject]@{
      Owners      = ''
      OwnersCount = 0
      OwnersNote  = "Owners fetch failed: $msg"
    }
  }
}

function Resolve-ResourcePermissionName {
  param(
    [Parameter(Mandatory)][string]$ResourceAppId,
    [Parameter(Mandatory)][Guid]  $AccessId,
    [Parameter(Mandatory)][ValidateSet('Scope','Role')][string]$Type
  )
  $resSp = Get-SpByAppId -AppId $ResourceAppId
  if (-not $resSp) { return ('[unknown-{0}:{1}]' -f $Type, $AccessId) }
  if ($Type -eq 'Role') {
    $role = $resSp.AppRoles | Where-Object { $_.Id -eq $AccessId }
    if ($role) { return $role.Value } else { return ('[unknown-role:{0}]' -f $AccessId) }
  } else {
    $scope = $resSp.Oauth2PermissionScopes | Where-Object { $_.Id -eq $AccessId }
    if ($scope) { return $scope.Value } else { return ('[unknown-scope:{0}]' -f $AccessId) }
  }
}

function To-IsoUtcOrEmpty {
  param([Nullable[datetimeoffset]]$Value)
  if (-not $Value) { return "" }
  [DateTimeOffset]::Parse($Value.ToString()).ToUniversalTime().ToString("o")
}

# ---------------- Main ----------------

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Ensure-GraphWithScopes

# Output directory
try {
  $resolvedOutputDir = (Resolve-Path -Path $OutputDir -ErrorAction Stop).Path
} catch {
  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
  $resolvedOutputDir = (Resolve-Path -Path $OutputDir).Path
}

# Fetch Applications
Write-Host "Fetching App Registrations..." -ForegroundColor Cyan
$appProps = @(
  "Id","AppId","DisplayName","PublisherDomain","VerifiedPublisher",
  "PasswordCredentials","KeyCredentials","RequiredResourceAccess","SignInAudience"
)
$apps = Get-MgApplication -All -Property $appProps

$ctxAfter = Get-MgContext -ErrorAction SilentlyContinue
$tenantShown = if ($ctxAfter -and $ctxAfter.TenantId) { $ctxAfter.TenantId } else { '' }
Write-Host ("Tenant: {0} | Applications: {1}" -f ($tenantShown ?? '<unknown>'), $apps.Count) -ForegroundColor DarkCyan

# Collect rows
$summaryRows = New-Object System.Collections.Generic.List[object]
$permRows    = New-Object System.Collections.Generic.List[object]

$nowUtc  = [DateTimeOffset]::UtcNow
$soonUtc = $nowUtc.AddDays($ExpiringDays)

Write-Host ("Processing {0} apps..." -f $apps.Count) -ForegroundColor Yellow
$idx = 0

foreach ($app in $apps) {
  $idx++
  Write-Progress -Activity "Processing app registrations" -Status ('{0} / {1}: {2}' -f $idx, $apps.Count, $app.DisplayName) -PercentComplete ([int](100*$idx/$apps.Count))

  $sp = $null
  if ($app.AppId) { $sp = Get-SpByAppId -AppId $app.AppId }

  # Configured permissions
  $configuredAppPerms    = @()
  $configuredDelegScopes = @()
  foreach ($rra in ($app.RequiredResourceAccess | Where-Object { $_ })) {
    $resSp = Get-SpByAppId -AppId $rra.ResourceAppId
    $resName = if ($resSp) { $resSp.DisplayName } else { $rra.ResourceAppId }
    foreach ($ra in ($rra.ResourceAccess | Where-Object { $_ })) {
      $name  = Resolve-ResourcePermissionName -ResourceAppId $rra.ResourceAppId -AccessId $ra.Id -Type $ra.Type
      $entry = ('{0}/{1}' -f $resName, $name)
      if ($ra.Type -eq "Role") { $configuredAppPerms += $entry } else { $configuredDelegScopes += $entry }
    }
  }

  # Granted application permissions
  $grantedAppPerms = @()
  if ($sp) {
    try {
      $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All
      foreach ($ara in $appRoleAssignments) {
        $targetSp   = Get-SpByObjectId -ObjectId $ara.ResourceId
        $targetName = if ($targetSp) { $targetSp.DisplayName } else { $ara.ResourceId }
        $roleName   = $null
        if ($targetSp -and $targetSp.AppRoles) {
          $match = $targetSp.AppRoles | Where-Object { $_.Id -eq $ara.AppRoleId }
          if ($match) { $roleName = $match.Value }
        }
        if (-not $roleName) { $roleName = ('[unknown-role:{0}]' -f $ara.AppRoleId) }
        $grantedAppPerms += ('{0}/{1}' -f $targetName, $roleName)
      }
    } catch {
      Write-Host ("[WARN] Error fetching AppRoleAssignments for SP {0}: {1}" -f $sp.Id, $_.Exception.Message) -ForegroundColor DarkYellow
    }
  }

  # Granted delegated permissions
  $grantedDelegScopes = @()
  if ($sp) {
    try {
      $grants = Get-MgOauth2PermissionGrant -All -Filter ("clientId eq '{0}'" -f $sp.Id)
      foreach ($g in $grants) {
        $resSp   = Get-SpByObjectId -ObjectId $g.ResourceId
        $resName = if ($resSp) { $resSp.DisplayName } else { $g.ResourceId }
        if ($g.Scope) {
          foreach ($s in ($g.Scope -split ' ' | Where-Object { $_ })) {
            $grantedDelegScopes += ('{0}/{1}' -f $resName, $s)
          }
        }
      }
    } catch {
      Write-Host ("[WARN] Error fetching OAuth2PermissionGrants for SP {0}: {1}" -f $sp.Id, $_.Exception.Message) -ForegroundColor DarkYellow
    }
  }

  # Owners
  $ownerInfo   = Get-AppOwnersInfo -ApplicationObjectId $app.Id
  $owners      = $ownerInfo.Owners
  $ownersCount = $ownerInfo.OwnersCount
  $ownersNote  = $ownerInfo.OwnersNote

  # Expirations
  $secretExpiries = @($app.PasswordCredentials | ForEach-Object { $_.EndDateTime } | Where-Object { $_ })
  $certExpiries   = @($app.KeyCredentials     | ForEach-Object { $_.EndDateTime } | Where-Object { $_ })
  $nextSecretExpiry = $secretExpiries | Sort-Object | Select-Object -First 1
  $nextCertExpiry   = $certExpiries   | Sort-Object | Select-Object -First 1
  $nextSecretUtc = if ($nextSecretExpiry) { [DateTimeOffset]$nextSecretExpiry } else { $null }
  $nextCertUtc   = if ($nextCertExpiry)   { [DateTimeOffset]$nextCertExpiry }   else { $null }
  $soonUtc = [DateTimeOffset]::UtcNow.AddDays($ExpiringDays)
  $secretExpiringSoon = $nextSecretUtc -and ($nextSecretUtc.ToUniversalTime() -lt $soonUtc)
  $certExpiringSoon   = $nextCertUtc   -and ($nextCertUtc.ToUniversalTime()   -lt $soonUtc)

  # Summary row
  $summaryRows.Add([pscustomobject]@{
    TenantId                      = $tenantShown
    AppDisplayName                = $app.DisplayName
    AppId                         = $app.AppId
    ApplicationObjectId           = $app.Id
    ServicePrincipalObjectId      = if ($sp) { $sp.Id } else { "" }
    PublisherDomain               = $app.PublisherDomain
    VerifiedPublisher             = if ($app.VerifiedPublisher -and $app.VerifiedPublisher.DisplayName) { $app.VerifiedPublisher.DisplayName } else { "" }
    Owners                        = $owners
    OwnersCount                   = $ownersCount
    OwnersNote                    = $ownersNote
    SecretsCount                  = @($app.PasswordCredentials).Count
    CertificatesCount             = @($app.KeyCredentials).Count
    NextSecretExpiryUtc           = To-IsoUtcOrEmpty $nextSecretUtc
    NextCertExpiryUtc             = To-IsoUtcOrEmpty $nextCertUtc
    SecretExpiringWithinDays      = [bool]$secretExpiringSoon
    CertExpiringWithinDays        = [bool]$certExpiringSoon
    ConfiguredApplicationPerms    = ($configuredAppPerms    | Sort-Object -Unique) -join "; "
    ConfiguredDelegatedScopes     = ($configuredDelegScopes | Sort-Object -Unique) -join "; "
    GrantedApplicationPerms       = ($grantedAppPerms       | Sort-Object -Unique) -join "; "
    GrantedDelegatedScopes        = ($grantedDelegScopes    | Sort-Object -Unique) -join "; "
  })

  # Permission rows (include Owners)
  foreach ($p in ($configuredAppPerms | Sort-Object -Unique)) {
    $permRows.Add([pscustomobject]@{
      TenantId = $tenantShown; AppDisplayName = $app.DisplayName; AppId = $app.AppId
      ServicePrincipalId = if ($sp) { $sp.Id } else { "" }; Owners = $owners
      PermissionType = "ConfiguredApplication"; Permission = $p
    })
  }
  foreach ($p in ($configuredDelegScopes | Sort-Object -Unique)) {
    $permRows.Add([pscustomobject]@{
      TenantId = $tenantShown; AppDisplayName = $app.DisplayName; AppId = $app.AppId
      ServicePrincipalId = if ($sp) { $sp.Id } else { "" }; Owners = $owners
      PermissionType = "ConfiguredDelegated"; Permission = $p
    })
  }
  foreach ($p in ($grantedAppPerms | Sort-Object -Unique)) {
    $permRows.Add([pscustomobject]@{
      TenantId = $tenantShown; AppDisplayName = $app.DisplayName; AppId = $app.AppId
      ServicePrincipalId = if ($sp) { $sp.Id } else { "" }; Owners = $owners
      PermissionType = "GrantedApplication"; Permission = $p
    })
  }
  foreach ($p in ($grantedDelegScopes | Sort-Object -Unique)) {
    $permRows.Add([pscustomobject]@{
      TenantId = $tenantShown; AppDisplayName = $app.DisplayName; AppId = $app.AppId
      ServicePrincipalId = if ($sp) { $sp.Id } else { "" }; Owners = $owners
      PermissionType = "GrantedDelegated"; Permission = $p
    })
  }
}

# Export
$summaryPath = Join-Path -Path $resolvedOutputDir -ChildPath "AppRegistrations_Summary.csv"
$permsPath   = Join-Path -Path $resolvedOutputDir -ChildPath "AppRegistrations_Permissions.csv"
$summaryRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $summaryPath
$permRows    | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $permsPath

$sw.Stop()
Write-Host ("Done in {0}s" -f [int]$sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host ("Summary:   {0}" -f $summaryPath)
Write-Host ("Perm-rows: {0}" -f $permsPath)
