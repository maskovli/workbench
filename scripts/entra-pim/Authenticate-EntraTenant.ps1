# =================== Microsoft Graph Authentication (drop-in) ===================
# WHAT THIS DOES
# - Reuse an existing Connect-MgGraph session if it has the required scopes.
# - Otherwise: try Interactive (browser) login; on failure → fallback to Device Code.
# - Accepts TenantId as GUID or verified domain (e.g., spirhed.onmicrosoft.com).
# - Verifies the token by calling /v1.0/me, and selects the v1.0 profile if available.
# - Shows a prompt to reuse the current session (same UX as your earlier scripts).
#
# HOW TO USE
#   1) Run the script directly: .\Autenticate-EntraTenant.ps1 -TenantId 'tenant.onmicrosoft.com'
#      or dot-source it and call Ensure-GraphWithScopes manually.
#   2) Optional switches:
#        -Scopes         : override required scopes
#        -ForceReauth    : ignore existing session and re-login
#        -DeviceCodeOnly : skip Interactive and use Device Code directly
# ================================================================================

[CmdletBinding()]
param(
  [string[]]$Scopes,
  [string]  $TenantId,
  [switch]  $ForceReauth,
  [switch]  $DeviceCodeOnly
)

if (-not (Test-Path Variable:RequiredGraphScopes) -or -not $RequiredGraphScopes) {
  $RequiredGraphScopes = @('User.Read','Directory.Read.All')
}
if ($Scopes) {
  $RequiredGraphScopes = $Scopes
} else {
  $Scopes = $RequiredGraphScopes
}

function Ensure-Module {
  param([Parameter(Mandatory)][string]$Name,[string]$MinVersion='0.0.1')
  if (-not (Get-Module -ListAvailable -Name $Name | Where-Object { $_.Version -ge [version]$MinVersion })) {
    Write-Host "Installing module $Name (CurrentUser)..." -ForegroundColor Yellow
    Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }
  Import-Module $Name -ErrorAction Stop | Out-Null
}

# Adjust per script, or pass -Scopes when calling the script/function

function Ensure-GraphWithScopes {
  [CmdletBinding()]
  param(
    [string[]]$Scopes = $RequiredGraphScopes,
    [string]  $TenantId,        # GUID or verified domain (e.g., spirhed.onmicrosoft.com)
    [switch]  $ForceReauth,
    [switch]  $DeviceCodeOnly
  )

  Ensure-Module Microsoft.Graph -MinVersion '2.15.0'
  Ensure-Module Microsoft.Graph.Authentication

  $needLogin = $true
  if (-not $ForceReauth) {
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx -and $ctx.Account) {
      $missing = if ($ctx.Scopes) { $Scopes | Where-Object { $ctx.Scopes -notcontains $_ } } else { $Scopes }
      Write-Host "Existing Microsoft Graph session:" -ForegroundColor Cyan
      Write-Host ("  Account : {0}" -f $ctx.Account)
      Write-Host ("  Tenant  : {0}" -f $ctx.TenantId)
      if ($TenantId -and ($TenantId -ne $ctx.TenantId)) {
        Write-Host ("Note: requested tenant '{0}' differs from current session." -f $TenantId) -ForegroundColor Yellow
      }
      $ans = Read-Host "Use this session? [Y]es / [S]witch account"
      if ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(y|yes)$') {
        if (-not $missing -or @($missing).Count -eq 0) {
          try {
            Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
            $needLogin = $false
          } catch { $needLogin = $true }
        }
      }
    }
  }

  if ($needLogin) {
    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    if (Get-Command Clear-MgContext    -ErrorAction SilentlyContinue) { Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue }

    $args = @{ Scopes = $Scopes; NoWelcome = $true }
    if ($TenantId) { $args.TenantId = $TenantId }

    if ($DeviceCodeOnly) {
      Write-Host "Connecting to Microsoft Graph (Device Code)..." -ForegroundColor Yellow
      $args.UseDeviceCode = $true
      Connect-MgGraph @args | Out-Null
    } else {
      Write-Host "Connecting to Microsoft Graph (Interactive browser)..." -ForegroundColor Yellow
      try {
        Connect-MgGraph @args | Out-Null
      } catch {
        Write-Warning ("Interactive sign-in failed: {0} → falling back to Device Code..." -f $_.Exception.Message)
        if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
        if (Get-Command Clear-MgContext    -ErrorAction SilentlyContinue) { Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue }
        $args.UseDeviceCode = $true
        Connect-MgGraph @args | Out-Null
      }
    }

    # Verify token & set profile
    Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
    if (Get-Command Select-MgProfile -ErrorAction SilentlyContinue) { Select-MgProfile -Name 'v1.0' }
  }
}

function Get-MyUserId {
  try {
    $me = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop
    if ($me -and $me.id) { return $me.id }
  } catch {}
  try {
    return (Get-MgUser -UserId (Get-MgContext).Account -ErrorAction Stop).Id
  } catch {
    throw "Could not resolve current user (me)."
  }
}

$isDotSourced = $MyInvocation.InvocationName -eq '.'
if (-not $isDotSourced) {
  $ensureParams = @{
    Scopes = $RequiredGraphScopes
  }
  if ($TenantId) { $ensureParams.TenantId = $TenantId }
  if ($ForceReauth) { $ensureParams.ForceReauth = $true }
  if ($DeviceCodeOnly) { $ensureParams.DeviceCodeOnly = $true }

  try {
    Ensure-GraphWithScopes @ensureParams
    $ctx = Get-MgContext
    if ($ctx) {
      Write-Host ("Authenticated as {0} (Tenant: {1})" -f $ctx.Account, $ctx.TenantId) -ForegroundColor Green
    }
  } catch {
    Write-Error $_
    exit 1
  }
}
