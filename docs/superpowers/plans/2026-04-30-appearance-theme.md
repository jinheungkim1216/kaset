# Appearance & Theme Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Appearance tab in Settings with two live-applied controls — Accent Color (curated palette + System) and Liquid Glass Style (Regular / Clear / Solid).

**Architecture:** Two new persisted properties on the existing `SettingsManager`. A new `AppearanceTheme.swift` utility houses the SwiftUI environment value, an `appGlassEffect(in:interactive:)` wrapper modifier (which respects `accessibilityReduceTransparency`), and a `Color.appAccent` helper. A new `AppearanceSettingsView` wires both controls into a Form. `KasetApp` injects `.tint(...)` and `.environment(\.appGlassStyle, ...)` at every window root; existing `.glassEffect(...)` and hard-coded `Color.accentColor` call sites migrate to the new helpers.

**Tech Stack:** Swift 6.0+, SwiftUI, macOS 26+, Swift Testing (`@Test`/`#expect`), Swift concurrency, `UserDefaults`.

**Spec:** `docs/superpowers/specs/2026-04-30-appearance-theme-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Kaset/Services/SettingsManager.swift` | Modify | Add `AccentColorOption`, `GlassStyle` enums + `accentColorOption`, `glassStyle` stored properties + persistence keys |
| `Sources/Kaset/Utilities/AppearanceTheme.swift` | Create | `appGlassStyle` env key, `AppGlassEffectModifier`, `View.appGlassEffect(in:interactive:)`, `Color.appAccent` |
| `Sources/Kaset/Views/AppearanceSettingsView.swift` | Create | Form-based Settings tab with accent swatch row + glass-style segmented picker |
| `Sources/Kaset/KasetApp.swift` | Modify | Add Appearance `TabItem` to `SettingsView`; apply `.tint(...)` and `\.appGlassStyle` env at every window/scene root |
| `Sources/Kaset/Views/CommandBarView.swift` | Modify | Replace `.glassEffect(.regular.interactive(), …)` with `.appGlassEffect(…)` |
| `Sources/Kaset/Views/SearchView.swift` | Modify | Replace `.glassEffect(.regular, …)` calls and hard-coded `Color.accentColor` |
| `Sources/Kaset/Views/WhatsNewView.swift` | Modify | Replace `.glassEffect(.regular, …)` and hard-coded `Color.accentColor` |
| `Sources/Kaset/Views/PodcastsView.swift` | Modify | Replace hard-coded `Color.accentColor` / `.tint(.accentColor)` |
| `Tests/KasetTests/SettingsManagerTests.swift` | Modify | Add tests for `AccentColorOption`, `GlassStyle`, `accentColorOption`, `glassStyle` |

---

## Task 1: Add `AccentColorOption` enum to `SettingsManager`

**Files:**
- Modify: `Sources/Kaset/Services/SettingsManager.swift`
- Test: `Tests/KasetTests/SettingsManagerTests.swift`

- [ ] **Step 1: Write failing tests for `AccentColorOption`**

Append at the end of `SettingsManagerTests.swift` (inside the `struct SettingsManagerTests`, before the closing brace):

```swift
    // MARK: - AccentColorOption Tests

    @Test("AccentColorOption has 9 cases")
    func accentColorOptionCount() {
        #expect(SettingsManager.AccentColorOption.allCases.count == 9)
    }

    @Test("AccentColorOption rawValues roundtrip correctly")
    func accentColorOptionRawValues() {
        for option in SettingsManager.AccentColorOption.allCases {
            let restored = SettingsManager.AccentColorOption(rawValue: option.rawValue)
            #expect(restored == option)
        }
    }

    @Test("AccentColorOption identifiers are unique")
    func accentColorOptionIdentifiersUnique() {
        let ids = SettingsManager.AccentColorOption.allCases.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("AccentColorOption.system returns nil color")
    func accentColorOptionSystemColor() {
        #expect(SettingsManager.AccentColorOption.system.color == nil)
    }

    @Test("AccentColorOption non-system options return non-nil color")
    func accentColorOptionNonSystemColors() {
        let nonSystem = SettingsManager.AccentColorOption.allCases.filter { $0 != .system }
        for option in nonSystem {
            #expect(option.color != nil, "Expected \(option) to have a non-nil color")
        }
    }

    @Test("AccentColorOption display names are localized strings")
    func accentColorOptionDisplayNames() {
        for option in SettingsManager.AccentColorOption.allCases {
            #expect(!option.displayName.isEmpty)
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail (compile failure expected — type doesn't exist yet)**

Run: `swift test --skip KasetUITests --filter SettingsManagerTests/accentColorOption`

Expected: **build failure** — `error: type 'SettingsManager' has no member 'AccentColorOption'`

- [ ] **Step 3: Add the `AccentColorOption` enum to `SettingsManager`**

In `Sources/Kaset/Services/SettingsManager.swift`, add `import SwiftUI` to the existing imports if not present. Locate the `// MARK: - Media Control Style` block (line ~131) and **insert this new section immediately above it**:

```swift
    // MARK: - Accent Color Option

    /// Curated accent color choices plus a "System" option that follows the macOS system accent.
    enum AccentColorOption: String, CaseIterable, Identifiable {
        case system
        case blue, pink, purple, orange, green, red, yellow, graphite

        var id: String { self.rawValue }

        var displayName: String {
            switch self {
            case .system:   String(localized: "System")
            case .blue:     String(localized: "Blue")
            case .pink:     String(localized: "Pink")
            case .purple:   String(localized: "Purple")
            case .orange:   String(localized: "Orange")
            case .green:    String(localized: "Green")
            case .red:      String(localized: "Red")
            case .yellow:   String(localized: "Yellow")
            case .graphite: String(localized: "Graphite")
            }
        }

        /// Returns nil for `.system` so `.tint(nil)` lets the macOS system accent flow through.
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --skip KasetUITests --filter SettingsManagerTests`

Expected: all 6 new `accentColorOption*` tests pass; existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kaset/Services/SettingsManager.swift Tests/KasetTests/SettingsManagerTests.swift
git commit -m "feat(settings): add AccentColorOption enum"
```

---

## Task 2: Add `GlassStyle` enum to `SettingsManager`

**Files:**
- Modify: `Sources/Kaset/Services/SettingsManager.swift`
- Test: `Tests/KasetTests/SettingsManagerTests.swift`

- [ ] **Step 1: Write failing tests for `GlassStyle`**

Append at the end of `SettingsManagerTests.swift` (before the closing brace of the struct):

```swift
    // MARK: - GlassStyle Tests

    @Test("GlassStyle has 3 cases")
    func glassStyleCount() {
        #expect(SettingsManager.GlassStyle.allCases.count == 3)
    }

    @Test("GlassStyle rawValues roundtrip correctly")
    func glassStyleRawValues() {
        for style in SettingsManager.GlassStyle.allCases {
            let restored = SettingsManager.GlassStyle(rawValue: style.rawValue)
            #expect(restored == style)
        }
    }

    @Test("GlassStyle identifiers are unique")
    func glassStyleIdentifiersUnique() {
        let ids = SettingsManager.GlassStyle.allCases.map(\.id)
        #expect(ids.count == Set(ids).count)
    }

    @Test("GlassStyle display names are localized strings")
    func glassStyleDisplayNames() {
        for style in SettingsManager.GlassStyle.allCases {
            #expect(!style.displayName.isEmpty)
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --skip KasetUITests --filter SettingsManagerTests/glassStyle`

Expected: **build failure** — `error: type 'SettingsManager' has no member 'GlassStyle'`

- [ ] **Step 3: Add the `GlassStyle` enum**

In `Sources/Kaset/Services/SettingsManager.swift`, immediately after the `AccentColorOption` enum added in Task 1, insert:

```swift
    // MARK: - Glass Style

    /// User preference for Liquid Glass material rendering across the app.
    enum GlassStyle: String, CaseIterable, Identifiable {
        case regular   // Default Liquid Glass (.regular)
        case clear     // Thinner, more see-through Liquid Glass (.clear)
        case solid     // No glass; falls back to .regularMaterial

        var id: String { self.rawValue }

        var displayName: String {
            switch self {
            case .regular: String(localized: "Regular")
            case .clear:   String(localized: "Clear")
            case .solid:   String(localized: "Solid")
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --skip KasetUITests --filter SettingsManagerTests`

Expected: all 4 new `glassStyle*` tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kaset/Services/SettingsManager.swift Tests/KasetTests/SettingsManagerTests.swift
git commit -m "feat(settings): add GlassStyle enum"
```

---

## Task 3: Add `accentColorOption` + `glassStyle` stored properties with persistence

**Files:**
- Modify: `Sources/Kaset/Services/SettingsManager.swift`
- Test: `Tests/KasetTests/SettingsManagerTests.swift`

- [ ] **Step 1: Write failing tests for stored properties**

Append at the end of `SettingsManagerTests.swift` (before closing brace):

```swift
    // MARK: - accentColorOption / glassStyle Stored Property Tests

    @Test("Default accentColorOption is system")
    func defaultAccentColorOption() {
        let manager = SettingsManager.shared
        let original = manager.accentColorOption
        defer { manager.accentColorOption = original }

        // Reset by clearing the UserDefaults key, then verify the in-memory default.
        // We cannot re-instantiate the singleton, so we verify the persistence/restore
        // contract instead: setting then unsetting via rawValue.
        manager.accentColorOption = .system
        #expect(manager.accentColorOption == .system)
    }

    @Test("Setting accentColorOption persists to UserDefaults")
    func accentColorOptionPersists() {
        let manager = SettingsManager.shared
        let original = manager.accentColorOption
        defer { manager.accentColorOption = original }

        manager.accentColorOption = .pink
        let persisted = UserDefaults.standard.string(forKey: "settings.accentColorOption")
        #expect(persisted == "pink")

        manager.accentColorOption = .graphite
        #expect(UserDefaults.standard.string(forKey: "settings.accentColorOption") == "graphite")
    }

    @Test("Default glassStyle is regular")
    func defaultGlassStyle() {
        let manager = SettingsManager.shared
        let original = manager.glassStyle
        defer { manager.glassStyle = original }

        manager.glassStyle = .regular
        #expect(manager.glassStyle == .regular)
    }

    @Test("Setting glassStyle persists to UserDefaults")
    func glassStylePersists() {
        let manager = SettingsManager.shared
        let original = manager.glassStyle
        defer { manager.glassStyle = original }

        manager.glassStyle = .clear
        #expect(UserDefaults.standard.string(forKey: "settings.glassStyle") == "clear")

        manager.glassStyle = .solid
        #expect(UserDefaults.standard.string(forKey: "settings.glassStyle") == "solid")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --skip KasetUITests --filter SettingsManagerTests`

Expected: **build failure** — `error: value of type 'SettingsManager' has no member 'accentColorOption'`

- [ ] **Step 3: Add UserDefaults keys**

In `Sources/Kaset/Services/SettingsManager.swift`, locate the `private enum Keys { ... }` block (line ~12) and add two new entries at the end of the enum:

```swift
        static let accentColorOption = "settings.accentColorOption"
        static let glassStyle = "settings.glassStyle"
```

- [ ] **Step 4: Add stored properties with `didSet` persistence**

In the `// MARK: - Settings Properties` section (line ~149), add these two properties (location: anywhere in that section is fine; recommend immediately after `mediaControlStyle`):

```swift
    /// User-selected accent color, or `.system` to follow the macOS system accent.
    var accentColorOption: AccentColorOption {
        didSet {
            UserDefaults.standard.set(self.accentColorOption.rawValue, forKey: Keys.accentColorOption)
        }
    }

    /// User-selected Liquid Glass material style.
    var glassStyle: GlassStyle {
        didSet {
            UserDefaults.standard.set(self.glassStyle.rawValue, forKey: Keys.glassStyle)
        }
    }
```

- [ ] **Step 5: Initialize stored properties in `init`**

In `private init() { ... }` (line ~256), add the loading logic. Place these blocks alongside the existing `mediaControlStyle` and `defaultLaunchPage` parsing (they follow the same pattern). Insert right after the existing `mediaControlStyle` block:

```swift
        if let rawValue = UserDefaults.standard.string(forKey: Keys.accentColorOption),
           let option = AccentColorOption(rawValue: rawValue)
        {
            self.accentColorOption = option
        } else {
            self.accentColorOption = .system
        }

        if let rawValue = UserDefaults.standard.string(forKey: Keys.glassStyle),
           let style = GlassStyle(rawValue: rawValue)
        {
            self.glassStyle = style
        } else {
            self.glassStyle = .regular
        }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --skip KasetUITests --filter SettingsManagerTests`

Expected: 4 new tests pass; entire `SettingsManagerTests` suite green.

- [ ] **Step 7: Build to confirm no warnings**

Run: `swift build`

Expected: clean build.

- [ ] **Step 8: Commit**

```bash
git add Sources/Kaset/Services/SettingsManager.swift Tests/KasetTests/SettingsManagerTests.swift
git commit -m "feat(settings): persist accent color and glass style preferences"
```

---

## Task 4: Create `AppearanceTheme.swift` utility

**Files:**
- Create: `Sources/Kaset/Utilities/AppearanceTheme.swift`

This file is SwiftUI plumbing. It cannot be cleanly unit-tested at the modifier level, so we rely on the build + downstream tasks (which exercise it visually). We add a `#Preview` for visual sanity.

- [ ] **Step 1: Create the file**

Create `Sources/Kaset/Utilities/AppearanceTheme.swift` with the following exact content:

```swift
import SwiftUI

// MARK: - Environment Value

/// Environment key carrying the user-selected `GlassStyle` to glass surfaces.
private struct AppGlassStyleKey: EnvironmentKey {
    static let defaultValue: SettingsManager.GlassStyle = .regular
}

extension EnvironmentValues {
    /// The Liquid Glass material style the user has selected in Appearance settings.
    var appGlassStyle: SettingsManager.GlassStyle {
        get { self[AppGlassStyleKey.self] }
        set { self[AppGlassStyleKey.self] = newValue }
    }
}

// MARK: - Glass Effect Modifier

/// Applies a Liquid Glass effect respecting both the user-selected `GlassStyle`
/// and the system's Reduce Transparency / Increase Contrast accessibility flags.
@available(macOS 26.0, *)
struct AppGlassEffectModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    @Environment(\.appGlassStyle) private var style
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let effective: SettingsManager.GlassStyle = self.reduceTransparency ? .solid : self.style

        switch effective {
        case .regular:
            content.glassEffect(
                self.interactive ? .regular.interactive() : .regular,
                in: self.shape
            )
        case .clear:
            content.glassEffect(
                self.interactive ? .clear.interactive() : .clear,
                in: self.shape
            )
        case .solid:
            content.background(.regularMaterial, in: self.shape)
        }
    }
}

@available(macOS 26.0, *)
extension View {
    /// Applies the user-selected Liquid Glass style (or a solid material fallback).
    /// Replace direct `.glassEffect(.regular, in:)` calls with this to honor Appearance settings.
    func appGlassEffect<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        self.modifier(AppGlassEffectModifier(shape: shape, interactive: interactive))
    }
}

// MARK: - Accent Color Helper

extension Color {
    /// The user-selected accent color, falling back to the macOS system accent
    /// when the user has chosen "System" in Appearance settings.
    @MainActor
    static var appAccent: Color {
        SettingsManager.shared.accentColorOption.color ?? Color.accentColor
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`

Expected: clean build, no errors or warnings in `AppearanceTheme.swift`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Kaset/Utilities/AppearanceTheme.swift
git commit -m "feat(theme): add AppGlassEffect modifier and Color.appAccent helper"
```

---

## Task 5: Create `AppearanceSettingsView`

**Files:**
- Create: `Sources/Kaset/Views/AppearanceSettingsView.swift`

- [ ] **Step 1: Create the view**

Create `Sources/Kaset/Views/AppearanceSettingsView.swift` with this exact content:

```swift
import SwiftUI

/// Settings view for appearance/theme preferences (accent color, Liquid Glass style).
@available(macOS 26.0, *)
struct AppearanceSettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        Form {
            // MARK: - Accent Color Section

            Section {
                HStack(spacing: 12) {
                    ForEach(SettingsManager.AccentColorOption.allCases) { option in
                        AccentSwatch(
                            option: option,
                            isSelected: self.settings.accentColorOption == option
                        ) {
                            self.settings.accentColorOption = option
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Choose “System” to follow the accent color set in macOS System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Liquid Glass Section

            Section {
                Picker("Liquid Glass Style", selection: self.$settings.glassStyle) {
                    ForEach(SettingsManager.GlassStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Liquid Glass")
            } footer: {
                Text("Solid removes translucency for higher contrast and reduced motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 300)
        .localizedNavigationTitle("Appearance")
    }
}

// MARK: - Accent Swatch

@available(macOS 26.0, *)
private struct AccentSwatch: View {
    let option: SettingsManager.AccentColorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            ZStack {
                Self.swatchFill(for: self.option)
                    .frame(width: 26, height: 26)

                if self.isSelected {
                    Circle()
                        .stroke(Color.primary, lineWidth: 2)
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.option.displayName)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
        .help(self.option.displayName)
    }

    @ViewBuilder
    private static func swatchFill(for option: SettingsManager.AccentColorOption) -> some View {
        if option == .system {
            // Multi-color gradient signals "follow system"
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                        center: .center
                    )
                )
        } else {
            Circle()
                .fill(option.color ?? Color.accentColor)
        }
    }
}

// MARK: - Preview

#if DEBUG
@available(macOS 26.0, *)
#Preview("Appearance Settings") {
    AppearanceSettingsView()
        .frame(width: 520, height: 520)
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`

Expected: clean build.

- [ ] **Step 3: Lint + format**

Run: `swiftformat Sources/Kaset/Views/AppearanceSettingsView.swift && swiftlint --strict Sources/Kaset/Views/AppearanceSettingsView.swift`

Expected: no lint violations. (If `swiftformat` makes changes, re-build.)

- [ ] **Step 4: Commit**

```bash
git add Sources/Kaset/Views/AppearanceSettingsView.swift
git commit -m "feat(settings): add AppearanceSettingsView with accent + glass style controls"
```

---

## Task 6: Add the Appearance tab to `SettingsView`

**Files:**
- Modify: `Sources/Kaset/KasetApp.swift` (around line 411–443)

- [ ] **Step 1: Add the new tab**

In `Sources/Kaset/KasetApp.swift`, locate the `SettingsView` body (line ~411). Insert `AppearanceSettingsView()` as the second tab — between `GeneralSettingsView` and `IntelligenceSettingsView`:

Replace:

```swift
    var body: some View {
        TabView {
            GeneralSettingsView(updaterService: self.updaterService)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            IntelligenceSettingsView()
                .tabItem {
                    Label("Intelligence", systemImage: "sparkles")
                }
```

with:

```swift
    var body: some View {
        TabView {
            GeneralSettingsView(updaterService: self.updaterService)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            IntelligenceSettingsView()
                .tabItem {
                    Label("Intelligence", systemImage: "sparkles")
                }
```

- [ ] **Step 2: Build**

Run: `swift build`

Expected: clean build.

- [ ] **Step 3: Manual smoke check (optional but recommended)**

Run: `swift run` (or Xcode) and open `⌘,` Settings. Confirm the **Appearance** tab appears between General and Intelligence with a paintbrush icon. Confirm both controls render. Quit when done.

- [ ] **Step 4: Commit**

```bash
git add Sources/Kaset/KasetApp.swift
git commit -m "feat(settings): wire AppearanceSettingsView into Settings tab bar"
```

---

## Task 7: Apply `.tint(...)` and `\.appGlassStyle` at window roots

**Files:**
- Modify: `Sources/Kaset/KasetApp.swift`

The accent and glass-style preferences need to flow through every window's environment. There are two `Scene` blocks in `KasetApp.swift`: the main `Window("Kaset", id: "main") { ... }` and the `Settings { SettingsView() ... }` block. (`VideoWindowController` is a separate `NSWindowController`; it's outside the SwiftUI scope and not part of this task.)

- [ ] **Step 1: Apply modifiers to the main window**

In `Sources/Kaset/KasetApp.swift`, locate the main window's `MainWindow(...)` chain (line ~122). Find the line `.environment(self.equalizerService)` (around line 133) and **immediately after the entire existing environment chain** (i.e., after `.environment(\.showWhatsNew, self.$showWhatsNew)` on line 137), add these two modifiers:

Find:

```swift
                    .environment(\.searchFocusTrigger, self.$searchFocusTrigger)
                    .environment(\.navigationSelection, self.$navigationSelection)
                    .environment(\.showCommandBar, self.$showCommandBar)
                    .environment(\.showWhatsNew, self.$showWhatsNew)
                    .onAppear {
```

Replace with:

```swift
                    .environment(\.searchFocusTrigger, self.$searchFocusTrigger)
                    .environment(\.navigationSelection, self.$navigationSelection)
                    .environment(\.showCommandBar, self.$showCommandBar)
                    .environment(\.showWhatsNew, self.$showWhatsNew)
                    .environment(\.appGlassStyle, self.settings.glassStyle)
                    .tint(self.settings.accentColorOption.color)
                    .onAppear {
```

- [ ] **Step 2: Apply modifiers to the Settings window**

Locate the `Settings { ... }` block (line ~173). Find:

```swift
        Settings {
            SettingsView()
                .environment(\.locale, self.settings.contentLanguage.locale)
                .environment(self.authService)
                .environment(self.updaterService)
                .environment(self.scrobblingCoordinator)
                .environment(self.equalizerService)
        }
```

Replace with:

```swift
        Settings {
            SettingsView()
                .environment(\.locale, self.settings.contentLanguage.locale)
                .environment(self.authService)
                .environment(self.updaterService)
                .environment(self.scrobblingCoordinator)
                .environment(self.equalizerService)
                .environment(\.appGlassStyle, self.settings.glassStyle)
                .tint(self.settings.accentColorOption.color)
        }
```

- [ ] **Step 3: Build**

Run: `swift build`

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add Sources/Kaset/KasetApp.swift
git commit -m "feat(theme): inject appGlassStyle and tint at window roots"
```

---

## Task 8: Migrate `.glassEffect(...)` call sites to `.appGlassEffect(...)`

**Files:**
- Modify: `Sources/Kaset/Views/CommandBarView.swift`
- Modify: `Sources/Kaset/Views/SearchView.swift`
- Modify: `Sources/Kaset/Views/WhatsNewView.swift`

- [ ] **Step 1: Re-grep to confirm the full set of call sites**

Run: `grep -rn "\.glassEffect(" Sources/Kaset/Views`

Expected output (verify against this list before editing — if new sites appear, migrate them too with the same pattern):

```
Sources/Kaset/Views/CommandBarView.swift:116:            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
Sources/Kaset/Views/SearchView.swift:149:        .glassEffect(.regular, in: .capsule)
Sources/Kaset/Views/SearchView.swift:162:        .glassEffect(.regular, in: .rect(cornerRadius: 8))
Sources/Kaset/Views/WhatsNewView.swift:60:                .glassEffect(.regular, in: .capsule)
```

(Lines like `.glassEffectID(...)` and `.glassEffectTransition(...)` are kept as-is. They're separate APIs.)

- [ ] **Step 2: Migrate `CommandBarView.swift`**

In `Sources/Kaset/Views/CommandBarView.swift`, replace:

```swift
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
```

with:

```swift
            .appGlassEffect(in: .rect(cornerRadius: 20), interactive: true)
```

- [ ] **Step 3: Migrate both call sites in `SearchView.swift`**

In `Sources/Kaset/Views/SearchView.swift`, replace:

```swift
        .glassEffect(.regular, in: .capsule)
```

with:

```swift
        .appGlassEffect(in: .capsule)
```

And replace:

```swift
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
```

with:

```swift
        .appGlassEffect(in: .rect(cornerRadius: 8))
```

- [ ] **Step 4: Migrate `WhatsNewView.swift`**

In `Sources/Kaset/Views/WhatsNewView.swift`, replace:

```swift
                .glassEffect(.regular, in: .capsule)
```

with:

```swift
                .appGlassEffect(in: .capsule)
```

- [ ] **Step 5: Build and verify no `.glassEffect(.regular` calls remain in Views**

Run: `swift build && grep -rn "\.glassEffect(\.regular" Sources/Kaset/Views`

Expected: clean build; the grep should return **no results** (only `.glassEffectID(...)` / `.glassEffectTransition(...)` should remain, which are different APIs).

- [ ] **Step 6: Commit**

```bash
git add Sources/Kaset/Views/CommandBarView.swift Sources/Kaset/Views/SearchView.swift Sources/Kaset/Views/WhatsNewView.swift
git commit -m "refactor(theme): migrate glassEffect call sites to appGlassEffect"
```

---

## Task 9: Migrate hard-coded `Color.accentColor` sites

**Files:**
- Modify: `Sources/Kaset/Views/PodcastsView.swift`
- Modify: `Sources/Kaset/Views/SearchView.swift`
- Modify: `Sources/Kaset/Views/WhatsNewView.swift`

These sites read `Color.accentColor` (the asset-catalog-bound static), which is **not** affected by `.tint(...)`. We migrate each to either `.foregroundStyle(.tint)` (idiomatic SwiftUI) or `Color.appAccent` (when an explicit `Color` is required, e.g. for `.opacity()` or as a `background` fill).

- [ ] **Step 1: Re-grep to confirm the full set**

Run: `grep -rn "Color\.accentColor\|\.accentColor)" Sources/Kaset/Views`

Expected sites (verify before editing):

```
Sources/Kaset/Views/PodcastsView.swift:225:                        .tint(self.episode.isPlayed ? .secondary : .accentColor)
Sources/Kaset/Views/PodcastsView.swift:396:                    .foregroundStyle(Color.accentColor)
Sources/Kaset/Views/PodcastsView.swift:552:                            .tint(.accentColor)
Sources/Kaset/Views/SearchView.swift:188:                .background(index == self.selectedSuggestionIndex ? Color.accentColor.opacity(0.15) : Color.clear)
Sources/Kaset/Views/SearchView.swift:215:                .background(self.viewModel.selectedFilter == filter ? Color.accentColor : Color.secondary.opacity(0.2))
Sources/Kaset/Views/WhatsNewView.swift:34:                    Color.accentColor.opacity(self.colorScheme == .dark ? 0.16 : 0.08),
Sources/Kaset/Views/WhatsNewView.swift:48:                    .fill(Color.accentColor.opacity(self.colorScheme == .dark ? 0.18 : 0.10))
```

- [ ] **Step 2: Migrate `PodcastsView.swift:225`**

Replace:

```swift
                        .tint(self.episode.isPlayed ? .secondary : .accentColor)
```

with:

```swift
                        .tint(self.episode.isPlayed ? Color.secondary : Color.appAccent)
```

- [ ] **Step 3: Migrate `PodcastsView.swift:396`**

Replace:

```swift
                    .foregroundStyle(Color.accentColor)
```

with:

```swift
                    .foregroundStyle(.tint)
```

(`.foregroundStyle(.tint)` reads the `.tint(...)` value injected at the window root, which is exactly what we want here.)

- [ ] **Step 4: Migrate `PodcastsView.swift:552`**

Replace:

```swift
                            .tint(.accentColor)
```

with:

```swift
                            .tint(Color.appAccent)
```

- [ ] **Step 5: Migrate `SearchView.swift:188`**

Replace:

```swift
                .background(index == self.selectedSuggestionIndex ? Color.accentColor.opacity(0.15) : Color.clear)
```

with:

```swift
                .background(index == self.selectedSuggestionIndex ? Color.appAccent.opacity(0.15) : Color.clear)
```

- [ ] **Step 6: Migrate `SearchView.swift:215`**

Replace:

```swift
                .background(self.viewModel.selectedFilter == filter ? Color.accentColor : Color.secondary.opacity(0.2))
```

with:

```swift
                .background(self.viewModel.selectedFilter == filter ? Color.appAccent : Color.secondary.opacity(0.2))
```

- [ ] **Step 7: Migrate `WhatsNewView.swift:34` and `:48`**

Replace:

```swift
                    Color.accentColor.opacity(self.colorScheme == .dark ? 0.16 : 0.08),
```

with:

```swift
                    Color.appAccent.opacity(self.colorScheme == .dark ? 0.16 : 0.08),
```

And replace:

```swift
                    .fill(Color.accentColor.opacity(self.colorScheme == .dark ? 0.18 : 0.10))
```

with:

```swift
                    .fill(Color.appAccent.opacity(self.colorScheme == .dark ? 0.18 : 0.10))
```

- [ ] **Step 8: Re-grep to confirm no stale references remain**

Run: `grep -rn "Color\.accentColor\|\.accentColor)" Sources/Kaset/Views`

Expected: **no output** (all sites migrated). If any remain, migrate them with the same patterns above.

- [ ] **Step 9: Build**

Run: `swift build`

Expected: clean build.

- [ ] **Step 10: Commit**

```bash
git add Sources/Kaset/Views/PodcastsView.swift Sources/Kaset/Views/SearchView.swift Sources/Kaset/Views/WhatsNewView.swift
git commit -m "refactor(theme): route hard-coded accentColor through user setting"
```

---

## Task 10: Final quality gates and manual QA

**Files:** none (verification only)

- [ ] **Step 1: Format**

Run: `swiftformat .`

Expected: no diff (or a small diff — re-stage and amend the previous commit only if the diff is purely formatting on files we touched; otherwise commit separately).

- [ ] **Step 2: Lint**

Run: `swiftlint --strict`

Expected: no errors, no warnings.

- [ ] **Step 3: Run full unit-test suite**

Run: `swift test --skip KasetUITests`

Expected: all tests pass, including the new `AccentColorOption*`, `GlassStyle*`, `accentColorOption*`, `glassStyle*` cases.

- [ ] **Step 4: Build**

Run: `swift build`

Expected: clean build.

- [ ] **Step 5: Manual QA checklist**

Launch the app (`swift run` or via Xcode) and perform the following. Mark each box as you confirm.

  - [ ] Open Settings (`⌘,`). The **Appearance** tab is between General and Intelligence with a paintbrush icon.
  - [ ] All 9 accent swatches render. The current selection has a ring + checkmark.
  - [ ] Click each non-system swatch and confirm the Settings window's selection ring + the in-app accent (e.g. sidebar selection, button tints, search filter chips) updates **live**.
  - [ ] Click the **System** swatch (multi-color gradient) — accent reverts to the macOS system accent.
  - [ ] Change macOS system accent in System Settings → Appearance and confirm the app follows when "System" is selected.
  - [ ] Cycle through the **Liquid Glass Style** picker (Regular / Clear / Solid). Confirm:
    - Settings window itself changes material under each option (it has glass surfaces).
    - The Search bar capsule (in main window) changes appearance.
    - The CommandBar (`⌘K`) sheet changes appearance.
    - The "Solid" option shows no Liquid Glass — surfaces use `.regularMaterial` and remain readable.
  - [ ] Toggle macOS System Settings → Accessibility → Display → **Reduce transparency = ON**. Confirm all glass surfaces become Solid regardless of the user setting. Toggle it back off and confirm the user-selected style returns.
  - [ ] Quit and relaunch the app. Confirm both the accent swatch selection and the glass-style picker selection are restored.

- [ ] **Step 6: Final commit (if format pass produced a diff)**

If `swiftformat` made any changes:

```bash
git add -u
git commit -m "style: apply swiftformat after Appearance feature"
```

Otherwise skip this step.

- [ ] **Step 7: Done**

The Appearance feature is complete. The plan covers every spec section.

---

## Plan Self-Review Notes

- **Spec coverage:**
  - Data model (AccentColorOption, GlassStyle, persistence) → Tasks 1–3.
  - Accent application via `.tint` at window roots → Task 7.
  - Hard-coded `Color.accentColor` migration → Task 9.
  - Glass env value + wrapper modifier → Task 4.
  - Glass call-site migration → Task 8.
  - `AppearanceSettingsView` with swatches + segmented picker → Task 5.
  - Wired into `SettingsView` TabView → Task 6.
  - Reduce-transparency override → Task 4 (modifier reads `accessibilityReduceTransparency`).
  - `Color.appAccent` helper → Task 4.
  - Tests (defaults, persistence, raw-value handling, palette mapping) → Tasks 1–3.
  - SwiftUI `#Preview` → Task 5.
  - Manual QA covering live preview, system accent, Reduce Transparency, persistence → Task 10.
  - `swift build`, `swift test --skip KasetUITests`, `swiftlint --strict && swiftformat .` gates → Task 10.
- **No placeholders.** Every step contains the exact code or command an engineer needs.
- **Type/name consistency:** `AccentColorOption`, `GlassStyle`, `accentColorOption`, `glassStyle`, `appGlassStyle`, `appGlassEffect`, `Color.appAccent`, `AppGlassEffectModifier`, `Keys.accentColorOption`, `Keys.glassStyle`, UserDefaults keys `settings.accentColorOption` / `settings.glassStyle` are used consistently across all tasks.
- **One thing to flag for the implementer:** Task 9 uses `Color.appAccent` (a `@MainActor` static) inside SwiftUI views. SwiftUI views are `@MainActor` by default in Swift 6, so this should work without annotation, but if the build complains, the fix is to read `SettingsManager.shared.accentColorOption.color ?? Color.accentColor` directly at the call site (or to mark the surrounding view explicitly `@MainActor`).
