# Appearance & Theme Settings — Design

**Date:** 2026-04-30
**Status:** Draft for review
**Scope:** New "Appearance" tab in Settings with two controls — Accent Color and Liquid Glass Style.

## Goal

Let users personalize Kaset's look through two coordinated controls, persisted across launches and applied live across every window:

1. **Accent color** — chosen from a curated palette, with a "System" option that follows macOS's system accent.
2. **Liquid Glass Style** — `Regular` (current default), `Clear` (thinner), or `Solid` (no glass).

## Non-goals

The following are explicitly out of scope for this spec. The architecture leaves room to add them later without rework.

- Custom free-form color picker.
- Per-surface glass overrides (sidebar vs. command bar vs. mini player).
- Color scheme override (Light / Dark independent of macOS).
- Album-artwork-derived tinting on the Now Playing screen.
- Bundled theme presets (e.g. Vibrant / Minimal).

## User-facing summary

A new **Appearance** tab is added to the Settings window between General and Intelligence (icon: `paintbrush`). It contains:

```
┌─ Appearance ──────────────────────────────────────────┐
│ Accent Color                                          │
│   ○ System  ● Blue  ○ Pink  ○ Purple                  │
│   ○ Orange  ○ Green ○ Red   ○ Yellow ○ Graphite       │
│   (row of circular swatches; selected one shows a     │
│    ring + checkmark; "System" swatch shows a          │
│    multi-color gradient signaling it follows macOS)   │
│                                                       │
│ Liquid Glass Style                                    │
│   ┌─────────┬─────────┬─────────┐                     │
│   │ Regular │  Clear  │  Solid  │  (segmented Picker) │
│   └─────────┴─────────┴─────────┘                     │
│   Caption: "Solid removes translucency for higher     │
│    contrast."                                         │
└───────────────────────────────────────────────────────┘
```

Both controls update the UI live across all windows.

## Architecture

### Data model — `SettingsManager` additions

Two new properties on the existing `@MainActor @Observable` `SettingsManager`, both persisted via the same `didSet` → `UserDefaults` pattern the file already uses.

```swift
enum AccentColorOption: String, CaseIterable, Identifiable {
    case system
    case blue, pink, purple, orange, green, red, yellow, graphite

    var id: String { rawValue }
    var displayName: String { /* localized */ }

    /// Returns nil for `.system` so `.tint(nil)` lets the macOS accent flow through.
    var color: Color? {
        switch self {
        case .system:   nil
        case .blue:     .blue
        case .pink:     .pink
        case .purple:   .purple
        case .orange:   .orange
        case .green:    .green
        case .red:      .red
        case .yellow:   .yellow
        case .graphite: Color(nsColor: .systemGray)
        }
    }
}

enum GlassStyle: String, CaseIterable, Identifiable {
    case regular, clear, solid
    var id: String { rawValue }
    var displayName: String { /* localized */ }
}

// New stored properties on SettingsManager (default values shown):
var accentColorOption: AccentColorOption = .system
var glassStyle: GlassStyle = .regular
```

UserDefaults keys: `settings.accentColorOption`, `settings.glassStyle`. Absence of either key → fall through to defaults; no migration needed.

### Accent color application

Apply at every window root via `.tint(...)`:

```swift
// in KasetApp.swift WindowGroup body
ContentView(...)
    .tint(settings.accentColorOption.color)  // nil for .system → no override
```

Repeat at the `Settings { ... }` root, the `VideoWindowController` window, and the mini-player window so the choice is consistent across every window in the app.

**Hard-coded `Color.accentColor` reads.** A grep of the current codebase shows ~5 call sites in `PodcastsView`, `SearchView`, and `WhatsNewView` reading `Color.accentColor` directly in fills/foregrounds. `Color.accentColor` reads from the `AccentColor` asset catalog, **not** from `.tint`, so they will not respect the user's choice unless we touch them. Approach:

- **Default:** migrate to `.foregroundStyle(.tint)` / `.tint(...)` where the surrounding code is idiomatic for that.
- **Fallback:** for cases where an explicit `Color` is needed (e.g. `Color.accentColor.opacity(0.15)` as a `background` fill), introduce a small helper:
  ```swift
  extension Color {
      /// Returns the user-selected accent (or system accent for `.system`).
      static var appAccent: Color {
          SettingsManager.shared.accentColorOption.color ?? Color.accentColor
      }
  }
  ```
  and replace `Color.accentColor` → `Color.appAccent` at those sites.

The implementation plan will enumerate every site and pick (a) or (b) per case.

### Glass style application — environment value + wrapper modifier

Three pieces:

```swift
// 1. Environment value
private struct AppGlassStyleKey: EnvironmentKey {
    static let defaultValue: GlassStyle = .regular
}

extension EnvironmentValues {
    var appGlassStyle: GlassStyle {
        get { self[AppGlassStyleKey.self] }
        set { self[AppGlassStyleKey.self] = newValue }
    }
}

// 2. Inject at every window root
ContentView(...)
    .environment(\.appGlassStyle, settings.glassStyle)

// 3. Wrapper modifier replacing every .glassEffect call site
extension View {
    func appGlassEffect<S: Shape>(
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        modifier(AppGlassEffectModifier(shape: shape, interactive: interactive))
    }
}

private struct AppGlassEffectModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    @Environment(\.appGlassStyle) private var style
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let effective: GlassStyle = reduceTransparency ? .solid : style
        switch effective {
        case .regular:
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        case .clear:
            content.glassEffect(interactive ? .clear.interactive() : .clear, in: shape)
        case .solid:
            content.background(.regularMaterial, in: shape)
        }
    }
}
```

**Call sites to migrate** (current grep — implementation plan will re-verify):

- `Sources/Kaset/Views/CommandBarView.swift:116` — `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))`
- `Sources/Kaset/Views/SearchView.swift:149` — `.glassEffect(.regular, in: .capsule)`
- `Sources/Kaset/Views/SearchView.swift:162` — `.glassEffect(.regular, in: .rect(cornerRadius: 8))`
- `Sources/Kaset/Views/WhatsNewView.swift:60` — `.glassEffect(.regular, in: .capsule)`
- (any additional sites the plan turns up)

Each becomes `.appGlassEffect(in: <same shape>, interactive: <bool>)`. Adjacent calls like `.glassEffectID(...)` and `.glassEffectTransition(...)` are kept; the implementation plan must verify they degrade gracefully when the underlying view is `.solid` (i.e., a `.background` instead of a glass effect).

### UI — `AppearanceSettingsView`

New file: `Sources/Kaset/Views/AppearanceSettingsView.swift`. Pattern matches `GeneralSettingsView` (`Form` + `.formStyle(.grouped)`, `@State private var settings = SettingsManager.shared`).

Layout:

- **Section: Accent Color** — a horizontal row of 9 circular swatches in an `HStack`. Each swatch is a `Button` that sets `settings.accentColorOption`. Selected swatch shows a `Circle().stroke()` ring and an `Image(systemName: "checkmark")` glyph. The `.system` swatch is rendered as an `AngularGradient` over the standard system hues so it visually reads as "follow system".
- **Section: Liquid Glass Style** — a segmented `Picker("Liquid Glass Style", selection: $settings.glassStyle)` with cases `Regular` / `Clear` / `Solid`. A small caption text below explains Solid.

Wired into `SettingsView` in `KasetApp.swift` (~line 412) as a new `TabView` entry between General and Intelligence:

```swift
AppearanceSettingsView()
    .tabItem { Label("Appearance", systemImage: "paintbrush") }
```

## Edge cases & accessibility

- **`.system` accent reacts to macOS accent changes live.** `.tint(nil)` lets `Color.accentColor` flow through, and SwiftUI re-evaluates when the user changes their macOS accent — no manual observation needed.
- **Reduce Transparency.** When `@Environment(\.accessibilityReduceTransparency)` is `true`, `AppGlassEffectModifier` forces `.solid` regardless of the user's choice. The setting itself is left as-is so it takes effect again if the user disables Reduce Transparency. Same biasing applies for Increase Contrast (also map to `.solid`).
- **Live updates.** Both new settings are observable via `@Observable` + `didSet` and are read at the window root. Changing a setting immediately re-renders across every window, including the Settings window itself (which doubles as the live preview for Liquid Glass).
- **First-run defaults.** Absent UserDefaults keys → `.system` accent + `.regular` glass. Behavior identical to today's app.

## Testing

- **Unit tests (Swift Testing).**
  - `SettingsManager` round-trip: setting `accentColorOption` and `glassStyle` persists to and reloads from UserDefaults, including invalid raw-value handling.
  - `AccentColorOption.color` mapping (especially `.system → nil`).
  - `GlassStyle.allCases` covers the picker correctly.
- **SwiftUI Preview.** Three side-by-side previews of `AppearanceSettingsView` and a representative glass surface (e.g. `CommandBarView`) under `.regular`, `.clear`, `.solid` for visual review.
- **Manual QA checklist** (in plan): toggle each accent swatch and verify CommandBar, sidebar selection, search filters, mini player, and Settings respond; cycle the glass picker and verify CommandBar / Search / WhatsNew surfaces switch material; toggle macOS Reduce Transparency and confirm `.solid` wins; change macOS system accent and confirm `.system` follows.
- **No UI tests** (per repo rules — UI tests require explicit human authorization and these settings do not warrant the disruption).

## Build & quality gates

`swift build`, `swift test --skip KasetUITests`, and `swiftlint --strict && swiftformat .` must all be green before completion.

## Files touched (summary)

- **New:** `Sources/Kaset/Views/AppearanceSettingsView.swift`
- **New:** `Sources/Kaset/Utilities/AppearanceTheme.swift` — `appGlassStyle` environment key, `AppGlassEffectModifier`, `View.appGlassEffect(in:interactive:)` modifier, and `Color.appAccent` helper.
- **Modified:** `Sources/Kaset/Services/SettingsManager.swift` — add `AccentColorOption`, `GlassStyle`, two new properties + persistence.
- **Modified:** `Sources/Kaset/KasetApp.swift` — add Appearance tab to `SettingsView`; apply `.tint(...)` and `.environment(\.appGlassStyle, ...)` at every window root.
- **Modified:** call sites currently using `.glassEffect(...)` (CommandBarView, SearchView, WhatsNewView) → `.appGlassEffect(...)`.
- **Modified:** call sites using hard-coded `Color.accentColor` (PodcastsView, SearchView, WhatsNewView) → `.tint` / `.foregroundStyle(.tint)` / `Color.appAccent` per case.
- **Modified:** `Tests/KasetTests/SettingsManagerTests.swift` — extend with cases for `accentColorOption` and `glassStyle` (defaults, persistence round-trip, invalid raw-value handling).
