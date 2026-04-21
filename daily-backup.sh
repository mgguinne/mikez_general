#!/usr/bin/env bash
# Take a Shortcuts snapshot, diff it against the previous one, and print a
# briefing-friendly summary of what changed. Designed to be invoked by a
# Claude Code skill and have its output quoted into a morning briefing.
#
# Exit codes:
#   0 = ran successfully (whether or not anything changed)
#   non-zero = backup or diff pipeline failed
#
# Usage: ./daily-backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "===== Shortcuts backup: $(date '+%Y-%m-%d %H:%M:%S') ====="
./backup-shortcuts.sh

new="$(ls -1dt ./backups/shortcuts-* 2>/dev/null | sed -n '1p')"
prev="$(ls -1dt ./backups/shortcuts-* 2>/dev/null | sed -n '2p')"

if [[ -z "$prev" ]]; then
  echo ""
  echo "First backup — no previous snapshot to diff against."
  exit 0
fi

diff_file="$new/changes-since-previous.diff"
./diff-shortcuts.sh "$prev" "$new" > "$diff_file" 2>&1 || true

if ! grep -q '^@@' "$diff_file"; then
  echo ""
  echo "No changes since previous backup ($(basename "$prev"))."
  rm -f "$diff_file"
  exit 0
fi

# Summarize per-file churn for the briefing.
echo ""
echo "Changes since previous backup ($(basename "$prev")):"
awk '
  /^diff / || /^--- / { next }
  /^\+\+\+ / {
    # The "b/<path>" (or just <path>) names the new file.
    path = $2
    sub(/^b\//, "", path)
    sub(/\.plist$/, "", path)
    split(path, parts, "/")
    name = parts[length(parts)]
    if (name in seen) next
    seen[name] = 1
    current = name
    adds[current] = 0
    dels[current] = 0
    order[++n] = current
    next
  }
  /^\+/ && !/^\+\+\+/ { adds[current]++ }
  /^-/ && !/^---/     { dels[current]++ }
  END {
    for (i = 1; i <= n; i++) {
      printf "  %-40s  +%-4d  -%-4d\n", order[i], adds[order[i]], dels[order[i]]
    }
  }
' "$diff_file"

echo ""
echo "Full diff: $diff_file"
