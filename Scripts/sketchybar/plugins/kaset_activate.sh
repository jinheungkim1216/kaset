#!/usr/bin/env bash
# Bring the Kaset window to the foreground. Plain `activate` only flips
# app focus — when the window lives on another Space, the user's view
# stays put unless they've enabled "switch to a Space with open windows"
# in System Settings → Desktop & Dock. To work regardless of that
# preference we also raise the first window via the Accessibility API
# (`AXRaise`), which forces macOS to switch Spaces or pull the window
# forward.
osascript <<'OSA' 2>/dev/null || true
tell application "Kaset" to activate
tell application "System Events"
    if exists process "Kaset" then
        tell process "Kaset"
            set frontmost to true
            if (count of windows) > 0 then
                perform action "AXRaise" of window 1
            end if
        end tell
    end if
end tell
OSA
