#!/usr/bin/env bash
# Back up all macOS Shortcuts.
#
# Copies the raw iCloud-synced Shortcut files into a timestamped folder.
# Signed files (AEA1 magic) are stored as-is in binary/ for re-import, and
# the inner binary plist is extracted and converted to XML in xml/ for
# diffing. Unsigned plists go straight to xml/.
#
# The AEA "decryption" here is just a 12-byte-header strip: shortcuts are
# profile 0 (signed, not encrypted), and the auth_data section at offset
# 12 IS the plist. Apple's `aea decrypt` would also want the signing
# public key to verify — we just skip verification and take the payload.
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

# Extract the binary-plist auth_data payload from a signed AEA1 file.
# Writes the raw bplist to $2. Returns non-zero if the magic doesn't match.
unwrap_aea() {
  python3 - "$1" "$2" <<'PY'
import struct, sys
with open(sys.argv[1], "rb") as f:
    data = f.read()
if data[:4] != b"AEA1":
    sys.exit(2)
size = struct.unpack("<I", data[8:12])[0]
with open(sys.argv[2], "wb") as f:
    f.write(data[12:12+size])
PY
}

count=0
signed=0
xml_written=0
unwrap_failed=0
for f in "${files[@]}"; do
  name="$(basename "$f")"
  base="${name%.*}"
  cp "$f" "$DEST/binary/$name"

  magic="$(head -c 4 "$f" 2>/dev/null || true)"
  if [[ "$magic" == "AEA1" ]]; then
    signed=$((signed + 1))
    tmp="$(mktemp)"
    if unwrap_aea "$f" "$tmp" \
       && plutil -convert xml1 -o "$DEST/xml/$base.plist" "$tmp" 2>/dev/null; then
      xml_written=$((xml_written + 1))
    else
      unwrap_failed=$((unwrap_failed + 1))
    fi
    rm -f "$tmp"
  elif cp "$f" "$DEST/xml/$name" && plutil -convert xml1 "$DEST/xml/$name" 2>/dev/null; then
    xml_written=$((xml_written + 1))
  else
    rm -f "$DEST/xml/$name"
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
