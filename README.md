# Kaset

A native macOS YouTube Music client built with Swift and SwiftUI.

<img src="docs/screenshot.png" alt="Kaset Screenshot">

## About this fork

This is a personal fork of [sozercan/kaset](https://github.com/sozercan/kaset) that adds tiling-WM-friendly integrations on top of upstream. Differences vs upstream:

- **[SketchyBar widget](docs/sketchybar.md)** — Now Playing widget for the macOS status bar (artwork, controls, click-to-seek progress), powered by a lightweight `sketchybar-bridge` daemon that converts player events into SketchyBar triggers.
- **[Distributed Notifications](docs/distributed-notifications.md)** — push-style `NSDistributedNotificationCenter` events broadcast on player state changes, so external processes can react without polling AppleScript.
- **`seek to N` AppleScript command** — seek to an absolute position in seconds (see [AppleScript docs](docs/applescript.md)).

**Currently based on upstream `v0.9.0`.** Upstream is periodically merged in; everything else mirrors sozercan/kaset.

### Updates

Sparkle auto-update is **disabled** in this fork — pointing it at upstream's appcast would prompt users to "update" to upstream builds (which would erase the fork-specific features above), and maintaining a separately-signed appcast for a personal fork isn't worth the overhead. The "Check for Updates…" menu item still exists but does nothing.

To update, check the [fork's Releases page](https://github.com/jinheungkim1216/kaset/releases) and install the newer DMG manually (replacing the existing `Kaset.app` in `/Applications`).

## Features

- 🎵 **Native macOS Experience** — Apple Music-style UI with Liquid Glass player bar and clean sidebar navigation
- 🎧 **YouTube Music Premium Support** — Full playback of DRM-protected content via your existing subscription
- 🎛️ **System Integration** — Now Playing in Control Center, media key support, Dock menu controls
- 📳 **Haptic Feedback** — Tactile feedback on Force Touch trackpads for player controls and navigation
- 🎶 **Track Notifications** — Get notified when a new track starts playing
- 🔊 **Background Audio** — Music continues playing when the window is closed; stops on quit
- 🎚️ **Equalizer** — System-wide 6-band parametric EQ with Spotify-style presets, applied to YouTube Music output
- ⌨️ **[Keyboard Shortcuts](docs/keyboard-shortcuts.md)** — Full keyboard control for playback, navigation, and more
- 🧭 **Explore** — Discover new releases, charts, and moods & genres
- 🎙️ **Podcasts** — Browse and listen to podcasts with episode progress tracking
- 📚 **Library Access** — Browse playlists, liked songs, and subscribed podcasts; create playlists, add songs to playlists, and delete your own playlists
- 🕓 **History** — Revisit recently played tracks
- 🔍 **Search** — Find songs, albums, artists, playlists, and podcasts
- 🌍 **Localized** — Available in English, French, Korean, Indonesian, Turkish, and Arabic
- ✨ **Apple Intelligence** — On-device AI for natural language commands, lyrics explanations, and playlist refinement
- 📜 **Lyrics** — View plain and synced lyrics with line-by-line highlighting when timing data is available, plus AI-powered explanations and mood analysis
- 📃 **Queue Management** — View, reorder, shuffle, and clear your playback queue
- 📣 **Share** — Share songs, playlists, albums, and artists via the native macOS share sheet
- 🔗 **[URL Scheme](docs/url-scheme.md)** — Open songs directly with `kaset://play?v=VIDEO_ID`
- 🤖 **[AppleScript Support](docs/applescript.md)** — Automate playback with scripts, Raycast, Alfred, and Shortcuts
- 📊 **[SketchyBar widget](docs/sketchybar.md)** — Now Playing widget for the macOS status bar (artwork, controls, click-to-seek progress)
- 🧩 **[Extensions](docs/extensions.md)** — Load WebKit Web Extensions, including [uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home)

## Requirements

- macOS 26.0 or later
- [Google](https://accounts.google.com) account

## Installation

### Download

Download the latest release from the [Releases](https://github.com/sozercan/kaset/releases) page.

### Homebrew

```bash
brew install sozercan/repo/kaset
```

> **Note:** The app is not signed.
> If you downloaded the app manually, you can clear extended attributes (including quarantine) with:
> ```bash
> xattr -cr /Applications/Kaset.app
> ```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, architecture, and coding guidelines.

We welcome AI-assisted contributions! You can submit traditional PRs or **prompt requests** — share the AI prompt that generates your changes, and maintainers can review the intent before running the code. See the [AI-Assisted Contributions](CONTRIBUTING.md#ai-assisted-contributions--prompt-requests) section for details.

## Disclaimer
Kaset is an unofficial application and not affiliated with YouTube or Google Inc. in any way. "YouTube", "YouTube Music" and the "YouTube Logo" are registered trademarks of Google Inc.
