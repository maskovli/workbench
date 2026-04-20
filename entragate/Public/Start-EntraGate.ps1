# ── Public/Start-EntraGate.ps1 · Main entry point ──

function Start-EntraGate {
  <#
  .SYNOPSIS
    Launch the EntraGate dashboard — your gateway to Entra Identity Governance.
  .DESCRIPTION
    Shows a live dashboard with pending items count, then a menu to navigate
    into PIM, Access Reviews, Guest Lifecycle, and more.
  .EXAMPLE
    Start-EntraGate
    Start-EntraGate -TenantId "abc-123"
    gate   # alias
  #>
  [CmdletBinding()]
  param(
    [Alias('Tenant')]
    [string] $TenantId,

    [ValidateSet('Auto','Interactive','DeviceCode')]
    [string] $Auth = 'Auto',

    [switch] $ForceLogin
  )

  $ErrorActionPreference = 'Stop'

  # ── Banner + Auth ──
  Clear-Host
  Show-GateBanner
  Connect-GateGraph -TenantId $TenantId -Auth $Auth -ForceLogin:$ForceLogin

  $ctx     = Get-MgContext
  $tenant  = Get-GateTenantName
  $tidFull = $ctx.TenantId

  # ── Dashboard counters (best-effort, non-blocking) ──
  Write-Host ""
  Write-Cyber "Loading dashboard..." 'INFO' 'DarkGray'

  $dashboard = @{
    PimActive    = 0
    PimEligible  = 0
    ReviewsPending = 0
    ReviewsDeadline = $null
    # Future counters:
    # RiskyUsers = 0
    # ExpiringSecrets = 0
  }

  $meId = Get-GateUserId

  # PIM counts
  try {
    $dashboard.PimEligible = (Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$meId'" -All -CountVariable c -ErrorAction Stop).Count
    $dashboard.PimActive   = (Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance  -Filter "principalId eq '$meId'" -All -CountVariable c -ErrorAction Stop).Count
  } catch { <# scopes may be missing — non-fatal #> }

  # Access Review counts
  try {
    $reviewCount = 0
    $earliest    = $null
    $defs = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions?$top=50' -ErrorAction Stop).value
    foreach ($def in $defs) {
      $instances = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions/$($def.id)/instances?`$filter=status eq 'InProgress'&`$top=10" -ErrorAction SilentlyContinue).value
      foreach ($inst in $instances) {
        $decisions = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions/$($def.id)/instances/$($inst.id)/decisions/filterByCurrentUser(on='reviewer')?`$filter=decision eq 'NotReviewed'&`$count=true&`$top=1" -ErrorAction SilentlyContinue)
        if ($decisions.value) { $reviewCount += $decisions.'@odata.count' }
        if ($inst.endDateTime) {
          $end = ([datetimeoffset]$inst.endDateTime).LocalDateTime
          if (-not $earliest -or $end -lt $earliest) { $earliest = $end }
        }
      }
    }
    $dashboard.ReviewsPending  = $reviewCount
    $dashboard.ReviewsDeadline = $earliest
  } catch { <# non-fatal #> }

  # ── Display dashboard ──
  Clear-Host
  Show-GateBanner
  Show-GateSessionBar -Account $ctx.Account -TenantName $tenant -TenantId $tidFull

  $c = "`e[38;5;51m"; $g = "`e[38;5;46m"; $y = "`e[38;5;226m"; $red = "`e[38;5;196m"; $d = "`e[38;5;240m"; $r = "`e[0m"

  Write-Host ""
  # PIM
  if ($dashboard.PimActive -gt 0) {
    Write-Host "  ${g}●${r} $($dashboard.PimActive) PIM roles active    ${d}○${r} $($dashboard.PimEligible) eligible"
  } else {
    Write-Host "  ${d}○${r} $($dashboard.PimEligible) PIM roles eligible  ${d}(none active)${r}"
  }
  # Reviews
  if ($dashboard.ReviewsPending -gt 0) {
    $daysLeft = if ($dashboard.ReviewsDeadline) { [math]::Max(0, [math]::Round(($dashboard.ReviewsDeadline - [datetime]::Now).TotalDays)) } else { '?' }
    Write-Host "  ${y}⚠${r} $($dashboard.ReviewsPending) access reviews pending ${d}(due in $daysLeft days)${r}"
  } else {
    Write-Host "  ${g}✓${r} No pending access reviews"
  }
  # Placeholder counters for future modules
  Write-Host "  ${d}·${r} Risky Users, Expiring Secrets, CA Policies ${d}(coming soon)${r}"

  # ── Menu loop ──
  Write-Host ""
  Write-Host "${c}╠══════════════════════════════════════════════════════════════════╣${r}"

  $menuRunning = $true
  while ($menuRunning) {
    Write-Host ""
    Write-Host "  ${c}Navigate to${r}" -ForegroundColor Cyan
    Write-Host "  ${g}▸${r} 1  PIM Activation ${d}(Directory · Groups · Azure)${r}"
    Write-Host "    2  Access Reviews"
    Write-Host "    ${d}3  Conditional Access Policies  (coming soon)${r}"
    Write-Host "    ${d}4  Guest Lifecycle               (coming soon)${r}"
    Write-Host "    ${d}5  Risky Users & Sign-ins        (coming soon)${r}"
    Write-Host "    ${d}6  App Registrations              (coming soon)${r}"
    Write-Host "    ${d}7  License Overview               (coming soon)${r}"
    Write-Host "    8  Session & Auth"
    Write-Host "    Q  Quit"
    Write-Host ""
    $choice = Read-Host "  Select"

    switch ($choice) {
      '1' {
        Write-Host ""
        Invoke-GatePim -TenantId $TenantId
      }
      '2' {
        Write-Host ""
        Invoke-GateAccessReview -TenantId $TenantId
      }
      '8' {
        Write-Host ""
        Write-Host "  Session info:" -ForegroundColor Cyan
        Write-Host "    Graph Account : $($ctx.Account)"
        Write-Host "    Tenant        : $tenant ($tidFull)"
        Write-Host "    Az Connected  : $($script:GateSession.AzConnected)"
        Write-Host ""
        Write-Host "    [S] Switch account  [D] Disconnect  [B] Back" -ForegroundColor Cyan
        $sAns = Read-Host "    Select"
        switch -Regex ($sAns) {
          '^[Ss]$' { Connect-GateGraph -TenantId $TenantId -Auth $Auth -ForceLogin; $ctx = Get-MgContext; $tenant = Get-GateTenantName }
          '^[Dd]$' { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null; Write-Cyber "Disconnected." 'OK' 'Green'; $menuRunning = $false }
        }
      }
      { $_ -match '^[Qq]$' } { $menuRunning = $false }
      { $_ -in '3','4','5','6','7' } { Write-Cyber "Coming soon — want to build it? Open an issue on GitHub!" 'INFO' 'DarkGray' }
      default { Write-Host "  Invalid selection." -ForegroundColor Yellow }
    }
  }

  Write-Host ""
  Write-Cyber "EntraGate session ended." 'INFO' 'DarkGray'
}
