# workbench

Personal workspace for general scripts, notes, and infrastructure tools.
Productized projects live in their own repositories.

## Structure

```
scripts/
├── entra-pim/        # PIM role activation and management
├── entra-governance/ # Entra ID governance, IDGov, shadow accounts
├── intune/           # Intune / Endpoint Management
├── m365/             # Microsoft 365, Teams
└── azure/            # Azure RBAC, governance
infra/
└── bicep/            # Bicep templates
notes/                # KQL queries, markdown notes
_archive/             # Old scripts kept for reference
```

## Related

- EntraGate — separate PowerShell module project for Entra ID governance: https://github.com/maskovli/entragate
