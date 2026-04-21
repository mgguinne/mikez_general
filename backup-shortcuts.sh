#!/usr/bin/env bash
# Back up all macOS Shortcuts as plist files.
#
# Copies the raw iCloud-synced Shortcut files (binary plists) into a
# timestamped folder, then writes an XML-plist sibling for each one so the
# contents are human-readable and diffable. The binary files remain
# re-importable by the Shortcuts app.
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
for f in "${files[@]}"; do
  name="$(basename "$f")"
  cp "$f" "$DEST/binary/$name"
  cp "$f" "$DEST/xml/$name"
  plutil -convert xml1 "$DEST/xml/$name" 2>/dev/null || {
    echo "  (could not convert $name to XML; leaving binary copy only)" >&2
    rm -f "$DEST/xml/$name"
  }
  count=$((count + 1))
done

# Record the shortcut names (as shown in the Shortcuts app) alongside the backup.
if command -v shortcuts >/dev/null 2>&1; then
  shortcuts list > "$DEST/shortcut-names.txt" 2>/dev/null || true
fi

echo "Backed up $count shortcut file(s) to:"
echo "  $DEST"
