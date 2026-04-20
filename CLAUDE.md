# CLAUDE.md — Instructions for Claude Code

## Commit policy

All commits in this repo represent the work of **Marius A. Skovli**.

- **Do NOT add `Co-Authored-By` lines** to commit messages in this repo
- Claude may assist with research, review, and suggestions, but commits are authored by Marius alone
- This is important for Microsoft MVP contribution tracking and community credibility

## About this repo

Personal monorepo for Entra ID, Intune, Azure, and M365 scripts.
See README.md for structure.

## Conventions

- PowerShell scripts follow `Verb-Noun.ps1` naming (Microsoft standard)
- Folders use lowercase kebab-case
- No customer-specific data — anything referencing a customer goes in `~/GitHub/customers/` instead
- `.gitignore` blocks: `*.csv`, `*.log`, `*.zip`, `*.exe`, `*.intunewin`, `*.DS_Store`, temp files
