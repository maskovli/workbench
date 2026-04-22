#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Activate / deactivate Microsoft Entra PIM roles (Directory roles + PIM for Groups).

.DESCRIPTION
  Merged & cleaned version of v1/v2/v3.
  - Reuses an existing Microsoft Graph session if one exists (asks: continue / switch / sign out).
  - Interactive browser auth first, automatic Device Code fallback.
  - Handles BOTH Entra directory roles AND PIM for Groups (member/owner).
  - Best-effort policy-max duration check before activating.
  - Keeps the session connected on exit by default (use -DisconnectOnExit to opt out).

.EXAMPLE
  ./Activate-EntraPimRoles.ps1
  ./Activate-EntraPimRoles.ps1 -Action ListActive
  ./Activate-EntraPimRoles.ps1 -Action Activate -Target Directory -Duration 2h -Justification "Change #1234"
#>

[CmdletBinding()]
param(
  [ValidateSet('Activate','Deactivate','ListEligible','ListActive','Report')]
  [string] $Action = 'Activate',

  [ValidateSet('Auto','Directory','Groups','AzureResources')]
  [string] $Target = 'Auto',

  [Alias('Tenant')]
  [string] $TenantId,

  [ValidateSet('Auto','Interactive','DeviceCode')]
  [string] $Auth = 'Auto',

  [string] $Duration,
  [string] $Justification,
  [string] $TicketSystem,
  [string] $TicketNumber,

  [string[]] $Roles,        # filter eligible/active list by display name
  [string]   $ExportPath,   # for Report action: .csv or .json

  # Azure Resources scopes to scan. Default = all subscriptions you can see.
  # Examples: "/subscriptions/<id>", "/subscriptions/<id>/resourceGroups/<rg>"
  [string[]] $AzureScopes,

  [switch] $SkipGrid,
  [switch] $ForceLogin,     # ignore existing session, force new login
  [switch] $DisconnectOnExit
)

$ErrorActionPreference = 'Stop'

# ================================================================
#  MODULE / UTILITIES
# ================================================================

function Ensure-Module {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Version]$MinVersion = [Version]'0.0.1',
    [switch]$Optional
  )
  $has = Get-Module -ListAvailable -Name $Name |
         Where-Object { $_.Version -ge $MinVersion } |
         Select-Object -First 1
  if (-not $has) {
    if ($Optional) {
      Write-Warning "Optional module '$Name' (>= $MinVersion) not installed."
      return $false
    }
    Write-Host "Installing module $Name (CurrentUser)..." -ForegroundColor Yellow
    Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }
  Import-Module $Name -ErrorAction Stop | Out-Null
  return $true
}

function ConvertTo-IsoDuration {
  <# Accepts: 90, 90m, 1h, 2h30m, 1d, 01:30:00, PT1H30M #>
  param([Parameter(Mandatory)][string]$Value)
  $s = $Value.Trim().ToLower()
  if ([string]::IsNullOrWhiteSpace($s)) { return 'PT1H' }
  if ($s -match '^pt') { return $s.ToUpper() }
  if ($s -match '^\d{1,2}:\d{2}(:\d{2})?$') {
    $ts = [TimeSpan]::Parse($s)
    if ($ts.Days -gt 0) { return "P$($ts.Days)D" }
    $parts = @()
    if ($ts.Hours   -gt 0) { $parts += "$($ts.Hours)H" }
    if ($ts.Minutes -gt 0) { $parts += "$($ts.Minutes)M" }
    if ($ts.Seconds -gt 0 -or $parts.Count -eq 0) { $parts += "$($ts.Seconds)S" }
    return "PT$($parts -join '')"
  }
  $d=0;$h=0;$m=0
  if ($s -match '(\d+)\s*d') { $d = [int]$Matches[1] }
  if ($s -match '(\d+)\s*h') { $h = [int]$Matches[1] }
  if ($s -match '(\d+)\s*m') { $m = [int]$Matches[1] }
  if ($d -eq 0 -and $h -eq 0 -and $m -eq 0 -and $s -match '^\d+$') { $m = [int]$s }
  if ($d -eq 0 -and $h -eq 0 -and $m -eq 0) {
    throw "Invalid duration '$Value'. Examples: 30m, 1h, 2h30m, 1d, 01:30:00, PT45M"
  }
  if ($d -gt 0) { return "P${d}D" }
  $parts = @()
  if ($h -gt 0) { $parts += "${h}H" }
  if ($m -gt 0) { $parts += "${m}M" }
  return "PT$($parts -join '')"
}

function Get-MinFromIso {
  param([string]$iso)
  if (-not $iso) { return 0 }
  if ($iso -match '^P(\d+)D$') { return [int]$Matches[1] * 24 * 60 }
  $h = 0; $m = 0
  if ($iso -match 'PT(\d+)H')      { $h = [int]$Matches[1] }
  if ($iso -match 'PT\d*H?(\d+)M') { $m = [int]$Matches[1] }
  return ($h * 60 + $m)
}

# ================================================================
#  AUTH — session reuse, interactive-first, device-code fallback
# ================================================================

$RequiredGraphScopes = @(
  'User.Read'
  'Directory.Read.All'
  'RoleManagementPolicy.Read.Directory'
  'RoleEligibilitySchedule.Read.Directory'
  'RoleAssignmentSchedule.Read.Directory'
  'RoleAssignmentSchedule.ReadWrite.Directory'
  'RoleManagement.Read.Directory'
  'RoleManagement.Read.All'
  'RoleManagement.ReadWrite.Directory'
  'Group.Read.All'
  'PrivilegedAccess.Read.AzureADGroup'
  'PrivilegedAccess.ReadWrite.AzureADGroup'
  'PrivilegedEligibilitySchedule.Read.AzureADGroup'
  'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup'
)

function Invoke-GraphLogin {
  param([string]$Method, [string]$TenantId)

  if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
  }
  if (Get-Command Clear-MgContext -ErrorAction SilentlyContinue) {
    Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue
  }
  # Also drop any lingering Az session — when switching Graph identity we
  # never want to silently keep an old Az token from a different account.
  if (Get-Command Disconnect-AzAccount -ErrorAction SilentlyContinue) {
    try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }

  $connArgs = @{
    Scopes       = $RequiredGraphScopes
    NoWelcome    = $true
    ContextScope = 'Process'
  }
  if ($TenantId) { $connArgs.TenantId = $TenantId }

  $useDevice = ($Method -eq 'DeviceCode')
  if ($Method -eq 'Auto') {
    # On macOS, the localhost redirect for interactive auth often fails.
    if ($PSVersionTable.OS -match 'Darwin') { $useDevice = $true }
  }

  if ($useDevice) {
    Write-Host "Connecting to Microsoft Graph (Device Code)..." -ForegroundColor Yellow
    $connArgs.UseDeviceCode = $true
    Connect-MgGraph @connArgs
  } else {
    Write-Host "Connecting to Microsoft Graph (Interactive browser)..." -ForegroundColor Yellow
    try {
      Connect-MgGraph @connArgs
    } catch {
      Write-Warning "Interactive sign-in failed: $($_.Exception.Message)"
      Write-Host "Falling back to Device Code..." -ForegroundColor Yellow
      $connArgs.UseDeviceCode = $true
      Connect-MgGraph @connArgs
    }
  }

  # Validate
  $ctx = Get-MgContext
  if (-not $ctx -or -not $ctx.Account) { throw "Login did not produce a valid Graph context." }
  Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
  Write-Host ("Signed in as: {0}" -f $ctx.Account) -ForegroundColor Green
}

function Get-SavedAzContextForUpn {
  <# Returns a saved Az context matching the given UPN, or $null.
     Match on Account.Id only — Tenant.Id reflects subscription tenant, which
     can differ from the Entra tenant and cause false negatives. #>
  param([Parameter(Mandatory)][string]$Upn)
  if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) { return $null }
  return Get-AzContext -ListAvailable -ErrorAction SilentlyContinue |
         Where-Object { $_.Account -and $_.Account.Id -ieq $Upn } |
         Select-Object -First 1
}

function Connect-GraphSmart {
  param([string]$TenantId, [string]$Auth = 'Auto', [switch]$ForceLogin)

  # Reset any cached per-session state so dot-sourcing the script twice
  # in the same shell doesn't leak tenant display names between runs.
  $script:CachedTenantName = $null
  $script:AzConnected      = $false
  $script:SkipAz           = $false

  Ensure-Module Microsoft.Graph.Authentication       -MinVersion '2.15.0' | Out-Null
  Ensure-Module Microsoft.Graph.Identity.Governance  -MinVersion '2.15.0' | Out-Null
  Ensure-Module Microsoft.Graph.Users                -MinVersion '2.15.0' | Out-Null
  Ensure-Module Microsoft.Graph.Groups               -MinVersion '2.15.0' | Out-Null

  if ($ForceLogin) {
    Invoke-GraphLogin -Method $Auth -TenantId $TenantId
    return
  }

  $ctx = Get-MgContext -ErrorAction SilentlyContinue

  if ($ctx -and $ctx.Account) {
    # Verify the session is actually alive
    $alive = $false
    try {
      Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
      $alive = $true
    } catch { $alive = $false }

    if ($alive) {
      $missing = @()
      if ($ctx.Scopes) {
        $missing = $RequiredGraphScopes | Where-Object { $ctx.Scopes -notcontains $_ }
      }
      $tenantMismatch = $TenantId -and ($TenantId -ne $ctx.TenantId)

      # Detect saved Az context for the same UPN — purely informational here.
      $savedAz = Get-SavedAzContextForUpn -Upn $ctx.Account
      $azStatus = if ($savedAz) { "reuse ready ($($savedAz.Account.Id))" } else { 'not connected (will ask before device code)' }

      Write-Host ""
      Write-Host "Existing Microsoft Graph session detected:" -ForegroundColor Cyan
      Write-Host ("  Account : {0}" -f $ctx.Account) -ForegroundColor White
      Write-Host ("  Tenant  : {0}" -f $ctx.TenantId) -ForegroundColor White
      Write-Host ("  Azure   : {0}" -f $azStatus) -ForegroundColor White
      if ($missing.Count -gt 0) {
        Write-Host ("  Warning : Missing {0} required scope(s) -- a re-login may be needed." -f $missing.Count) -ForegroundColor Yellow
      }
      if ($tenantMismatch) {
        Write-Host ("  Note    : Requested tenant '{0}' differs from current session." -f $TenantId) -ForegroundColor Yellow
      }
      Write-Host ""
      Write-Host "What do you want to do?" -ForegroundColor Cyan
      Write-Host "  [C] Continue with this session (default)"
      Write-Host "  [D] Continue, Directory/Groups only (skip Azure Resources)"
      Write-Host "  [S] Switch account / sign in as someone else"
      Write-Host "  [Q] Quit"
      $ans = Read-Host "Select [C/D/S/Q]"

      switch -Regex ($ans) {
        '^(q|Q)$' { throw "Aborted by user." }
        '^(s|S)$' { Invoke-GraphLogin -Method $Auth -TenantId $TenantId; return }
        '^(d|D)$' {
          $script:SkipAz = $true
          if ($missing.Count -gt 0 -or $tenantMismatch) {
            Write-Host "Re-authenticating to obtain required scopes / tenant..." -ForegroundColor Yellow
            Invoke-GraphLogin -Method $Auth -TenantId $TenantId
            return
          }
          Write-Host "Reusing existing session. Azure Resources will be skipped." -ForegroundColor Green
          return
        }
        default {
          if ($missing.Count -gt 0 -or $tenantMismatch) {
            Write-Host "Re-authenticating to obtain required scopes / tenant..." -ForegroundColor Yellow
            Invoke-GraphLogin -Method $Auth -TenantId $TenantId
            return
          }
          Write-Host "Reusing existing session." -ForegroundColor Green
          return
        }
      }
    }
  }

  # No usable session
  Invoke-GraphLogin -Method $Auth -TenantId $TenantId
}

function Ensure-AzConnected {
  <# Lazy connect to Azure. Returns $true if connected, $false if user skipped.
     Called only when we actually need to query/modify Azure Resources PIM. #>
  param([string]$TenantId)
  if ($script:SkipAz)     { return $false }
  if ($script:AzConnected) { return $true  }
  $connected = Connect-AzureSmart -TenantId $TenantId
  $script:AzConnected = $connected
  return $connected
}

function Connect-AzureSmart {
  <# Ensures Az session matches the current Graph session (same UPN + tenant).
     Silently reuses a saved Az context if one exists; otherwise asks the user
     before triggering device code auth. Returns $true on success, $false if
     user declined. #>
  param([string]$TenantId)

  Ensure-Module Az.Accounts  -MinVersion '2.13.0' | Out-Null
  Ensure-Module Az.Resources -MinVersion '6.0.0'  | Out-Null

  # Establish the "truth" identity from the active Graph session
  $graphCtx = Get-MgContext -ErrorAction SilentlyContinue
  if (-not $graphCtx -or -not $graphCtx.Account) {
    throw "No Graph session — cannot align Azure identity. Connect to Graph first."
  }
  $expectedUpn      = $graphCtx.Account
  $expectedTenantId = if ($TenantId) { $TenantId } else { $graphCtx.TenantId }

  # Fast path: saved context exists — reuse silently.
  $matchCtx = Get-SavedAzContextForUpn -Upn $expectedUpn
  if ($matchCtx) {
    Select-AzContext -InputObject $matchCtx -ErrorAction Stop | Out-Null
    Write-Cyber "Az context reused: $($matchCtx.Account.Id)" 'AUTH' 'Green'
    return $true
  }

  # No saved context — ask the user before triggering interactive device code.
  Write-Host ""
  Write-Cyber "Azure Resources requires a separate Azure sign-in." 'AUTH' 'Yellow'
  Write-Host "  [Y] Sign in now (device code)  [N] Skip Azure Resources for this session" -ForegroundColor Cyan
  $ans = Read-Host "Select [Y/N]"
  if ($ans -notmatch '^(y|Y|j|J)$') {
    $script:SkipAz = $true
    Write-Cyber "Skipping Azure Resources for this session." 'INFO' 'DarkGray'
    return $false
  }

  # Clear any mismatched active context before connecting fresh.
  $azCtx = Get-AzContext -ErrorAction SilentlyContinue
  if ($azCtx -and $azCtx.Account -and $azCtx.Account.Id -ine $expectedUpn) {
    Write-Cyber "Active Az context belongs to a different identity — clearing." 'WARN' 'Yellow'
    try { Clear-AzContext -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }

  Write-Cyber "Connecting to Azure as $expectedUpn (tenant $expectedTenantId)..." 'AUTH' 'Yellow'
  # Omit -AccountId: on macOS it triggers an extra MSAL "Please select the account"
  # prompt even with -UseDeviceAuthentication. Identity is verified below.
  Connect-AzAccount -Tenant $expectedTenantId `
                    -UseDeviceAuthentication -WarningAction SilentlyContinue | Out-Null

  $newCtx = Get-AzContext -ErrorAction SilentlyContinue
  if (-not $newCtx -or -not $newCtx.Account) { throw "Azure login did not produce a context." }
  if ($newCtx.Account.Id -ine $expectedUpn) {
    throw "Azure login returned wrong identity: got '$($newCtx.Account.Id)', expected '$expectedUpn'."
  }
  Write-Cyber "Az session OK: $($newCtx.Account.Id)" 'OK' 'Green'
  return $true
}

function Get-MyUserId {
  try {
    $me = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop
    if ($me -and $me.id) { return $me.id }
  } catch {}
  try { return (Get-MgUser -UserId (Get-MgContext).Account -ErrorAction Stop).Id }
  catch { throw "Could not resolve current user (me)." }
}

# ================================================================
#  CYBER UI
# ================================================================

function Show-CyberBanner {
  $reset = "`e[0m"; $cyan = "`e[38;5;51m"; $magenta = "`e[38;5;201m"
  $green = "`e[38;5;46m"; $dim = "`e[38;5;240m"; $yellow = "`e[38;5;226m"

  $lines = @(
    "${cyan}╔══════════════════════════════════════════════════════════════╗${reset}"
    "${cyan}║${reset}  ${magenta}███████╗${cyan}███╗   ██╗${green}████████╗${yellow}██████╗  █████╗${reset}    ${dim}// PIM${reset}     ${cyan}║${reset}"
    "${cyan}║${reset}  ${magenta}██╔════╝${cyan}████╗  ██║${green}╚══██╔══╝${yellow}██╔══██╗██╔══██╗${reset}             ${cyan}║${reset}"
    "${cyan}║${reset}  ${magenta}█████╗  ${cyan}██╔██╗ ██║${green}   ██║   ${yellow}██████╔╝███████║${reset}             ${cyan}║${reset}"
    "${cyan}║${reset}  ${magenta}██╔══╝  ${cyan}██║╚██╗██║${green}   ██║   ${yellow}██╔══██╗██╔══██║${reset}             ${cyan}║${reset}"
    "${cyan}║${reset}  ${magenta}███████╗${cyan}██║ ╚████║${green}   ██║   ${yellow}██║  ██║██║  ██║${reset}             ${cyan}║${reset}"
    "${cyan}║${reset}  ${magenta}╚══════╝${cyan}╚═╝  ╚═══╝${green}   ╚═╝   ${yellow}╚═╝  ╚═╝╚═╝  ╚═╝${reset}             ${cyan}║${reset}"
    "${cyan}║${reset}  ${dim}╶─${reset} ${green}role activation interface${reset} ${dim}─────────────────────╴${reset}  ${cyan}║${reset}"
    "${cyan}║${reset}    ${dim}>${reset} ${cyan}directory${reset}  ${dim}::${reset}  ${cyan}groups${reset}  ${dim}::${reset}  ${cyan}azure resources${reset}     ${cyan}║${reset}"
    "${cyan}╚══════════════════════════════════════════════════════════════╝${reset}"
  )
  $lines | ForEach-Object { Write-Host $_ }
}

function Write-Cyber {
  param([string]$Text, [string]$Tag = 'INFO', [string]$Color = 'Cyan')
  $tagColor = switch ($Tag) {
    'OK'    { 'Green' }
    'ERR'   { 'Red' }
    'WARN'  { 'Yellow' }
    'AUTH'  { 'Magenta' }
    default { 'DarkCyan' }
  }
  Write-Host "[" -NoNewline -ForegroundColor DarkGray
  Write-Host $Tag -NoNewline -ForegroundColor $tagColor
  Write-Host "] " -NoNewline -ForegroundColor DarkGray
  Write-Host $Text -ForegroundColor $Color
}

# ================================================================
#  GRID / SELECTION
# ================================================================

function Test-GridAvailable {
  if ($SkipGrid) { return $false }
  return [bool](Ensure-Module Microsoft.PowerShell.ConsoleGuiTools -MinVersion '0.7.0' -Optional)
}

function Select-FromList {
  param(
    [array]    $Rows,
    [string[]] $ShowCols,
    [string]   $Title,
    [switch]   $Multi
  )
  if (-not $Rows -or $Rows.Count -eq 0) { return @() }
  $hasGrid = Test-GridAvailable

  if ($hasGrid) {
    # Build display objects with ONLY the visible columns; keep a parallel map
    # back to the original rows so __IsSeparator/__Ref don't leak into the grid.
    # Also prettifies values for a more "cyber" look: icons per category,
    # active state glyphs, and box-drawing separator rows.
    $catIcon = @{
      'Directory'      = '◆ DIR'
      'Groups'         = '◆ GRP'
      'AzureResources' = '◆ AZR'
    }
    $pairs = foreach ($r in $Rows) {
      $o = [ordered]@{}
      if ($r.IsSeparator) {
        # A full-width banner row: "━━━━ NAME ━━━━━━━━━━━━━━━━━━"
        $label = " $($r.Name) "
        $pad   = [math]::Max(0, 56 - $label.Length)
        $left  = [string]('━' * 4)
        $right = [string]('━' * $pad)
        foreach ($c in $ShowCols) {
          if ($c -eq $ShowCols[0]) { $o[$c] = "$left$label$right" }
          else                     { $o[$c] = '' }
        }
      } else {
        foreach ($c in $ShowCols) {
          $val = $r.$c
          switch ($c) {
            'Category'  { $val = if ($catIcon.ContainsKey([string]$val)) { $catIcon[[string]$val] } else { $val } }
            'ActiveNow' { $val = if ($val) { '● LIVE' } else { '·' } }
            default     { }
          }
          $o[$c] = $val
        }
      }
      [pscustomobject]@{ Display = [pscustomobject]$o; Original = $r }
    }
    $displayList = $pairs | ForEach-Object { $_.Display }
    $mode = if ($Multi) { 'Multiple' } else { 'Single' }
    $sel = $displayList | Out-ConsoleGridView -Title $Title -OutputMode $mode
    if (-not $sel) { return @() }
    $picked = foreach ($s in $sel) {
      ($pairs | Where-Object { [object]::ReferenceEquals($_.Display, $s) } | Select-Object -First 1).Original
    }
    return @($picked | Where-Object { -not $_.IsSeparator })
  }

  # Fallback: numbered list
  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan
  $i = 1
  foreach ($r in $Rows) {
    if ($r.IsSeparator) {
      Write-Host "  ----- $($r.Name) -----" -ForegroundColor DarkCyan
      continue
    }
    $vals = ($ShowCols | ForEach-Object { $r.$_ }) -join '  |  '
    Write-Host ("  [{0,2}] {1}" -f $i, $vals)
    $r | Add-Member -NotePropertyName __Index -NotePropertyValue $i -Force
    $i++
  }
  $prompt = if ($Multi) { "Numbers (comma-separated), Enter to cancel" } else { "Number, Enter to cancel" }
  $ans = Read-Host $prompt
  if ([string]::IsNullOrWhiteSpace($ans)) { return @() }
  $idx = $ans -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
  $sel = @()
  foreach ($n in $idx) {
    $hit = $Rows | Where-Object { $_.__Index -eq $n }
    if ($hit) { $sel += $hit }
  }
  if ($Multi) { return $sel } else { if ($sel.Count -gt 0) { return ,$sel[0] } else { return @() } }
}

# ================================================================
#  POLICY MAX-DURATION (best-effort)
# ================================================================

function Get-DirectoryRoleMaxIso {
  param([Parameter(Mandatory)][string]$RoleDefinitionId)
  try {
    $assign = Get-MgPolicyRoleManagementPolicyAssignment `
                -Filter "scopeId eq '/' and scopeType eq 'DirectoryRole'" `
                -ExpandProperty "policy(`$expand=rules)" -All
    $durs = @()
    foreach ($a in $assign) {
      if ($a.RoleDefinitionId -and $a.RoleDefinitionId -ne $RoleDefinitionId) { continue }
      foreach ($r in $a.Policy.Rules) {
        if ($r.'@odata.type' -eq '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule' -and
            $r.Target.Caller -eq 'EndUser' -and $r.Target.Level -eq 'Assignment' -and $r.MaximumDuration) {
          $durs += $r.MaximumDuration
        }
      }
    }
    if ($durs.Count -gt 0) {
      return ($durs | Sort-Object { Get-MinFromIso $_ } -Descending | Select-Object -First 1)
    }
  } catch {}
  return $null
}

function Get-GroupMaxIso {
  param(
    [Parameter(Mandatory)][string]$GroupId,
    [Parameter(Mandatory)][ValidateSet('member','owner')][string]$AccessId
  )
  try {
    $assign = Get-MgPolicyRoleManagementPolicyAssignment `
                -Filter "scopeType eq 'Group'" `
                -ExpandProperty "policy(`$expand=rules)" -All
    $durs = @()
    foreach ($a in $assign) {
      if ($a.ScopeId -and $a.ScopeId -ne $GroupId) { continue }
      if ($a.RoleDefinitionId -and $a.RoleDefinitionId -ne $AccessId) { continue }
      foreach ($r in $a.Policy.Rules) {
        if ($r.'@odata.type' -eq '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule' -and
            $r.Target.Caller -eq 'EndUser' -and $r.Target.Level -eq 'Assignment' -and $r.MaximumDuration) {
          $durs += $r.MaximumDuration
        }
      }
    }
    if ($durs.Count -gt 0) {
      return ($durs | Sort-Object { Get-MinFromIso $_ } -Descending | Select-Object -First 1)
    }
  } catch {}
  return $null
}

# ================================================================
#  DATA FETCHERS — Directory + Groups
# ================================================================

function Get-DirRoleDefMap {
  $map = @{}
  Get-MgRoleManagementDirectoryRoleDefinition -All | ForEach-Object { $map[$_.Id] = $_ }
  return $map
}

function Get-TenantDisplayName {
  if ($script:CachedTenantName) { return $script:CachedTenantName }
  try {
    $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
    if ($org -and $org.DisplayName) {
      $script:CachedTenantName = $org.DisplayName
      return $script:CachedTenantName
    }
  } catch {}
  # Fallback: use tenant id from context
  try {
    $tid = (Get-MgContext).TenantId
    if ($tid) { $script:CachedTenantName = $tid; return $tid }
  } catch {}
  return $null
}

function Resolve-ScopeName {
  param([string]$DirectoryScopeId)
  if ([string]::IsNullOrEmpty($DirectoryScopeId) -or $DirectoryScopeId -eq '/') {
    $name = Get-TenantDisplayName
    if ($name) { return "Tenant - $name" } else { return 'Tenant' }
  }
  if ($DirectoryScopeId -match '/administrativeUnits/(?<id>[0-9a-fA-F-]+)') {
    return "AU: $($Matches.id)"
  }
  return $DirectoryScopeId
}

function Get-DirEligibleRows {
  $meId = Get-MyUserId
  $defs = Get-DirRoleDefMap
  $eligible = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$meId'" -All
  $active   = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance  -Filter "principalId eq '$meId'" -All
  $activeSet = @{}
  foreach ($a in $active) { $activeSet["$($a.RoleDefinitionId)|$($a.DirectoryScopeId)"] = 1 }

  $rows = foreach ($e in $eligible) {
    $name = if ($defs[$e.RoleDefinitionId]) { $defs[$e.RoleDefinitionId].DisplayName } else { $e.RoleDefinitionId }
    [pscustomobject]@{
      Category             = 'Directory'
      Name                 = $name
      Scope                = Resolve-ScopeName $e.DirectoryScopeId
      ActiveNow            = $activeSet.ContainsKey("$($e.RoleDefinitionId)|$($e.DirectoryScopeId)")
      Dir_RoleDefinitionId = $e.RoleDefinitionId
      Dir_ScopeId          = if ([string]::IsNullOrEmpty($e.DirectoryScopeId)) { '/' } else { $e.DirectoryScopeId }
      Dir_EligibilitySchedId = $e.RoleEligibilityScheduleId
      IsSeparator          = $false
    }
  }
  return @($rows | Sort-Object ActiveNow, Name)
}

function Get-DirActiveRows {
  $meId = Get-MyUserId
  $defs = Get-DirRoleDefMap
  $act  = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "principalId eq '$meId'" -All

  $rows = foreach ($a in $act) {
    $name = if ($defs[$a.RoleDefinitionId]) { $defs[$a.RoleDefinitionId].DisplayName } else { $a.RoleDefinitionId }
    $ends = $a.EndDateTime
    $minLeft = if ($ends) {
      [math]::Round([math]::Max(0, ([datetimeoffset]$ends).UtcDateTime.Subtract([datetime]::UtcNow).TotalMinutes), 0)
    } else { $null }
    [pscustomobject]@{
      Category             = 'Directory'
      Name                 = $name
      Scope                = Resolve-ScopeName $a.DirectoryScopeId
      Ends                 = $ends
      MinutesLeft          = $minLeft
      ActiveNow            = $true
      Dir_RoleDefinitionId = $a.RoleDefinitionId
      Dir_ScopeId          = if ([string]::IsNullOrEmpty($a.DirectoryScopeId)) { '/' } else { $a.DirectoryScopeId }
      IsSeparator          = $false
    }
  }
  return @($rows | Sort-Object MinutesLeft, Name)
}

function Get-GroupEligibleRows {
  $meId = Get-MyUserId
  $elig = Get-MgIdentityGovernancePrivilegedAccessGroupEligibilityScheduleInstance -Filter "principalId eq '$meId'" -All
  $act  = Get-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleInstance  -Filter "principalId eq '$meId'" -All

  $gmap = @{}
  foreach ($gid in ($elig | Select-Object -ExpandProperty GroupId -Unique)) {
    try { $gmap[$gid] = (Get-MgGroup -GroupId $gid).DisplayName } catch { $gmap[$gid] = $gid }
  }
  $actSet = @{}
  foreach ($a in $act) { $actSet["$($a.GroupId)|$($a.AccessId)"] = 1 }

  $rows = foreach ($e in $elig) {
    [pscustomobject]@{
      Category       = 'Groups'
      Name           = $gmap[$e.GroupId]
      Scope          = $e.AccessId
      ActiveNow      = $actSet.ContainsKey("$($e.GroupId)|$($e.AccessId)")
      Group_GroupId  = $e.GroupId
      Group_AccessId = $e.AccessId
      IsSeparator    = $false
    }
  }
  return @($rows | Sort-Object ActiveNow, Name, Scope)
}

function Get-GroupActiveRows {
  $meId = Get-MyUserId
  $list = Get-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleInstance -Filter "principalId eq '$meId'" -All

  $gmap = @{}
  foreach ($gid in ($list | Select-Object -ExpandProperty GroupId -Unique)) {
    try { $gmap[$gid] = (Get-MgGroup -GroupId $gid).DisplayName } catch { $gmap[$gid] = $gid }
  }

  $rows = foreach ($a in $list) {
    $ends = $a.EndDateTime
    $minLeft = if ($ends) {
      [math]::Round([math]::Max(0, ([datetimeoffset]$ends).UtcDateTime.Subtract([datetime]::UtcNow).TotalMinutes), 0)
    } else { $null }
    [pscustomobject]@{
      Category       = 'Groups'
      Name           = $gmap[$a.GroupId]
      Scope          = $a.AccessId
      Ends           = $ends
      MinutesLeft    = $minLeft
      ActiveNow      = $true
      Group_GroupId  = $a.GroupId
      Group_AccessId = $a.AccessId
      IsSeparator    = $false
    }
  }
  return @($rows | Sort-Object MinutesLeft, Name, Scope)
}

function Get-AzScopesToScan {
  if ($AzureScopes -and $AzureScopes.Count -gt 0) { return $AzureScopes }
  try {
    $subs = Get-AzSubscription -ErrorAction Stop
    return @($subs | ForEach-Object { "/subscriptions/$($_.Id)" })
  } catch {
    Write-Warning "Could not enumerate subscriptions: $($_.Exception.Message)"
    return @()
  }
}

function Get-AzEligibleRows {
  if (-not (Ensure-AzConnected -TenantId $TenantId)) { return @() }
  $meId = Get-MyUserId
  $rows = @()
  foreach ($scope in (Get-AzScopesToScan)) {
    try {
      $eligible = Get-AzRoleEligibilityScheduleInstance -Scope $scope -Filter "asTarget()" -ErrorAction Stop
      $active   = Get-AzRoleAssignmentScheduleInstance  -Scope $scope -Filter "asTarget()" -ErrorAction SilentlyContinue
      $activeSet = @{}
      foreach ($a in $active) { $activeSet["$($a.RoleDefinitionId)|$($a.Scope)"] = 1 }

      foreach ($e in $eligible) {
        if ($e.PrincipalId -ne $meId) { continue }
        $rows += [pscustomobject]@{
          Category              = 'AzureResources'
          Name                  = $e.RoleDefinitionDisplayName
          Scope                 = ($e.ScopeDisplayName ?? $e.Scope)
          ActiveNow             = $activeSet.ContainsKey("$($e.RoleDefinitionId)|$($e.Scope)")
          Az_RoleDefinitionId   = $e.RoleDefinitionId
          Az_Scope              = $e.Scope
          Az_LinkedRoleEligibilityScheduleId = $e.RoleEligibilityScheduleId
          IsSeparator           = $false
        }
      }
    } catch {
      Write-Warning "Az eligibility fetch failed for scope $scope : $($_.Exception.Message)"
    }
  }
  return @($rows | Sort-Object ActiveNow, Name, Scope)
}

function Get-AzActiveRows {
  if (-not (Ensure-AzConnected -TenantId $TenantId)) { return @() }
  $meId = Get-MyUserId
  $rows = @()
  foreach ($scope in (Get-AzScopesToScan)) {
    try {
      $act = Get-AzRoleAssignmentScheduleInstance -Scope $scope -Filter "asTarget()" -ErrorAction Stop
      foreach ($a in $act) {
        if ($a.PrincipalId -ne $meId) { continue }
        $ends = $a.EndDateTime
        $minLeft = if ($ends) {
          [math]::Round([math]::Max(0, ([datetimeoffset]$ends).UtcDateTime.Subtract([datetime]::UtcNow).TotalMinutes), 0)
        } else { $null }
        $rows += [pscustomobject]@{
          Category            = 'AzureResources'
          Name                = $a.RoleDefinitionDisplayName
          Scope               = ($a.ScopeDisplayName ?? $a.Scope)
          Ends                = $ends
          MinutesLeft         = $minLeft
          ActiveNow           = $true
          Az_RoleDefinitionId = $a.RoleDefinitionId
          Az_Scope            = $a.Scope
          Az_LinkedRoleEligibilityScheduleId = $a.LinkedRoleEligibilityScheduleId
          IsSeparator         = $false
        }
      }
    } catch {
      Write-Warning "Az active fetch failed for scope $scope : $($_.Exception.Message)"
    }
  }
  return @($rows | Sort-Object MinutesLeft, Name, Scope)
}

function Activate-AzureItem {
  param([pscustomobject]$Item, [string]$Iso, [string]$Justification, [string]$TicketSystem, [string]$TicketNumber)

  $meId = Get-MyUserId
  $guid = [guid]::NewGuid().ToString()
  $params = @{
    Name                            = $guid
    Scope                           = $Item.Az_Scope
    PrincipalId                     = $meId
    RoleDefinitionId                = $Item.Az_RoleDefinitionId
    RequestType                     = 'SelfActivate'
    Justification                   = $Justification
    ScheduleInfoStartDateTime       = ([DateTime]::UtcNow.ToString('o'))
    ExpirationType                  = 'AfterDuration'
    ExpirationDuration              = $Iso
  }
  if ($Item.Az_LinkedRoleEligibilityScheduleId) {
    $params.LinkedRoleEligibilityScheduleId = $Item.Az_LinkedRoleEligibilityScheduleId
  }
  if ($TicketSystem -or $TicketNumber) {
    $params.TicketSystem = ($TicketSystem ?? 'N/A')
    $params.TicketNumber = $TicketNumber
  }

  $req = New-AzRoleAssignmentScheduleRequest @params -ErrorAction Stop
  Write-Host "[OK] Activated AzureResources: $($Item.Name) ($($Item.Scope))" -ForegroundColor Green
  [pscustomobject]@{
    Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope
    Status=($req.Status ?? 'Sent'); RequestId=$req.Name; Requested=$Iso
  }
}

function Deactivate-AzureItem {
  param([pscustomobject]$Item, [string]$Justification)

  $meId = Get-MyUserId
  $guid = [guid]::NewGuid().ToString()
  $params = @{
    Name                      = $guid
    Scope                     = $Item.Az_Scope
    PrincipalId               = $meId
    RoleDefinitionId          = $Item.Az_RoleDefinitionId
    RequestType               = 'SelfDeactivate'
    Justification             = ($Justification ?? 'Deactivate via PowerShell')
  }
  if ($Item.Az_LinkedRoleEligibilityScheduleId) {
    $params.LinkedRoleEligibilityScheduleId = $Item.Az_LinkedRoleEligibilityScheduleId
  }
  $req = New-AzRoleAssignmentScheduleRequest @params -ErrorAction Stop
  Write-Host "[OK] Deactivated AzureResources: $($Item.Name) ($($Item.Scope))" -ForegroundColor Green
  [pscustomobject]@{
    Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope
    Status=($req.Status ?? 'Sent'); RequestId=$req.Name
  }
}

function Build-CombinedEligible {
  param([bool]$IncDir, [bool]$IncGrp, [bool]$IncAz)
  $list = @()
  if ($IncDir) {
    $list += [pscustomobject]@{ Category=''; Name='Directory (Entra roles)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    $list += Get-DirEligibleRows
  }
  if ($IncGrp) {
    $list += [pscustomobject]@{ Category=''; Name='Groups (PIM for Groups)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-GroupEligibleRows } catch { Write-Warning "Could not fetch Group eligibilities: $($_.Exception.Message)" }
  }
  if ($IncAz -and -not $script:SkipAz) {
    $list += [pscustomobject]@{ Category=''; Name='Azure Resources'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-AzEligibleRows } catch { Write-Warning "Could not fetch Azure eligibilities: $($_.Exception.Message)" }
  }
  return $list
}

function Build-CombinedActive {
  param([bool]$IncDir, [bool]$IncGrp, [bool]$IncAz)
  $list = @()
  if ($IncDir) {
    $list += [pscustomobject]@{ Category=''; Name='Directory (active)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    $list += Get-DirActiveRows
  }
  if ($IncGrp) {
    $list += [pscustomobject]@{ Category=''; Name='Groups (active)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-GroupActiveRows } catch { Write-Warning "Could not fetch Group assignments: $($_.Exception.Message)" }
  }
  if ($IncAz -and -not $script:SkipAz) {
    $list += [pscustomobject]@{ Category=''; Name='Azure Resources (active)'; Scope=''; ActiveNow=$false; IsSeparator=$true }
    try { $list += Get-AzActiveRows } catch { Write-Warning "Could not fetch Azure assignments: $($_.Exception.Message)" }
  }
  return $list
}

# ================================================================
#  EXECUTORS
# ================================================================

function Activate-DirectoryItem {
  param([pscustomobject]$Item, [string]$Iso, [string]$Justification, [string]$TicketSystem, [string]$TicketNumber)

  $max = Get-DirectoryRoleMaxIso -RoleDefinitionId $Item.Dir_RoleDefinitionId
  if ($max -and (Get-MinFromIso $Iso) -gt (Get-MinFromIso $max)) {
    Write-Host "[Policy] Requested $Iso exceeds policy max $max. Entra may cap it." -ForegroundColor Yellow
  }

  $meId = Get-MyUserId
  $body = @{
    action           = 'selfActivate'
    principalId      = $meId
    roleDefinitionId = $Item.Dir_RoleDefinitionId
    directoryScopeId = $Item.Dir_ScopeId
    justification    = $Justification
    scheduleInfo     = @{
      startDateTime = ([DateTime]::UtcNow.ToString('o'))
      expiration    = @{ type = 'AfterDuration'; duration = $Iso }
    }
  }
  if ($Item.Dir_EligibilitySchedId) { $body.activatedUsing = $Item.Dir_EligibilitySchedId }
  if ($TicketSystem -or $TicketNumber) {
    $body.ticketInfo = @{ ticketSystem = ($TicketSystem ?? 'N/A'); ticketNumber = $TicketNumber }
  }

  $req = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Host "[OK] Activated Directory: $($Item.Name) ($($Item.Scope))" -ForegroundColor Green
  [pscustomobject]@{
    Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope
    Status=($req.Status ?? 'Sent'); RequestId=$req.Id; Requested=$Iso
  }
}

function Deactivate-DirectoryItem {
  param([pscustomobject]$Item, [string]$Justification)
  $meId = Get-MyUserId
  $body = @{
    action           = 'selfDeactivate'
    principalId      = $meId
    roleDefinitionId = $Item.Dir_RoleDefinitionId
    directoryScopeId = $Item.Dir_ScopeId
    justification    = ($Justification ?? 'Deactivate via PowerShell')
  }
  $req = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Host "[OK] Deactivated Directory: $($Item.Name) ($($Item.Scope))" -ForegroundColor Green
  [pscustomobject]@{
    Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope
    Status=($req.Status ?? 'Sent'); RequestId=$req.Id
  }
}

function Activate-GroupItem {
  param([pscustomobject]$Item, [string]$Iso, [string]$Justification, [string]$TicketSystem, [string]$TicketNumber)

  $max = Get-GroupMaxIso -GroupId $Item.Group_GroupId -AccessId $Item.Group_AccessId
  if ($max -and (Get-MinFromIso $Iso) -gt (Get-MinFromIso $max)) {
    Write-Host "[Policy] Requested $Iso exceeds policy max $max. Entra may cap it." -ForegroundColor Yellow
  }

  $meId = Get-MyUserId
  $body = @{
    accessId      = $Item.Group_AccessId
    action        = 'selfActivate'
    principalId   = $meId
    groupId       = $Item.Group_GroupId
    justification = $Justification
    scheduleInfo  = @{
      startDateTime = ([DateTime]::UtcNow.ToString('o'))
      expiration    = @{ type = 'afterDuration'; duration = $Iso }
    }
  }
  if ($TicketSystem -or $TicketNumber) {
    $body.ticketInfo = @{ ticketSystem = ($TicketSystem ?? 'N/A'); ticketNumber = $TicketNumber }
  }

  $req = New-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Host "[OK] Activated Group: $($Item.Name) [$($Item.Scope)]" -ForegroundColor Green
  [pscustomobject]@{
    Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope
    Status=($req.Status ?? 'Sent'); RequestId=$req.Id; Requested=$Iso
  }
}

function Deactivate-GroupItem {
  param([pscustomobject]$Item, [string]$Justification)
  $meId = Get-MyUserId
  $body = @{
    accessId      = $Item.Group_AccessId
    action        = 'selfDeactivate'
    principalId   = $meId
    groupId       = $Item.Group_GroupId
    justification = ($Justification ?? 'Deactivate via PowerShell')
  }
  $req = New-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
  Write-Host "[OK] Deactivated Group: $($Item.Name) [$($Item.Scope)]" -ForegroundColor Green
  [pscustomobject]@{
    Category=$Item.Category; Role=$Item.Name; Scope=$Item.Scope
    Status=($req.Status ?? 'Sent'); RequestId=$req.Id
  }
}

# ================================================================
#  MAIN
# ================================================================

try {
  Show-CyberBanner
  Connect-GraphSmart -TenantId $TenantId -Auth $Auth -ForceLogin:$ForceLogin

  $IncDir = $true; $IncGrp = $true; $IncAz = $true
  switch ($Target) {
    'Directory'      { $IncGrp = $false; $IncAz = $false }
    'Groups'         { $IncDir = $false; $IncAz = $false }
    'AzureResources' { $IncDir = $false; $IncGrp = $false }
  }

  switch ($Action) {

    'ListEligible' {
      $rows = Build-CombinedEligible -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz |
              Where-Object { -not $_.IsSeparator }
      if ($Roles) { $rows = $rows | Where-Object { $Roles -contains $_.Name } }
      if (-not $rows) { Write-Host "No eligible roles." -ForegroundColor Yellow; break }
      $rows | Select-Object Category, Name, Scope, ActiveNow | Format-Table -AutoSize
    }

    'ListActive' {
      $rows = Build-CombinedActive -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz |
              Where-Object { -not $_.IsSeparator }
      if (-not $rows) { Write-Host "You currently have no active roles." -ForegroundColor Yellow; break }
      $rows | Select-Object Category, Name, Scope, MinutesLeft, Ends | Format-Table -AutoSize
    }

    'Report' {
      $elig = Build-CombinedEligible -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz | Where-Object { -not $_.IsSeparator }
      $act  = Build-CombinedActive   -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz | Where-Object { -not $_.IsSeparator }
      if ($ExportPath) {
        if ($ExportPath.ToLower().EndsWith('.json')) {
          [pscustomobject]@{ Eligible=$elig; Active=$act } |
            ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $ExportPath
          Write-Host "Report written to $ExportPath"
        } else {
          $csv1 = [IO.Path]::ChangeExtension($ExportPath, '.eligible.csv')
          $csv2 = [IO.Path]::ChangeExtension($ExportPath, '.active.csv')
          $elig | Export-Csv -NoTypeInformation -Path $csv1
          $act  | Export-Csv -NoTypeInformation -Path $csv2
          Write-Host "CSV written to $csv1 and $csv2"
        }
      } else {
        Write-Host "Eligible:" -ForegroundColor Cyan
        $elig | Select-Object Category,Name,Scope,ActiveNow | Format-Table -AutoSize
        Write-Host "Active:" -ForegroundColor Cyan
        $act  | Select-Object Category,Name,Scope,MinutesLeft,Ends | Format-Table -AutoSize
      }
    }

    'Activate' {
      $combined = Build-CombinedEligible -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz
      $eligibleOnly = $combined | Where-Object { -not $_.IsSeparator }
      if ($Roles) {
        $combined = $combined | Where-Object { $_.IsSeparator -or ($Roles -contains $_.Name) }
        $eligibleOnly = $eligibleOnly | Where-Object { $Roles -contains $_.Name }
      }
      if (-not $eligibleOnly -or $eligibleOnly.Count -eq 0) {
        Write-Host "No eligible roles found." -ForegroundColor Yellow; break
      }

      $picked = if ($Roles) {
        $eligibleOnly
      } else {
        Select-FromList -Rows $combined -ShowCols 'Category','Name','Scope','ActiveNow' `
                        -Title '╸ ENTRA::PIM ╺ select roles to ACTIVATE ╺╺╺ space=toggle  enter=confirm  esc=cancel' -Multi
      }
      if (-not $picked -or $picked.Count -eq 0) { Write-Host "Nothing selected."; break }

      $rawDur = if ($Duration) { $Duration } else { Read-Host "Duration (e.g. 30m, 1h, 2h30m, 4h) [Enter = 1h]" }
      if ([string]::IsNullOrWhiteSpace($rawDur)) { $rawDur = '1h' }
      $iso = ConvertTo-IsoDuration $rawDur

      if (-not $Justification) { $Justification = Read-Host "Enter justification" }
      if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification cannot be empty." }

      if (-not $TicketSystem -and -not $TicketNumber) {
        $ask = Read-Host "Policy requires ticket (ServiceNow/Jira)? (y/N)"
        if ($ask -match '^(y|j)') {
          $TicketSystem = Read-Host "Ticket system"
          $TicketNumber = Read-Host "Ticket number"
        }
      }

      $summary = @()
      foreach ($item in $picked) {
        if ($item.ActiveNow) {
          Write-Host "[SKIP] $($item.Name) ($($item.Scope)) already active." -ForegroundColor Yellow
          continue
        }
        try {
          $row = switch ($item.Category) {
            'Directory'      { Activate-DirectoryItem -Item $item -Iso $iso -Justification $Justification -TicketSystem $TicketSystem -TicketNumber $TicketNumber }
            'Groups'         { Activate-GroupItem     -Item $item -Iso $iso -Justification $Justification -TicketSystem $TicketSystem -TicketNumber $TicketNumber }
            'AzureResources' { Activate-AzureItem     -Item $item -Iso $iso -Justification $Justification -TicketSystem $TicketSystem -TicketNumber $TicketNumber }
          }
          if ($row) { $summary += $row }
        } catch {
          $summary += [pscustomobject]@{ Category=$item.Category; Role=$item.Name; Scope=$item.Scope; Status='Error'; RequestId=$null; Requested=$iso; Error=$_.Exception.Message }
          Write-Host "[ERR] $($item.Category): $($item.Name) -> $($_.Exception.Message)" -ForegroundColor Red
        }
      }
      if ($summary.Count -gt 0) {
        Write-Host "`nResult:" -ForegroundColor Cyan
        $summary | Format-Table Category,Role,Scope,Status,Requested,RequestId -AutoSize
      }
    }

    'Deactivate' {
      $combined = Build-CombinedActive -IncDir $IncDir -IncGrp $IncGrp -IncAz $IncAz
      $activeOnly = $combined | Where-Object { -not $_.IsSeparator }
      if ($Roles) {
        $combined   = $combined   | Where-Object { $_.IsSeparator -or ($Roles -contains $_.Name) }
        $activeOnly = $activeOnly | Where-Object { $Roles -contains $_.Name }
      }
      if (-not $activeOnly -or $activeOnly.Count -eq 0) {
        Write-Host "You currently have no active roles." -ForegroundColor Yellow; break
      }

      $picked = Select-FromList -Rows $combined -ShowCols 'Category','Name','Scope','MinutesLeft' `
                                -Title '╸ ENTRA::PIM ╺ select roles to DEACTIVATE ╺╺╺ space=toggle  enter=confirm  esc=cancel' -Multi
      if (-not $picked -or $picked.Count -eq 0) { Write-Host "Nothing selected."; break }

      if (-not $Justification) { $Justification = Read-Host "Justification (optional, Enter to skip)" }

      $summary = @()
      foreach ($item in $picked) {
        try {
          $row = switch ($item.Category) {
            'Directory'      { Deactivate-DirectoryItem -Item $item -Justification $Justification }
            'Groups'         { Deactivate-GroupItem     -Item $item -Justification $Justification }
            'AzureResources' { Deactivate-AzureItem     -Item $item -Justification $Justification }
          }
          if ($row) { $summary += $row }
        } catch {
          $summary += [pscustomobject]@{ Category=$item.Category; Role=$item.Name; Scope=$item.Scope; Status='Error'; RequestId=$null; Error=$_.Exception.Message }
          Write-Host "[ERR] $($item.Category): $($item.Name) -> $($_.Exception.Message)" -ForegroundColor Red
        }
      }
      if ($summary.Count -gt 0) {
        Write-Host "`nResult:" -ForegroundColor Cyan
        $summary | Format-Table Category,Role,Scope,Status,RequestId -AutoSize
      }
    }
  }
}
finally {
  if ($DisconnectOnExit) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Disconnected from Microsoft Graph." -ForegroundColor DarkGray
  }
}