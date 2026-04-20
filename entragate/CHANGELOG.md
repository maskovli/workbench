# Changelog

All notable changes to EntraGate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-04-20

### Added
- Initial module structure with `Start-EntraGate` dashboard
- Shared auth module (`Connect-GateGraph`, `Connect-GateAzure`) with session reuse and identity validation
- Shared UI module (`Write-Cyber`, `Show-GateBanner`, `Select-GateItems`)
- Duration parser with support for decimal hours (0.5h, 1.5h) and Norwegian comma (0,5h)
- `Invoke-GatePim` stub — PIM activation for Directory, Groups, Azure Resources
- `Invoke-GateAccessReview` stub — bulk approve/deny access reviews
- Standalone reference scripts in `_standalone/`
- MIT License, README, CHANGELOG

### Notes
- PIM and Access Review modules are stubs referencing standalone scripts
- Full migration planned for v0.2.0
