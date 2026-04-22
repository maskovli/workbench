# CLAUDE.md — Instructions for Claude Code

## Project

**EntraGate** — a PowerShell 7.2+ module providing a terminal-based dashboard
for Microsoft Entra Identity Governance (PIM, Access Reviews, Guest Lifecycle, etc.).

## Architecture

```
EntraGate.psm1          # Module loader — dot-sources Private/ then Public/
Private/Auth.ps1        # Shared auth: Connect-GateGraph, Connect-GateAzure, Get-GateUserId, Get-GateTenantName
Private/UI.ps1          # Shared UI: Show-GateBanner, Write-Cyber, Select-GateItems
Private/Duration.ps1    # ConvertTo-IsoDuration, Get-MinFromIso
Public/Start-EntraGate.ps1      # Main entry: dashboard + menu loop
Public/Invoke-GatePim.ps1       # PIM activation — Directory, Groups, Azure Resources ✓
Public/Invoke-GateAccessReview.ps1  # Access Reviews (STUB — needs migration)
_standalone/            # Original working scripts — use as reference for migration
Tests/                  # Pester tests
```

## Key conventions

- **Shared state**: `$script:GateSession` hashtable (GraphConnected, AzConnected, CachedTenantName, CachedUserId)
- **Auth**: Always use `Connect-GateGraph` / `Connect-GateAzure` — never inline `Connect-MgGraph`
- **User ID**: Always use `Get-GateUserId` (cached)
- **UI output**: Use `Write-Cyber` with tags (OK, ERR, WARN, AUTH, INFO, SKIP)
- **Selection**: Use `Select-GateItems` — handles ConsoleGridView with numbered fallback
- **Duration**: Use `ConvertTo-IsoDuration` — handles 0.5h, 0,5h, 1h30m, etc.
- **Azure lazy connect**: `Connect-GateAzure` is only called when Azure Resources are needed

## Priority tasks

1. ~~**Migrate PIM**~~ ✓ Done — `Public/Invoke-GatePim.ps1` fully migrated from `_standalone/Activate-EntraPimRoles.ps1`.
2. **Migrate Access Reviews**: `_standalone/Invoke-EntraAccessReview.ps1` → `Public/Invoke-GateAccessReview.ps1` (still stub).
3. **New modules**: Build Conditional Access, Guest Lifecycle, Risky Users, Expiring Secrets, License Overview as new files in Public/.

## Testing

```bash
pwsh -Command "Invoke-Pester ./Tests/ -Output Detailed"
```

## Commit policy

All commits are made by **Marius A. Skovli**.

- **Do NOT commit or push** — stage changes and stop. Marius reviews and commits manually
- **Do NOT add `Co-Authored-By` lines** to suggested commit messages
- Prepare a suggested commit message using conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`) and present it for Marius to use
- This workflow is important for Microsoft MVP contribution tracking and community credibility

## Style

- PowerShell 7.2+ features OK (ternary, null-coalescing, etc.)
- ANSI color codes for terminal UI (256-color safe)
- Conventional commits: feat:, fix:, docs:, refactor:
- Norwegian comments OK in non-exported code
