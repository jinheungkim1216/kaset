#!/usr/bin/env bash
# Installs the kaset-sketchybar-bridge daemon and SketchyBar plugin
# scripts. Builds the binary in release mode, copies files to standard
# user locations, and registers the LaunchAgent so the bridge starts
# at login.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN_DIR="$HOME/.local/bin"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins/kaset"
LOG_DIR="$HOME/.local/share/kaset"
LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCHAGENT_LABEL="app.kaset.sketchybar-bridge"
LAUNCHAGENT_PLIST="$LAUNCHAGENT_DIR/${LAUNCHAGENT_LABEL}.plist"
LOG_PATH="$LOG_DIR/sketchybar-bridge.log"
BIN_PATH="$BIN_DIR/kaset-sketchybar-bridge"

# ── Dependency check ──────────────────────────────────────────────────
missing=()
for cmd in sketchybar jq curl; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
    echo "ERROR: missing required tools: ${missing[*]}"
    echo "Install with:"
    for cmd in "${missing[@]}"; do
        case "$cmd" in
            sketchybar) echo "  brew tap FelixKratz/formulae && brew install sketchybar" ;;
            jq)         echo "  brew install jq" ;;
            curl)       echo "  curl is normally included with macOS — check your PATH." ;;
        esac
    done
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────
echo "🔨 Building kaset-sketchybar-bridge (release)…"
cd "$ROOT"
swift build -c release --product kaset-sketchybar-bridge

# ── Install binary ────────────────────────────────────────────────────
echo "📦 Installing binary → $BIN_PATH"
mkdir -p "$BIN_DIR"
cp ".build/release/kaset-sketchybar-bridge" "$BIN_PATH"
chmod +x "$BIN_PATH"

# ── Install plugin scripts ────────────────────────────────────────────
echo "📜 Installing plugins → $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp "$ROOT/Scripts/sketchybar/plugins/"*.sh "$PLUGIN_DIR/"
chmod +x "$PLUGIN_DIR/"*.sh

# ── Log dir ───────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

# ── LaunchAgent ───────────────────────────────────────────────────────
echo "🚀 Installing LaunchAgent…"
mkdir -p "$LAUNCHAGENT_DIR"
sed -e "s|__INSTALL_PATH__|$BIN_PATH|g" \
    -e "s|__LOG_PATH__|$LOG_PATH|g" \
    "$ROOT/Scripts/sketchybar/launchagent/${LAUNCHAGENT_LABEL}.plist" \
    > "$LAUNCHAGENT_PLIST"

# Reload if already loaded (idempotent install).
launchctl bootout "gui/$(id -u)/${LAUNCHAGENT_LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCHAGENT_PLIST"

cat <<MSG

✅ Bridge installed.

Next steps:
  1. Add the kaset widget items to your sketchybarrc. Either:
       source $ROOT/Scripts/sketchybar/sketchybarrc.example
     or copy the contents into your sketchybarrc directly.
  2. Reload SketchyBar: sketchybar --reload

Logs:           tail -f $LOG_PATH
Bridge status:  launchctl print gui/\$(id -u)/${LAUNCHAGENT_LABEL}
MSG
