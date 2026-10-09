# Themes: Custom Themes, `.mctheme` Files and the Theme Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Duplicate, edit, rename and delete custom colour themes (the built-ins Dracula, Alucard and Nord stay
read-only), export and import them as `.mctheme` files, remember the chosen theme between launches, map the theme
onto MetalUI's control tokens, and edit each role's colour in a floating theme editor with MetalUI's `ColorPicker`.

**Architecture:** The theme library is `CreatorStyle`'s existing `@MainActor @Observable ThemeStore`, which gains the
custom themes and every operation on them. Each change is saved to an injected `ThemeFolder` (one
`<id>.mctheme` per theme) before it is shown; the chosen id goes to an injected `ThemePreferences`, the app's backed
by `UserDefaults`. `ThemeRole` names each `ThemeColors` property, so the file format and the editor walk the roles
without listing them again. The editor's behaviour is a `@MainActor @Observable ThemeEditorModel` in `CreatorApp`; its
views are thin `Component`s in a floating glass panel that a new window root, `AppWindowRoot`, draws over `AppRoot`
together with `.theme(current.controlTheme)`, so `AppRoot`, `AppInput` and `AppModel` are untouched.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), SwiftPM, MetalUI (`../MetalUI`, master `67a579e`;
Task 11 needs C10's `ColorPicker`), Foundation (`JSONEncoder`/`JSONDecoder`, `FileManager`, `UserDefaults`), Swift
Testing, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§6.6 and Errata (M6), with all
Errata), and `docs/metalui-gaps.md` gap M6-f. MetalUI's `ColorPicker`: branch `feat/controls-looks`
(`Sources/MetalUI/ColorPicker.swift`, `ColorPickerPanel.swift`, rulings `LK-C`, `LK-D`, `LK-P` in
`docs/superpowers/2026-10-08-controls-looks-decisions.md`).

## Global Constraints

- Platform floor `.macOS(.v26)`; `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: data races are errors.
- Never edit `Package.swift` (this plan adds no target and no dependency) and never its `../MetalUI` path.
- Tests are Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), never XCTest.
- A `swift test` run passes only if its exit code is 0 **and** no output line says "recorded an issue" or "failed
  after".
- `swiftlint lint --strict` reports zero violations after every task; no new `swiftlint:disable`.
- No new compiler warnings (master has one, in `Tests/CreatorViewportTests/ContextMenuTests.swift:96`, untouched).
- `@MainActor @Observable` models hold all behaviour; views are thin MetalUI `Component`s; one type per file.
- No force unwraps or `try!`, no GCD, no legacy `Formatter`s; filtering user text would use `localizedStandardContains`.
- Colour hex values are written only in `CreatorStyle` (spec §6.6: "Colours are defined once, as the roles of the
  built-in themes in `CreatorStyle`"); fonts use MetalUI's semantic text styles, no sizes.
- Dracula is the default theme; Dracula, Alucard and Nord are read-only (spec §6.6, Errata (M6)).
- Themes are app-level and never stored in a `.mcgraph` file (spec §6.6); `GraphFile.currentFormatVersion` stays 4.
- MetalUI gaps are logged in `docs/metalui-gaps.md` and never worked around (spec §9).
- Tests never touch the person's real themes or defaults: a temporary `ThemeFolder`, `InMemoryThemePreferences` or a
  `UserDefaults(suiteName:)` suite of the test's own, removed afterwards.
- A refused colour reads exactly "‘selection’ isn’t a colour like #ff79c6." (the role's name, then Dracula's colour
  for that role).
- Run every command from the repository root (`/Users/maxburger/Developer/MetalCreator-themes`).

## Review Focus

The five inputs the spec implies but no task's happy path exercises, most likely first. Each has its test in the
task that owns the code.

1. **A colour drag writes on every move.** `ColorPicker` writes the binding continuously (`LK-D` item 3), so each
   move saves a file. The last colour must be the one kept, and nothing may stall. Test:
   `ThemeLibraryTests.manyQuickEditsKeepTheLastColour` (Task 5).
2. **A name typed, or Delete… pressed, then another theme chosen from View ▸ Theme before Return or Delete.** The
   typed name must land on the theme it was typed for, never on the newly shown one, and the field must show the new
   theme's name; the confirmation must name, and Delete remove, the theme it asked about, never the one shown now
   (View ▸ Theme stays reachable while the drawn dialog is up). Tests:
   `ThemeEditorModelTests.aTypedNameStaysWithItsTheme`, `ThemeEditorModelTests.aDeleteConfirmationStaysWithItsTheme`
   (Task 8).
3. **A damaged file, a bad colour, a file naming only some roles, or a file named like a built-in in the themes
   folder.** The app must still start (in the remembered theme or Dracula) and the editor must say which file was
   skipped and why; a partial file's missing roles are Dracula's quantized, so it reads back equal. Tests:
   `ThemeImportExportTests.aPartialFileImportsAsTheThemeTheFolderReadsBack` (Task 5),
   `ThemeFolderTests.unreadableFilesAreSkippedWithAReason` (Task 4), `ThemeLibraryTests.filesThatCantBeReadAreReported`
   (Task 5), `ThemeEditorModelTests.openingShowsTheFoldersProblemsAndDoneCloses` (Task 8).
4. **The remembered theme is gone** (deleted in Finder, or its file damaged). Start in Dracula, not a crash or a blank
   window. Test: `ThemeLibraryTests.theRememberedCustomThemeIsShownAtLaunchAndAGoneOneFallsBackToDracula` (Task 5).
5. **A save that fails** (a full disk, a locked folder) **or an import whose name is taken.** A failed save changes
   nothing and says why; an import never replaces a theme ("Dracula 2"). Tests:
   `ThemeLibraryTests.aFailedSaveChangesNothing` (Task 5),
   `ThemeImportExportTests.anExportedThemeImportsAsANewThemeWithAFreeName` (Task 5).

## Key Decisions

1. **The editor is a floating glass panel in the main window**, at the top right below the top bar, over the
   inspector, down to the window's bottom margin, or to a margin above the graph panel's resize handle when the graph
   is docked at the bottom (`ThemeEditorLayout.bottom(dock:panelHeight:)`), so it never covers the graph panel
   (`ThemeEditorDock`, opened by View ▸ Theme ▸ Edit Themes…, closed by Done or Escape). It is 360 pt wide with its
   glass, 60 pt wider than the inspector, so it covers that strip of the viewport's model area: intended, because the
   model area isn't narrowed while it is open (the part would reframe each time it opens), and the roles' rows need
   the width. Escape is both its Done and, during a pick, `PickBanner`'s Cancel; MetalUI runs the first shortcut in
   tree order and `AppRoot` comes before the dock, so the first Escape cancels the pick and the second closes the
   editor (human check TH-1; MetalUI headless windows take no simulated keys in MetalCreator's tests). Not a second window: on MetalUI master `App.openWindow`'s close callback terminates the app for *any*
   window (C8 lane 2, `feat/app-shell`, changes that, `docs/superpowers/specs/2026-10-08-app-shell-design.md` §8.1
   item 4), and closing a "Themes" window would quit MetalCreator. Not a sheet: MetalUI has none (its alerts and file
   dialogs are its only sheets). Not a popover: it would nest `ColorPicker`'s own popover and is anchored to an edge
   (gap EP-b). A floating panel is the app's own language (§6.1's glass panels float over the viewport), keeps the
   graph panel and most of the viewport visible so every edit is seen live, and is not a stopgap that must be undone.
2. **The library is `ThemeStore`**, the existing single source of truth that every view and the viewport already
   observe. It gains `customs` and duplicate, rename, `setColor`, `setDark`, delete, import and export, split over
   `ThemeStore.swift`, `ThemeStore+Library.swift` and `ThemeStore+Files.swift`. The editor's own state (open, the typed
   name, the confirmation, the last problem) is `ThemeEditorModel` in `CreatorApp`, because Import… and Export… use
   `CreatorApp`'s `FilePicker`. No new target, so `Package.swift` is untouched.
3. **One file per custom theme, named by its id** (`custom-<uuid>.mctheme`), so a rename rewrites one file and never
   moves it. Built-in ids are reserved: a `dracula.mctheme` in the folder is skipped with a reason.
4. **Every change is saved before it is shown.** MetalUI can't intercept quit (gap M6-b), so nothing waits for a
   "Save" or for the editor to close. A save that throws leaves the store as it was.
5. **Custom colours are quantized** to a byte of opacity (`HexColor.quantized`), as a `.mctheme` file holds them, so
   a theme saved and read back equals itself exactly. Built-ins keep their exact opacities (Dracula's glass 0.86);
   duplicating quantizes the copy, and a file's missing roles are Dracula's quantized (`ThemeFile.decode`), so a
   partial import reads back from the folder unchanged.
6. **`.mctheme` format version 1**: `version`, `name`, `dark` and `colors` (role name → `#rrggbb` or `#rrggbbaa`),
   pretty-printed with sorted keys. `version` and `colors` are required (so a `.mcgraph` opened by mistake is
   refused); a missing role is Dracula's (quantized); unknown roles and keys are ignored whatever their values; a missing `dark`
   follows the panel base's lightness; a missing name is the file's name. The id is not in the file.
7. **MetalUI's control tokens** (`ColorTheme.controlTheme`): background ← background bottom, surface ← node body,
   surfaceSecondary ← field, accent ← accent, separator ← comment, textPrimary ← foreground, scrollIndicator ←
   foreground at 35%; scrim and shadow stay MetalUI's for a dark or light theme. In every built-in the well's bezel,
   track, border and canvas tokens differ (`everyBuiltInKeepsItsControlPartsApart`).
8. **`AppWindowRoot`** is the window's new root: `ZStack { AppRoot; ThemeEditorDock }` with the store in the
   environment and `.theme(model.themes.current.controlTheme)`. `AppRoot.swift`, `AppInput.swift` and the `AppModel`
   files (which the graph-input track edits) are not touched. The dock contributes `AppKeyContext.panel` so the
   viewport's F, + and − type into the name field.
9. **Before C10 there is no colour editing in the editor**, only a hex readout and a swatch per role, and colours
   change by import. Gap M6-f's suggested hex-field stopgap is not built, because C10's `ColorPicker` exists and its
   panel already has a hex field (`LK-D` item 6). Task 11 swaps the swatch for the picker.
10. **View ▸ Theme** is `ThemeMenu`: the built-ins, a divider, the custom themes by name and a divider when there are
    any, then Edit Themes…. What it lists is `ThemeMenu.sections(_:)`, tested, because MetalUI menu content can't be
    evaluated outside MetalUI (new gap TH-a).
11. **Delete… asks first** (`confirmationDialog`) about the theme shown when it was pressed: `ThemeEditorModel`
    records its id (`pendingDeleteID`), the dialog's title names it (`deleteTitle`) and its Delete removes it, even if
    another theme was chosen from View ▸ Theme meanwhile. A deleted current theme falls back to Dracula, remembered.
12. **Dark controls is editable** on a custom theme (`setDark`), because a recoloured light copy of Dracula must be
    able to ask for light controls and a light window.
13. **"Needs MetalUI C10 merged" means merged into MetalUI master.** `feat/controls-looks` branches from `cd84b0c`,
    before C7 (`c62d6ba`), and MetalCreator master needs C7, so the branch alone doesn't build MetalCreator. Task 11
    was verified on a scratch merge of master `67a579e` and `feat/controls-looks` (`e931b7f`). The merge has textual
    conflicts in MetalUI's `docs/divergences.md`, `docs/probes/closeout-public-api.tsv` and
    `Sources/MetalUIDemoContent/LooksDemo.swift` (the MetalUI session's to resolve; none touches MetalCreator).

## Files Shared With Other Tracks

- `Sources/CreatorApp/AppCommands.swift`: View ▸ Theme becomes `ThemeMenu.items(themeEditor)`, and
  `install(on:model:)` gains `themeEditor:` (Task 10). Shared with graph-input if it adds commands.
- `Sources/MetalCreatorApp/main.swift`: the store, the editor model and `AppWindowRoot` (Task 10). Shared with
  graph-input if it changes how input is installed.
- `CLAUDE.md` and its mirror `AGENTS.md` (the same paragraph edits; `AGENTS.md` lags `CLAUDE.md`, so its old text is
  quoted separately), `docs/superpowers/roadmap.md` (the "Themes" row only),
  `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (a new "Errata (Themes)" section at the
  end), `docs/metalui-gaps.md` (M6-f, and a new section at the end) and `docs/verification/human-checks.md` (a new
  group TH at the end): every track edits or appends to these (Tasks 10, 11).
- `Sources/CreatorStyle/ThemeStore.swift` and the new `CreatorStyle` files: sketcher-s5 reads the sketch roles; this
  plan changes no existing role or `ThemeColors` property.
- **Not touched:** `Package.swift`, `Sources/CreatorApp/AppRoot.swift`, `Sources/CreatorApp/AppInput.swift`,
  `Sources/CreatorApp/AppModel*.swift`, `CreatorEditor`, `CreatorViewport`.

## File Structure

`Sources/CreatorStyle/` (the model, UI-free apart from MetalUI's colour types):

| File | Responsibility | Task |
|---|---|---|
| `HexColor+Text.swift` | `#rrggbb`/`#rrggbbaa` reading and writing, `quantized`, `HexColor(Color)` | 1 |
| `ThemeRoleGroup.swift` | the editor's role headings | 2 |
| `ThemeRole.swift` | a role: name (`.mctheme` key), title, group, opacity, key path | 2 |
| `ThemeRole+All.swift` | the 38 roles in `ThemeColors`' order | 2 |
| `ThemeColors+Roles.swift` | `ThemeColors[role]`, `ThemeColors.quantized` | 2 |
| `ThemeFileError.swift` | why a file can't be read, as a sentence | 3 |
| `ThemeFile.swift` | the `.mctheme` format: encode, decode | 3 |
| `ThemeFileBody.swift`, `ThemeFileColor.swift` | the file's JSON object and a `colors` value | 3 |
| `ThemeProblem.swift` | a refused action's sentence | 4 |
| `ThemeFolder.swift` | the folder of `<id>.mctheme` files: load, save, remove | 4 |
| `ThemeStore.swift` (modify) | built-ins, `customs`, `current`, `select`, `loadProblems`, the injected folder | 5 |
| `ThemeStore+Library.swift` | duplicate, rename, `setColor`, `setDark`, delete | 5 |
| `ThemeStore+Files.swift` | import and export | 5 |
| `UserDefaultsThemePreferences.swift` | the chosen id in the person's defaults | 6 |
| `ThemePreferences.swift`, `InMemoryThemePreferences.swift` (modify) | doc comments only | 6 |
| `ColorTheme+Controls.swift` | `controlTheme` (MetalUI tokens), `HexColor.hsla` | 7 |

`Sources/CreatorApp/` (the editor and its wiring):

| File | Responsibility | Task |
|---|---|---|
| `ContentType+Theme.swift` | `ContentType.mctheme` | 8 |
| `ThemeEditorModel.swift` | the editor's state and behaviour | 8 |
| `ThemeEditorLayout.swift` | the editor's layout numbers; its bottom inset over a bottom-docked graph | 9 (11) |
| `ThemeEditorDock.swift` | places the panel (top, right, `bottom`), key context | 9 |
| `ThemeEditorPanel.swift` | the glass panel, input catcher, delete confirmation (`deleteTitle`) | 9 |
| `ThemeEditorHeader.swift` | "Themes" and Done | 9 |
| `ThemeEditorControls.swift` | theme menu, buttons, name, Dark controls | 9 |
| `ThemeRoleList.swift`, `ThemeRoleSection.swift`, `ThemeRoleRow.swift` | the roles by group | 9 (11) |
| `ThemeSwatch.swift` | a role's swatch (removed in Task 11) | 9 |
| `AppWindowRoot.swift` | the window's root: `AppRoot`, the editor, the control tokens | 9 |
| `ThemeMenu.swift` | View ▸ Theme | 10 |
| `AppThemes.swift` | the app's store (defaults, Application Support) | 10 |
| `AppCommands.swift`, `../MetalCreatorApp/main.swift` (modify) | wiring | 10 |

Docs (Tasks 10, 11): `CLAUDE.md`, `AGENTS.md`, `docs/superpowers/roadmap.md`, the spec's Errata (Themes),
`docs/metalui-gaps.md`, `docs/verification/human-checks.md`.

Tests: `Tests/CreatorStyleTests/` gains `HexColorTextTests`, `ThemeRoleTests`, `ThemeFileTests`, `ThemeFolderTests`,
`ThemeLibraryTests`, `ThemeImportExportTests`, `UserDefaultsThemePreferencesTests`, `ControlThemeTests`;
`Tests/CreatorAppTests/` gains `ThemeEditorModelTests`, `ThemeEditorRenderTests`, `ThemeMenuTests`. The existing
`ThemeStoreTests`, `ThemeTests`, `PaletteTests`, `ThemeRenderTests` and `AppRootRenderTests` pass unchanged.

---

### Task 1: Colours as `.mctheme` text

**Files:**
- Create: `Sources/CreatorStyle/HexColor+Text.swift`
- Test: `Tests/CreatorStyleTests/HexColorTextTests.swift`

**Interfaces:**
- Consumes: `HexColor(_ rgb: UInt32, opacity: Double = 1)`, `HexColor.rgb`, `.opacity`, `.color` (existing);
  MetalUI `Color`, `Color.Resolved`, `EnvironmentValues()`.
- Produces: `HexColor.init?(hex: String)`; `HexColor.hex: String`; `HexColor.quantized: HexColor`;
  `HexColor.init(_ resolved: Color.Resolved)`; `HexColor.init(_ color: Color)`; internal `HexColor.opacityByte: UInt8`.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorStyle
import MetalUI
import Testing

/// A colour as `.mctheme` text: `#rrggbb`, or `#rrggbbaa` when it is translucent, and back.
struct HexColorTextTests {
    @Test func itReadsSixAndEightDigitHex() {
        #expect(HexColor(hex: "#ff79c6") == HexColor(0xff79c6))
        #expect(HexColor(hex: "FF79C6") == HexColor(0xff79c6), "the # is optional and either case is read")
        #expect(HexColor(hex: " #50fa7b\n") == HexColor(0x50fa7b), "surrounding spaces are ignored")
        #expect(HexColor(hex: "#21222cdb") == HexColor(0x21222c, opacity: 219.0 / 255))
        #expect(HexColor(hex: "#00000000") == HexColor(0x000000, opacity: 0))
    }

    static let notColours = [
        "", "#", "pink", "ff79c", "#ff79c6f", "#ff79c6ff00", "#gg79c6", "+f79c6", "-f79c6", "#ff 79c6", "##ff79c6",
        "0xff79c6", "#ｆｆ79c6",
    ]

    @Test(arguments: notColours)
    func anythingElseIsNotAColour(_ text: String) {
        #expect(HexColor(hex: text) == nil)
    }

    @Test func itWritesLowercaseWithAlphaOnlyWhenTranslucent() {
        #expect(HexColor(0xff79c6).hex == "#ff79c6")
        #expect(HexColor(0x00000a).hex == "#00000a", "zero-padded")
        #expect(HexColor(0xffffff, opacity: 31.0 / 255).hex == "#ffffff1f")
        #expect(ColorTheme.dracula.colors.glassFill.hex == "#21222cdb", "86% is the nearest byte, 219")
        #expect(HexColor(0x123456, opacity: 0.999).hex == "#123456", "rounds to opaque")
    }

    static let samples = [
        HexColor(0xff79c6), HexColor(0x000000, opacity: 0), HexColor(0x21222c, opacity: 0.86),
        HexColor(0xf8f8f2, opacity: 0.9), HexColor(0xffffff, opacity: 31.0 / 255),
    ]

    @Test(arguments: samples)
    func textRoundTripsTheQuantizedColour(_ colour: HexColor) {
        #expect(HexColor(hex: colour.hex) == colour.quantized)
        #expect(colour.quantized.quantized == colour.quantized)
    }

    @Test func quantizingRoundsOnlyTheOpacity() {
        #expect(HexColor(0x21222c, opacity: 0.86).quantized == HexColor(0x21222c, opacity: 219.0 / 255))
        #expect(HexColor(0xff79c6).quantized == HexColor(0xff79c6))
    }

    /// `ColorPicker` writes gamma-sRGB literals; each channel comes back as its nearest byte.
    @Test func aMetalUIColourBecomesItsNearestBytes() {
        #expect(HexColor(Color(.sRGB, red: 1, green: 128.0 / 255, blue: 0, opacity: 0.5)) == HexColor(0xff8000, opacity: 128.0 / 255))
        #expect(HexColor(HexColor(0xbd93f9).color) == HexColor(0xbd93f9))
        #expect(HexColor(Color(.sRGB, red: 1.4, green: -0.2, blue: 0.5)) == HexColor(0xff0080), "clamped, then rounded")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorStyleTests.HexColorTextTests`
Expected: the build fails: `HexColor` has no `init(hex:)`, no member `hex` and no `quantized`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import MetalUI

extension HexColor {
    /// Reads `#rrggbb`, or `#rrggbbaa` with an opacity byte: the form a `.mctheme` file writes. The `#` is optional,
    /// either case is read and surrounding spaces are ignored. Anything else is `nil`, never a guess.
    public init?(hex text: String) {
        var digits = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if digits.first == "#" { digits = digits.dropFirst() }
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(value)
        } else {
            self.init(value >> 8, opacity: Double(value & 0xff) / 255)
        }
    }

    /// `#rrggbb`, or `#rrggbbaa` when the colour isn't opaque: lowercase, as the spec's table writes colours.
    public var hex: String {
        let alpha = opacityByte
        if alpha == 255 { return "#" + Self.digits(rgb & 0xffffff, count: 6) }
        return "#" + Self.digits((rgb & 0xffffff) << 8 | UInt32(alpha), count: 8)
    }

    /// This colour with its opacity rounded to one of the 256 steps a `.mctheme` file holds, so a custom theme that
    /// is saved and read back equals itself.
    public var quantized: HexColor { HexColor(rgb & 0xffffff, opacity: Double(opacityByte) / 255) }

    /// The colour MetalUI resolved, each channel and the opacity rounded to its nearest byte.
    public init(_ resolved: Color.Resolved) {
        func byte(_ value: Float) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        self.init(byte(resolved.red) << 16 | byte(resolved.green) << 8 | byte(resolved.blue),
                  opacity: Double(byte(resolved.opacity)) / 255)
    }

    /// A MetalUI colour literal, such as `ColorPicker` writes (`Color(.sRGB, red:green:blue:opacity:)`), as a
    /// `HexColor`. A literal resolves the same in any environment, so it is resolved in the default one.
    public init(_ color: Color) {
        self.init(color.resolve(in: EnvironmentValues()))
    }

    /// The opacity as a byte, 0…255.
    var opacityByte: UInt8 { UInt8((min(max(opacity, 0), 1) * 255).rounded()) }

    /// `value` in lowercase hexadecimal, zero-padded to `count` digits.
    private static func digits(_ value: UInt32, count: Int) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, count - digits.count)) + digits
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorStyleTests`
Expected: `Test run with 17 tests in 3 suites passed` (11 before, 6 new), no "recorded an issue".

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict` (no violations), then `swift test` (exit 0, no "recorded an issue" or "failed after").
Expected total: master + 6 = 1091 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle/HexColor+Text.swift Tests/CreatorStyleTests/HexColorTextTests.swift
git commit -m "feat(style): colours as .mctheme text — #rrggbb/#rrggbbaa, quantized, from MetalUI colours"
```

---

### Task 2: The roles by name

**Files:**
- Create: `Sources/CreatorStyle/ThemeRoleGroup.swift`, `Sources/CreatorStyle/ThemeRole.swift`,
  `Sources/CreatorStyle/ThemeRole+All.swift`, `Sources/CreatorStyle/ThemeColors+Roles.swift`
- Test: `Tests/CreatorStyleTests/ThemeRoleTests.swift`

**Interfaces:**
- Consumes: `ThemeColors` (its 38 stored `HexColor` properties), `HexColor.quantized` (Task 1).
- Produces: `struct ThemeRole: Identifiable, Hashable, Sendable` with `name`, `title`, `group: ThemeRoleGroup`,
  `allowsOpacity`, `id` (= `name`); `ThemeRole.all: [ThemeRole]`; `ThemeRole.named(_ name: String) -> ThemeRole?`;
  `enum ThemeRoleGroup: String, CaseIterable, Identifiable` (`.surfaces`, `.text`, `.interaction`, `.nodes`,
  `.status`, `.model`, `.widgets`, `.sketcher`) with `title` and `roles`; `ThemeColors[role] -> HexColor { get set }`;
  `ThemeColors.quantized`.

The key path is typed `WritableKeyPath<ThemeColors, HexColor> & Sendable` so the static role list is `Sendable` (Swift
6 infers key-path literals `Sendable`). The list is data, not a 38-case `switch`, which would break SwiftLint's
cyclomatic complexity limit.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorStyle
import Testing

/// The roles by name: the `.mctheme` keys and the theme editor's rows. They must be exactly `ThemeColors`' stored
/// properties, in order, each reading and writing its own colour.
struct ThemeRoleTests {
    /// `ThemeColors`' stored properties by label, in declaration order.
    static func properties(_ colors: ThemeColors) -> [(label: String, colour: HexColor)] {
        Mirror(reflecting: colors).children.compactMap { child in
            guard let label = child.label, let colour = child.value as? HexColor else { return nil }
            return (label, colour)
        }
    }

    @Test func theRolesAreThePropertiesOfThemeColorsInOrder() {
        #expect(Self.properties(ColorTheme.dracula.colors).map(\.label) == ThemeRole.all.map(\.name))
        #expect(ThemeRole.all.count == 38)
    }

    @Test(arguments: ThemeRole.all)
    func eachRoleReadsAndWritesItsOwnColour(_ role: ThemeRole) {
        var colors = ColorTheme.dracula.colors
        #expect(colors[role] == Self.properties(colors).first { $0.label == role.name }?.colour)
        colors[role] = HexColor(0x123456)
        for (label, colour) in Self.properties(colors) {
            let original = Self.properties(ColorTheme.dracula.colors).first { $0.label == label }?.colour
            #expect(colour == (label == role.name ? HexColor(0x123456) : original), "\(role.name) wrote \(label)")
        }
    }

    @Test func namesAndTitlesAreUniqueAndNamesFindTheirRole() {
        #expect(Set(ThemeRole.all.map(\.name)).count == ThemeRole.all.count)
        #expect(Set(ThemeRole.all.map(\.title)).count == ThemeRole.all.count)
        #expect(ThemeRole.named("selection")?.title == "Selection")
        #expect(ThemeRole.named("sparkle") == nil)
    }

    @Test func everyGroupHasRolesAndTheGroupsListEveryRoleInOrder() {
        #expect(ThemeRoleGroup.allCases.allSatisfy { !$0.roles.isEmpty })
        #expect(ThemeRoleGroup.allCases.flatMap(\.roles) == ThemeRole.all)
    }

    @Test func onlyTheGlassAndTheEdgesOfferOpacity() {
        #expect(ThemeRole.all.filter(\.allowsOpacity).map(\.name) == ["glassFill", "glassStroke", "edge"])
    }

    @Test func quantizingAThemeRoundsOnlyItsTranslucentRoles() {
        let quantized = ColorTheme.dracula.colors.quantized
        #expect(quantized.glassFill == HexColor(0x21222c, opacity: 219.0 / 255))
        #expect(quantized.edge == HexColor(0xf8f8f2, opacity: 230.0 / 255))
        #expect(quantized.selection == ColorTheme.dracula.colors.selection)
        #expect(quantized.quantized == quantized)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorStyleTests.ThemeRoleTests`
Expected: the build fails: cannot find `ThemeRole` and `ThemeRoleGroup` in scope.

- [ ] **Step 3: Implement**

`Sources/CreatorStyle/ThemeRoleGroup.swift`:

```swift
/// The headings the theme editor lists roles under, in `ThemeColors`' order.
public enum ThemeRoleGroup: String, CaseIterable, Identifiable, Sendable {
    case surfaces, text, interaction, nodes, status, model, widgets, sketcher

    public var id: String { rawValue }

    /// The heading shown in the theme editor.
    public var title: String {
        switch self {
        case .surfaces: "Surfaces"
        case .text: "Text"
        case .interaction: "Interaction"
        case .nodes: "Node categories"
        case .status: "Status"
        case .model: "The model"
        case .widgets: "Viewport widgets"
        case .sketcher: "Sketcher"
        }
    }

    /// This group's roles, in order.
    public var roles: [ThemeRole] { ThemeRole.all.filter { $0.group == self } }
}
```

`Sources/CreatorStyle/ThemeRole.swift`:

```swift
/// One colour role (spec §6.6): its name, which is `ThemeColors`' property name and the key a `.mctheme` file uses,
/// its title in the theme editor and its group there. `ThemeColors[role]` reads and writes the role's colour, so
/// code that walks every role (the file format, the editor) never lists the properties again.
public struct ThemeRole: Identifiable, Hashable, Sendable {
    /// The `.mctheme` key, `ThemeColors`' property name: "selection".
    public let name: String
    /// The editor's label: "Selection".
    public let title: String
    public let group: ThemeRoleGroup
    /// Whether the editor offers an opacity: the glass and the edges are translucent by design, every other role
    /// is opaque.
    public let allowsOpacity: Bool
    let keyPath: WritableKeyPath<ThemeColors, HexColor> & Sendable

    public var id: String { name }

    init(_ name: String, _ title: String, _ group: ThemeRoleGroup,
         _ keyPath: WritableKeyPath<ThemeColors, HexColor> & Sendable, allowsOpacity: Bool = false) {
        self.name = name
        self.title = title
        self.group = group
        self.keyPath = keyPath
        self.allowsOpacity = allowsOpacity
    }

    /// The role a `.mctheme` file calls `name`, or `nil` for a name this version doesn't know.
    public static func named(_ name: String) -> ThemeRole? { byName[name] }

    private static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    public static func == (lhs: ThemeRole, rhs: ThemeRole) -> Bool { lhs.name == rhs.name }

    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
```

`Sources/CreatorStyle/ThemeRole+All.swift`:

```swift
extension ThemeRole {
    /// Every role, in `ThemeColors`' declaration order (`ThemeRoleTests` checks the two agree).
    public static let all: [ThemeRole] = [
        ThemeRole("backgroundTop", "Background top", .surfaces, \.backgroundTop),
        ThemeRole("backgroundBottom", "Background bottom", .surfaces, \.backgroundBottom),
        ThemeRole("glassFill", "Glass", .surfaces, \.glassFill, allowsOpacity: true),
        ThemeRole("glassStroke", "Glass hairline", .surfaces, \.glassStroke, allowsOpacity: true),
        ThemeRole("panelBase", "Panel base", .surfaces, \.panelBase),
        ThemeRole("nodeBody", "Node body", .surfaces, \.nodeBody),
        ThemeRole("field", "Fields and tracks", .surfaces, \.field),
        ThemeRole("foreground", "Text", .text, \.foreground),
        ThemeRole("comment", "Secondary text", .text, \.comment),
        ThemeRole("textOnAccent", "Text on accents", .text, \.textOnAccent),
        ThemeRole("accent", "Accent", .interaction, \.accent),
        ThemeRole("focus", "Focus and hover", .interaction, \.focus),
        ThemeRole("selection", "Selection", .interaction, \.selection),
        ThemeRole("valueHeader", "Value nodes", .nodes, \.valueHeader),
        ThemeRole("profileHeader", "Profile nodes", .nodes, \.profileHeader),
        ThemeRole("solidHeader", "Solid nodes", .nodes, \.solidHeader),
        ThemeRole("selectionHeader", "Selection rules", .nodes, \.selectionHeader),
        ThemeRole("featureHeader", "Feature nodes", .nodes, \.featureHeader),
        ThemeRole("outputHeader", "Output node", .nodes, \.outputHeader),
        ThemeRole("success", "Success", .status, \.success),
        ThemeRole("warning", "Warning", .status, \.warning),
        ThemeRole("error", "Error", .status, \.error),
        ThemeRole("shadeLight", "Shading, lit", .model, \.shadeLight),
        ThemeRole("shadeDark", "Shading, unlit", .model, \.shadeDark),
        ThemeRole("edge", "Edges", .model, \.edge, allowsOpacity: true),
        ThemeRole("gridMinor", "Grid, minor lines", .model, \.gridMinor),
        ThemeRole("gridMajor", "Grid, major lines", .model, \.gridMajor),
        ThemeRole("cubeFace", "View cube faces", .widgets, \.cubeFace),
        ThemeRole("cubeRim", "View cube rim", .widgets, \.cubeRim),
        ThemeRole("cubeLabel", "View cube labels", .widgets, \.cubeLabel),
        ThemeRole("axisX", "X axis", .widgets, \.axisX),
        ThemeRole("axisY", "Y axis", .widgets, \.axisY),
        ThemeRole("axisZ", "Z axis", .widgets, \.axisZ),
        ThemeRole("sketchUnderConstrained", "Under-constrained", .sketcher, \.sketchUnderConstrained),
        ThemeRole("sketchFullyConstrained", "Fully constrained", .sketcher, \.sketchFullyConstrained),
        ThemeRole("sketchConflicting", "Conflicting", .sketcher, \.sketchConflicting),
        ThemeRole("sketchConstruction", "Construction", .sketcher, \.sketchConstruction),
        ThemeRole("sketchProjected", "Projected", .sketcher, \.sketchProjected),
    ]
}
```

`Sources/CreatorStyle/ThemeColors+Roles.swift`:

```swift
extension ThemeColors {
    /// The colour of `role`.
    public subscript(role: ThemeRole) -> HexColor {
        get { self[keyPath: role.keyPath] }
        set { self[keyPath: role.keyPath] = newValue }
    }

    /// Every role's colour quantized (`HexColor.quantized`), as a `.mctheme` file holds them.
    public var quantized: ThemeColors {
        var colors = self
        for role in ThemeRole.all { colors[role] = colors[role].quantized }
        return colors
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorStyleTests`
Expected: `Test run with 23 tests in 4 suites passed`.

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 12 = 1097.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle/ThemeRoleGroup.swift Sources/CreatorStyle/ThemeRole.swift \
  Sources/CreatorStyle/ThemeRole+All.swift Sources/CreatorStyle/ThemeColors+Roles.swift \
  Tests/CreatorStyleTests/ThemeRoleTests.swift
git commit -m "feat(style): ThemeRole — every role by its .mctheme name, title and group; ThemeColors[role]"
```

---

### Task 3: The `.mctheme` file format

**Files:**
- Create: `Sources/CreatorStyle/ThemeFileError.swift`, `Sources/CreatorStyle/ThemeFile.swift`,
  `Sources/CreatorStyle/ThemeFileBody.swift`, `Sources/CreatorStyle/ThemeFileColor.swift`
- Test: `Tests/CreatorStyleTests/ThemeFileTests.swift`

**Interfaces:**
- Consumes: `ThemeRole.all`, `ThemeRole.named(_:)`, `ThemeColors[role]` (Task 2); `HexColor(hex:)`, `.hex` (Task 1).
- Produces: `enum ThemeFile` with `currentVersion = 1`, `encode(_ theme: ColorTheme) throws -> Data` and
  `decode(_ data: Data, id: ColorTheme.ID, fallbackName: String) throws(ThemeFileError) -> ColorTheme`;
  `enum ThemeFileError: Error, Equatable, Sendable` (`.damaged`, `.newerVersion(Int)`, `.notAColour(role: String)`)
  with `message: String`. A missing role is `ColorTheme.dracula.colors.quantized`'s, so a decoded theme is always
  quantized (Key Decision 5). Internal JSON helpers, used by `ThemeFile` only: `struct ThemeFileBody: Codable` (`version`,
  `name?`, `dark?`, `colors: [String: ThemeFileColor]`) and `enum ThemeFileColor: Codable` (`.text(String)`, `.other`
  for any non-string value, so an unknown role's value never fails the file).

- [ ] **Step 1: Write the failing test**

Note the raw-string delimiters: a JSON string holding `"#…"` needs `##"…"##`, because `"#` ends a `#"…"#` string.

```swift
import CreatorStyle
import Foundation
import Testing

/// `.mctheme` files: small, versioned JSON of hex colours by role. Missing roles are Dracula's, unknown roles are
/// ignored, and anything that isn't a theme is refused with one plain sentence.
struct ThemeFileTests {
    /// A custom theme as the app holds one: quantized colours, a few changed.
    static let midnight: ColorTheme = {
        var colors = ColorTheme.dracula.colors.quantized
        colors.selection = HexColor(0x00ffaa)
        colors.glassFill = HexColor(0x101010, opacity: 128.0 / 255)
        return ColorTheme(id: "custom-1", name: "Midnight", isDark: false, colors: colors)
    }()

    func decode(_ json: String, fallbackName: String = "File") throws(ThemeFileError) -> ColorTheme {
        try ThemeFile.decode(Data(json.utf8), id: "custom-2", fallbackName: fallbackName)
    }

    @Test func aThemeRoundTripsExactly() throws {
        let data = try ThemeFile.encode(Self.midnight)
        #expect(try ThemeFile.decode(data, id: "custom-1", fallbackName: "") == Self.midnight)
        #expect(try ThemeFile.encode(Self.midnight) == data, "the same theme always writes the same bytes")
    }

    @Test func theFileIsVersionedJSONWithEveryRoleAsHex() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: ThemeFile.encode(ColorTheme.dracula)) as? [String: Any])
        #expect(object.keys.sorted() == ["colors", "dark", "name", "version"])
        #expect(object["version"] as? Int == 1)
        #expect(object["name"] as? String == "Dracula")
        #expect(object["dark"] as? Bool == true)
        let colors = try #require(object["colors"] as? [String: String])
        #expect(colors.keys.sorted() == ThemeRole.all.map(\.name).sorted())
        #expect(colors["selection"] == "#ff79c6")
        #expect(colors["glassFill"] == "#21222cdb")
    }

    /// A missing role is Dracula's, quantized like every colour a file holds (Dracula's glass is 0.86 opaque, a file's
    /// 219/255), so the theme equals itself once saved and read back.
    @Test func missingRolesAreDraculas() throws {
        let theme = try decode(##"{ "version": 1, "name": "Pink", "dark": true, "colors": { "selection": "#00ff00" } }"##)
        var expected = ColorTheme.dracula.colors.quantized
        expected.selection = HexColor(0x00ff00)
        #expect(theme == ColorTheme(id: "custom-2", name: "Pink", isDark: true, colors: expected))
    }

    @Test func unknownRolesAndKeysAreIgnored() throws {
        let theme = try decode(##"""
        { "version": 1, "name": "Later", "dark": true, "author": "someone",
          "colors": { "accent": "#112233", "sparkle": "#123456", "glow": "not a colour", "rim": { "a": 1 }, "n": 3 } }
        """##)
        #expect(theme.colors.accent == HexColor(0x112233))
        #expect(theme.name == "Later")
    }

    @Test func aBadColourIsRefusedNamingItsRole() {
        #expect(throws: ThemeFileError.notAColour(role: "selection")) {
            try decode(#"{ "version": 1, "colors": { "selection": "pink" } }"#)
        }
        #expect(ThemeFileError.notAColour(role: "selection").message == "‘selection’ isn’t a colour like #ff79c6.")
        #expect(throws: ThemeFileError.notAColour(role: "accent")) {
            try decode(#"{ "version": 1, "colors": { "accent": 12 } }"#)
        }
        #expect(ThemeFileError.notAColour(role: "accent").message == "‘accent’ isn’t a colour like #bd93f9.")
    }

    @Test(arguments: [
        "not json", "{}", "[]", #"{ "version": 1 }"#, #"{ "colors": {} }"#, #"{ "version": 0, "colors": {} }"#,
        #"{ "version": "1", "colors": {} }"#, #"{ "formatVersion": 4, "graph": { "nodes": {} } }"#,
    ])
    func whatIsntAThemeIsRefused(_ json: String) {
        #expect(throws: ThemeFileError.damaged) { try decode(json) }
    }

    @Test func aNewerVersionIsRefused() {
        #expect(throws: ThemeFileError.newerVersion(2)) { try decode(#"{ "version": 2, "colors": {} }"#) }
        #expect(ThemeFileError.newerVersion(2).message
            == "It was made by a newer MetalCreator (theme version 2); this one reads version 1.")
        #expect(ThemeFileError.damaged.message == "It isn’t a MetalCreator theme, or it is damaged.")
    }

    @Test func aMissingNameIsTheFallbackAndAMissingDarkFollowsThePanelBase() throws {
        #expect(try decode(#"{ "version": 1, "colors": {} }"#, fallbackName: "Ocean").name == "Ocean")
        #expect(try decode(#"{ "version": 1, "name": "  ", "colors": {} }"#, fallbackName: "Ocean").name == "Ocean")
        #expect(try decode(#"{ "version": 1, "name": " Sea ", "colors": {} }"#).name == "Sea")
        #expect(try decode(#"{ "version": 1, "colors": {} }"#).isDark, "Dracula's panel base is dark")
        #expect(try !decode(##"{ "version": 1, "colors": { "panelBase": "#fffbeb" } }"##).isDark)
        #expect(try !decode(#"{ "version": 1, "dark": false, "colors": {} }"#).isDark, "a stated `dark` wins")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorStyleTests.ThemeFileTests`
Expected: the build fails: cannot find `ThemeFile` and `ThemeFileError` in scope.

- [ ] **Step 3: Implement**

`Sources/CreatorStyle/ThemeFileError.swift`:

```swift
/// Why a `.mctheme` file can't be read, as one plain sentence (`message`).
public enum ThemeFileError: Error, Equatable, Sendable {
    /// Not JSON, or JSON without a theme's `version` and `colors`.
    case damaged
    /// Written by a newer MetalCreator in a version this one can't read.
    case newerVersion(Int)
    /// The colour of the role named `role` isn't `#rrggbb` or `#rrggbbaa`.
    case notAColour(role: String)

    public var message: String {
        switch self {
        case .damaged:
            "It isn’t a MetalCreator theme, or it is damaged."
        case .newerVersion(let version):
            "It was made by a newer MetalCreator (theme version \(version)); this one reads version \(ThemeFile.currentVersion)."
        case .notAColour(let role):
            "‘\(role)’ isn’t a colour like \(Self.example(for: role))."
        }
    }

    /// Dracula's colour for `role`, to show what a colour looks like.
    private static func example(for role: String) -> String {
        ThemeRole.named(role).map { ColorTheme.dracula.colors[$0].hex } ?? "#ff79c6"
    }
}
```

`Sources/CreatorStyle/ThemeFile.swift`:

````swift
import Foundation

/// The `.mctheme` file (Themes milestone): small, versioned JSON holding a theme's name, whether it is dark, and a
/// colour per role, keyed by role name (`ThemeRole.name`), as `#rrggbb` or, when translucent, `#rrggbbaa`:
///
/// ```json
/// { "colors" : { "accent" : "#bd93f9", "backgroundBottom" : "#191a21", … }, "dark" : true, "name" : "Midnight",
///   "version" : 1 }
/// ```
///
/// Reading forgives what it safely can and refuses the rest plainly: a missing role is Dracula's (quantized, as every
/// colour a file holds is), a role this version doesn't know is ignored (a newer MetalCreator's), a missing `dark`
/// follows the panel base's lightness and a missing name is the caller's fallback (the file's name); but a colour
/// that isn't one is refused, naming the role, and so is a file from a newer version or one that isn't a theme. The
/// theme's id is not in the file: it is the caller's (the themes folder names files by id; an import makes a new one).
public enum ThemeFile {
    /// The version this build writes and the newest it reads.
    public static let currentVersion = 1

    /// The file's bytes: every role, keys sorted, so the same theme always writes the same file.
    public static func encode(_ theme: ColorTheme) throws -> Data {
        var colors: [String: ThemeFileColor] = [:]
        for role in ThemeRole.all { colors[role.name] = .text(theme.colors[role].hex) }
        let body = ThemeFileBody(version: currentVersion, name: theme.name, dark: theme.isDark, colors: colors)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(body)
    }

    /// The theme in `data`, with `id`, named `fallbackName` if the file names it nothing.
    public static func decode(_ data: Data, id: ColorTheme.ID, fallbackName: String) throws(ThemeFileError) -> ColorTheme {
        let body: ThemeFileBody
        do {
            body = try JSONDecoder().decode(ThemeFileBody.self, from: data)
        } catch {
            throw .damaged
        }
        guard body.version >= 1 else { throw .damaged }
        guard body.version <= currentVersion else { throw .newerVersion(body.version) }
        // Quantized like every custom theme's colours, so a missing role reads back from a saved file unchanged.
        var colors = ColorTheme.dracula.colors.quantized
        for role in ThemeRole.all {
            guard let entry = body.colors[role.name] else { continue }
            guard case .text(let text) = entry, let colour = HexColor(hex: text) else { throw .notAColour(role: role.name) }
            colors[role] = colour
        }
        let name = body.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ColorTheme(id: id, name: name.isEmpty ? fallbackName : name, isDark: body.dark ?? isDarkSurface(colors.panelBase),
                          colors: colors)
    }

    /// Whether `colour` is on the dark side of mid-grey: a file that doesn't say asks for dark controls on a dark panel.
    static func isDarkSurface(_ colour: HexColor) -> Bool {
        let channels = [16, 8, 0].map { (colour.rgb >> UInt32($0)) & 0xff }
        return channels.reduce(0, +) < 3 * 128
    }
}
````

`Sources/CreatorStyle/ThemeFileBody.swift`:

```swift
/// The file's JSON object. Unknown top-level keys are ignored by `Decodable`.
struct ThemeFileBody: Codable {
    var version: Int
    var name: String?
    var dark: Bool?
    var colors: [String: ThemeFileColor]
}
```

`Sources/CreatorStyle/ThemeFileColor.swift`:

```swift
/// A value in `colors`: text, or anything else (kept apart so an unknown role's value never fails the file).
enum ThemeFileColor: Codable, Equatable {
    case text(String)
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = (try? container.decode(String.self)).map(ThemeFileColor.text) ?? .other
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .other: try container.encodeNil()
        }
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorStyleTests`
Expected: `Test run with 31 tests in 5 suites passed`.

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 20 = 1105.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle/ThemeFileError.swift Sources/CreatorStyle/ThemeFile.swift \
  Sources/CreatorStyle/ThemeFileBody.swift Sources/CreatorStyle/ThemeFileColor.swift Tests/CreatorStyleTests/ThemeFileTests.swift
git commit -m "feat(style): the .mctheme format — versioned JSON of hex colours by role, forgiving and plain"
```

---

### Task 4: The themes folder

**Files:**
- Create: `Sources/CreatorStyle/ThemeProblem.swift`, `Sources/CreatorStyle/ThemeFolder.swift`
- Test: `Tests/CreatorStyleTests/ThemeFolderTests.swift`

**Interfaces:**
- Consumes: `ThemeFile.encode(_:)`, `ThemeFile.decode(_:id:fallbackName:)`, `ThemeFileError.message` (Task 3).
- Produces: `struct ThemeProblem: Error, Equatable, Sendable` (`message`, `init(_:)`); `struct ThemeFolder: Hashable,
  Sendable` with `url`, `init(_ url: URL)`, `static var applicationSupport: ThemeFolder`,
  `fileURL(for id: ColorTheme.ID) -> URL`, `load(reserved: Set<ColorTheme.ID>) -> (themes: [ColorTheme], problems:
  [String])`, `save(_ theme: ColorTheme) throws(ThemeProblem)`, `remove(_ id: ColorTheme.ID) throws(ThemeProblem)`.
  Test helper used by later tasks: `ThemeFolderTests.temporaryFolder() -> ThemeFolder`.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorStyle
import Foundation
import Testing

/// The themes folder: one `<id>.mctheme` per custom theme, in a temporary folder here, never the person's own.
struct ThemeFolderTests {
    /// A folder path in the temporary directory that doesn't exist yet; the caller removes it.
    static func temporaryFolder() -> ThemeFolder {
        ThemeFolder(URL.temporaryDirectory.appending(path: "ThemeFolderTests-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    static func custom(_ id: String, _ name: String) -> ColorTheme {
        ColorTheme(id: id, name: name, isDark: true, colors: ColorTheme.nord.colors.quantized)
    }

    @Test func theAppsFolderIsInApplicationSupport() {
        #expect(ThemeFolder.applicationSupport.url.path(percentEncoded: false).hasSuffix("Application Support/MetalCreator/Themes/"))
    }

    @Test func aFolderThatDoesntExistHoldsNoThemes() {
        let loaded = Self.temporaryFolder().load(reserved: [])
        #expect(loaded.themes.isEmpty && loaded.problems.isEmpty)
    }

    @Test func savedThemesLoadBackByFileName() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.custom("custom-b", "Beta"))
        try folder.save(Self.custom("custom-a", "Alpha"))
        #expect(FileManager.default.fileExists(atPath: folder.fileURL(for: "custom-a").path(percentEncoded: false)))
        let loaded = folder.load(reserved: [])
        #expect(loaded.themes == [Self.custom("custom-a", "Alpha"), Self.custom("custom-b", "Beta")])
        #expect(loaded.problems.isEmpty)
    }

    @Test func removingDeletesTheFileAndAGoneFileIsFine() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.custom("custom-a", "Alpha"))
        try folder.remove("custom-a")
        #expect(folder.load(reserved: []).themes.isEmpty)
        try folder.remove("custom-a")
    }

    /// A damaged file, a bad colour or a file named like a built-in never stops the others loading, and each says
    /// why it was skipped. Other files are not themes and are left alone.
    @Test func unreadableFilesAreSkippedWithAReason() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.save(Self.custom("custom-a", "Alpha"))
        try folder.save(Self.custom("dracula", "Not Dracula"))
        try Data("nope".utf8).write(to: folder.fileURL(for: "junk"))
        try Data(#"{ "version": 1, "colors": { "selection": "pink" } }"#.utf8).write(to: folder.fileURL(for: "pink"))
        try Data("notes".utf8).write(to: folder.url.appending(path: "notes.txt"))
        let loaded = folder.load(reserved: ["dracula"])
        #expect(loaded.themes == [Self.custom("custom-a", "Alpha")])
        #expect(loaded.problems == [
            "“dracula.mctheme” was skipped: its name is a built-in theme’s.",
            "“junk.mctheme” was skipped: It isn’t a MetalCreator theme, or it is damaged.",
            "“pink.mctheme” was skipped: ‘selection’ isn’t a colour like #ff79c6.",
        ])
    }

    @Test func aFileWithoutANameIsNamedByItsFile() throws {
        let folder = Self.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data(#"{ "version": 1, "colors": {} }"#.utf8).write(to: folder.fileURL(for: "Ocean"))
        #expect(folder.load(reserved: []).themes.map(\.name) == ["Ocean"])
    }

    @Test func aSaveThatFailsSaysSo() throws {
        let blocker = URL.temporaryDirectory.appending(path: "ThemeFolderTests-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("a file, not a folder".utf8).write(to: blocker)
        let error = #expect(throws: ThemeProblem.self) { try ThemeFolder(blocker).save(Self.custom("custom-a", "Alpha")) }
        #expect(error?.message.hasPrefix("“Alpha” couldn’t be saved: ") == true)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorStyleTests.ThemeFolderTests`
Expected: the build fails: cannot find `ThemeFolder` and `ThemeProblem` in scope.

- [ ] **Step 3: Implement**

`Sources/CreatorStyle/ThemeProblem.swift`:

```swift
/// A theme action that couldn't be done, as the one sentence the theme editor shows.
public struct ThemeProblem: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}
```

`Sources/CreatorStyle/ThemeFolder.swift`:

```swift
import Foundation

/// The folder the person's own themes live in, one `<id>.mctheme` file each: the file's name is the theme's id,
/// which renames never change. The app's is `~/Library/Application Support/MetalCreator/Themes`; tests pass a
/// temporary folder, so they never touch the person's themes.
public struct ThemeFolder: Hashable, Sendable {
    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/MetalCreator/Themes`.
    public static var applicationSupport: ThemeFolder {
        ThemeFolder(URL.applicationSupportDirectory.appending(path: "MetalCreator/Themes", directoryHint: .isDirectory))
    }

    /// The `.mctheme` file of the theme with `id`.
    public func fileURL(for id: ColorTheme.ID) -> URL {
        url.appending(path: "\(id).mctheme", directoryHint: .notDirectory)
    }

    /// Every theme in the folder, by file name, and a sentence for each file that was skipped: one that can't be
    /// read, or one named like a `reserved` (built-in) id. A folder that doesn't exist yet holds no themes.
    public func load(reserved: Set<ColorTheme.ID>) -> (themes: [ColorTheme], problems: [String]) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return ([], [])
        } catch {
            return ([], ["The themes folder couldn’t be read: \(error.localizedDescription)"])
        }
        var themes: [ColorTheme] = []
        var problems: [String] = []
        let themeFiles = files.filter { $0.pathExtension == "mctheme" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in themeFiles {
            let id = file.deletingPathExtension().lastPathComponent
            let skipped = "“\(file.lastPathComponent)” was skipped:"
            guard !reserved.contains(id) else {
                problems.append("\(skipped) its name is a built-in theme’s.")
                continue
            }
            do {
                let data = try Data(contentsOf: file)
                do throws(ThemeFileError) {
                    themes.append(try ThemeFile.decode(data, id: id, fallbackName: id))
                } catch {
                    problems.append("\(skipped) \(error.message)")
                }
            } catch {
                problems.append("\(skipped) \(error.localizedDescription)")
            }
        }
        return (themes, problems)
    }

    /// Writes `theme` to its file, creating the folder if needed.
    public func save(_ theme: ColorTheme) throws(ThemeProblem) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try ThemeFile.encode(theme).write(to: fileURL(for: theme.id), options: .atomic)
        } catch {
            throw ThemeProblem("“\(theme.name)” couldn’t be saved: \(error.localizedDescription)")
        }
    }

    /// Deletes the file of the theme with `id`. A file that is already gone is fine.
    public func remove(_ id: ColorTheme.ID) throws(ThemeProblem) {
        do {
            try FileManager.default.removeItem(at: fileURL(for: id))
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            throw ThemeProblem("The theme couldn’t be deleted: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorStyleTests`
Expected: `Test run with 38 tests in 6 suites passed`.

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 27 = 1112.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle/ThemeProblem.swift Sources/CreatorStyle/ThemeFolder.swift Tests/CreatorStyleTests/ThemeFolderTests.swift
git commit -m "feat(style): ThemeFolder — one <id>.mctheme per custom theme; unreadable files skipped with a reason"
```

---

### Task 5: Custom themes in `ThemeStore`, import and export

**Files:**
- Modify: `Sources/CreatorStyle/ThemeStore.swift` (whole file below)
- Create: `Sources/CreatorStyle/ThemeStore+Library.swift`, `Sources/CreatorStyle/ThemeStore+Files.swift`
- Test: `Tests/CreatorStyleTests/ThemeLibraryTests.swift`, `Tests/CreatorStyleTests/ThemeImportExportTests.swift`
  (`ThemeStoreTests.swift` is unchanged and must still pass)

**Interfaces:**
- Consumes: `ThemeFolder` and `ThemeProblem` (Task 4), `ThemeFile` (Task 3), `ThemeRole` and
  `ThemeColors.quantized` (Task 2), `HexColor.quantized` (Task 1), `ThemePreferences` (existing).
- Produces, on `ThemeStore` (`@MainActor @Observable`):
  `init(preferences: any ThemePreferences = InMemoryThemePreferences(), builtIns: [ColorTheme] = ColorTheme.builtIns,
  folder: ThemeFolder? = nil)` (existing callers compile unchanged); `customs: [ColorTheme]` (by name);
  `current: ColorTheme` (now `internal(set)`); `loadProblems: [String]`; `themes: [ColorTheme]`;
  `theme(_ id: ColorTheme.ID) -> ColorTheme?`; `isBuiltIn(_ id:) -> Bool`; `select(_:)` (now over every theme);
  `@discardableResult duplicate(_ id:) throws(ThemeProblem) -> ColorTheme`; `rename(_ id:, to name: String)
  throws(ThemeProblem)`; `setColor(_ color: HexColor, for role: ThemeRole, in id:) throws(ThemeProblem)`;
  `setDark(_ isDark: Bool, in id:) throws(ThemeProblem)`; `delete(_ id:) throws(ThemeProblem)`;
  `@discardableResult importTheme(from url: URL) throws(ThemeProblem) -> ColorTheme`;
  `exportTheme(_ id:, to url: URL) throws(ThemeProblem)`.
- Sentences (exact): "Built-in themes can’t be changed. Duplicate one to make your own.", "A theme needs a name.",
  "There’s already a theme called “<name>”.", "That theme no longer exists.", "“<file>” couldn’t be imported.
  <reason>", "“<file>” couldn’t be exported. <reason>", "“<name>” couldn’t be saved: <reason>".

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorStyleTests/ThemeLibraryTests.swift`:

```swift
import CreatorStyle
import Foundation
import Observation
import Testing

/// Custom themes: duplicate any theme, then rename, recolour, darken or delete the copy; the built-ins stay
/// read-only. With a folder every change is on disk at once; without one (most tests) it is kept in memory.
@MainActor
struct ThemeLibraryTests {
    static let readOnly = ThemeProblem("Built-in themes can’t be changed. Duplicate one to make your own.")

    /// Counts observation callbacks.
    @MainActor
    final class Observer {
        var changes = 0
    }

    @Test func duplicatingABuiltInMakesAnEditableCopyAndShowsIt() throws {
        let preferences = InMemoryThemePreferences()
        let store = ThemeStore(preferences: preferences)
        let copy = try store.duplicate("dracula")
        #expect(copy.name == "Dracula Copy" && copy.isDark)
        #expect(copy.colors == ColorTheme.dracula.colors.quantized)
        #expect(copy.id.hasPrefix("custom-"))
        #expect(store.customs == [copy] && store.current == copy && preferences.selectedThemeID == copy.id)
        #expect(!store.isBuiltIn(copy.id) && store.isBuiltIn("dracula"))
        #expect(store.themes.map(\.name) == ["Dracula", "Alucard", "Nord", "Dracula Copy"])
    }

    @Test func copiesAreNumberedAndListedByName() throws {
        let store = ThemeStore()
        let first = try store.duplicate("nord")
        try store.duplicate("nord")
        try store.duplicate(first.id)
        try store.duplicate("alucard")
        #expect(store.customs.map(\.name) == ["Alucard Copy", "Nord Copy", "Nord Copy 2", "Nord Copy Copy"])
    }

    @Test func theBuiltInsAreReadOnly() throws {
        let store = ThemeStore()
        let accent = try #require(ThemeRole.named("accent"))
        #expect(throws: Self.readOnly) { try store.rename("dracula", to: "Mine") }
        #expect(throws: Self.readOnly) { try store.setColor(HexColor(0x000000), for: accent, in: "nord") }
        #expect(throws: Self.readOnly) { try store.setDark(false, in: "dracula") }
        #expect(throws: Self.readOnly) { try store.delete("alucard") }
        #expect(store.builtIns == ColorTheme.builtIns && store.customs.isEmpty)
        #expect(throws: ThemeProblem("That theme no longer exists.")) { try store.rename("custom-gone", to: "Mine") }
    }

    @Test func renamingTrimsAndRefusesEmptyAndTakenNames() throws {
        let store = ThemeStore()
        let copy = try store.duplicate("dracula")
        try store.rename(copy.id, to: "  Midnight ")
        #expect(store.current.name == "Midnight" && store.customs.map(\.name) == ["Midnight"])
        #expect(throws: ThemeProblem("A theme needs a name.")) { try store.rename(copy.id, to: "   ") }
        #expect(throws: ThemeProblem("There’s already a theme called “nord”.")) { try store.rename(copy.id, to: "nord") }
        try store.rename(copy.id, to: "MIDNIGHT")
        #expect(store.current.name == "MIDNIGHT", "a change of case alone is its own name")
        #expect(store.current.id == copy.id)
    }

    @Test func renamingReordersTheList() throws {
        let store = ThemeStore()
        let first = try store.duplicate("dracula")
        try store.duplicate("nord")
        try store.rename(first.id, to: "Zebra")
        #expect(store.customs.map(\.name) == ["Nord Copy", "Zebra"])
    }

    @Test func aColourEditIsShownAtOnce() throws {
        let store = ThemeStore()
        let copy = try store.duplicate("dracula")
        let observer = Observer()
        withObservationTracking { _ = store.current } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
        let selection = try #require(ThemeRole.named("selection"))
        try store.setColor(HexColor(0x00ffaa), for: selection, in: copy.id)
        #expect(store.current.colors.selection == HexColor(0x00ffaa))
        #expect(observer.changes == 1, "the views and the viewport redraw")
        try store.setColor(HexColor(0x101010, opacity: 0.5), for: try #require(ThemeRole.named("glassFill")), in: copy.id)
        #expect(store.current.colors.glassFill == HexColor(0x101010, opacity: 128.0 / 255), "quantized as the file holds it")
        #expect(ThemeStore().current.colors.selection == HexColor(0xff79c6), "Dracula itself is untouched")
    }

    @Test func darkCanBeTurnedOff() throws {
        let store = ThemeStore()
        let copy = try store.duplicate("dracula")
        try store.setDark(false, in: copy.id)
        #expect(!store.current.isDark)
    }

    @Test func deletingTheShownThemeShowsDracula() throws {
        let preferences = InMemoryThemePreferences()
        let store = ThemeStore(preferences: preferences)
        let copy = try store.duplicate("nord")
        let other = try store.duplicate("alucard")
        try store.delete(other.id)
        #expect(store.customs == [copy])
        #expect(store.current == .dracula && preferences.selectedThemeID == "dracula")
    }

    @Test func aFolderKeepsEveryChange() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        try store.rename(copy.id, to: "Midnight")
        try store.setColor(HexColor(0x00ffaa), for: try #require(ThemeRole.named("accent")), in: copy.id)
        try store.setDark(false, in: copy.id)
        let doomed = try store.duplicate("nord")
        #expect(ThemeStore(folder: folder).customs == store.customs)
        try store.delete(doomed.id)
        let reloaded = ThemeStore(folder: folder)
        #expect(reloaded.customs == store.customs && reloaded.customs.count == 1)
        #expect(reloaded.customs.first?.colors.accent == HexColor(0x00ffaa))
    }

    /// Review focus: a colour drag writes on every move; the last colour is the one kept.
    @Test func manyQuickEditsKeepTheLastColour() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let accent = try #require(ThemeRole.named("accent"))
        for step in 0..<120 {
            try store.setColor(HexColor(UInt32(step) << 16), for: accent, in: copy.id)
        }
        #expect(ThemeStore(folder: folder).customs.first?.colors.accent == HexColor(119 << 16))
    }

    /// Review focus: the remembered theme is a custom one, or one that has since gone.
    @Test func theRememberedCustomThemeIsShownAtLaunchAndAGoneOneFallsBackToDracula() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let preferences = InMemoryThemePreferences()
        let copy = try ThemeStore(preferences: preferences, folder: folder).duplicate("nord")
        #expect(ThemeStore(preferences: preferences, folder: folder).current == copy)
        try FileManager.default.removeItem(at: folder.fileURL(for: copy.id))
        #expect(ThemeStore(preferences: preferences, folder: folder).current == .dracula)
    }

    /// Review focus: an unreadable file in the folder never stops the app starting; the editor shows why.
    @Test func filesThatCantBeReadAreReported() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: folder.fileURL(for: "junk"))
        let store = ThemeStore(folder: folder)
        #expect(store.customs.isEmpty && store.current == .dracula)
        #expect(store.loadProblems == ["“junk.mctheme” was skipped: It isn’t a MetalCreator theme, or it is damaged."])
    }

    /// Review focus: a save that fails (a full disk, a locked folder) changes nothing and says why.
    @Test func aFailedSaveChangesNothing() throws {
        let blocker = URL.temporaryDirectory.appending(path: "ThemeLibraryTests-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("a file, not a folder".utf8).write(to: blocker)
        let preferences = InMemoryThemePreferences(selectedThemeID: "nord")
        let store = ThemeStore(preferences: preferences, folder: ThemeFolder(blocker))
        let error = #expect(throws: ThemeProblem.self) { try store.duplicate("dracula") }
        #expect(error?.message.hasPrefix("“Dracula Copy” couldn’t be saved: ") == true)
        #expect(store.customs.isEmpty && store.current == .nord && preferences.selectedThemeID == "nord")
    }
}
```

`Tests/CreatorStyleTests/ThemeImportExportTests.swift`:

```swift
import CreatorStyle
import Foundation
import Testing

/// Import… and Export…: `.mctheme` files anywhere on disk. An import is always a new custom theme.
@MainActor
struct ThemeImportExportTests {
    /// A path in the temporary directory; the caller removes it.
    static func temporaryFile(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
    }

    @Test func anExportedThemeImportsAsANewThemeWithAFreeName() throws {
        let url = Self.temporaryFile("Dracula.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ThemeStore()
        try store.exportTheme("dracula", to: url)
        let imported = try store.importTheme(from: url)
        #expect(imported.name == "Dracula 2", "never replaces a theme, built-in or custom")
        #expect(imported.colors == ColorTheme.dracula.colors.quantized && imported.isDark)
        #expect(store.current == imported && store.customs == [imported])
        #expect(try store.importTheme(from: url).name == "Dracula 3")
    }

    @Test func aCustomThemeExportsAsItIs() throws {
        let url = Self.temporaryFile("mine.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ThemeStore()
        let copy = try store.duplicate("nord")
        try store.rename(copy.id, to: "Fjord")
        try store.exportTheme(copy.id, to: url)
        let other = ThemeStore()
        let imported = try other.importTheme(from: url)
        #expect(imported.name == "Fjord" && imported.colors == store.current.colors)
    }

    @Test func aFileWithoutANameIsNamedAfterTheFile() throws {
        let url = Self.temporaryFile("Ocean.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{ "version": 1, "colors": {} }"#.utf8).write(to: url)
        #expect(try ThemeStore().importTheme(from: url).name == url.deletingPathExtension().lastPathComponent)
    }

    @Test func aBadFileIsRefusedPlainlyAndChangesNothing() throws {
        let url = Self.temporaryFile("bad.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{ "version": 1, "colors": { "selection": "pink" } }"#.utf8).write(to: url)
        let store = ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "nord"))
        #expect(throws: ThemeProblem("“\(url.lastPathComponent)” couldn’t be imported. ‘selection’ isn’t a colour like #ff79c6.")) {
            try store.importTheme(from: url)
        }
        #expect(store.customs.isEmpty && store.current == .nord)
    }

    @Test func aMissingFileIsRefused() {
        let url = Self.temporaryFile("gone.mctheme")
        let error = #expect(throws: ThemeProblem.self) { try ThemeStore().importTheme(from: url) }
        #expect(error?.message.hasPrefix("“\(url.lastPathComponent)” couldn’t be imported. ") == true)
    }

    @Test func anImportIsSavedInTheFolder() throws {
        let url = Self.temporaryFile("Nord.mctheme")
        let folder = ThemeFolderTests.temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: folder.url)
        }
        let store = ThemeStore(folder: folder)
        try store.exportTheme("nord", to: url)
        let imported = try store.importTheme(from: url)
        #expect(ThemeStore(folder: folder).customs == [imported])
    }

    /// A file that names only some roles: the missing ones are Dracula's, quantized, so the theme the import shows is
    /// the one the folder gives back at the next launch (Dracula's glass is 0.86 opaque, a file's 219/255).
    @Test func aPartialFileImportsAsTheThemeTheFolderReadsBack() throws {
        let url = Self.temporaryFile("Partial.mctheme")
        let folder = ThemeFolderTests.temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: folder.url)
        }
        try Data(#"{ "version": 1, "colors": {} }"#.utf8).write(to: url)
        let imported = try ThemeStore(folder: folder).importTheme(from: url)
        #expect(imported.colors == ColorTheme.dracula.colors.quantized)
        #expect(ThemeStore(folder: folder).customs == [imported])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter CreatorStyleTests`
Expected: the build fails: `ThemeStore` has no `duplicate`, `customs`, `folder:` argument, `importTheme` or
`exportTheme`.

- [ ] **Step 3: Implement**

Replace `Sources/CreatorStyle/ThemeStore.swift` with:

```swift
import Foundation
import Observation

/// The app's themes and the one it shows (spec §6.6: themeable, Dracula by default). Views read `current` through
/// the environment and the app shell hands it to the viewport, so selecting a theme, or editing the current one,
/// re-renders the editor by observation and reaches the GPU colours on the viewport's next frame. The built-ins are
/// read-only; the person's own themes (`customs`) are duplicated, renamed, recoloured, deleted, imported and
/// exported here (`ThemeStore+Library`, `ThemeStore+Files`), and each change is saved to `folder` at once.
@MainActor
@Observable
public final class ThemeStore {
    /// The read-only themes, in menu order.
    public let builtIns: [ColorTheme]
    /// The person's own themes, by name.
    public internal(set) var customs: [ColorTheme]
    /// The theme shown now.
    public internal(set) var current: ColorTheme
    /// One sentence for each file in the themes folder that couldn't be read at launch (the theme editor shows them).
    public let loadProblems: [String]
    @ObservationIgnored let preferences: any ThemePreferences
    /// Where custom themes are saved; `nil` keeps them in memory only (tests, previews).
    @ObservationIgnored let folder: ThemeFolder?

    /// Loads the custom themes from `folder`, then starts with the theme `preferences` remembers, or Dracula when it
    /// remembers none or one that no longer exists.
    public init(preferences: any ThemePreferences = InMemoryThemePreferences(), builtIns: [ColorTheme] = ColorTheme.builtIns,
                folder: ThemeFolder? = nil) {
        self.preferences = preferences
        self.builtIns = builtIns
        self.folder = folder
        let loaded = folder?.load(reserved: Set(builtIns.map(\.id))) ?? (themes: [], problems: [])
        let customs = Self.sorted(loaded.themes)
        self.customs = customs
        loadProblems = loaded.problems
        current = (builtIns + customs).first { $0.id == preferences.selectedThemeID } ?? .dracula
    }

    /// Every theme in menu order: the built-ins, then the custom themes.
    public var themes: [ColorTheme] { builtIns + customs }

    /// The theme with `id`, or `nil`.
    public func theme(_ id: ColorTheme.ID) -> ColorTheme? { themes.first { $0.id == id } }

    /// Whether `id` is a read-only built-in.
    public func isBuiltIn(_ id: ColorTheme.ID) -> Bool { builtIns.contains { $0.id == id } }

    /// Shows the theme with `id` and remembers it. An id no theme has is ignored.
    public func select(_ id: ColorTheme.ID) {
        guard let theme = theme(id) else { return }
        preferences.selectedThemeID = id
        if theme != current { current = theme }
    }

    /// Custom themes in menu order: by name as Finder sorts, then by id.
    static func sorted(_ themes: [ColorTheme]) -> [ColorTheme] {
        themes.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }
}
```

`Sources/CreatorStyle/ThemeStore+Library.swift`:

```swift
import Foundation

/// Custom themes (Themes milestone): duplicate any theme, then rename, recolour, darken or delete the copy. The
/// built-ins stay read-only (spec §6.6). Every change is saved before it is shown, so a save that fails changes
/// nothing and says why.
extension ThemeStore {
    /// Duplicate: a custom copy of the theme with `id` named "<name> Copy" (then "… Copy 2" and on), saved and shown.
    @discardableResult
    public func duplicate(_ id: ColorTheme.ID) throws(ThemeProblem) -> ColorTheme {
        guard let source = theme(id) else { throw Self.gone }
        let copy = ColorTheme(id: Self.newID(), name: uniqueName(source.name + " Copy"), isDark: source.isDark,
                              colors: source.colors.quantized)
        try add(copy)
        return copy
    }

    /// Renames a custom theme. The name is trimmed; an empty name, or one another theme has (in any case), is refused.
    public func rename(_ id: ColorTheme.ID, to name: String) throws(ThemeProblem) {
        var theme = try editable(id)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ThemeProblem("A theme needs a name.") }
        guard trimmed != theme.name else { return }
        guard !isTaken(trimmed, except: id) else { throw ThemeProblem("There’s already a theme called “\(trimmed)”.") }
        theme.name = trimmed
        try replace(theme)
    }

    /// Sets one role's colour in a custom theme, quantized as its file will hold it. Shown at once if it is current.
    public func setColor(_ color: HexColor, for role: ThemeRole, in id: ColorTheme.ID) throws(ThemeProblem) {
        var theme = try editable(id)
        let color = color.quantized
        guard theme.colors[role] != color else { return }
        theme.colors[role] = color
        try replace(theme)
    }

    /// Whether a custom theme asks for MetalUI's dark controls (and the window's dark appearance) or its light ones.
    public func setDark(_ isDark: Bool, in id: ColorTheme.ID) throws(ThemeProblem) {
        var theme = try editable(id)
        guard theme.isDark != isDark else { return }
        theme.isDark = isDark
        try replace(theme)
    }

    /// Deletes a custom theme and its file. If it was shown, Dracula is shown and remembered instead.
    public func delete(_ id: ColorTheme.ID) throws(ThemeProblem) {
        _ = try editable(id)
        try folder?.remove(id)
        customs.removeAll { $0.id == id }
        if current.id == id {
            current = .dracula
            preferences.selectedThemeID = ColorTheme.dracula.id
        }
    }

    /// The custom theme with `id`. A built-in is refused (read-only), and so is a theme that is gone.
    func editable(_ id: ColorTheme.ID) throws(ThemeProblem) -> ColorTheme {
        guard !isBuiltIn(id) else { throw ThemeProblem("Built-in themes can’t be changed. Duplicate one to make your own.") }
        guard let theme = customs.first(where: { $0.id == id }) else { throw Self.gone }
        return theme
    }

    /// Saves a new custom theme, then lists and shows it.
    func add(_ theme: ColorTheme) throws(ThemeProblem) {
        try folder?.save(theme)
        customs = Self.sorted(customs + [theme])
        select(theme.id)
    }

    /// Saves a changed custom theme, then lists it and, if it is current, shows the change.
    func replace(_ theme: ColorTheme) throws(ThemeProblem) {
        try folder?.save(theme)
        customs = Self.sorted(customs.map { $0.id == theme.id ? theme : $0 })
        if current.id == theme.id { current = theme }
    }

    /// `base`, or `base` followed by the first free number from 2.
    func uniqueName(_ base: String) -> String {
        guard isTaken(base) else { return base }
        var number = 2
        while isTaken("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Whether a theme other than `id` is called `name`, ignoring case.
    func isTaken(_ name: String, except id: ColorTheme.ID? = nil) -> Bool {
        themes.contains { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// A new custom theme's id, which is also its file's name.
    static func newID() -> ColorTheme.ID { "custom-" + UUID().uuidString.lowercased() }

    static var gone: ThemeProblem { ThemeProblem("That theme no longer exists.") }
}
```

`Sources/CreatorStyle/ThemeStore+Files.swift`:

```swift
import Foundation

/// Import… and Export…: `.mctheme` files anywhere on disk (Themes milestone).
extension ThemeStore {
    /// Reads the `.mctheme` file at `url` as a new custom theme, saves it and shows it. Its name is the file's (or,
    /// if it has none, the file name's) made unique, so an import never replaces a theme.
    @discardableResult
    public func importTheme(from url: URL) throws(ThemeProblem) -> ColorTheme {
        let refusal = "“\(url.lastPathComponent)” couldn’t be imported."
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeProblem("\(refusal) \(error.localizedDescription)")
        }
        var theme: ColorTheme
        do throws(ThemeFileError) {
            theme = try ThemeFile.decode(data, id: Self.newID(), fallbackName: url.deletingPathExtension().lastPathComponent)
        } catch {
            throw ThemeProblem("\(refusal) \(error.message)")
        }
        theme.name = uniqueName(theme.name)
        try add(theme)
        return theme
    }

    /// Writes the theme with `id`, a built-in or a custom one, to `url` as a `.mctheme` file.
    public func exportTheme(_ id: ColorTheme.ID, to url: URL) throws(ThemeProblem) {
        guard let theme = theme(id) else { throw Self.gone }
        do {
            try ThemeFile.encode(theme).write(to: url, options: .atomic)
        } catch {
            throw ThemeProblem("“\(url.lastPathComponent)” couldn’t be exported. \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run them to see them pass**

Run: `swift test --filter CreatorStyleTests`
Expected: `Test run with 58 tests in 8 suites passed` (the four `ThemeStoreTests` among them, unchanged).

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test` (the editor, the app and the viewport compile against the new
initialiser). Expected total: master + 47 = 1132.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle/ThemeStore.swift Sources/CreatorStyle/ThemeStore+Library.swift \
  Sources/CreatorStyle/ThemeStore+Files.swift Tests/CreatorStyleTests/ThemeLibraryTests.swift \
  Tests/CreatorStyleTests/ThemeImportExportTests.swift
git commit -m "feat(style): custom themes — duplicate, rename, recolour, dark, delete, import, export; saved first"
```

---

### Task 6: The chosen theme in the person's defaults

**Files:**
- Create: `Sources/CreatorStyle/UserDefaultsThemePreferences.swift`
- Modify: `Sources/CreatorStyle/ThemePreferences.swift` (doc comment), `Sources/CreatorStyle/InMemoryThemePreferences.swift`
  (doc comment)
- Test: `Tests/CreatorStyleTests/UserDefaultsThemePreferencesTests.swift`

**Interfaces:**
- Consumes: `ThemePreferences` (existing), `ThemeStore.init(preferences:)`, `select(_:)` (Task 5).
- Produces: `@MainActor final class UserDefaultsThemePreferences: ThemePreferences` with
  `init(defaults: UserDefaults = .standard)` and `static let key = "selectedThemeID"`.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorStyle
import Foundation
import Testing

/// The chosen theme is remembered in the person's defaults: here a suite of the test's own, removed afterwards.
@MainActor
struct UserDefaultsThemePreferencesTests {
    /// A fresh defaults suite and its name, for `removePersistentDomain(forName:)`.
    static func suite() throws -> (defaults: UserDefaults, name: String) {
        let name = "MetalCreatorTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func itRemembersTheChosenThemeAcrossInstances() throws {
        let (defaults, name) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserDefaultsThemePreferences(defaults: defaults)
        #expect(preferences.selectedThemeID == nil)
        preferences.selectedThemeID = "nord"
        #expect(UserDefaultsThemePreferences(defaults: defaults).selectedThemeID == "nord")
        #expect(defaults.string(forKey: UserDefaultsThemePreferences.key) == "nord")
        preferences.selectedThemeID = nil
        #expect(UserDefaultsThemePreferences(defaults: defaults).selectedThemeID == nil)
    }

    @Test func theStoreStartsInTheThemeItWasLeftIn() throws {
        let (defaults, name) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        ThemeStore(preferences: UserDefaultsThemePreferences(defaults: defaults)).select("alucard")
        #expect(ThemeStore(preferences: UserDefaultsThemePreferences(defaults: defaults)).current == .alucard)
    }

    @Test func aRememberedValueThatIsntAThemeShowsDracula() throws {
        let (defaults, name) = try Self.suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(42, forKey: UserDefaultsThemePreferences.key)
        #expect(ThemeStore(preferences: UserDefaultsThemePreferences(defaults: defaults)).current == .dracula)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorStyleTests.UserDefaultsThemePreferencesTests`
Expected: the build fails: cannot find `UserDefaultsThemePreferences` in scope.

- [ ] **Step 3: Implement**

`Sources/CreatorStyle/UserDefaultsThemePreferences.swift`:

```swift
import Foundation

/// The chosen theme's id in the person's defaults (Themes milestone), so the app starts in the theme it was left
/// in. The app passes `.standard`; tests pass a suite of their own and remove it.
@MainActor
public final class UserDefaultsThemePreferences: ThemePreferences {
    /// The defaults key.
    public static let key = "selectedThemeID"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedThemeID: ColorTheme.ID? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
```

`Sources/CreatorStyle/ThemePreferences.swift` becomes:

```swift
/// Where the chosen theme's id is remembered between launches. Injected into `ThemeStore`, so tests never touch
/// the real preferences: the app uses `UserDefaultsThemePreferences`, tests `InMemoryThemePreferences` or a defaults
/// suite of their own.
@MainActor
public protocol ThemePreferences: AnyObject {
    var selectedThemeID: ColorTheme.ID? { get set }
}
```

`Sources/CreatorStyle/InMemoryThemePreferences.swift` becomes:

```swift
/// Theme preferences that last as long as the object: every test's, and any store that shouldn't remember.
@MainActor
public final class InMemoryThemePreferences: ThemePreferences {
    public var selectedThemeID: ColorTheme.ID?

    public init(selectedThemeID: ColorTheme.ID? = nil) {
        self.selectedThemeID = selectedThemeID
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorStyleTests`
Expected: `Test run with 61 tests in 9 suites passed`.

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 50 = 1135.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle/UserDefaultsThemePreferences.swift Sources/CreatorStyle/ThemePreferences.swift \
  Sources/CreatorStyle/InMemoryThemePreferences.swift Tests/CreatorStyleTests/UserDefaultsThemePreferencesTests.swift
git commit -m "feat(style): remember the chosen theme in the person's defaults"
```

---

### Task 7: MetalUI's control tokens from the theme

**Files:**
- Create: `Sources/CreatorStyle/ColorTheme+Controls.swift`
- Test: `Tests/CreatorStyleTests/ControlThemeTests.swift`

**Interfaces:**
- Consumes: `ColorTheme`, `ThemeColors`, `HexColor.opacity(_:)` (existing); MetalUI `Theme`, `Theme.dark`,
  `Theme.light`, `Hsla.rgb(_:alpha:)`.
- Produces: `ColorTheme.controlTheme: Theme` (MetalUI's); `HexColor.hsla: Hsla`. Task 9 applies it.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorStyle
import MetalUI
import Testing

/// MetalUI's control tokens follow the theme, role by role, so its controls match the panels.
struct ControlThemeTests {
    @Test func draculasControlsUseItsRoles() {
        let tokens = ColorTheme.dracula.controlTheme
        #expect(tokens.background == .rgb(0x191a21))
        #expect(tokens.surface == .rgb(0x343746))
        #expect(tokens.surfaceSecondary == .rgb(0x44475a))
        #expect(tokens.accent == .rgb(0xbd93f9))
        #expect(tokens.separator == .rgb(0x6272a4))
        #expect(tokens.textPrimary == .rgb(0xf8f8f2))
        #expect(tokens.scrollIndicator == .rgb(0xf8f8f2, alpha: 0.35))
        #expect(tokens.scrim == Theme.dark.scrim && tokens.shadow == Theme.dark.shadow)
    }

    @Test func aLightThemeKeepsMetalUIsLightScrim() {
        #expect(ColorTheme.alucard.controlTheme.scrim == Theme.light.scrim)
        #expect(ColorTheme.alucard.controlTheme.accent == .rgb(0x644ac9))
    }

    /// A colour well is a `surface` bezel with a `separator` border around a track-coloured field: in every built-in
    /// the three differ, so none disappears into another.
    @Test(arguments: ColorTheme.builtIns)
    func everyBuiltInKeepsItsControlPartsApart(_ theme: ColorTheme) {
        let tokens = theme.controlTheme
        #expect(Set([tokens.surface, tokens.surfaceSecondary, tokens.separator, tokens.background]).count == 4)
    }

    @Test func aCustomThemesEditsReachTheControls() {
        var theme = ColorTheme.nord
        theme.colors.accent = HexColor(0x00ffaa)
        #expect(theme.controlTheme.accent == .rgb(0x00ffaa))
        #expect(HexColor(0x123456, opacity: 0.5).hsla == .rgb(0x123456, alpha: 0.5))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorStyleTests.ControlThemeTests`
Expected: the build fails: `ColorTheme` has no member `controlTheme`.

- [ ] **Step 3: Implement**

```swift
import MetalUI

extension ColorTheme {
    /// MetalUI's control tokens in this theme, for `.theme(_:)` over the window, so MetalUI's own buttons, fields,
    /// menus, pickers, sliders, toggles and colour wells match the panels. Each token takes the role it means: the
    /// canvas `background` is the gradient's bottom, a control's `surface` the node body, a track
    /// (`surfaceSecondary`) the field colour, `accent` the accent, `separator` (hairlines, and a control's accent
    /// outside the key window) the secondary text, `textPrimary` the text, and the scroll thumb the text at 35%.
    /// The modal `scrim` and the default `shadow`, which no role names, stay MetalUI's for a dark or a light theme.
    public var controlTheme: Theme {
        let base: Theme = isDark ? .dark : .light
        return Theme(background: colors.backgroundBottom.hsla, surface: colors.nodeBody.hsla,
                     surfaceSecondary: colors.field.hsla, accent: colors.accent.hsla, separator: colors.comment.hsla,
                     textPrimary: colors.foreground.hsla, scrollIndicator: colors.foreground.opacity(0.35).hsla,
                     scrim: base.scrim, shadow: base.shadow)
    }
}

extension HexColor {
    /// The colour as MetalUI's `Hsla`, for theme tokens.
    public var hsla: Hsla { .rgb(rgb & 0xffffff, alpha: Float(opacity)) }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorStyleTests`
Expected: `Test run with 65 tests in 10 suites passed`.

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 54 = 1139.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle/ColorTheme+Controls.swift Tests/CreatorStyleTests/ControlThemeTests.swift
git commit -m "feat(style): ColorTheme.controlTheme — MetalUI's control tokens from the theme's roles"
```

---

### Task 8: The theme editor's model

**Files:**
- Create: `Sources/CreatorApp/ContentType+Theme.swift`, `Sources/CreatorApp/ThemeEditorModel.swift`
- Test: `Tests/CreatorAppTests/ThemeEditorModelTests.swift`

**Interfaces:**
- Consumes: everything on `ThemeStore` from Task 5; `ThemeRole` (Task 2); `HexColor(Color)` (Task 1); `FilePicker`
  (`chooseFileToOpen(_:)`, `chooseDestination(_:defaultName:)`, existing in `CreatorApp`); test helpers `ScriptedPicker`
  and `temporaryURL(_:)` (existing, `Tests/CreatorAppTests/Support/AppTestSupport.swift`).
- Produces: `ContentType.mctheme`; `@MainActor @Observable final class ThemeEditorModel` with `init(themes:
  ThemeStore)`, `themes`, `isOpen` (read-only), `message: String?` (read-only), `pendingDeleteID: ColorTheme.ID?`
  (read-only: the theme Delete… asked about), `isConfirmingDelete: Bool` (`pendingDeleteID != nil`; setting `false`
  is Cancel), `deleteTitle: String`,
  `filePicker: (any FilePicker)?`, `theme: ColorTheme`, `isEditable: Bool`, `nameText: String`, `open()`, `close()`,
  `select(_:)`, `typeName(_:)`, `commitName()`, `duplicate()`, `requestDelete()`, `confirmDelete()`,
  `setColor(_:for:)`, `colorBinding(for role: ThemeRole) -> Binding<Color>`, `setDark(_:)`,
  `importTheme(using:) async`, `exportTheme(using:) async`, `withFilePicker(_:)`.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorStyle
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// The theme editor's behaviour: it edits the shown theme through `ThemeStore`, keeps a typed name with the theme
/// it was typed for, asks before deleting, and shows each problem as one sentence.
@MainActor
struct ThemeEditorModelTests {
    func makeEditor(_ store: ThemeStore = ThemeStore()) -> ThemeEditorModel {
        ThemeEditorModel(themes: store)
    }

    @Test func openingShowsTheFoldersProblemsAndDoneCloses() throws {
        let folder = ThemeFolder(URL.temporaryDirectory.appending(path: "ThemeEditorModelTests-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: folder.fileURL(for: "junk"))
        let editor = makeEditor(ThemeStore(folder: folder))
        #expect(!editor.isOpen)
        editor.open()
        #expect(editor.isOpen)
        #expect(editor.message == "“junk.mctheme” was skipped: It isn’t a MetalCreator theme, or it is damaged.")
        editor.close()
        #expect(!editor.isOpen)
    }

    @Test func theBuiltInsAreShownButNotEditable() throws {
        let editor = makeEditor()
        #expect(editor.theme == .dracula && !editor.isEditable)
        editor.setColor(HexColor(0x000000), for: try #require(ThemeRole.named("accent")))
        #expect(editor.message == "Built-in themes can’t be changed. Duplicate one to make your own.")
        #expect(editor.theme == .dracula)
        editor.requestDelete()
        #expect(!editor.isConfirmingDelete)
    }

    @Test func duplicateMakesAnEditableCopyAndClearsTheMessage() throws {
        let editor = makeEditor()
        editor.setDark(false)
        #expect(editor.message != nil)
        editor.duplicate()
        #expect(editor.theme.name == "Dracula Copy" && editor.isEditable && editor.message == nil)
        editor.setColor(HexColor(0x00ffaa), for: try #require(ThemeRole.named("selection")))
        #expect(editor.theme.colors.selection == HexColor(0x00ffaa))
    }

    @Test func aTypedNameIsCommittedOnReturn() {
        let editor = makeEditor()
        editor.duplicate()
        editor.typeName("Midnight")
        #expect(editor.nameText == "Midnight" && editor.theme.name == "Dracula Copy")
        editor.commitName()
        #expect(editor.theme.name == "Midnight" && editor.nameText == "Midnight")
    }

    /// Review focus: a name typed, then another theme chosen from View ▸ Theme before Return: the name lands on the
    /// theme it was typed for, and the field shows the new theme's own name.
    @Test func aTypedNameStaysWithItsTheme() throws {
        let editor = makeEditor()
        editor.duplicate()
        let copy = editor.theme
        editor.typeName("Midnight")
        editor.themes.select("nord")
        #expect(editor.nameText == "Nord")
        editor.commitName()
        #expect(editor.themes.theme(copy.id)?.name == "Midnight")
        #expect(editor.theme == .nord)
    }

    @Test func aRefusedNameSaysWhyAndTheFieldShowsTheName() {
        let editor = makeEditor()
        editor.duplicate()
        editor.typeName("nord")
        editor.commitName()
        #expect(editor.message == "There’s already a theme called “nord”.")
        #expect(editor.nameText == "Dracula Copy")
    }

    @Test func closingAndSelectingCommitATypedName() {
        let editor = makeEditor()
        editor.open()
        editor.duplicate()
        let copy = editor.theme
        editor.typeName("Dusk")
        editor.select("alucard")
        #expect(editor.themes.theme(copy.id)?.name == "Dusk" && editor.theme == .alucard)
        editor.select(copy.id)
        editor.typeName("Dawn")
        editor.close()
        #expect(editor.themes.theme(copy.id)?.name == "Dawn")
    }

    @Test func deleteAsksFirst() {
        let editor = makeEditor()
        editor.duplicate()
        let copy = editor.theme
        editor.requestDelete()
        #expect(editor.isConfirmingDelete)
        editor.isConfirmingDelete = false
        #expect(editor.themes.theme(copy.id) != nil)
        editor.requestDelete()
        #expect(editor.deleteTitle == "Delete “Dracula Copy”?")
        editor.confirmDelete()
        #expect(!editor.isConfirmingDelete && editor.themes.theme(copy.id) == nil && editor.theme == .dracula)
    }

    /// Delete… asked about one theme, then another was chosen from View ▸ Theme while the confirmation was up: the
    /// confirmation still names the first, and Delete removes that one, never the one shown now.
    @Test func aDeleteConfirmationStaysWithItsTheme() {
        let editor = makeEditor()
        editor.duplicate()
        let first = editor.theme
        editor.select("nord")
        editor.duplicate()
        let second = editor.theme
        editor.select(first.id)
        editor.requestDelete()
        editor.select(second.id)
        #expect(editor.isConfirmingDelete && editor.deleteTitle == "Delete “Dracula Copy”?")
        editor.confirmDelete()
        #expect(editor.themes.theme(first.id) == nil)
        #expect(editor.themes.theme(second.id) == second && editor.theme == second)
    }

    /// The colour picker's binding reads the shown theme and writes through `setColor`.
    @Test func theColourBindingReadsAndWritesTheRole() throws {
        let editor = makeEditor()
        editor.duplicate()
        let accent = try #require(ThemeRole.named("accent"))
        let binding = editor.colorBinding(for: accent)
        #expect(HexColor(binding.wrappedValue) == HexColor(0xbd93f9))
        binding.wrappedValue = Color(.sRGB, red: 0, green: 1, blue: 2.0 / 3)
        #expect(editor.theme.colors.accent == HexColor(0x00ffaa))
    }

    @Test func importAsksForAThemeFileAndShowsTheImport() async throws {
        let url = temporaryURL("Fjord.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try ThemeStore().exportTheme("nord", to: url)
        let editor = makeEditor()
        let picker = ScriptedPicker([url])
        await editor.importTheme(using: picker)
        #expect(picker.asked.map(\.types) == [[.mctheme]])
        #expect(editor.theme.name == "Nord 2" && editor.isEditable && editor.message == nil)
    }

    @Test func aCancelledImportChangesNothing() async {
        let editor = makeEditor()
        await editor.importTheme(using: ScriptedPicker([nil]))
        #expect(editor.themes.customs.isEmpty && editor.theme == .dracula && editor.message == nil)
    }

    @Test func aRefusedImportIsShown() async throws {
        let url = temporaryURL("bad.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{ "version": 1, "colors": { "selection": "pink" } }"#.utf8).write(to: url)
        let editor = makeEditor()
        await editor.importTheme(using: ScriptedPicker([url]))
        #expect(editor.message == "“\(url.lastPathComponent)” couldn’t be imported. ‘selection’ isn’t a colour like #ff79c6.")
    }

    @Test func exportWritesTheShownThemeUnderItsName() async throws {
        let url = temporaryURL("Nord.mctheme")
        defer { try? FileManager.default.removeItem(at: url) }
        let editor = makeEditor(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "nord")))
        let picker = ScriptedPicker([url])
        await editor.exportTheme(using: picker)
        #expect(picker.asked.map(\.name) == ["Nord.mctheme"])
        #expect(try ThemeFile.decode(Data(contentsOf: url), id: "x", fallbackName: "").colors == ColorTheme.nord.colors.quantized)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorAppTests.ThemeEditorModelTests`
Expected: the build fails: cannot find `ThemeEditorModel` in scope; `ContentType` has no member `mctheme`.

- [ ] **Step 3: Implement**

`Sources/CreatorApp/ContentType+Theme.swift`:

```swift
import MetalUI

extension ContentType {
    /// A MetalCreator colour theme (Themes milestone): small JSON, saved as `.mctheme`. Not registered with the
    /// system, so the file panels match it by extension.
    public static let mctheme = ContentType("com.metalcreator.mctheme", conformingTo: [.json], filenameExtensions: ["mctheme"])
}
```

`Sources/CreatorApp/ThemeEditorModel.swift`:

```swift
import CreatorStyle
import Foundation
import MetalUI
import Observation

/// The theme editor's state and behaviour (Themes milestone). It edits the theme the window shows, so every change
/// is seen at once on the panels and in the viewport; choosing another theme in it shows that one everywhere. All
/// changes go through `ThemeStore`, which saves them; the views only forward. A problem is shown as one sentence
/// (`message`) until the next action.
@MainActor
@Observable
public final class ThemeEditorModel {
    public let themes: ThemeStore
    public private(set) var isOpen = false
    /// The last action's problem, or the themes folder's load problems when the editor opens.
    public private(set) var message: String?
    /// The theme Delete… asked about, while its confirmation is up. The confirmation deletes this one even if
    /// another theme is shown by now (View ▸ Theme stays reachable while the dialog is up).
    public private(set) var pendingDeleteID: ColorTheme.ID?
    /// The name typed into the name field and not yet committed, with the theme it was typed for.
    private var nameDraft: (id: ColorTheme.ID, text: String)?
    /// The window's open and save panels. The app sets it once the window is open.
    @ObservationIgnored public var filePicker: (any FilePicker)?

    public init(themes: ThemeStore) {
        self.themes = themes
    }

    /// The theme being edited: the one shown.
    public var theme: ColorTheme { themes.current }

    /// Whether the shown theme can be changed: built-ins are read-only (spec §6.6).
    public var isEditable: Bool { !themes.isBuiltIn(theme.id) }

    /// Delete… is waiting for its confirmation. Setting it `false` is the confirmation's Cancel.
    public var isConfirmingDelete: Bool {
        get { pendingDeleteID != nil }
        set { if !newValue { pendingDeleteID = nil } }
    }

    /// The confirmation's title: it names the theme it would delete.
    public var deleteTitle: String {
        "Delete “\(pendingDeleteID.flatMap { themes.theme($0) }?.name ?? theme.name)”?"
    }

    /// The name field's text: what was typed for this theme, else its name.
    public var nameText: String {
        if let nameDraft, nameDraft.id == theme.id { return nameDraft.text }
        return theme.name
    }

    /// View ▸ Theme ▸ Edit Themes…. It says which theme files couldn't be read, if any.
    public func open() {
        isOpen = true
        message = themes.loadProblems.isEmpty ? nil : themes.loadProblems.joined(separator: " ")
    }

    /// Done (or Escape): commits a typed name, then closes.
    public func close() {
        commitName()
        isOpen = false
        pendingDeleteID = nil
    }

    /// Shows the theme with `id`, from the editor's menu or View ▸ Theme.
    public func select(_ id: ColorTheme.ID) {
        commitName()
        themes.select(id)
        message = nil
    }

    /// A keystroke in the name field.
    public func typeName(_ text: String) {
        nameDraft = (theme.id, text)
    }

    /// Return in the name field, or the field losing focus: renames the theme the name was typed for, even if
    /// another is shown by now. A refused name says why and the field shows the theme's name again.
    public func commitName() {
        guard let draft = nameDraft else { return }
        nameDraft = nil
        perform { () throws(ThemeProblem) in try themes.rename(draft.id, to: draft.text) }
    }

    /// Duplicate: an editable copy of the shown theme, shown at once.
    public func duplicate() {
        commitName()
        perform { () throws(ThemeProblem) in _ = try themes.duplicate(theme.id) }
    }

    /// Delete…: asks first, about the shown theme.
    public func requestDelete() {
        guard isEditable else { return }
        pendingDeleteID = theme.id
    }

    /// The confirmation's Delete: deletes the theme it asked about, never one chosen since; if that one is shown,
    /// Dracula is shown instead.
    public func confirmDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        if nameDraft?.id == id { nameDraft = nil }
        perform { () throws(ThemeProblem) in try themes.delete(id) }
    }

    /// One role's new colour, from its colour picker.
    public func setColor(_ color: HexColor, for role: ThemeRole) {
        perform { () throws(ThemeProblem) in try themes.setColor(color, for: role, in: theme.id) }
    }

    /// The colour picker's binding for `role`: the shown theme's colour, and `setColor` for each write.
    public func colorBinding(for role: ThemeRole) -> Binding<Color> {
        Binding(get: { [self] in theme.colors[role].color }, set: { [self] in setColor(HexColor($0), for: role) })
    }

    /// The Dark controls toggle.
    public func setDark(_ isDark: Bool) {
        perform { () throws(ThemeProblem) in try themes.setDark(isDark, in: theme.id) }
    }

    /// Import…: the open panel, then the chosen `.mctheme` file as a new theme, shown at once.
    public func importTheme(using picker: any FilePicker) async {
        commitName()
        do {
            guard let url = try await picker.chooseFileToOpen([.mctheme]) else { return }
            perform { () throws(ThemeProblem) in _ = try themes.importTheme(from: url) }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Export…: the save panel, then the shown theme (built-in or custom) as a `.mctheme` file.
    public func exportTheme(using picker: any FilePicker) async {
        commitName()
        let theme = theme
        do {
            guard let url = try await picker.chooseDestination([.mctheme], defaultName: "\(theme.name).mctheme") else { return }
            perform { () throws(ThemeProblem) in try themes.exportTheme(theme.id, to: url) }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Runs `action` with the window's file picker, from a button.
    public func withFilePicker(_ action: @escaping @MainActor (any FilePicker) async -> Void) {
        guard let filePicker else { return }
        Task { await action(filePicker) }
    }

    /// Runs a store action: success clears the message, a problem shows it.
    private func perform(_ action: () throws(ThemeProblem) -> Void) {
        do {
            try action()
            message = nil
        } catch {
            message = error.message
        }
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorAppTests.ThemeEditorModelTests`
Expected: `Test run with 14 tests in 1 suite passed`.

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 68 = 1153.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorApp/ContentType+Theme.swift Sources/CreatorApp/ThemeEditorModel.swift \
  Tests/CreatorAppTests/ThemeEditorModelTests.swift
git commit -m "feat(app): ThemeEditorModel — the theme editor's behaviour over ThemeStore"
```

---

### Task 9: The theme editor's views and the window root

**Files:**
- Create: `Sources/CreatorApp/ThemeEditorLayout.swift`, `ThemeEditorDock.swift`, `ThemeEditorPanel.swift`,
  `ThemeEditorHeader.swift`, `ThemeEditorControls.swift`, `ThemeRoleList.swift`, `ThemeRoleSection.swift`,
  `ThemeRoleRow.swift`, `ThemeSwatch.swift`, `AppWindowRoot.swift` (all in `Sources/CreatorApp/`)
- Test: `Tests/CreatorAppTests/ThemeEditorRenderTests.swift`

**Interfaces:**
- Consumes: `ThemeEditorModel` (Task 8); `ColorTheme.controlTheme` (Task 7); `ThemeRoleGroup.roles` (Task 2);
  `GlassPanel`, `Palette(_:)`, `GraphPanelLayout.glassPadding`, `EditorModel.dock`, `.setDock(_:)` (CreatorEditor,
  existing); `DockSide` (CreatorGraph); `AppLayout.margin`, `.topBarHeight`, `.resizeHandle`, `AppModel.panelHeight`,
  `AppKeyContext.panel`, `Double.px`, `AppRoot`, `AppInput` (CreatorApp, existing); `ThemeEditorModel.deleteTitle`
  (Task 8); test helper `makeApp()` (existing).
- Produces: `public struct AppWindowRoot: Component` with `init(model: AppModel, input: AppInput, themeEditor:
  ThemeEditorModel)`; internal `ThemeEditorLayout.width` (340), `.top`, `.rowHeight`, `.swatchWidth` (40),
  `.swatchHeight` (18), `.spacing`, `ThemeEditorLayout.bottom(dock:panelHeight:) -> Double`; internal views
  `ThemeEditorDock(model:bottom:)`, `ThemeEditorPanel(model:)`,
  `ThemeRoleRow(model:role:)`.

MetalUI notes: a `Component`'s `.padding` takes one length, so the dock wraps the panel in a `ZStack` to pad it by
edges. The panel catches presses and scrolls on its glass with a clear backdrop (`DragGesture(minimumDistance: 0)` and
a claiming `.onScrollWheel`), as `SearchPaletteView` does. A headless frame is in the light scheme (the window's
`.preferredColorScheme` applies to the platform window), so the token test compares with both of MetalUI's defaults.
A rendered rect's colour is a C struct (`MUIHsla`) with `h`, `s`, `l`, `a`; the test converts it through `Hsla`.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorEditor
import CreatorKernel
import CreatorStyle
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp

/// Headless frames of the whole window with the theme editor. They prove it floats where `ThemeEditorLayout` puts
/// it, draws each role's colour, follows edits at once, and that MetalUI's own controls take the theme's tokens.
/// Looks are human checks (group TH).
@MainActor
struct ThemeEditorRenderTests {
    /// A filled rect of a frame, in window points, with its fill as the nearest bytes.
    struct Fill: Equatable {
        let x, y, width, height: Double
        let colour: HexColor
    }

    static let window = Size(width: Pixels(1400), height: Pixels(900))
    static let scale = 2.0

    /// The frame's filled rects: the whole window with the editor, or `AppRoot` alone.
    func fills(_ app: AppModel, _ editor: ThemeEditorModel? = nil) -> [Fill] {
        let input = AppInput(model: app)
        let scene = renderFrame({
            ZStack {
                if let editor {
                    AppWindowRoot(model: app, input: input, themeEditor: editor)
                } else {
                    AppRoot(model: app, input: input)
                }
            }
        }, size: Self.window, scaleFactor: Float(Self.scale), textSystem: CoreTextTextSystem(),
           atlas: GlyphAtlas(width: 1024, height: 1024))
        return scene.rects.map { rect in
            let fill = rect.background
            return Fill(x: Double(rect.bounds.origin.x) / Self.scale, y: Double(rect.bounds.origin.y) / Self.scale,
                        width: Double(rect.bounds.size.width) / Self.scale, height: Double(rect.bounds.size.height) / Self.scale,
                        colour: Self.hex(Hsla(h: fill.h, s: fill.s, l: fill.l, a: fill.a)))
        }
    }

    /// A drawn colour to its nearest bytes, to compare with a theme's.
    static func hex(_ colour: Hsla) -> HexColor {
        let rgba = colour.toRgba()
        func byte(_ value: Float) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return HexColor(byte(rgba.r) << 16 | byte(rgba.g) << 8 | byte(rgba.b), opacity: Double(byte(rgba.a)) / 255)
    }

    func makeApp() async -> (AppModel, ThemeEditorModel) {
        let app = await CreatorAppTests.makeApp()
        return (app, ThemeEditorModel(themes: app.themes))
    }

    @Test func aClosedEditorDrawsNothing() async {
        let (app, editor) = await makeApp()
        let closed = fills(app, editor)
        #expect(closed.count == fills(app).count)
        editor.open()
        #expect(fills(app, editor).count > closed.count)
    }

    @Test func theEditorFloatsAtTheTopRightBelowTheTopBarAndFillsTheHeight() async {
        let (app, editor) = await makeApp()
        editor.open()
        let width = ThemeEditorLayout.width + 2 * GraphPanelLayout.glassPadding
        let x = Double(Self.window.width.value) - AppLayout.margin - width
        let height = Double(Self.window.height.value) - ThemeEditorLayout.top - AppLayout.margin
        let glass = fills(app, editor).filter { fill in
            fill.colour == Palette.dracula.glass.quantized && abs(fill.x - x) < 1 && abs(fill.y - ThemeEditorLayout.top) < 1
        }
        #expect(glass.count == 1, "one glass panel at (\(x), \(ThemeEditorLayout.top))")
        #expect(glass.allSatisfy { abs($0.width - width) < 1 && abs($0.height - height) < 1 })
    }

    /// With the graph panel docked at the bottom, the editor stops a margin above the panel's resize handle, so it
    /// never covers the graph panel.
    @Test func theEditorStopsAboveAGraphPanelDockedAtTheBottom() async {
        let (app, editor) = await makeApp()
        app.editor.setDock(.bottom)
        editor.open()
        let width = ThemeEditorLayout.width + 2 * GraphPanelLayout.glassPadding
        let x = Double(Self.window.width.value) - AppLayout.margin - width
        let windowHeight = Double(Self.window.height.value)
        let graphTop = windowHeight - AppLayout.margin - app.panelHeight
        let height = graphTop - AppLayout.resizeHandle - AppLayout.margin - ThemeEditorLayout.top
        let glass = fills(app, editor).filter { fill in
            fill.colour == Palette.dracula.glass.quantized && abs(fill.x - x) < 1 && abs(fill.y - ThemeEditorLayout.top) < 1
        }
        #expect(glass.count == 1, "one glass panel at (\(x), \(ThemeEditorLayout.top))")
        #expect(glass.allSatisfy { abs($0.height - height) < 1 && $0.y + $0.height < graphTop })
    }

    @Test func theSwatchesShowTheShownThemesColoursAndFollowAnEdit() async throws {
        let (app, editor) = await makeApp()
        editor.select("nord")
        editor.duplicate()
        editor.open()
        func swatches() -> [HexColor] {
            fills(app, editor).filter { fill in
                abs(fill.width - ThemeEditorLayout.swatchWidth) < 0.5 && abs(fill.height - ThemeEditorLayout.swatchHeight) < 0.5
                    && fill.colour.opacity > 0
            }.map(\.colour)
        }
        let surfaces = ThemeRoleGroup.surfaces.roles.map { editor.theme.colors[$0].quantized }
        #expect(Array(swatches().prefix(surfaces.count)) == surfaces, "the first rows are the surfaces, in order")
        editor.setColor(HexColor(0x00ffaa), for: try #require(ThemeRole.named("backgroundTop")))
        #expect(swatches().first == HexColor(0x00ffaa))
    }

    /// MetalUI's own controls (the top bar's buttons, filled with the `surfaceSecondary` token) draw the theme's
    /// tokens, not MetalUI's defaults.
    @Test func metalUIsControlsTakeTheThemesTokens() async {
        let (app, editor) = await makeApp()
        let defaults = [Theme.light.surfaceSecondary, Theme.dark.surfaceSecondary].map(Self.hex)
        #expect(fills(app).contains { defaults.contains($0.colour) }, "without the tokens a button is MetalUI's own")
        let dracula = Set(fills(app, editor).map(\.colour))
        #expect(dracula.isDisjoint(with: defaults))
        #expect(dracula.contains(Self.hex(ColorTheme.dracula.controlTheme.surfaceSecondary)))
        app.themes.select("alucard")
        let alucard = Set(fills(app, editor).map(\.colour))
        #expect(alucard.contains(Self.hex(ColorTheme.alucard.controlTheme.surfaceSecondary)))
        #expect(!alucard.contains(Self.hex(ColorTheme.dracula.controlTheme.surfaceSecondary)))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorAppTests.ThemeEditorRenderTests`
Expected: the build fails: cannot find `AppWindowRoot` and `ThemeEditorLayout` in scope.

- [ ] **Step 3: Implement**

`Sources/CreatorApp/ThemeEditorLayout.swift`:

```swift
import CreatorGraph

/// The theme editor's layout numbers. It floats at the window's top-right corner, below the top bar, over the
/// inspector, and runs down to the window's bottom margin, or to just above the graph panel when that is docked at
/// the bottom, so the panel stays whole.
enum ThemeEditorLayout {
    /// The editor's content column, inside its glass padding.
    static let width = 340.0
    /// The panel's distance from the window's top edge: below the top bar.
    static let top = AppLayout.margin * 2 + AppLayout.topBarHeight
    /// A role's row.
    static let rowHeight = 24.0
    /// A role's swatch.
    static let swatchWidth = 40.0
    static let swatchHeight = 18.0
    /// Between the editor's sections.
    static let spacing = 8.0

    /// The panel's distance from the window's bottom edge: a margin, or, over a graph panel docked at the bottom, a
    /// margin above that panel's resize handle (`AppLayout.graphPanelFrame`, `PanelArea`).
    static func bottom(dock: DockSide, panelHeight: Double) -> Double {
        switch dock {
        case .bottom: AppLayout.margin + panelHeight + AppLayout.resizeHandle + AppLayout.margin
        case .left, .hidden: AppLayout.margin
        }
    }
}
```

`Sources/CreatorApp/ThemeEditorDock.swift`:

```swift
import MetalUI

/// The theme editor (Themes milestone), floating at the window's top-right corner below the top bar, over the
/// inspector and down to `bottom` points from the window's bottom edge (above a graph panel docked at the bottom,
/// `ThemeEditorLayout.bottom(dock:panelHeight:)`), so the graph panel and the viewport show each change as it is made. Drawn over everything else in
/// the window (`AppWindowRoot`); nothing while it is closed. It contributes the `AppKeyContext.panel` key context,
/// so the viewport's F, + and − type into its name field (gap M4-a), as they do in the other panels.
struct ThemeEditorDock: Component {
    let model: ThemeEditorModel
    /// The panel's distance from the window's bottom edge.
    let bottom: Double

    var content: some ElementGroup {
        Stack(alignment: .topTrailing) {
            if model.isOpen {
                ZStack(alignment: .topTrailing) { ThemeEditorPanel(model: model) }
                    .padding(Edges(top: ThemeEditorLayout.top.px, right: AppLayout.margin.px, bottom: bottom.px,
                                   left: Pixels(0)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .keyContext(AppKeyContext.panel)
    }
}
```

`Sources/CreatorApp/ThemeEditorPanel.swift`:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// The theme editor's glass panel: its header, the theme's controls, the last problem, and every role's colour
/// under its group's heading, scrolling. A press or a scroll on its glass is caught here, so it never reaches the
/// viewport or the inspector beneath. Delete… asks first, naming the theme it asked about.
struct ThemeEditorPanel: Component {
    let model: ThemeEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let width = ThemeEditorLayout.width + 2 * GraphPanelLayout.glassPadding
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Pixels(0)))
                .onScrollWheel { _ in true }
            GlassPanel {
                VStack(alignment: .leading, spacing: ThemeEditorLayout.spacing.px) {
                    ThemeEditorHeader(model: model)
                    ThemeEditorControls(model: model)
                    if let message = model.message {
                        Text(message).font(.caption).foregroundStyle(palette.statusError.color)
                    }
                    ScrollView {
                        ThemeRoleList(model: model)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: ThemeEditorLayout.width.px)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: width.px)
        .frame(maxHeight: .infinity, alignment: .top)
        .confirmationDialog(model.deleteTitle, isPresented: Binding(get: { model.isConfirmingDelete },
                                                                    set: { model.isConfirmingDelete = $0 })) {
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.isConfirmingDelete = false }
        } message: {
            Text("Its file is removed from the themes folder. Export it first to keep a copy.")
        }
    }
}
```

`Sources/CreatorApp/ThemeEditorHeader.swift`:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// "Themes" and Done (Escape), which commits a typed name and closes the editor.
struct ThemeEditorHeader: Component {
    let model: ThemeEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        HStack(spacing: ThemeEditorLayout.spacing.px) {
            Text("Themes").font(.headline).foregroundStyle(Palette(themes).primaryText.color)
            Spacer()
            Button("Done") { model.close() }
                .keyboardShortcut(.escape, modifiers: [])
        }
    }
}
```

`Sources/CreatorApp/ThemeEditorControls.swift`:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// The shown theme: a menu of every theme, Duplicate, Delete…, Import… and Export…, its name and its Dark controls
/// toggle. A built-in's name and toggle are disabled, with a line saying how to make it your own.
struct ThemeEditorControls: Component {
    let model: ThemeEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
    @FocusState var nameFocused: Bool

    var content: some ElementGroup {
        let palette = Palette(themes)
        return VStack(alignment: .leading, spacing: ThemeEditorLayout.spacing.px) {
            Picker("Theme", selection: Binding(get: { model.theme.id }, set: { model.select($0) })) {
                ForEach(model.themes.themes, id: \.id) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
            .pickerStyle(.menu)
            HStack(spacing: ThemeEditorLayout.spacing.px) {
                Button("Duplicate") { model.duplicate() }
                Button("Delete…") { model.requestDelete() }
                    .disabled(!model.isEditable)
                Button("Import…") { model.withFilePicker { await model.importTheme(using: $0) } }
                Button("Export…") { model.withFilePicker { await model.exportTheme(using: $0) } }
            }
            HStack(spacing: ThemeEditorLayout.spacing.px) {
                Text("Name").font(.callout).foregroundStyle(palette.primaryText.color)
                TextField("Name", text: model.nameText, onChange: { model.typeName($0) })
                    .focused($nameFocused)
                    .onSubmit { model.commitName() }
                    .disabled(!model.isEditable)
            }
            .onChange(of: nameFocused) { wasFocused, focused in
                if wasFocused, !focused { model.commitName() }
            }
            Toggle("Dark controls", isOn: Binding(get: { model.theme.isDark }, set: { model.setDark($0) }))
                .disabled(!model.isEditable)
            if !model.isEditable {
                Text("Built-in themes are read-only. Duplicate one to make it your own.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
    }
}
```

`Sources/CreatorApp/ThemeRoleList.swift`:

```swift
import CreatorStyle
import MetalUI

/// Every role of the shown theme, under its group's heading, in `ThemeColors`' order.
struct ThemeRoleList: Component {
    let model: ThemeEditorModel

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: ThemeEditorLayout.spacing.px) {
            ForEach(ThemeRoleGroup.allCases, id: \.id) { group in
                ThemeRoleSection(model: model, group: group)
            }
        }
    }
}
```

`Sources/CreatorApp/ThemeRoleSection.swift`:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// One group's heading and its roles' rows.
struct ThemeRoleSection: Component {
    let model: ThemeEditorModel
    let group: ThemeRoleGroup
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(2)) {
            Text(group.title.uppercased())
                .font(.caption2)
                .foregroundStyle(Palette(themes).secondaryText.color)
            ForEach(group.roles, id: \.id) { role in
                ThemeRoleRow(model: model, role: role)
            }
        }
    }
}
```

`Sources/CreatorApp/ThemeRoleRow.swift`:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// One role: its title, its colour as hex and a swatch of it.
struct ThemeRoleRow: Component {
    let model: ThemeEditorModel
    let role: ThemeRole
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let colour = model.theme.colors[role]
        return HStack(spacing: ThemeEditorLayout.spacing.px) {
            Text(role.title).font(.callout).foregroundStyle(palette.primaryText.color)
            Spacer()
            Text(colour.hex).font(.caption).foregroundStyle(palette.secondaryText.color)
            ThemeSwatch(colour: colour)
        }
        .frame(height: ThemeEditorLayout.rowHeight.px)
    }
}
```

`Sources/CreatorApp/ThemeSwatch.swift`:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// A role's colour as a small rounded swatch with the glass hairline around it.
struct ThemeSwatch: Component {
    let colour: HexColor
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let shape = RoundedRectangle(cornerRadius: Pixels(4))
        return Color.clear
            .frame(width: ThemeEditorLayout.swatchWidth.px, height: ThemeEditorLayout.swatchHeight.px)
            .background(colour.color, in: shape)
            .overlay { shape.strokeBorder(Palette(themes).hairline.color, lineWidth: Pixels(1)) }
    }
}
```

`Sources/CreatorApp/AppWindowRoot.swift`:

```swift
import CreatorStyle
import MetalUI

/// The window's root (spec §6.1, Themes milestone): the app (`AppRoot`) with the theme editor floating over
/// everything, all drawn in the shown theme, including MetalUI's own controls (`ColorTheme.controlTheme`), so its
/// buttons, fields, menus and pickers match the panels and follow each theme edit at once.
public struct AppWindowRoot: Component {
    public let model: AppModel
    public let input: AppInput
    public let themeEditor: ThemeEditorModel

    public init(model: AppModel, input: AppInput, themeEditor: ThemeEditorModel) {
        self.model = model
        self.input = input
        self.themeEditor = themeEditor
    }

    public var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            AppRoot(model: model, input: input)
            ThemeEditorDock(model: themeEditor,
                            bottom: ThemeEditorLayout.bottom(dock: model.editor.dock, panelHeight: model.panelHeight))
        }
        .environment(model.themes)
        .theme(model.themes.current.controlTheme)
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `swift test --filter CreatorAppTests.ThemeEditorRenderTests`
Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 5: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 73 = 1158.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorApp/ThemeEditorLayout.swift Sources/CreatorApp/ThemeEditorDock.swift \
  Sources/CreatorApp/ThemeEditorPanel.swift Sources/CreatorApp/ThemeEditorHeader.swift \
  Sources/CreatorApp/ThemeEditorControls.swift Sources/CreatorApp/ThemeRoleList.swift \
  Sources/CreatorApp/ThemeRoleSection.swift Sources/CreatorApp/ThemeRoleRow.swift Sources/CreatorApp/ThemeSwatch.swift \
  Sources/CreatorApp/AppWindowRoot.swift Tests/CreatorAppTests/ThemeEditorRenderTests.swift
git commit -m "feat(app): the theme editor's floating panel and AppWindowRoot with MetalUI's tokens from the theme"
```

---

### Task 10: View ▸ Theme, the app's wiring, and the docs

**Files:**
- Create: `Sources/CreatorApp/ThemeMenu.swift`, `Sources/CreatorApp/AppThemes.swift`
- Modify: `Sources/CreatorApp/AppCommands.swift` (shared), `Sources/MetalCreatorApp/main.swift` (shared),
  `CLAUDE.md`, `AGENTS.md`, `docs/superpowers/roadmap.md`,
  `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `docs/metalui-gaps.md`,
  `docs/verification/human-checks.md` (all shared)
- Test: `Tests/CreatorAppTests/ThemeMenuTests.swift`

**Interfaces:**
- Consumes: `ThemeEditorModel` (Task 8), `AppWindowRoot` (Task 9), `ThemeStore.customs` (Task 5),
  `UserDefaultsThemePreferences` (Task 6), `ThemeFolder.applicationSupport` (Task 4).
- Produces: `ThemeMenu.sections(_ themes: ThemeStore) -> [[ColorTheme]]`, `ThemeMenu.items(_ editor:) -> MenuItems`;
  `AppThemes.store() -> ThemeStore`; `AppCommands.install(on: App, model: AppModel, themeEditor: ThemeEditorModel)`
  (was `install(on:model:)`; `main.swift` is its only caller).

`main.swift` doesn't import `CreatorStyle` (its target doesn't depend on it, and `Package.swift` stays as it is), so
the app's store is made by `AppThemes.store()` in `CreatorApp`.

- [ ] **Step 1: Write the failing test**

```swift
import CreatorStyle
import Testing
@testable import CreatorApp

/// View ▸ Theme lists the built-ins, then the custom themes by name, each group divided from the next.
@MainActor
struct ThemeMenuTests {
    @Test func withoutCustomThemesTheMenuListsTheBuiltIns() {
        #expect(ThemeMenu.sections(ThemeStore()) == [ColorTheme.builtIns])
    }

    @Test func customThemesFollowTheBuiltInsByName() throws {
        let store = ThemeStore()
        let zebra = try store.duplicate("nord")
        try store.rename(zebra.id, to: "Zebra")
        try store.duplicate("alucard")
        #expect(ThemeMenu.sections(store).map { $0.map(\.name) } == [["Dracula", "Alucard", "Nord"], ["Alucard Copy", "Zebra"]])
        try store.delete(zebra.id)
        #expect(ThemeMenu.sections(store).map { $0.map(\.name) } == [["Dracula", "Alucard", "Nord"], ["Alucard Copy"]])
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorAppTests.ThemeMenuTests`
Expected: the build fails: cannot find `ThemeMenu` in scope.

- [ ] **Step 3: Implement the menu and the app's store**

`Sources/CreatorApp/ThemeMenu.swift`:

```swift
import CreatorStyle
import MetalUI

/// View ▸ Theme (spec §6.6, Themes milestone): the built-in themes, then the person's own, each with a checkmark on
/// the one shown and shown at once when chosen, then Edit Themes…, which opens the theme editor. Rebuilt each time
/// the menu opens, so a new, renamed or deleted theme is listed as it is.
enum ThemeMenu {
    /// The menu's groups of themes, divided in the menu: the built-ins, then the custom themes if there are any.
    /// (What the menu lists is tested here: MetalUI can't evaluate menu content outside itself, gap TH-a.)
    @MainActor
    static func sections(_ themes: ThemeStore) -> [[ColorTheme]] {
        themes.customs.isEmpty ? [themes.builtIns] : [themes.builtIns, themes.customs]
    }

    @MainActor
    @MenuContentBuilder
    static func items(_ editor: ThemeEditorModel) -> MenuItems {
        for section in sections(editor.themes) {
            for theme in section {
                // Choosing the checked theme writes `false`; selecting it again changes nothing.
                Toggle(theme.name, isOn: Binding(get: { editor.theme.id == theme.id }, set: { _ in editor.select(theme.id) }))
            }
            Divider()
        }
        Button("Edit Themes…") { editor.open() }
    }
}
```

`Sources/CreatorApp/AppThemes.swift`:

```swift
import CreatorStyle

/// The app's themes (Themes milestone): the chosen one remembered in the person's defaults, their own themes in
/// `~/Library/Application Support/MetalCreator/Themes`. Only the app makes this store; tests and previews make
/// theirs with in-memory preferences and no folder.
public enum AppThemes {
    @MainActor
    public static func store() -> ThemeStore {
        ThemeStore(preferences: UserDefaultsThemePreferences(), folder: .applicationSupport)
    }
}
```

- [ ] **Step 4: Wire them into the menu bar and the window**

In `Sources/CreatorApp/AppCommands.swift`, replace the doc comment's last three lines and the signature:

```swift
/// the document (`AppModel.undo()`, which commits a typed value first), and View ▸ Theme, the built-in themes with
/// a checkmark on the current one (spec §6.6). Commands run when nothing in the window claims their key first (a
/// focused field keeps its own editing keys).
public enum AppCommands {
    @MainActor
    public static func install(on app: App, model: AppModel) {
```

with:

```swift
/// the document (`AppModel.undo()`, which commits a typed value first), and View ▸ Theme (`ThemeMenu`: every theme
/// with a checkmark on the current one, and Edit Themes…, spec §6.6). Commands run when nothing in the window claims
/// their key first (a focused field keeps its own editing keys).
public enum AppCommands {
    @MainActor
    public static func install(on app: App, model: AppModel, themeEditor: ThemeEditorModel) {
```

and replace the Theme menu:

```swift
                Menu("Theme") {
                    for theme in model.themes.builtIns {
                        // Choosing the checked theme writes `false`; selecting it again changes nothing.
                        Toggle(theme.name, isOn: Binding(get: { model.themes.current.id == theme.id },
                                                         set: { _ in model.themes.select(theme.id) }))
                    }
                }
```

with:

```swift
                Menu("Theme") { ThemeMenu.items(themeEditor) }
```

In `Sources/MetalCreatorApp/main.swift`, replace the doc comment's first two lines:

```swift
/// `swift run MetalCreatorApp [path.mcgraph]`: the app (spec §6.1, M6). It opens the window over the OCCT kernel,
/// installs the menu bar and the window's input hooks, and opens the file named on the command line, if any.
```

with:

```swift
/// `swift run MetalCreatorApp [path.mcgraph]`: the app (spec §6.1, M6). It loads the app's themes (the remembered
/// one and the person's own), opens the window over the OCCT kernel, installs the menu bar and the window's input
/// hooks, and opens the file named on the command line, if any.
```

replace:

```swift
    let model = AppModel(kernel: OCCTKernel())
    let input = AppInput(model: model)
    AppCommands.install(on: app, model: model)
```

with:

```swift
    let model = AppModel(kernel: OCCTKernel(), themes: AppThemes.store())
    let themeEditor = ThemeEditorModel(themes: model.themes)
    let input = AppInput(model: model)
    AppCommands.install(on: app, model: model, themeEditor: themeEditor)
```

replace the window's root:

```swift
        ZStack { AppRoot(model: model, input: input) }
```

with:

```swift
        ZStack { AppWindowRoot(model: model, input: input, themeEditor: themeEditor) }
```

and after `model.filePicker = WindowFilePicker(window: window)` add:

```swift
    themeEditor.filePicker = model.filePicker
```

The whole file afterwards:

```swift
import CreatorApp
import CreatorOCCT
import Foundation
import MetalUI

/// `swift run MetalCreatorApp [path.mcgraph]`: the app (spec §6.1, M6). It loads the app's themes (the remembered
/// one and the person's own), opens the window over the OCCT kernel, installs the menu bar and the window's input
/// hooks, and opens the file named on the command line, if any.
/// `app.run()` is called from synchronous top-level code, as MetalUI requires.
@MainActor
func runApp(opening path: String?) throws {
    let app = try App()
    app.preferredColorScheme = .dark
    let model = AppModel(kernel: OCCTKernel(), themes: AppThemes.store())
    let themeEditor = ThemeEditorModel(themes: model.themes)
    let input = AppInput(model: model)
    AppCommands.install(on: app, model: model, themeEditor: themeEditor)
    let window = try app.openWindow(title: "MetalCreator", size: Size(width: Pixels(1440), height: Pixels(900)),
                                    minSize: Size(width: Pixels(1000), height: Pixels(640))) {
        // A window's root must be an Element, and a Component is a group, so it's wrapped.
        ZStack { AppWindowRoot(model: model, input: input, themeEditor: themeEditor) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    input.install(on: window)
    model.filePicker = WindowFilePicker(window: window)
    themeEditor.filePicker = model.filePicker
    if let path {
        do {
            try model.open(URL(fileURLWithPath: path))
        } catch {
            model.alert = .problem(error)
        }
    }
    app.run()
}

/// `--self-test` (packaging): the checks run in a main-actor task, which the main run loop drains because this is
/// called from synchronous top-level code; the task exits the process.
@MainActor
func runSelfTest() -> Never {
    Task { @MainActor in
        let scratch = URL.temporaryDirectory.appending(path: "MetalCreator-self-test-\(UUID().uuidString)")
        let report = await SelfTest.run(kernel: OCCTKernel(), scratch: scratch)
        print(report.text)
        exit(report.passed ? 0 : 1)
    }
    while true {
        RunLoop.main.run()
    }
}

/// Writes `text` and a newline to standard error.
func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

switch LaunchCommand(arguments: Array(CommandLine.arguments.dropFirst())) {
case .run(let path):
    try runApp(opening: path)
case .version:
    print(AppBundleInfo.versionLine)
case .selfTest:
    runSelfTest()
case .infoPlist(let minimum):
    FileHandle.standardOutput.write(try AppBundleInfo.infoPlistData(minimumSystemVersion: minimum))
case .usageError(let message):
    printError(message + "\n" + LaunchCommand.usage)
    exit(64)
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift build` (no new warnings), then `swift test --filter CreatorAppTests.ThemeMenuTests`
Expected: `Test run with 2 tests in 1 suite passed`.

- [ ] **Step 6: Update the docs**

`CLAUDE.md`, under "Project state", after the Packaging line, add:

```markdown
Themes (custom themes, `.mctheme` files, the theme editor) code is done; its human checks (group TH) are pending.
```

In the `CreatorStyle` bullet, replace its last four lines (from "`.dracula`, `.alucard` and `.nord`; `@MainActor
@Observable ThemeStore` holds `current` and `select(_:)`, with injected" to "Tests: `swift test --filter
CreatorStyleTests`.") with:

```markdown
  `.dracula`, `.alucard` and `.nord` (read-only); `ThemeRole` names each role (`ThemeColors[role]`; the names are the
  `.mctheme` keys; `ThemeRoleTests` pins them to the stored properties). `@MainActor @Observable ThemeStore` holds
  `current`, `select(_:)` and the custom themes (`customs`: duplicate, rename, `setColor`, `setDark`, delete, import,
  export), saving each change to an injected `ThemeFolder` before showing it (`nil`: memory only, every test's), with
  injected `ThemePreferences` (`UserDefaultsThemePreferences` in the app). `ThemeFile` is the `.mctheme` format
  (version 1; missing roles are Dracula's, unknown ones ignored, a bad colour refused naming its role); custom themes'
  colours are always `quantized` (opacity to a byte) so a file round-trips exactly. `ColorTheme.controlTheme` maps
  roles onto MetalUI's control tokens. Editor and app views read `@Environment(ThemeStore.self) var themes:
  ThemeStore?` and draw `Palette(themes)` (Dracula without a store); the viewport draws `ViewportModel.theme`, which the
  app shell sets. Themes are app-level, never in `.mcgraph`. Tests: `swift test --filter CreatorStyleTests`.
```

In the `CreatorApp` bullet, replace these two lines:

```markdown
  `MetalCreatorApp` is the executable (`OCCTKernel`). It owns the app's `ThemeStore` (View ▸ Theme) and provides it
  to every view with `.environment(model.themes)`. `LaunchCommand` parses its command line: a file to open, or the
```

with:

```markdown
  `MetalCreatorApp` is the executable (`OCCTKernel`). It makes the app's `ThemeStore` (`AppThemes.store()`: user
  defaults, `~/Library/Application Support/MetalCreator/Themes`) and its `ThemeEditorModel`, and opens the window on
  `AppWindowRoot`: `AppRoot` with the theme editor (`ThemeEditorDock`, a floating glass panel at the top right) over
  it, the store in the environment and `.theme(current.controlTheme)` for MetalUI's controls. View ▸ Theme is
  `ThemeMenu` (every theme, then Edit Themes…). `LaunchCommand` parses its command line: a file to open, or the
```

and in "Commands" replace the `CreatorStyleTests` line's comment with
`# colour themes: built-ins, roles, .mctheme files, the folder, ThemeStore`.

Make the same edits to `AGENTS.md`, which mirrors `CLAUDE.md` but lags it (it has no Editor polish, Packaging or
`LaunchCommand` lines):

- after its line "M6 (app shell) code is done; its human checks (group M6) are pending." add the same Themes line;
- in its `CreatorStyle` bullet, the same replacement (its four old lines are the same as `CLAUDE.md`'s);
- in its `CreatorApp` bullet, replace its last two lines:

```markdown
  `MetalCreatorApp` is the executable (`OCCTKernel`). It owns the app's `ThemeStore` (View ▸ Theme) and provides it
  to every view with `.environment(model.themes)`.
```

with the same five lines as `CLAUDE.md`'s, ending at "`ThemeMenu` (every theme, then Edit Themes…)." (no
`LaunchCommand` text follows in `AGENTS.md`);
- in its "Commands", the same `CreatorStyleTests` comment.

In `docs/superpowers/roadmap.md`, in the "Themes" row, replace the status cell `⏳ after M6` with
`✅ code done; human checks TH pending (Task 11 needs MetalUI C10)`.

Append to the spec (`docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`), after the last
Errata section:

```markdown
## Errata (Themes)

Plan `2026-10-09-themes-editor.md` (roadmap row "Themes").

- §6.6's "Custom themes and `.mctheme` files are the Themes milestone after M6" is done. Any theme can be duplicated
  ("<name> Copy", then "… Copy 2"); a copy is renamed, recoloured role by role, switched between dark and light
  controls, deleted (after a confirmation), exported and imported. The built-ins Dracula, Alucard and Nord stay
  read-only. View ▸ Theme lists the built-ins, then the custom themes by name, then Edit Themes….
- A `.mctheme` file is small JSON: `version` (1), `name`, `dark` and `colors`, a `#rrggbb` (or, translucent,
  `#rrggbbaa`) per role keyed by `ThemeColors`' property names. A missing role is Dracula's, an unknown role is
  ignored, a missing `dark` follows the panel base's lightness, a missing name is the file's name, and a colour that
  isn't one is refused plainly ("‘selection’ isn’t a colour like #ff79c6."). A newer version, or a file that isn't a
  theme, is refused with a sentence. An import never replaces a theme: a taken name becomes "<name> 2".
- Custom themes live in `~/Library/Application Support/MetalCreator/Themes`, one `<id>.mctheme` per theme (the id
  survives renames); a file that can't be read is skipped and the editor says which and why. Each change is saved at
  once. The chosen theme is remembered in the user's defaults (`selectedThemeID`), which replaces Errata (M6)'s "isn't
  remembered between launches either"; a remembered theme that is gone falls back to Dracula. Themes are still
  app-level and never in a `.mcgraph`.
- The theme editor is a floating glass panel at the window's top right, below the top bar and over the inspector,
  down to the window's bottom margin or, with the graph panel docked at the bottom, to a margin above it, so the graph
  panel and the viewport show each edit as it is made (a second window would end the app when closed until
  MetalUI C8 lane 2, and MetalUI has no sheet). It lists every role under its group with its colour; each role is
  edited with MetalUI's `ColorPicker` (gap M6-f, MetalUI C10 lane 1).
- MetalUI's own controls follow the theme: `ColorTheme.controlTheme` maps roles onto its tokens (background ←
  background bottom, surface ← node body, surfaceSecondary ← field, accent ← accent, separator ← comment,
  textPrimary ← foreground) for `.theme(_:)` over the window.
```

In `docs/metalui-gaps.md`, gap M6-f, after "Wanted: `ColorPicker` over MetalUI's `Color`." add:

```markdown
**Being fixed by MetalUI C10
  lane 1** (`feat/controls-looks`: `ColorPicker(_:selection:supportsOpacity:)` and its drawn panel, rulings `LK-C`,
  `LK-D`, `LK-P`). The Themes plan (`2026-10-09-themes-editor.md`) adopts it in its last task once C10 is merged; until
  then the editor shows each role's hex and a swatch, and colours change only by import, with no hex-field stopgap.
```

and append at the end of the file:

```markdown
## Hit by the Themes milestone, 2026-10-09

Labelled TH-a… so they don't clash with the labels above. Checked against MetalUI `67a579e`.

- **TH-a. Menu content can't be evaluated outside MetalUI.** View ▸ Theme is built from the store each time it
  opens (the built-ins, a divider, the custom themes, a divider, Edit Themes…), and a test should check what it lists,
  which item is checked, and that choosing one runs its action. `MenuContent`'s only requirement is SPI and
  `MenuNode` is internal (`MN-D` item 1), so a client test can't read a `CommandMenu`'s or a `Menu`'s items. Stopgap:
  `ThemeMenu.sections(_:)` returns the themes it lists, which `ThemeMenuTests` checks; the builder only turns them into
  items. Wanted: a public read-only evaluation of menu content (titles, enabled, `isOn`, shortcut, and a way to run an
  item), or one in a test-support product (with M6-e's headless window).
```

Append at the end of `docs/verification/human-checks.md`:

```markdown
## Group TH — themes: custom themes, `.mctheme` files and the theme editor

**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Your own themes are saved in
`~/Library/Application Support/MetalCreator/Themes`; move that folder aside first to start clean, and back afterwards.

- [ ] **TH-1 The editor.** View ▸ Theme lists Dracula, Alucard and Nord, then Edit Themes…. Choose it: a glass panel
  opens at the top right below the top bar, over the inspector, as tall as the window allows, and lists every role
  under its group with its hex and a swatch; it scrolls. Dracula's name field and Dark controls toggle are disabled and
  a line says built-ins are read-only. Drag or scroll on the panel: the viewport neither orbits nor zooms. Done (or
  Escape) closes it. Dock the graph at the bottom (Bottom) and open the editor again: it ends a margin above the graph
  panel, which stays whole; drag the panel's top edge up and down: the editor follows. On the Chamfer, press "Pick
  edges in view…", then open the editor: the first Escape cancels the pick (the banner's Cancel runs first) and the
  editor stays open; a second Escape closes it. Pinned:
  `theEditorFloatsAtTheTopRightBelowTheTopBarAndFillsTheHeight`, `theEditorStopsAboveAGraphPanelDockedAtTheBottom`.
  **Observed:**
- [ ] **TH-2 Duplicate, rename, dark.** Duplicate: "Dracula Copy" is shown and View ▸ Theme lists it after a divider.
  Type "Midnight" in the name field (F, + and − type, the viewport doesn't frame or zoom) and press Return: the
  editor's menu and View ▸ Theme say "Midnight". Type "nord" and press Return: "There’s already a theme called “nord”."
  and the field shows "Midnight" again. Turn Dark controls off: the window and its buttons turn light. Pinned:
  `ThemeEditorModelTests`. **Observed:**
- [ ] **TH-3 Colours (needs MetalUI C10 merged).** Click a role's colour well: MetalUI's colour panel opens. Drag in
  its square: the role's colour changes as you drag, on the panels and in the viewport (try Selection, Solid nodes,
  Shading). Glass, Glass hairline and Edges offer opacity, others don't. With VoiceOver on, move to a role's well: it
  reads the role's name (e.g. "Selection"), then "colour well" and its value. Quit and relaunch: Midnight is shown,
  with your colours. Pinned: `theColourBindingReadsAndWritesTheRole`, `manyQuickEditsKeepTheLastColour`. **Observed:**
- [ ] **TH-4 Export and import.** Export… offers "Midnight.mctheme"; save it to the Desktop and open it in a text
  editor: small JSON, every role as `#rrggbb`. Change `"selection"` to `"pink"` and save as `bad.mctheme`; Import…
  it: "“bad.mctheme” couldn’t be imported. ‘selection’ isn’t a colour like #ff79c6." Import `Midnight.mctheme`:
  "Midnight 2" is shown. Pinned: `ThemeImportExportTests`. **Observed:**
- [ ] **TH-5 Delete and launch.** Delete… asks first; Cancel keeps it, Delete removes it and Dracula is shown. With
  two custom themes, press Delete… on one, choose the other from View ▸ Theme, then press Delete: the first is
  removed, the one shown stays. Choose Nord, quit and relaunch: Nord is shown. Put a file named `junk.mctheme`
  containing "nope" in the themes folder and relaunch: the app starts, and Edit Themes… says “junk.mctheme” was
  skipped and why. Pinned: `aDeleteConfirmationStaysWithItsTheme`, `filesThatCantBeReadAreReported`,
  `theRememberedCustomThemeIsShownAtLaunchAndAGoneOneFallsBackToDracula`. **Observed:**
- [ ] **TH-6 MetalUI's controls follow the theme.** In each built-in and in a custom theme, the top bar's buttons, the
  Preview and Export menus, the inspector's fields and sliders, and the editor's own controls are drawn in the theme's
  colours (Dracula: node-body grey buttons, purple accent), not MetalUI's blue defaults. Pinned:
  `metalUIsControlsTakeTheThemesTokens`. **Observed:**
```

- [ ] **Step 7: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 75 = 1160. Then run the app once
(`swift run MetalCreatorApp`), choose View ▸ Theme ▸ Edit Themes…, and quit: it opens and nothing crashes (the
group TH checks are the human's).

- [ ] **Step 8: Commit**

```bash
git add Sources/CreatorApp/ThemeMenu.swift Sources/CreatorApp/AppThemes.swift Sources/CreatorApp/AppCommands.swift \
  Sources/MetalCreatorApp/main.swift Tests/CreatorAppTests/ThemeMenuTests.swift CLAUDE.md AGENTS.md \
  docs/superpowers/roadmap.md docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md \
  docs/metalui-gaps.md docs/verification/human-checks.md
git commit -m "feat(app): View ▸ Theme lists custom themes and opens the editor; themes remembered; docs, gap TH-a"
```

---

### Task 11: Each role's `ColorPicker` — needs MetalUI C10 merged

**Needs MetalUI C10 merged** into MetalUI master (`ColorPicker`, `feat/controls-looks`). Don't start it before:
`grep -l "public struct ColorPicker" ../MetalUI/Sources/MetalUI/ColorPicker.swift` must find the file on the
MetalUI checkout MetalCreator builds against. Everything before this task works on MetalUI master `67a579e`.

**Files:**
- Modify: `Sources/CreatorApp/ThemeRoleRow.swift` (whole file below), `Sources/CreatorApp/ThemeEditorLayout.swift`
  (the swatch numbers go), `Tests/CreatorAppTests/ThemeEditorRenderTests.swift` (the swatch test becomes the well
  test), `docs/metalui-gaps.md` (M6-f), `docs/verification/human-checks.md` (TH-1, TH-3)
- Delete: `Sources/CreatorApp/ThemeSwatch.swift`

**Interfaces:**
- Consumes: `ThemeEditorModel.colorBinding(for:)`, `.isEditable` (Task 8); `ThemeRole.allowsOpacity` (Task 2);
  MetalUI `ColorPicker(_ titleKey: String, selection: Binding<Color>, supportsOpacity: Bool = true)` (an empty title
  draws the 48×24 well alone, `LK-C` items 1–2; the well shows the colour inset 4 pt, 40×16, item 3; every panel write
  is a gamma-sRGB literal, item 5, which `HexColor(Color)` reads exactly; the well has no accessibility label of its
  own, `C1`, and `.accessibilityLabel(_:)` on the picker reaches the well, because the picker's box is a plain
  container and distributes it, AB-T: probed on the scratch merge, an untitled picker labelled "Accent" publishes
  a `.colorWell` labelled "Accent", valued `rgb 1 0 0 1`).
- Produces: nothing new for other tasks.

- [ ] **Step 1: Change the render test to look for the wells**

In `Tests/CreatorAppTests/ThemeEditorRenderTests.swift` replace the whole
`theSwatchesShowTheShownThemesColoursAndFollowAnEdit` test with:

```swift
    /// Each role's colour well (MetalUI's `ColorPicker`: a 48×24 bezel showing the colour inset 4 pt, 40×16,
    /// `LK-C` item 3) shows the shown theme's colour, and follows an edit at once.
    @Test func theColourWellsShowTheShownThemesColoursAndFollowAnEdit() async throws {
        let (app, editor) = await makeApp()
        editor.select("nord")
        editor.duplicate()
        editor.open()
        func wells() -> [HexColor] {
            fills(app, editor).filter { fill in
                abs(fill.width - 40) < 0.5 && abs(fill.height - 16) < 0.5 && fill.colour.opacity > 0
            }.map(\.colour)
        }
        let surfaces = ThemeRoleGroup.surfaces.roles.map { editor.theme.colors[$0].quantized }
        #expect(Array(wells().prefix(surfaces.count)) == surfaces, "the first rows are the surfaces, in order")
        editor.setColor(HexColor(0x00ffaa), for: try #require(ThemeRole.named("backgroundTop")))
        #expect(wells().first == HexColor(0x00ffaa))
    }
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CreatorAppTests.ThemeEditorRenderTests`
Expected: `theColourWellsShowTheShownThemesColoursAndFollowAnEdit` records an issue: `wells()` is empty (the rows
still draw 40×18 swatches).

- [ ] **Step 3: Put the picker in each row**

Replace `Sources/CreatorApp/ThemeRoleRow.swift` with:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// One role: its title, its colour as hex, and MetalUI's colour well, which opens its colour panel and writes each
/// move to the theme (`ThemeEditorModel.colorBinding(for:)`, saved and shown at once). Opacity is offered only where
/// the role is translucent by design; a built-in's wells are disabled. The well is untitled (the role's title is its
/// own text), so it carries the title as its accessibility label: VoiceOver reads "Selection", not an unnamed well
/// (MetalUI's `C1`: an untitled well has no label; the label distributes from the picker's box to the well, AB-T).
struct ThemeRoleRow: Component {
    let model: ThemeEditorModel
    let role: ThemeRole
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: ThemeEditorLayout.spacing.px) {
            Text(role.title).font(.callout).foregroundStyle(palette.primaryText.color)
            Spacer()
            Text(model.theme.colors[role].hex).font(.caption).foregroundStyle(palette.secondaryText.color)
            ColorPicker("", selection: model.colorBinding(for: role), supportsOpacity: role.allowsOpacity)
                .accessibilityLabel(role.title)
                .disabled(!model.isEditable)
        }
        .frame(height: ThemeEditorLayout.rowHeight.px)
    }
}
```

Replace `Sources/CreatorApp/ThemeEditorLayout.swift` with:

```swift
import CreatorGraph

/// The theme editor's layout numbers. It floats at the window's top-right corner, below the top bar, over the
/// inspector, and runs down to the window's bottom margin, or to just above the graph panel when that is docked at
/// the bottom, so the panel stays whole.
enum ThemeEditorLayout {
    /// The editor's content column, inside its glass padding.
    static let width = 340.0
    /// The panel's distance from the window's top edge: below the top bar.
    static let top = AppLayout.margin * 2 + AppLayout.topBarHeight
    /// A role's row.
    static let rowHeight = 24.0
    /// Between the editor's sections.
    static let spacing = 8.0

    /// The panel's distance from the window's bottom edge: a margin, or, over a graph panel docked at the bottom, a
    /// margin above that panel's resize handle (`AppLayout.graphPanelFrame`, `PanelArea`).
    static func bottom(dock: DockSide, panelHeight: Double) -> Double {
        switch dock {
        case .bottom: AppLayout.margin + panelHeight + AppLayout.resizeHandle + AppLayout.margin
        case .left, .hidden: AppLayout.margin
        }
    }
}
```

Delete the swatch: `git rm Sources/CreatorApp/ThemeSwatch.swift`.

- [ ] **Step 4: Run it to see it pass**

Run: `swift build` (no new warnings), then `swift test --filter CreatorAppTests.ThemeEditorRenderTests`
Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 5: Update the docs**

In `docs/metalui-gaps.md`, gap M6-f, replace the paragraph Task 10 added ("**Being fixed by MetalUI C10 lane 1** …
with no hex-field stopgap.") with:

```markdown
**Fixed by MetalUI C10
  lane 1** (`ColorPicker(_:selection:supportsOpacity:)` and its drawn panel, rulings `LK-C`, `LK-D`, `LK-P`) and
  adopted by the Themes plan's last task: each role's row in the theme editor is a `ColorPicker`, opacity only for the
  glass and the edges. MetalUI draws its own panel on macOS too (its divergence 165: SwiftUI opens `NSColorPanel`).
```

In `docs/verification/human-checks.md`, TH-1: replace "with its hex and a swatch" with "with its hex and a colour
well"; TH-3: replace "**TH-3 Colours (needs MetalUI C10 merged).**" with "**TH-3 Colours.**".

- [ ] **Step 6: Lint and run everything**

Run: `swiftlint lint --strict`, then `swift test`. Expected total: master + 75 = 1160 (one test renamed, none added;
the total is MetalCreator's, on whatever MetalUI master holds C10).

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorApp/ThemeRoleRow.swift Sources/CreatorApp/ThemeEditorLayout.swift \
  Tests/CreatorAppTests/ThemeEditorRenderTests.swift docs/metalui-gaps.md docs/verification/human-checks.md
git commit -m "feat(app): edit each role with MetalUI's ColorPicker (gap M6-f, C10)"
```

---

## Self-Review

**Spec coverage** (the brief's and §6.6/Errata (M6)'s requirements → tasks):

| Requirement | Task |
|---|---|
| Duplicate, edit, rename and delete custom themes; built-ins read-only | 5 (store), 8 (editor), 9 (views) |
| Export and import `.mctheme`: small versioned JSON of hex colours by role | 3 (format), 5 (files), 8 (panels) |
| Missing roles fall back to Dracula, unknown roles ignored, bad hex refused plainly | 3 |
| Stored in `~/Library/Application Support/MetalCreator/Themes`, injectable for tests | 4, 5, 10 (`AppThemes`) |
| The selected theme remembered (`ThemePreferences` over the user's defaults) | 6, 10 |
| Themes app-level, never in `.mcgraph` | unchanged: nothing touches `GraphFile` (Global Constraints) |
| Roles mapped onto MetalUI's control tokens (`.theme(_:)`) | 7, 9 (`AppWindowRoot`) |
| Colours edited role by role with MetalUI's `ColorPicker` (gap M6-f) | 11 (needs C10), binding in 8 |
| Where the editor lives | Key Decision 1; 9 |
| View ▸ Theme menu | 10 |
| Switching applies at once to the panels and the viewport (§6.6) | 5 (`current` observed; `AppModel+Scene` already follows it), 9 render test |
| MetalUI gaps logged, never worked around | 10 (TH-a, M6-f), 11 (M6-f fixed) |

**Placeholder scan:** every code step is a complete file or an exact old → new pair; every run step names its command
and expected count. Nothing is "TBD" or "similar to".

**Type consistency:** `ThemeRole.named(_:)`, `ThemeColors[role]`, `HexColor.quantized`, `ThemeFile.decode(_:id:
fallbackName:)`, `ThemeFolder.load(reserved:)`, `ThemeStore.duplicate/rename/setColor/setDark/delete/importTheme/
exportTheme`, `ThemeEditorModel.colorBinding(for:)`, `.pendingDeleteID`, `.deleteTitle`,
`ThemeEditorLayout.bottom(dock:panelHeight:)` and `AppWindowRoot(model:input:themeEditor:)` are spelled the same
in every task that defines or uses them; the code blocks were applied in this order and compiled.

**Review Focus:** each of the five lines has its test in the owning task (named there).

## Verification Record

Every code block above was applied task by task to a scratch copy of `themes` at `d9fedec`, with `../MetalUI` a
symlink to the MetalUI checkout at master `67a579e` for Tasks 1–10. After each task: `swift build --build-tests`
with no new warnings (only master's `ContextMenuTests.swift:96`), `swift test` exit 0 with no "recorded an issue" or
"failed after" line, and `swiftlint lint --strict` with no violations. After review, Tasks 3, 5, 8, 9, 10 and 11
changed (quantized fallback roles, the pending delete's id, the editor's bottom inset, `AGENTS.md` and the roadmap,
the wells' accessibility label); the chain was re-applied from Task 3 and re-verified the same way, and each new test
was seen to fail against the old code first.

| After task | Tests | Of which new |
|---|---|---|
| master `d9fedec` | 1085 | |
| 1 | 1091 | +6 |
| 2 | 1097 | +6 |
| 3 | 1105 | +8 |
| 4 | 1112 | +7 |
| 5 | 1132 | +20 |
| 6 | 1135 | +3 |
| 7 | 1139 | +4 |
| 8 | 1153 | +14 |
| 9 | 1158 | +5 |
| 10 | 1160 | +2 |
| 11 (MetalUI master `67a579e` + `feat/controls-looks` `e931b7f`, merged in a scratch clone) | 1160 | +0 (one renamed) |

Total: master + 75.

## Execution

Recommended: **subagent-driven**. Tasks 1–7 are a chain of small `CreatorStyle` units whose names later tasks use
exactly, and a fresh reviewer per task catches a drifted signature before it spreads; Task 11 waits for C10.
