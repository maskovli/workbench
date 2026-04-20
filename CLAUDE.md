# CLAUDE.md — Instructions for Claude Code

## Commit policy

All commits in this repo are made by **Marius A. Skovli**.

- **Do NOT commit or push** — stage changes and stop. Marius reviews and commits manually
- **Do NOT add `Co-Authored-By` lines** to suggested commit messages
- Prepare a suggested commit message (conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`) and present it for Marius to use
- This workflow is important for Microsoft MVP contribution tracking and community credibility

## About this repo

Personal monorepo for Entra ID, Intune, Azure, and M365 scripts.
See README.md for structure.

## Conventions

- PowerShell scripts follow `Verb-Noun.ps1` naming (Microsoft standard)
- Folders use lowercase kebab-case
- No customer-specific data — anything referencing a customer goes in `~/GitHub/customers/` instead
- `.gitignore` blocks: `*.csv`, `*.log`, `*.zip`, `*.exe`, `*.intunewin`, `*.DS_Store`, temp files
