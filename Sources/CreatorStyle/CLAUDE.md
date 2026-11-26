# CreatorStyle (themes and glass)

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

MetalUI C21's backdrop blur is adopted (gap C10-a; plan `docs/superpowers/plans/2026-10-12-adopt-c21.md`; human checks group C21
pending): every glass panel and sketch chip is a MetalUI material that blurs the viewport under the theme's `glass` tint
(`GlassStyle` in `CreatorStyle`: `GlassSurface` picks the thickness, the tint's opacity is lowered so the pair hides what the
role's opacity says, `GlassPanel(_ surface:)` and `glassBackground(_:in:)` draw it). MetalUI C27 is adopted too (gaps C21-a and C21-b; plan `docs/superpowers/plans/2026-10-13-adopt-c27.md`): the material's own opacity is read from `Material.tint(in:)`, and Reduce Transparency is honoured (MetalUI draws every material as an opaque grey with no blur; `GlassPanel` and the chips read `\.accessibilityReduceTransparency` into `GlassStyle(reducesTransparency:)`, which makes the theme's tint opaque). `GlassPanel` carries an opaque backdrop for the pointer (a material paints, it takes no pointer; a click on a panel's title or padding must not reach the viewport; `takesPointer: false`, the top bar's alone, opts out), and `SketchChrome` is a `GlassPanel`.
Themes (custom themes, `.mctheme` files, the theme editor) code is done; its human checks (group TH) are pending. Each role is edited with MetalUI C10's `ColorPicker` (plan Task 11).

- `CreatorStyle`: colour themes (spec §6.6, Dracula by default), the only place colour hex values are written.
  `ThemeColors` is a colour per role (never a hue); `ColorTheme` (not `Theme`: MetalUI exports one) has the built-ins
  `.dracula`, `.alucard` and `.nord` (read-only); `ThemeRole` names each role (`ThemeColors[role]`; the names are the
  `.mctheme` keys; `ThemeRoleTests` pins them to the stored properties). The field preview's ramp is three roles, `fieldLow`,
  `fieldMid` and `fieldHigh` (group `ThemeRoleGroup.fieldPreview`, last in `ThemeRole.all`); a `.mctheme` without them reads
  Dracula's. `@MainActor @Observable ThemeStore` holds
  `current`, `select(_:)` and the custom themes (`customs`: duplicate, rename, `setColor`, `setDark`, delete, import,
  export), saving each change to an injected `ThemeFolder` before showing it (`nil`: memory only, every test's; a colour
  picker's drag is the one exception: `previewColor` shows each sample and `saveColors()` writes once, driven by
  `ThemeEditorModel.dragColor` after `saveDelay` and by `flush()` on close, and a failed save puts the saved colours
  back; the folder skips a file named like a built-in in any case, and never writes an id that is not a file name), with
  injected `ThemePreferences` (`UserDefaultsThemePreferences` in the app). `ThemeFile` is the `.mctheme` format
  (version 1; missing roles are Dracula's, unknown ones ignored, a bad colour refused naming its role); custom themes'
  colours are always `quantized` (opacity to a byte) so a file round-trips exactly. `ColorTheme.controlTheme` maps
  roles onto MetalUI's control tokens. Glass (MetalUI C21): `GlassSurface` (which floating surface) gives `GlassThickness` (a
  MetalUI material), `GlassStyle` is the material plus the theme's `glassFill` at the opacity that keeps the role's meaning
  (`tintOpacity(glass:materialOpacity:)`; `materialOpacity` reads MetalUI's `Material.tint(in:)`, gap C21-a; Reduce Transparency
  makes the tint opaque, gap C21-b), `glassBackground(_:in:)` draws it. Editor and app views read `@Environment(ThemeStore.self) var themes:
  ThemeStore?` and draw `Palette(themes)` (Dracula without a store), except the canvas's own views (node, header, row, status
  badge, socket layer, wire, comment frame, note, handle): `CanvasLayers` makes the `Palette` and passes it down as a stored
  value, and each of those is `Equatable` and `.equatable()` where `CanvasLayers` and `NodeView` build it (MetalUI C14 slice 1,
  gap PERF-b), so an unchanged node's `content` getter is skipped, and (MetalUI C14b-2, record §110) an unchanged outermost
  occurrence also skips its whole build recursion, grafts its retained layout nodes and replays its prepaint and paint, so a
  steady frame counts one `contentSkips` per outermost canvas view (inner views are no longer visited) and one
  `retainedGrafts` each. The panels around the canvas are `.equatable()` too (MetalUI C14-d): `GraphPanel`, `GraphPanelBody`,
  `GraphCanvas`, `CanvasSurface`, `NodeLibraryView` and `InspectorPanel` compare their model and input by identity (`===`; both are
  final classes and the model is `@Observable`, whose reads MetalUI tracks), so the outermost occurrences of a steady frame are the
  body and the inspector (`PanelContentSkipWindowTests`, `PanelEqualityTests`). `DocumentModel` keeps the file's view state as separate observable properties (`dock`, `canvasOffset`, `canvasZoom`, `camera`, `homeCamera`, `showsLibrary`; `viewState` assembles them, the encoding is unchanged, `ViewStateEncodingTests`), so a pan, which writes only the canvas transform, does not evaluate `GraphPanelBody`. `ViewportView` is not (`\.textMeasurer` is not
  comparable). The benchmarks' `-warm` rows (`WarmBenchWindow`, `WarmWorkPinTests`) keep one window and `Frame` alive and are
  what the 60 fps budget is judged on; the `(cold frame)` rows are a first frame. Since MetalUI C14-c
  (environment epoch, PR #96, record §120, `41a2180f`) an `.equatable()` view may read `@Environment`: it is skipped while
  the values it read are unchanged (an `@Environment(Type.self)` object by instance plus the observation session over the
  properties read, an Equatable custom key by `==`, a reference by identity); closures and `@FocusState` are still refused
  (divergence 346 now covers only those). `BoxSelectionView` reads `@Environment(ThemeStore)` and is `.equatable()` on
  its `rect` alone (`CanvasContentSkipWindowTests` pins it); the other canvas views still take the `Palette` by value. Its `==`
  must cover every stored property the getter reads (the synthesized one does; a hand-written one is
  `nonisolated static func ==`), and `expectEqualityCovers` (`CreatorEditorTests`) fails when a view gains a property its
  test has no variant for. The viewport draws `ViewportModel.theme`, which the
  app shell sets. Themes are app-level, never in `.mcgraph`. Tests: `swift test --filter CreatorStyleTests`.
