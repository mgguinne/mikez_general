#!/usr/bin/env bash
# Back up all macOS Shortcuts.
#
# Copies the raw iCloud-synced Shortcut files into a timestamped folder.
# Signed files (AEA1 magic) are stored as-is in binary/ for re-import, and
# the inner Shortcut.wflow is extracted and converted to XML plist in xml/
# for diffing. Unsigned plists go straight to xml/.
#
# Usage: ./backup-shortcuts.sh [destination-dir]
#   Default destination: ./backups/shortcuts-YYYYmmdd-HHMMSS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNWRAP="$SCRIPT_DIR/unwrap-shortcut.sh"

SRC="$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"
DEST_ROOT="${1:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$DEST_ROOT/shortcuts-$STAMP"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script only runs on macOS." >&2
  exit 1
fi

if [[ ! -x "$UNWRAP" ]]; then
  echo "Missing or non-executable helper: $UNWRAP" >&2
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
unwrap_failed=0
for f in "${files[@]}"; do
  name="$(basename "$f")"
  base="${name%.*}"
  cp "$f" "$DEST/binary/$name"

  magic="$(head -c 4 "$f" 2>/dev/null || true)"
  [[ "$magic" == "AEA1" ]] && signed=$((signed + 1))

  if "$UNWRAP" "$f" "$DEST/xml/$base.plist" 2>/dev/null; then
    xml_written=$((xml_written + 1))
  else
    rm -f "$DEST/xml/$base.plist"
    [[ "$magic" == "AEA1" ]] && unwrap_failed=$((unwrap_failed + 1))
  fi
  count=$((count + 1))
done

rmdir "$DEST/xml" 2>/dev/null || true

if command -v shortcuts >/dev/null 2>&1; then
  shortcuts list > "$DEST/shortcut-names.txt" 2>/dev/null || true
fi

echo "Backed up $count shortcut file(s) to:"
echo "  $DEST"
if (( signed > 0 )); then
  echo "  $signed signed (AEA) stored in binary/ for re-import."
fi
if (( xml_written > 0 )); then
  echo "  $xml_written XML plist(s) written to xml/ for diffing."
fi
if (( unwrap_failed > 0 )); then
  echo "  $unwrap_failed signed file(s) could not be unwrapped — binary backup only." >&2
fi
