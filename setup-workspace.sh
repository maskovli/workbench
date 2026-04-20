#!/usr/bin/env bash

# Root directory
ROOT="$HOME/Work"

echo "Creating workspace structure under $ROOT"

mkdir -p \
  "$ROOT/00-Inbox" \
  "$ROOT/01-Private/"{playground,vibe-lab,scripts,tooling,apps,notes,repos} \
  "$ROOT/02-Spirhed/internal/"{scripts,tooling,apps,templates,docs,repos} \
  "$ROOT/02-Spirhed/communities/"{mmugno,workplaceninja} \
  "$ROOT/03-Clients/_template/"{00-admin,01-discovery,02-design,03-implementation,04-operations,05-handover,scripts,tooling,apps,docs,repos} \
  "$ROOT/04-Libs/"{powershell,python,bicep,terraform,kql} \
  "$ROOT/05-Tools/"{devcontainers,vscode-profiles,docker} \
  "$ROOT/90-Archive"

echo "Creating basic README markers..."

echo "# Inbox
Temporary dumping ground. Clean weekly." > "$ROOT/00-Inbox/README.md"

echo "# Private Workspace
Personal experiments, scripts and tooling." > "$ROOT/01-Private/README.md"

echo "# Spirhed Workspace
Internal tools, scripts and reusable components." > "$ROOT/02-Spirhed/README.md"

echo "# Clients
Each customer gets its own folder based on _template." > "$ROOT/03-Clients/README.md"

echo "# Shared Libraries
Reusable code not tied to any client." > "$ROOT/04-Libs/README.md"

echo "# Dev Tools
Containers, VS Code profiles and helper tooling." > "$ROOT/05-Tools/README.md"

echo "Done."
echo "Workspace created at: $ROOT"