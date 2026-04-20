# EntraGate

**Governance & Access Terminal for Entra**

> Your gateway to Microsoft Entra Identity Governance — from the terminal.

![PowerShell](https://img.shields.io/badge/PowerShell-7.2+-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)

<!-- TODO: Add terminal screenshot here -->
<!-- ![EntraGate Dashboard](docs/screenshot-dashboard.png) -->

---

## What is EntraGate?

EntraGate is a terminal-based dashboard for Microsoft Entra Identity Governance.
It consolidates daily identity admin tasks into a single, fast, keyboard-driven interface.

Think of it as **InTUI, but for Entra ID** — PIM activation, Access Reviews, guest lifecycle, and more.

## Features

| Module | Status | Description |
|--------|--------|-------------|
| **PIM Activation** | ✅ Ready | Activate/deactivate Directory roles, PIM for Groups, Azure Resources |
| **Access Reviews** | ✅ Ready | List pending, bulk approve/deny guests & members |
| Conditional Access | 🔜 Planned | View/compare CA policies |
| Guest Lifecycle | 🔜 Planned | Audit & cleanup external users |
| Risky Users | 🔜 Planned | Review risky sign-ins & users |
| App Registrations | 🔜 Planned | Find expiring secrets & certificates |
| License Overview | 🔜 Planned | SKU usage & availability |

## Quick Start

```powershell
# Install (when published to PSGallery)
Install-Module EntraGate -Scope CurrentUser

# Or clone and import directly
git clone https://github.com/YOUR_USERNAME/EntraGate.git
Import-Module ./EntraGate/EntraGate.psd1

# Launch
Start-EntraGate
# or just:
gate
```

## Prerequisites

- **PowerShell 7.2+**
- **Microsoft.Graph modules** (installed automatically if missing):
  - Microsoft.Graph.Authentication (>= 2.15.0)
  - Microsoft.Graph.Identity.Governance
  - Microsoft.Graph.Users
  - Microsoft.Graph.Groups
- **Optional**: `Microsoft.PowerShell.ConsoleGuiTools` for the interactive grid selector
- **Optional**: `Az.Accounts` + `Az.Resources` for Azure Resources PIM

## Usage

### Dashboard

```powershell
Start-EntraGate                    # interactive dashboard
Start-EntraGate -TenantId "abc"    # specify tenant
Start-EntraGate -Auth DeviceCode   # force device code auth
```

### PIM Activation (direct)

```powershell
Invoke-GatePim                                    # interactive
Invoke-GatePim -PimAction ListActive              # show active roles
Invoke-GatePim -Target Directory -Duration 2h     # directory only
```

### Access Reviews (direct)

```powershell
Invoke-GateAccessReview                           # interactive
Invoke-GateAccessReview -ReviewAction ListPending  # just list
Invoke-GateAccessReview -ReviewAction AutoApprove -Justification "Verified"
```

## Architecture

```
EntraGate/
├── EntraGate.psd1           # Module manifest
├── EntraGate.psm1           # Module loader (dot-sources Private/ then Public/)
├── Private/
│   ├── Auth.ps1             # Shared auth: Connect-GateGraph, Connect-GateAzure
│   ├── UI.ps1               # Banners, Write-Cyber, Select-GateItems
│   └── Duration.ps1         # ISO 8601 duration parsing
├── Public/
│   ├── Start-EntraGate.ps1  # Dashboard entry point
│   ├── Invoke-GatePim.ps1   # PIM activation module
│   └── Invoke-GateAccessReview.ps1  # Access Reviews module
├── Tests/                   # Pester tests
├── docs/                    # Screenshots, architecture notes
└── _standalone/             # Original standalone scripts (reference)
```

## Session Management

EntraGate reuses existing Microsoft Graph sessions. On launch you'll see:

```
Existing Microsoft Graph session:
  Account : admin@contoso.com
  Tenant  : df55caf0-d133-...

  [C] Continue  [S] Switch account  [Q] Quit
```

When Azure Resources PIM is needed, EntraGate validates that the Az identity
matches the Graph identity — preventing cross-tenant credential leaks.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- Built with [Microsoft Graph PowerShell SDK](https://github.com/microsoftgraph/msgraph-sdk-powershell)
- Inspired by [InTUI](https://github.com/jorgeasaurus/intui) (Intune Terminal User Interface)
