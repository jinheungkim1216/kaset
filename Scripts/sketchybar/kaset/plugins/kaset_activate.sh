#!/usr/bin/env bash
# Bring the Kaset window to the foreground.
#
# Plain `osascript -e 'tell application "Kaset" to activate'` only flips
# app focus — when the window is on another Space, the user's view stays
# put unless the macOS preference "switch to a Space with open windows
# for the application" is on. To work regardless of that setting we
# defer to `open -a`, which goes through Launch Services and handles
# cross-Space switching consistently. The AppleScript fallback covers
# edge cases where Launch Services hasn't registered the bundle yet
# (e.g. fresh dev builds outside /Applications).
if ! open -a "Kaset" 2>/dev/null; then
    osascript -e 'tell application "Kaset" to activate' 2>/dev/null || true
fi
