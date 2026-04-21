#!/usr/bin/env bash
# Diff the XML-plist contents of two Shortcuts backups.
#
# Usage:
#   ./diff-shortcuts.sh                           # diff two newest ./backups/shortcuts-*
#   ./diff-shortcuts.sh <backup-a> <backup-b>
#   ./diff-shortcuts.sh --live <backup>           # diff a backup against the
#                                                 # current live iCloud state
#   ./diff-shortcuts.sh --one <shortcut-name>     # diff one shortcut across
#                                                 # the two newest backups
#
# Honors the DIFF env var (default: "diff -u"). Try DIFF="git --no-pager diff
# --no-index" for colored side-by-side output.

set -euo pipefail

DIFF_CMD="${DIFF:-diff -u}"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script only runs on macOS (uses the aea CLI)." >&2
  exit 1
fi

# Unwrap/convert one shortcut file to an XML plist at $2. Returns 0 on success.
to_xml() {
  local input="$1" output="$2"
  local magic
  magic="$(head -c 4 "$input" 2>/dev/null || true)"
  if [[ "$magic" == "AEA1" ]]; then
    local tmp
    tmp="$(mktemp)"
    if aea decrypt -i "$input" -o "$tmp" 2>/dev/null \
       && plutil -convert xml1 -o "$output" "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      return 0
    fi
    rm -f "$tmp"
    return 1
  fi
  cp "$input" "$output"
  plutil -convert xml1 "$output" 2>/dev/null
}

newest_backups() {
  ls -1dt ./backups/shortcuts-* 2>/dev/null || true
}

# Resolve a backup dir to the folder that actually contains files to diff.
# Prefers xml/ (already unwrapped), falls back to binary/, then the dir itself.
resolve_source() {
  local dir="$1"
  if [[ -d "$dir/xml" ]] && compgen -G "$dir/xml/*" >/dev/null; then
    echo "$dir/xml"
  elif [[ -d "$dir/binary" ]]; then
    echo "$dir/binary"
  else
    echo "$dir"
  fi
}

# ---- modes ----

mode="${1:-}"

if [[ "$mode" == "--live" ]]; then
  backup="${2:-}"
  if [[ -z "$backup" ]]; then
    backup="$(newest_backups | head -n1)"
  fi
  [[ -d "$backup" ]] || { echo "Backup not found: $backup" >&2; exit 1; }
  LIVE="$HOME/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"
  [[ -d "$LIVE" ]] || { echo "Live Shortcuts folder not found." >&2; exit 1; }
  LEFT_DIR="$backup"
  RIGHT_SRC="$LIVE"
elif [[ "$mode" == "--one" ]]; then
  name="${2:-}"
  [[ -n "$name" ]] || { echo "Usage: $0 --one <shortcut-name>" >&2; exit 1; }
  mapfile -t bs < <(newest_backups)
  (( ${#bs[@]} >= 2 )) || { echo "Need at least two backups." >&2; exit 1; }
  LEFT_DIR="${bs[1]}"
  RIGHT_DIR="${bs[0]}"
  ONE_NAME="$name"
else
  if [[ -n "$mode" ]]; then
    LEFT_DIR="$mode"
    RIGHT_DIR="${2:?Usage: $0 <backup-a> <backup-b>}"
  else
    mapfile -t bs < <(newest_backups)
    (( ${#bs[@]} >= 2 )) || { echo "Need at least two backups in ./backups." >&2; exit 1; }
    LEFT_DIR="${bs[1]}"
    RIGHT_DIR="${bs[0]}"
    echo "Diffing: $LEFT_DIR  →  $RIGHT_DIR"
  fi
fi

# Stage each side as XML in a temp dir, keyed by shortcut name (no extension).
stage_dir() {
  local src_dir="$1" out_dir="$2" only="${3:-}"
  mkdir -p "$out_dir"
  shopt -s nullglob
  local files=("$src_dir"/*.shortcut "$src_dir"/*.wflow "$src_dir"/*.plist)
  local f name base
  for f in "${files[@]}"; do
    name="$(basename "$f")"
    base="${name%.*}"
    if [[ -n "$only" && "$base" != "$only" ]]; then continue; fi
    to_xml "$f" "$out_dir/$base.plist" || true
  done
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ "${mode:-}" == "--live" ]]; then
  stage_dir "$(resolve_source "$LEFT_DIR")" "$TMP/a"
  stage_dir "$RIGHT_SRC" "$TMP/b"
  LEFT_LABEL="$LEFT_DIR"
  RIGHT_LABEL="(live)"
elif [[ "${mode:-}" == "--one" ]]; then
  stage_dir "$(resolve_source "$LEFT_DIR")" "$TMP/a" "$ONE_NAME"
  stage_dir "$(resolve_source "$RIGHT_DIR")" "$TMP/b" "$ONE_NAME"
  LEFT_LABEL="$LEFT_DIR"
  RIGHT_LABEL="$RIGHT_DIR"
else
  stage_dir "$(resolve_source "$LEFT_DIR")" "$TMP/a"
  stage_dir "$(resolve_source "$RIGHT_DIR")" "$TMP/b"
  LEFT_LABEL="$LEFT_DIR"
  RIGHT_LABEL="$RIGHT_DIR"
fi

echo "--- $LEFT_LABEL"
echo "+++ $RIGHT_LABEL"
echo
# shellcheck disable=SC2086
$DIFF_CMD "$TMP/a" "$TMP/b" || true
