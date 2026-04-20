#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Semi-automate Microsoft Entra Access Reviews from the command line.

.DESCRIPTION
  Lists all pending access review decisions assigned to you, lets you
  bulk-approve or deny guests/members with justification — no portal clicking.

  Uses Microsoft Graph v1.0 API:
    - GET  .../accessReviews/definitions → instances → decisions/filterByCurrentUser(on='reviewer')
    - PATCH .../decisions/{id}           → Approve / Deny

.EXAMPLE
  ./Invoke-EntraAccessReview.ps1                        # interactive
  ./Invoke-EntraAccessReview.ps1 -Action ListPending    # just show what's waiting
  ./Invoke-EntraAccessReview.ps1 -Action AutoDeny -Justification "Guest no longer in project"
#>

[CmdletBinding()]
param(
  [ValidateSet('ListPending','Review','AutoApprove','AutoDeny')]
  [string] $Action = 'Review',

  [Alias('Tenant')]
  [string] $TenantId,

  [ValidateSet('Auto','Interactive','DeviceCode')]
  [string] $Auth = 'Auto',

  [string]   $Justification,
  [switch]   $SkipGrid,
  [switch]   $ForceLogin,
  [switch]   $DisconnectOnExit
)

$ErrorActionPreference = 'Stop'

# ================================================================
#  UTILITIES
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
    if ($Optional) { Write-Warning "Optional module '$Name' not installed."; return $false }
    Write-Host "Installing module $Name (CurrentUser)..." -ForegroundColor Yellow
    Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }
  Import-Module $Name -ErrorAction Stop | Out-Null
  return $true
}

# ================================================================
#  CYBER UI
# ================================================================

function Show-ReviewBanner {
  $reset = "`e[0m"; $cyan = "`e[38;5;51m"; $green = "`e[38;5;46m"
  $dim = "`e[38;5;240m"; $yellow = "`e[38;5;226m"

  $lines = @(
    "${cyan}╔══════════════════════════════════════════════════════════════╗${reset}"
    "${cyan}║${reset}  ${green}ACCESS REVIEW${reset}  ${dim}///${reset} ${yellow}Entra ID${reset}                              ${cyan}║${reset}"
    "${cyan}║${reset}  ${dim}╶─ semi-automated guest & member review ──────────────╴${reset}  ${cyan}║${reset}"
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
    'SKIP'  { 'DarkYellow' }
    default { 'DarkCyan' }
  }
  Write-Host "[" -NoNewline -ForegroundColor DarkGray
  Write-Host $Tag -NoNewline -ForegroundColor $tagColor
  Write-Host "] " -NoNewline -ForegroundColor DarkGray
  Write-Host $Text -ForegroundColor $Color
}

# ================================================================
#  AUTH (reuse from PIM script pattern)
# ================================================================

$RequiredScopes = @(
  'User.Read'
  'AccessReview.ReadWrite.All'
)

function Invoke-GraphLogin {
  param([string]$Method, [string]$TenantId)
  if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
  }
  if (Get-Command Clear-MgContext -ErrorAction SilentlyContinue) {
    Clear-MgContext -Scope Process -Force -ErrorAction SilentlyContinue
  }
  $connArgs = @{ Scopes = $RequiredScopes; NoWelcome = $true; ContextScope = 'Process' }
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
}

function Connect-GraphForReview {
  param([string]$TenantId, [string]$Auth = 'Auto', [switch]$ForceLogin)

  Ensure-Module Microsoft.Graph.Authentication -MinVersion '2.15.0' | Out-Null

  if ($ForceLogin) { Invoke-GraphLogin -Method $Auth -TenantId $TenantId; return }

  $ctx = Get-MgContext -ErrorAction SilentlyContinue
  if ($ctx -and $ctx.Account) {
    $alive = $false
    try { Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null; $alive = $true } catch {}
    if ($alive) {
      Write-Host ""
      Write-Host "Existing Graph session:" -ForegroundColor Cyan
      Write-Host ("  Account : {0}" -f $ctx.Account)
      Write-Host ("  Tenant  : {0}" -f $ctx.TenantId)
      Write-Host ""
      Write-Host "  [C] Continue  [S] Switch account  [Q] Quit" -ForegroundColor Cyan
      $ans = Read-Host "Select [C/S/Q]"
      switch -Regex ($ans) {
        '^(q|Q)$' { throw "Aborted." }
        '^(s|S)$' { Invoke-GraphLogin -Method $Auth -TenantId $TenantId; return }
        default   { Write-Cyber "Reusing existing session." 'OK' 'Green'; return }
      }
    }
  }
  Invoke-GraphLogin -Method $Auth -TenantId $TenantId
}

# ================================================================
#  DATA FETCHING
# ================================================================

function Get-PendingDecisions {
  <# Returns all "NotReviewed" decision items across all active review instances
     where the current user is a reviewer. #>

  Write-Cyber "Scanning for pending access reviews..." 'INFO' 'Cyan'

  # 1. Get all access review definitions
  $defs = @()
  $uri = 'https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions?$top=100'
  while ($uri) {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    if ($resp.value) { $defs += $resp.value }
    $uri = $resp.'@odata.nextLink'
  }

  if ($defs.Count -eq 0) {
    Write-Cyber "No access review definitions found." 'WARN' 'Yellow'
    return @()
  }
  Write-Cyber "Found $($defs.Count) review definition(s). Checking for active instances..." 'INFO' 'DarkGray'

  # 2. For each definition, find InProgress instances
  $allDecisions = @()
  foreach ($def in $defs) {
    $instUri = "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions/$($def.id)/instances?`$filter=status eq 'InProgress'&`$top=100"
    try {
      $instResp = Invoke-MgGraphRequest -Method GET -Uri $instUri -ErrorAction Stop
    } catch { continue }
    if (-not $instResp.value -or $instResp.value.Count -eq 0) { continue }

    foreach ($inst in $instResp.value) {
      # 3. Get decisions where I am the reviewer and haven't reviewed yet
      $decUri = "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions/$($def.id)/instances/$($inst.id)/decisions/filterByCurrentUser(on='reviewer')?`$filter=decision eq 'NotReviewed'&`$top=500"
      try {
        $decResp = Invoke-MgGraphRequest -Method GET -Uri $decUri -ErrorAction Stop
      } catch { continue }
      if (-not $decResp.value -or $decResp.value.Count -eq 0) { continue }

      foreach ($dec in $decResp.value) {
        $principalName = $dec.principal.displayName
        $principalUpn  = $dec.principal.userPrincipalName
        $principalType = $dec.principal.'@odata.type' -replace '#microsoft.graph.', ''
        $resourceName  = $dec.resource.displayName
        $resourceType  = $dec.resource.'@odata.type' -replace '#microsoft.graph.', ''

        # Detect guest vs member
        $isGuest = if ($principalUpn -match '#EXT#') { $true }
                   elseif ($dec.principal.userType -eq 'Guest') { $true }
                   else { $false }

        $allDecisions += [pscustomobject]@{
          ReviewName    = $def.displayName
          Principal     = $principalName
          UPN           = $principalUpn
          PrincipalType = $principalType
          UserType      = if ($isGuest) { 'Guest' } else { 'Member' }
          Resource      = $resourceName
          ResourceType  = $resourceType
          Deadline      = if ($inst.endDateTime) { ([datetimeoffset]$inst.endDateTime).LocalDateTime.ToString('yyyy-MM-dd') } else { 'N/A' }
          Decision      = $dec.decision
          DefinitionId  = $def.id
          InstanceId    = $inst.id
          DecisionId    = $dec.id
          IsSeparator   = $false
        }
      }
    }
  }

  Write-Cyber "Found $($allDecisions.Count) pending decision(s)." 'INFO' 'Cyan'
  return $allDecisions
}

# ================================================================
#  GRID / SELECTION
# ================================================================

function Test-GridAvailable {
  if ($SkipGrid) { return $false }
  return [bool](Ensure-Module Microsoft.PowerShell.ConsoleGuiTools -MinVersion '0.7.0' -Optional)
}

function Select-Decisions {
  param([array]$Rows, [string]$Title, [switch]$Multi)
  if (-not $Rows -or $Rows.Count -eq 0) { return @() }
  $showCols = @('ReviewName','Principal','UserType','Resource','Deadline')
  $hasGrid = Test-GridAvailable

  if ($hasGrid) {
    $pairs = foreach ($r in $Rows) {
      $o = [ordered]@{}
      foreach ($c in $showCols) { $o[$c] = $r.$c }
      # Prettify UserType
      $o['UserType'] = if ($r.UserType -eq 'Guest') { '👤 Guest' } else { '👥 Member' }
      [pscustomobject]@{ Display = [pscustomobject]$o; Original = $r }
    }
    $displayList = $pairs | ForEach-Object { $_.Display }
    $mode = if ($Multi) { 'Multiple' } else { 'Single' }
    $sel = $displayList | Out-ConsoleGridView -Title $Title -OutputMode $mode
    if (-not $sel) { return @() }
    $picked = foreach ($s in $sel) {
      ($pairs | Where-Object { [object]::ReferenceEquals($_.Display, $s) } | Select-Object -First 1).Original
    }
    return @($picked)
  }

  # Fallback: numbered list
  Write-Host ""
  Write-Host $Title -ForegroundColor Cyan
  $i = 1
  foreach ($r in $Rows) {
    $type = if ($r.UserType -eq 'Guest') { 'GUEST' } else { 'MEMBR' }
    Write-Host ("  [{0,3}] [{1}] {2,-30} → {3,-30} (due {4})" -f $i, $type, $r.Principal, $r.Resource, $r.Deadline)
    $r | Add-Member -NotePropertyName __Index -NotePropertyValue $i -Force
    $i++
  }
  $prompt = if ($Multi) { "Numbers (comma-separated, 'all' for all), Enter to cancel" } else { "Number, Enter to cancel" }
  $ans = Read-Host $prompt
  if ([string]::IsNullOrWhiteSpace($ans)) { return @() }
  if ($ans -ieq 'all') { return $Rows }
  $idx = $ans -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
  return @($Rows | Where-Object { $idx -contains $_.__Index })
}

# ================================================================
#  EXECUTORS
# ================================================================

function Submit-Decision {
  param(
    [pscustomobject]$Item,
    [ValidateSet('Approve','Deny')][string]$Decision,
    [string]$Justification
  )
  $uri = "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions/$($Item.DefinitionId)/instances/$($Item.InstanceId)/decisions/$($Item.DecisionId)"
  $body = @{
    decision      = $Decision
    justification = $Justification
  }
  Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body ($body | ConvertTo-Json) -ContentType 'application/json' -ErrorAction Stop | Out-Null
}

function Invoke-BulkDecision {
  param(
    [array]$Items,
    [ValidateSet('Approve','Deny')][string]$Decision,
    [string]$Justification
  )
  $summary = @()
  $total = $Items.Count
  $current = 0
  foreach ($item in $Items) {
    $current++
    $pct = [math]::Round(($current / $total) * 100)
    Write-Host "`r  Processing $current/$total ($pct%) " -NoNewline -ForegroundColor DarkGray
    try {
      Submit-Decision -Item $item -Decision $Decision -Justification $Justification
      $summary += [pscustomobject]@{
        Principal = $item.Principal; Resource = $item.Resource
        UserType = $item.UserType; Decision = $Decision; Status = 'OK'
      }
    } catch {
      $summary += [pscustomobject]@{
        Principal = $item.Principal; Resource = $item.Resource
        UserType = $item.UserType; Decision = $Decision; Status = "ERR: $($_.Exception.Message)"
      }
    }
  }
  Write-Host ""  # newline after progress
  return $summary
}

# ================================================================
#  MAIN
# ================================================================

try {
  Show-ReviewBanner
  Connect-GraphForReview -TenantId $TenantId -Auth $Auth -ForceLogin:$ForceLogin

  $pending = Get-PendingDecisions
  if (-not $pending -or $pending.Count -eq 0) {
    Write-Cyber "No pending reviews. You're all caught up!" 'OK' 'Green'
    exit 0
  }

  switch ($Action) {

    'ListPending' {
      $pending | Format-Table ReviewName, Principal, UserType, Resource, ResourceType, Deadline -AutoSize
    }

    'AutoApprove' {
      if (-not $Justification) { $Justification = Read-Host "Justification for approving ALL $($pending.Count) items" }
      if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification required." }

      Write-Cyber "Auto-approving $($pending.Count) decision(s)..." 'INFO' 'Yellow'
      $results = Invoke-BulkDecision -Items $pending -Decision 'Approve' -Justification $Justification
      $ok  = ($results | Where-Object { $_.Status -eq 'OK' }).Count
      $err = ($results | Where-Object { $_.Status -ne 'OK' }).Count
      Write-Cyber "Done: $ok approved, $err errors." $(if ($err -gt 0) { 'WARN' } else { 'OK' }) $(if ($err -gt 0) { 'Yellow' } else { 'Green' })
      if ($err -gt 0) { $results | Where-Object { $_.Status -ne 'OK' } | Format-Table -AutoSize }
    }

    'AutoDeny' {
      if (-not $Justification) { $Justification = Read-Host "Justification for denying ALL $($pending.Count) items" }
      if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification required." }

      Write-Cyber "Auto-denying $($pending.Count) decision(s)..." 'INFO' 'Yellow'
      $results = Invoke-BulkDecision -Items $pending -Decision 'Deny' -Justification $Justification
      $ok  = ($results | Where-Object { $_.Status -eq 'OK' }).Count
      $err = ($results | Where-Object { $_.Status -ne 'OK' }).Count
      Write-Cyber "Done: $ok denied, $err errors." $(if ($err -gt 0) { 'WARN' } else { 'OK' }) $(if ($err -gt 0) { 'Yellow' } else { 'Green' })
      if ($err -gt 0) { $results | Where-Object { $_.Status -ne 'OK' } | Format-Table -AutoSize }
    }

    default { # 'Review' — interactive
      # Group by review name for overview
      $grouped = $pending | Group-Object ReviewName
      Write-Host ""
      Write-Host "Pending reviews summary:" -ForegroundColor Cyan
      foreach ($g in $grouped) {
        $guests  = ($g.Group | Where-Object { $_.UserType -eq 'Guest' }).Count
        $members = ($g.Group | Where-Object { $_.UserType -eq 'Member' }).Count
        $deadline = ($g.Group | Select-Object -First 1).Deadline
        Write-Host ("  {0,-45} {1,3} guest(s), {2,3} member(s)  due {3}" -f $g.Name, $guests, $members, $deadline)
      }

      Write-Host ""
      Write-Host "What would you like to do?" -ForegroundColor Cyan
      Write-Host "  [1] Select individual items to approve/deny"
      Write-Host "  [2] Approve ALL guests (bulk)"
      Write-Host "  [3] Deny ALL guests (bulk)"
      Write-Host "  [4] Approve ALL (guests + members)"
      Write-Host "  [5] Deny ALL (guests + members)"
      Write-Host "  [Q] Quit"
      $choice = Read-Host "Select"

      switch ($choice) {
        '1' {
          $picked = Select-Decisions -Rows $pending `
                      -Title '╸ ACCESS REVIEW ╺ select items ╺╺╺ space=toggle  enter=confirm' -Multi
          if (-not $picked -or $picked.Count -eq 0) { Write-Host "Nothing selected."; break }

          Write-Host ""
          Write-Host "  [A] Approve selected  [D] Deny selected  [Q] Cancel" -ForegroundColor Cyan
          $dec = Read-Host "Select"
          if ($dec -match '^[Qq]') { break }
          $decision = if ($dec -match '^[Dd]') { 'Deny' } else { 'Approve' }

          if (-not $Justification) { $Justification = Read-Host "Justification" }
          if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification required." }

          $results = Invoke-BulkDecision -Items $picked -Decision $decision -Justification $Justification
          Write-Host ""
          Write-Cyber "Result:" 'INFO' 'Cyan'
          $results | Format-Table Principal, Resource, UserType, Decision, Status -AutoSize
        }
        '2' {
          $guests = $pending | Where-Object { $_.UserType -eq 'Guest' }
          if (-not $guests -or $guests.Count -eq 0) { Write-Cyber "No guest decisions found." 'WARN' 'Yellow'; break }
          if (-not $Justification) { $Justification = Read-Host "Justification for approving $($guests.Count) guest(s)" }
          if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification required." }
          $results = Invoke-BulkDecision -Items $guests -Decision 'Approve' -Justification $Justification
          Write-Cyber "Approved $($guests.Count) guest(s)." 'OK' 'Green'
        }
        '3' {
          $guests = $pending | Where-Object { $_.UserType -eq 'Guest' }
          if (-not $guests -or $guests.Count -eq 0) { Write-Cyber "No guest decisions found." 'WARN' 'Yellow'; break }
          if (-not $Justification) { $Justification = Read-Host "Justification for denying $($guests.Count) guest(s)" }
          if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification required." }
          $results = Invoke-BulkDecision -Items $guests -Decision 'Deny' -Justification $Justification
          Write-Cyber "Denied $($guests.Count) guest(s)." 'OK' 'Green'
        }
        '4' {
          if (-not $Justification) { $Justification = Read-Host "Justification for approving ALL $($pending.Count) items" }
          if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification required." }
          $results = Invoke-BulkDecision -Items $pending -Decision 'Approve' -Justification $Justification
          Write-Cyber "Approved $($pending.Count) item(s)." 'OK' 'Green'
        }
        '5' {
          if (-not $Justification) { $Justification = Read-Host "Justification for denying ALL $($pending.Count) items" }
          if ([string]::IsNullOrWhiteSpace($Justification)) { throw "Justification required." }
          $results = Invoke-BulkDecision -Items $pending -Decision 'Deny' -Justification $Justification
          Write-Cyber "Denied $($pending.Count) item(s)." 'OK' 'Green'
        }
        default { Write-Host "Cancelled." }
      }
    }
  }
}
finally {
  if ($DisconnectOnExit) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
  }
}
