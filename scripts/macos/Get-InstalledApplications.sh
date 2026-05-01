#!/bin/bash

# List installed macOS apps with name, path, size (MB), last used, and install date.
# Sources: /Applications, /System/Applications, ~/Applications.
# Output: CSV saved to Desktop by default.

set -euo pipefail

OUTPUT_FILE="${1:-$HOME/Desktop/applications_$(date +%Y%m%d_%H%M%S).csv}"

csv_escape() {
  local s="$1"
  s=${s//\"/\"\"}
  printf '"%s"' "$s"
}

format_date() {
  local raw="$1"
  if [[ -z "$raw" || "$raw" == "(null)" ]]; then
    echo ""
  else
    # mdls dates look like: 2024-01-01 12:34:56 +0000
    date -j -f '%Y-%m-%d %H:%M:%S %z' "$raw" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$raw"
  fi
}

get_mdls_value() {
  local attr="$1" file="$2"
  mdls -name "$attr" -raw "$file" 2>/dev/null || echo ""
}

echo "Writing app inventory to: $OUTPUT_FILE"
printf 'Name,Path,Size_MB,Last_Used,Installed\n' >"$OUTPUT_FILE"

find /Applications /System/Applications "$HOME/Applications" -maxdepth 2 -type d -name "*.app" -print0 2>/dev/null |
while IFS= read -r -d '' app; do
  name=$(basename "$app")

  size_kb=$(du -sk "$app" 2>/dev/null | awk '{print $1}')
  if [[ -z "$size_kb" ]]; then
    size_mb=""
  else
    size_mb=$(printf "%.1f" "$(echo "$size_kb/1024" | bc -l)")
  fi

  last_used_raw=$(get_mdls_value "kMDItemLastUsedDate" "$app")
  installed_raw=$(get_mdls_value "kMDItemFSCreationDate" "$app")

  last_used=$(format_date "$last_used_raw")
  installed=$(format_date "$installed_raw")

  printf '%s,%s,%s,%s,%s\n' \
    "$(csv_escape "$name")" \
    "$(csv_escape "$app")" \
    "$size_mb" \
    "$(csv_escape "$last_used")" \
    "$(csv_escape "$installed")" \
    >>"$OUTPUT_FILE"
done

echo "Done. $(wc -l < "$OUTPUT_FILE") rows (including header)."
echo "Tip: open in Numbers/Excel and sort by last used or size."

