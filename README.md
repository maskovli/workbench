# workbench

Personal workspace for general scripts, notes, and infrastructure tools.
Productized projects live in their own repositories.

## Structure

```
scripts/
├── active-directory/ # Domain controller and AD inventory/reporting
├── ad-cs/            # AD CS and NDES helpers
├── apps/             # Application-specific endpoint scripts
├── azure/            # Azure RBAC, governance
├── configmgr/        # Configuration Manager helpers
├── entra-governance/ # Entra ID governance, IDGov, shadow accounts
├── entra-pim/        # PIM role activation and management
├── hyper-v-lab/      # Local Hyper-V lab setup
├── intune/           # Intune / Endpoint Management
├── m365/             # Microsoft 365, Teams, Office deployment
├── macos/            # macOS inventory and maintenance
├── powershell/       # General PowerShell maintenance
└── windows/          # Windows deployment, Defender, and power settings
infra/
└── bicep/            # Bicep templates
notes/                # KQL queries, markdown notes
_archive/             # Old scripts kept for reference
```

## Related

- EntraGate — separate PowerShell module project for Entra ID governance: https://github.com/maskovli/entragate
