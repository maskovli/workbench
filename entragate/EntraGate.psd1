@{
  RootModule        = 'EntraGate.psm1'
  ModuleVersion     = '0.1.0'
  GUID              = 'a7e3f1b2-4c5d-6e7f-8a9b-0c1d2e3f4a5b'
  Author            = 'Marius A. Skovli'
  CompanyName       = 'Community'
  Copyright         = '(c) 2026 Marius A. Skovli. MIT License.'
  Description       = 'EntraGate — Governance & Access Terminal for Entra. A terminal-based dashboard for Microsoft Entra Identity Governance: PIM activation, Access Reviews, Guest Lifecycle, Risky Users, and more.'

  PowerShellVersion = '7.2'

  RequiredModules   = @(
    @{ ModuleName = 'Microsoft.Graph.Authentication';        ModuleVersion = '2.15.0' }
    @{ ModuleName = 'Microsoft.Graph.Identity.Governance';   ModuleVersion = '2.15.0' }
    @{ ModuleName = 'Microsoft.Graph.Users';                 ModuleVersion = '2.15.0' }
    @{ ModuleName = 'Microsoft.Graph.Groups';                ModuleVersion = '2.15.0' }
  )

  FunctionsToExport = @(
    'Start-EntraGate'
    'Invoke-GatePim'
    'Invoke-GateAccessReview'
    # Future:
    # 'Invoke-GateGuestLifecycle'
    # 'Invoke-GateRiskyUsers'
    # 'Invoke-GateExpiringSecrets'
    # 'Invoke-GateConditionalAccess'
    # 'Invoke-GateLicenseOverview'
  )

  CmdletsToExport   = @()
  VariablesToExport  = @()
  AliasesToExport    = @('gate')

  PrivateData = @{
    PSData = @{
      Tags         = @('Entra', 'EntraID', 'PIM', 'AccessReview', 'IdentityGovernance', 'TUI', 'Terminal', 'Azure', 'Security')
      LicenseUri   = 'https://github.com/maskovli/workbench/blob/main/entragate/LICENSE'
      ProjectUri   = 'https://github.com/maskovli/workbench/tree/main/entragate'
      IconUri      = ''
      ReleaseNotes = 'Initial release — PIM Activation + Access Reviews.'
    }
  }
}
