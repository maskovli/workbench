#Requires -Version 7.2

# ── EntraGate · Module Loader ──────────────────────────────────────
# Dot-source Private (internal) functions first, then Public (exported).
# File naming convention:  Auth.ps1, UI.ps1, etc.
# Each .ps1 file should define one or more functions.

$Private = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1"  -ErrorAction SilentlyContinue)

foreach ($file in ($Private + $Public)) {
  try {
    . $file.FullName
  } catch {
    Write-Error "EntraGate: Failed to load $($file.FullName): $_"
  }
}

# Alias
Set-Alias -Name 'gate' -Value 'Start-EntraGate' -Scope Global

# Module-scoped state
$script:GateSession = @{
  GraphConnected = $false
  AzConnected    = $false
  CachedTenantName = $null
  CachedUserId     = $null
}
