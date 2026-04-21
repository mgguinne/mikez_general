#!/usr/bin/env bash
# Back up all macOS Shortcuts.
#
# Copies the raw iCloud-synced Shortcut files into a timestamped folder.
# Modern Shortcuts are signed Apple Encrypted Archives (magic "AEA1") —
# those get stored as-is in binary/ and are still re-importable. Any
# unsigned plist files also get an XML sidecar in xml/ for diffing.
#
# Usage: ./backup-shortcuts.sh [destination-dir]
#   Default destination: ./backups/shortcuts-YYYYmmdd-HHMMSS

set -euo pipefail

SRC="$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"
DEST_ROOT="${1:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$DEST_ROOT/shortcuts-$STAMP"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script only runs on macOS." >&2
  exit 1
fi

if [[ ! -d "$SRC" ]]; then
  echo "Shortcuts iCloud folder not found at:" >&2
  echo "  $SRC" >&2
  echo "Open the Shortcuts app once to trigger sync, or make sure iCloud Drive is enabled." >&2
  exit 1
fi

mkdir -p "$DEST/binary" "$DEST/xml"

shopt -s nullglob
files=("$SRC"/*.shortcut "$SRC"/*.wflow)
if (( ${#files[@]} == 0 )); then
  echo "No .shortcut/.wflow files found in $SRC" >&2
  exit 1
fi

count=0
signed=0
xml_written=0
for f in "${files[@]}"; do
  name="$(basename "$f")"
  cp "$f" "$DEST/binary/$name"

  magic="$(head -c 4 "$f" 2>/dev/null || true)"
  if [[ "$magic" == "AEA1" ]]; then
    signed=$((signed + 1))
  elif cp "$f" "$DEST/xml/$name" && plutil -convert xml1 "$DEST/xml/$name" 2>/dev/null; then
    xml_written=$((xml_written + 1))
  else
    rm -f "$DEST/xml/$name"
  fi
  count=$((count + 1))
done

# Remove the xml/ folder if nothing landed in it.
rmdir "$DEST/xml" 2>/dev/null || true

# Record the shortcut names (as shown in the Shortcuts app) alongside the backup.
if command -v shortcuts >/dev/null 2>&1; then
  shortcuts list > "$DEST/shortcut-names.txt" 2>/dev/null || true
fi

echo "Backed up $count shortcut file(s) to:"
echo "  $DEST"
if (( signed > 0 )); then
  echo "  $signed signed (AEA) — stored as-is in binary/; re-importable."
fi
if (( xml_written > 0 )); then
  echo "  $xml_written unsigned — XML copy also written to xml/."
fi
