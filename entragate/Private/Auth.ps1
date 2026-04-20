# ── Private/Auth.ps1 · Shared authentication for all EntraGate modules ──

$script:RequiredGraphScopes = @(
  'User.Read'
  'Directory.Read.All'
  'Organization.Read.All'
  # PIM - Directory
  'RoleManagementPolicy.Read.Directory'
  'RoleEligibilitySchedule.Read.Directory'
  'RoleAssignmentSchedule.Read.Directory'
  'RoleAssignmentSchedule.ReadWrite.Directory'
  'RoleManagement.Read.Directory'
  'RoleManagement.Read.All'
  'RoleManagement.ReadWrite.Directory'
  # PIM - Groups
  'Group.Read.All'
  'PrivilegedAccess.Read.AzureADGroup'
  'PrivilegedAccess.ReadWrite.AzureADGroup'
  'PrivilegedEligibilitySchedule.Read.AzureADGroup'
  'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
  # Access Reviews
  'AccessReview.ReadWrite.All'
  # App registrations
  'Application.Read.All'
  # Risky users / sign-ins
  'IdentityRiskEvent.Read.All'
  'IdentityRiskyUser.Read.All'
)

function Invoke-GateGraphLogin {
  <# .SYNOPSIS  Force a fresh Graph login. Clears old contexts first. #>
  param([string]$Method, [string]$TenantId)

  if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
  }
  if (Get-Command Clear-MgContext -ErrorAction SilentlyContinue) {
    Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue
  }
  # Drop lingering Az session when switching identity
  if (Get-Command Disconnect-AzAccount -ErrorAction SilentlyContinue) {
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }

  $connArgs = @{
    Scopes       = $script:RequiredGraphScopes
    NoWelcome    = $true
    ContextScope = 'Process'
  }
  if ($TenantId) { $connArgs.TenantId = $TenantId }

  $useDevice = ($Method -eq 'DeviceCode') -or ($PSVersionTable.OS -match 'Darwin' -and $Method -eq 'Auto')

  if ($useDevice) {
    Write-Cyber "Connecting to Microsoft Graph (Device Code)..." 'AUTH' 'Yellow'
    $connArgs.UseDeviceCode = $true
    Connect-MgGraph @connArgs
  } else {
    Write-Cyber "Connecting to Microsoft Graph (Interactive)..." 'AUTH' 'Yellow'
    try { Connect-MgGraph @connArgs }
    catch {
      Write-Warning "Interactive failed, falling back to Device Code..."
      $connArgs.UseDeviceCode = $true
      Connect-MgGraph @connArgs
    }
  }

  $ctx = Get-MgContext
  if (-not $ctx -or -not $ctx.Account) { throw "Login failed." }
  Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
  Write-Cyber "Signed in as: $($ctx.Account)" 'OK' 'Green'

  # Reset cached state
  $script:GateSession.GraphConnected   = $true
  $script:GateSession.CachedTenantName = $null
  $script:GateSession.CachedUserId     = $null
}

function Connect-GateGraph {
  <#
  .SYNOPSIS  Ensure a valid Graph session — reuse, switch, or fresh login.
  .DESCRIPTION
    Shows existing session info and lets user [C]ontinue, [S]witch, or [Q]uit.
    Called automatically by Start-EntraGate; individual modules can also call it.
  #>
  param(
    [string] $TenantId,
    [ValidateSet('Auto','Interactive','DeviceCode')]
    [string] $Auth = 'Auto',
    [switch] $ForceLogin
  )

  # Reset per-session caches
  $script:GateSession.CachedTenantName = $null
  $script:GateSession.AzConnected      = $false

  if ($ForceLogin) { Invoke-GateGraphLogin -Method $Auth -TenantId $TenantId; return }

  $ctx = Get-MgContext -ErrorAction SilentlyContinue
  if ($ctx -and $ctx.Account) {
    $alive = $false
    try {
      Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
      $alive = $true
    } catch {}

    if ($alive) {
      $tenantMismatch = $TenantId -and ($TenantId -ne $ctx.TenantId)
      Write-Host ""
      Write-Host "Existing Microsoft Graph session:" -ForegroundColor Cyan
      Write-Host ("  Account : {0}" -f $ctx.Account)
      Write-Host ("  Tenant  : {0}" -f $ctx.TenantId)
      if ($tenantMismatch) {
        Write-Host ("  Note    : Requested tenant '{0}' differs." -f $TenantId) -ForegroundColor Yellow
      }
      Write-Host ""
      Write-Host "  [C] Continue  [S] Switch account  [Q] Quit" -ForegroundColor Cyan
      $ans = Read-Host "Select [C/S/Q]"

      switch -Regex ($ans) {
        '^(q|Q)$' { throw "Aborted by user." }
        '^(s|S)$' { Invoke-GateGraphLogin -Method $Auth -TenantId $TenantId; return }
        default {
          if ($tenantMismatch) {
            Write-Host "Re-authenticating for requested tenant..." -ForegroundColor Yellow
            Invoke-GateGraphLogin -Method $Auth -TenantId $TenantId
            return
          }
          Write-Cyber "Reusing existing session." 'OK' 'Green'
          $script:GateSession.GraphConnected = $true
          return
        }
      }
    }
  }

  Invoke-GateGraphLogin -Method $Auth -TenantId $TenantId
}

function Connect-GateAzure {
  <#
  .SYNOPSIS  Lazy Azure connection — validates identity matches Graph session.
  .DESCRIPTION
    Only called when Azure Resources PIM is needed. Ensures Az identity
    matches the active Graph identity to prevent cross-tenant leaks.
  #>
  param([string]$TenantId)

  if ($script:GateSession.AzConnected) { return }

  # Ensure Az modules
  if (-not (Get-Module -ListAvailable -Name 'Az.Accounts')) {
    throw "Az.Accounts not installed. Run: Install-Module Az.Accounts -Scope CurrentUser -Force"
  }
  if (-not (Get-Module -ListAvailable -Name 'Az.Resources')) {
    throw "Az.Resources not installed. Run: Install-Module Az.Resources -Scope CurrentUser -Force"
  }
  Import-Module Az.Accounts  -ErrorAction Stop | Out-Null
  Import-Module Az.Resources -ErrorAction Stop | Out-Null

  # Truth from Graph
  $graphCtx = Get-MgContext -ErrorAction SilentlyContinue
  if (-not $graphCtx -or -not $graphCtx.Account) {
    throw "No Graph session — connect to Graph first."
  }
  $expectedUpn    = $graphCtx.Account
  $expectedTenant = if ($TenantId) { $TenantId } else { $graphCtx.TenantId }

  # Check existing Az session
  $azCtx = Get-AzContext -ErrorAction SilentlyContinue
  if ($azCtx -and $azCtx.Account) {
    $upnOk    = ($azCtx.Account.Id -ieq $expectedUpn)
    $tenantOk = ($azCtx.Tenant.Id  -ieq $expectedTenant)
    if ($upnOk -and $tenantOk) {
      Write-Cyber "Az session matches Graph identity." 'OK' 'Green'
      $script:GateSession.AzConnected = $true
      return
    }
    Write-Cyber "Az session mismatch — re-authenticating." 'WARN' 'Yellow'
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }

  Write-Cyber "Connecting to Azure as $expectedUpn..." 'AUTH' 'Yellow'
  Connect-AzAccount -Tenant $expectedTenant -AccountId $expectedUpn -UseDeviceAuthentication | Out-Null

  # Verify
  $newCtx = Get-AzContext -ErrorAction SilentlyContinue
  if (-not $newCtx -or $newCtx.Account.Id -ine $expectedUpn) {
    throw "Azure login returned wrong identity."
  }
  Write-Cyber "Az session OK: $($newCtx.Account.Id)" 'OK' 'Green'
  $script:GateSession.AzConnected = $true
}

function Get-GateUserId {
  <# .SYNOPSIS  Returns the current user's object ID (cached). #>
  if ($script:GateSession.CachedUserId) { return $script:GateSession.CachedUserId }
  try {
    $me = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop
    if ($me -and $me.id) {
      $script:GateSession.CachedUserId = $me.id
      return $me.id
    }
  } catch {}
  try {
    $id = (Get-MgUser -UserId (Get-MgContext).Account -ErrorAction Stop).Id
    $script:GateSession.CachedUserId = $id
    return $id
  } catch { throw "Could not resolve current user." }
}

function Get-GateTenantName {
  <# .SYNOPSIS  Returns the org display name (cached per session). #>
  if ($script:GateSession.CachedTenantName) { return $script:GateSession.CachedTenantName }
  try {
    $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
    if ($org -and $org.DisplayName) {
      $script:GateSession.CachedTenantName = $org.DisplayName
      return $org.DisplayName
    }
  } catch {}
  try {
    $tid = (Get-MgContext).TenantId
    $script:GateSession.CachedTenantName = $tid
    return $tid
  } catch {}
  return 'Unknown'
}
