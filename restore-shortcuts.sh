#!/usr/bin/env bash
# Restore macOS Shortcuts from a backup produced by backup-shortcuts.sh.
#
# Copies the binary .shortcut/.wflow files back into the iCloud-synced
# Shortcuts Documents folder. iCloud then syncs them, and the Shortcuts
# app picks them up (existing shortcuts with the same UUID are replaced).
#
# Usage:
#   ./restore-shortcuts.sh                       # restore from newest backup in ./backups
#   ./restore-shortcuts.sh <backup-dir>          # restore from a specific backup
#   ./restore-shortcuts.sh <backup-dir> --open   # also open each file in the
#                                                # Shortcuts app (prompts to add)
#
# The backup-dir should either be a folder containing a binary/ subfolder
# (as produced by backup-shortcuts.sh) or a folder containing the .shortcut
# files directly.

set -euo pipefail

DEST="$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script only runs on macOS." >&2
  exit 1
fi

BACKUP_DIR="${1:-}"
OPEN_FLAG="${2:-}"

if [[ -z "$BACKUP_DIR" ]]; then
  BACKUP_DIR="$(ls -1dt ./backups/shortcuts-* 2>/dev/null | head -n1 || true)"
  if [[ -z "$BACKUP_DIR" ]]; then
    echo "No backup directory given and none found under ./backups/." >&2
    echo "Usage: $0 [backup-dir] [--open]" >&2
    exit 1
  fi
  echo "Using most recent backup: $BACKUP_DIR"
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "Not a directory: $BACKUP_DIR" >&2
  exit 1
fi

SRC="$BACKUP_DIR"
if [[ -d "$BACKUP_DIR/binary" ]]; then
  SRC="$BACKUP_DIR/binary"
fi

if [[ ! -d "$DEST" ]]; then
  echo "Shortcuts iCloud folder not found at:" >&2
  echo "  $DEST" >&2
  echo "Open the Shortcuts app once and make sure iCloud Drive is enabled." >&2
  exit 1
fi

shopt -s nullglob
files=("$SRC"/*.shortcut "$SRC"/*.wflow)
if (( ${#files[@]} == 0 )); then
  echo "No .shortcut/.wflow files found in $SRC" >&2
  exit 1
fi

echo "About to restore ${#files[@]} shortcut file(s) into:"
echo "  $DEST"
echo "Existing shortcuts with the same UUID will be overwritten."
read -r -p "Continue? [y/N] " reply
if [[ ! "$reply" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

count=0
for f in "${files[@]}"; do
  name="$(basename "$f")"
  cp "$f" "$DEST/$name"
  if [[ "$OPEN_FLAG" == "--open" ]]; then
    open -a Shortcuts "$DEST/$name"
  fi
  count=$((count + 1))
done

echo "Restored $count shortcut file(s). Give iCloud a moment to sync,"
echo "then open the Shortcuts app to verify."
