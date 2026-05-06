#!/usr/bin/env bash
# Reverses install.sh. Leaves the user's sketchybarrc, the artwork
# cache, and the log directory in place — the user should clean
# those up themselves if desired.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins/kaset"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCHAGENT_LABEL="app.kaset.sketchybar-bridge"
LAUNCHAGENT_PLIST="$LAUNCHAGENT_DIR/${LAUNCHAGENT_LABEL}.plist"

echo "🛑 Unloading LaunchAgent…"
launchctl bootout "gui/$(id -u)/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
rm -f "$LAUNCHAGENT_PLIST"

echo "🧹 Removing binary…"
rm -f "$BIN_DIR/kaset-sketchybar-bridge"

echo "🧹 Removing plugin scripts…"
rm -rf "$PLUGIN_DIR"

cat <<'MSG'

✅ Bridge uninstalled.

Note: I did NOT touch your sketchybarrc. To fully remove the widget:
  1. Delete the kaset.* item lines (or the source line that pulls in
     sketchybarrc.example).
  2. Reload SketchyBar: sketchybar --reload

Cache (~/.cache/kaset-sketchybar) and logs (~/.local/share/kaset) were
left in place. Remove them yourself if desired.
MSG
