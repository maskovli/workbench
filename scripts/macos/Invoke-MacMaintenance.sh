#!/bin/bash

# macOS maintenance helper for Apple Silicon (Sonoma and newer)
# This script avoids storing your password, adds guardrails, and logs its actions.
# It focuses on safe cleanup (caches/logs), Microsoft 365/Teams cache refresh,
# optional Homebrew cleanup, and macOS software updates.

set -euo pipefail

LOG_FILE="$HOME/Desktop/mac_maintenance_$(date +"%Y%m%d_%H%M%S").log"
SUDO_KEEPALIVE_PID=""

confirm() {
  local prompt="${1:-Proceed?}"
  read -r -p "$prompt [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

start_logging() {
  echo "Logging to $LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

start_sudo_keepalive() {
  sudo -v
  # Keep sudo alive while the script runs.
  while true; do sudo -n true; sleep 50; done &
  SUDO_KEEPALIVE_PID=$!
}

preflight_info() {
  echo "macOS: $(sw_vers -productVersion)"
  echo "Hardware: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")"
  echo "Uptime: $(uptime)"
  echo "Disk free on /: $(df -h / | awk 'NR==2{print $4 " free of " $2}')"
}

safe_clear_dir_contents() {
  local dir="$1"
  [[ -d "$dir" ]] || return
  echo "Clearing contents of: $dir"
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

software_updates() {
  if confirm "Run macOS software updates now (may take a while)"; then
    start_sudo_keepalive
    echo "Checking and installing macOS updates..."
    sudo softwareupdate -ia
  else
    echo "Skipped macOS software updates."
  fi
}

homebrew_cleanup() {
  if command -v brew >/dev/null 2>&1; then
    if confirm "Update and clean Homebrew packages?"; then
      echo "Updating Homebrew..."
      brew update
      echo "Upgrading installed formulae and casks..."
      brew upgrade
      echo "Removing old versions and cache..."
      brew cleanup
    else
      echo "Skipped Homebrew maintenance."
    fi
  else
    echo "Homebrew not detected; skipping Homebrew maintenance."
  fi
}

user_cache_cleanup() {
  if confirm "Clear user caches and logs (safe)"; then
    safe_clear_dir_contents "$HOME/Library/Caches"
    safe_clear_dir_contents "$HOME/Library/Logs"
  else
    echo "Skipped user cache cleanup."
  fi
}

system_cache_cleanup() {
  if confirm "Clear system caches in /Library/Caches (requires sudo)"; then
    start_sudo_keepalive
    safe_clear_dir_contents "/Library/Caches"
  else
    echo "Skipped system cache cleanup."
  fi
}

microsoft_365_cache_cleanup() {
  echo "This will refresh Microsoft 365 caches. Close Word/Excel/PowerPoint/Outlook/Teams before continuing."
  if ! confirm "Proceed with Microsoft 365 cache cleanup"; then
    echo "Skipped Microsoft 365 cache cleanup."
    return
  fi

  local paths=(
    "$HOME/Library/Containers/com.microsoft.Word/Data/Library/Caches"
    "$HOME/Library/Containers/com.microsoft.Excel/Data/Library/Caches"
    "$HOME/Library/Containers/com.microsoft.Powerpoint/Data/Library/Caches"
    "$HOME/Library/Containers/com.microsoft.Outlook/Data/Library/Caches"
    "$HOME/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/Word"
    "$HOME/Library/Application Support/Microsoft/Teams"
    "$HOME/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/Teams" # new Teams (Work/School)
  )

  for target in "${paths[@]}"; do
    if [[ -d "$target" ]]; then
      echo "Clearing: $target"
      safe_clear_dir_contents "$target"
    else
      echo "Not found (skipped): $target"
    fi
  done
}

list_unused_apps() {
  echo "Scanning /Applications for apps not modified in the last 90 days..."
  find /Applications -maxdepth 1 -type d -name "*.app" -mtime +90 -print
  echo "Review the list above and manually remove apps you no longer need."
}

restart_prompt() {
  if confirm "Restart the Mac now to finish cleanup"; then
    start_sudo_keepalive
    echo "Restarting..."
    sudo shutdown -r now
  else
    echo "Restart skipped. A restart is recommended after cache cleaning."
  fi
}

main() {
  start_logging
  echo "Starting maintenance..."

  preflight_info
  user_cache_cleanup
  system_cache_cleanup
  microsoft_365_cache_cleanup
  homebrew_cleanup
  software_updates
  list_unused_apps
  restart_prompt

  echo "Maintenance complete. Log saved to $LOG_FILE"
}

main "$@"
