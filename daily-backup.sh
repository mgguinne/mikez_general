#!/usr/bin/env bash
# Daily Shortcuts backup: take a new snapshot, diff against the previous one,
# and record any changes inside the new backup folder.
#
# Usage:
#   ./daily-backup.sh              run the backup + diff now
#   ./daily-backup.sh --install    schedule via launchd to run at 08:00 daily
#   ./daily-backup.sh --uninstall  remove the launchd schedule

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.mgguinne.shortcuts-backup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

install_launchd() {
  mkdir -p "$HOME/Library/LaunchAgents" "$SCRIPT_DIR/backups"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/daily-backup.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>8</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/backups/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/backups/launchd.log</string>
</dict>
</plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "Installed launchd job: $LABEL"
  echo "  plist : $PLIST"
  echo "  runs  : daily at 08:00"
  echo "  logs  : $SCRIPT_DIR/backups/launchd.log"
}

uninstall_launchd() {
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Uninstalled: $PLIST"
}

case "${1:-}" in
  --install)   install_launchd; exit 0 ;;
  --uninstall) uninstall_launchd; exit 0 ;;
esac

cd "$SCRIPT_DIR"

echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
./backup-shortcuts.sh

new="$(ls -1dt ./backups/shortcuts-* 2>/dev/null | sed -n '1p')"
prev="$(ls -1dt ./backups/shortcuts-* 2>/dev/null | sed -n '2p')"

if [[ -z "$prev" ]]; then
  echo "First backup — nothing to diff against."
  exit 0
fi

diff_file="$new/changes-since-previous.diff"
./diff-shortcuts.sh "$prev" "$new" > "$diff_file" 2>&1 || true

if grep -q '^@@' "$diff_file"; then
  echo ""
  echo "Changes since previous backup recorded in:"
  echo "  $diff_file"
else
  echo "No changes since previous backup."
  rm -f "$diff_file"
fi
