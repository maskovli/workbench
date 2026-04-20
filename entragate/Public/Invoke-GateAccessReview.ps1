# ── Public/Invoke-GateAccessReview.ps1 · Access Reviews ──

function Invoke-GateAccessReview {
  <#
  .SYNOPSIS
    Semi-automate Entra Access Reviews — list, approve, deny in bulk.
  .DESCRIPTION
    EntraGate-integrated version of Invoke-EntraAccessReview.ps1.

    TODO (Claude Code): Migrate the full logic from Invoke-EntraAccessReview.ps1
    into this function, replacing inline auth/UI with shared Gate* functions.
  .EXAMPLE
    Invoke-GateAccessReview                              # interactive
    Invoke-GateAccessReview -ReviewAction ListPending     # just show pending
    Invoke-GateAccessReview -ReviewAction AutoApprove -Justification "Verified"
  #>
  [CmdletBinding()]
  param(
    [ValidateSet('ListPending','Review','AutoApprove','AutoDeny')]
    [string] $ReviewAction = 'Review',

    [string] $TenantId,
    [string] $Justification
  )

  if (-not $script:GateSession.GraphConnected) {
    Connect-GateGraph -TenantId $TenantId
  }

  # ── TODO: Migrate from Invoke-EntraAccessReview.ps1 ──
  # The full implementation lives in the standalone script.
  # In Claude Code, refactor the following into this function:
  #   - Get-PendingDecisions
  #   - Select-Decisions        → replace with Select-GateItems
  #   - Submit-Decision
  #   - Invoke-BulkDecision
  #   - The interactive Review menu (options 1-5)
  #
  # Use shared functions:
  #   - Write-Cyber, Select-GateItems, Get-GateUserId

  Write-Cyber "Access Review module loaded. Action: $ReviewAction" 'INFO' 'Cyan'
  Write-Host ""
  Write-Host "  This is a stub. In Claude Code, run:" -ForegroundColor Yellow
  Write-Host "  'Migrate Invoke-EntraAccessReview.ps1 into Invoke-GateAccessReview'" -ForegroundColor Yellow
  Write-Host "  to complete the integration." -ForegroundColor Yellow
  Write-Host ""
}
