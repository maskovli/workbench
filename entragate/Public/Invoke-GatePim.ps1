# ── Public/Invoke-GatePim.ps1 · PIM Activation (Directory + Groups + Azure Resources) ──

function Invoke-GatePim {
  <#
  .SYNOPSIS
    Activate or deactivate PIM roles — Directory, Groups, and Azure Resources.
  .DESCRIPTION
    This is the EntraGate-integrated version of Activate-EntraPimRoles.ps1.
    Uses shared auth from Private/Auth.ps1 and shared UI from Private/UI.ps1.

    TODO (Claude Code): Migrate the full logic from Activate-EntraPimRoles.ps1
    into this function, replacing inline auth/UI with the shared Gate* functions.
  .EXAMPLE
    Invoke-GatePim                           # interactive activate
    Invoke-GatePim -PimAction Deactivate     # deactivate
    Invoke-GatePim -PimAction ListActive     # show active roles
  #>
  [CmdletBinding()]
  param(
    [ValidateSet('Activate','Deactivate','ListEligible','ListActive')]
    [string] $PimAction = 'Activate',

    [ValidateSet('Auto','Directory','Groups','AzureResources')]
    [string] $Target = 'Auto',

    [string]   $TenantId,
    [string]   $Duration,
    [string]   $Justification,
    [string]   $TicketSystem,
    [string]   $TicketNumber,
    [string[]] $Roles,
    [string[]] $AzureScopes
  )

  # Ensure Graph is connected (may already be from Start-EntraGate)
  if (-not $script:GateSession.GraphConnected) {
    Connect-GateGraph -TenantId $TenantId
  }

  $IncDir = $true; $IncGrp = $true; $IncAz = $true
  switch ($Target) {
    'Directory'      { $IncGrp = $false; $IncAz = $false }
    'Groups'         { $IncDir = $false; $IncAz = $false }
    'AzureResources' { $IncDir = $false; $IncGrp = $false }
  }

  # ── TODO: Migrate from Activate-EntraPimRoles.ps1 ──
  # The full implementation lives in the standalone script.
  # In Claude Code, refactor the following into this function:
  #   - Get-DirEligibleRows / Get-DirActiveRows
  #   - Get-GroupEligibleRows / Get-GroupActiveRows
  #   - Get-AzEligibleRows / Get-AzActiveRows  (calls Connect-GateAzure lazily)
  #   - Build-CombinedEligible / Build-CombinedActive
  #   - Activate-DirectoryItem / Deactivate-DirectoryItem
  #   - Activate-GroupItem / Deactivate-GroupItem
  #   - Activate-AzureItem / Deactivate-AzureItem
  #
  # Use these shared functions instead of inline versions:
  #   - Get-GateUserId          (replaces Get-MyUserId)
  #   - Get-GateTenantName      (replaces Get-TenantDisplayName)
  #   - Select-GateItems        (replaces Select-FromList / Choose-Items)
  #   - Write-Cyber             (replaces Write-Host with tags)
  #   - ConvertTo-IsoDuration   (replaces Convert-ToIso8601Duration)
  #   - Connect-GateAzure       (replaces Connect-AzureSmart)

  Write-Cyber "PIM module loaded. Action: $PimAction, Target: $Target" 'INFO' 'Cyan'
  Write-Host ""
  Write-Host "  This is a stub. In Claude Code, run:" -ForegroundColor Yellow
  Write-Host "  'Migrate Activate-EntraPimRoles.ps1 into Invoke-GatePim'" -ForegroundColor Yellow
  Write-Host "  to complete the integration." -ForegroundColor Yellow
  Write-Host ""
}
