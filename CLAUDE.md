# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done. S5a (the sketch editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve) code is done; its human checks (group S5) are pending; S5b (Project, New sketch on face, trim/fillet/mirror/pattern tools) is next. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
M6 (app shell) code is done; its human checks (group M6) are pending.
Editor polish (the floating add-node palette and the node library) code is done; its human checks (group EP) are pending.
Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
Themes (custom themes, `.mctheme` files, the theme editor) code is done; its human checks (group TH) are pending. Each role is edited with MetalUI C10's `ColorPicker` (plan Task 11).

Module boundaries (dependency order):
- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
- `CreatorSketch`: the constraint sketch model, `SketchSolver` (numeric Levenberg–Marquardt with analytic Jacobians,
  DOF and minimal conflicts), `SketchRegions` and `SketchCommands`. Imports only `CreatorGeometry` and Foundation;
  never iterate a dictionary where order reaches output. Tests: `swift test --filter CreatorSketchTests`.
- `CreatorKernel`: the `Kernel` protocol, `Solid`, tagged topology tables, `FakeKernel` for tests.
- `COCCT` + `CreatorOCCT`: the OpenCascade C shim and `OCCTKernel: Kernel` (topology tables, face tags carried through
  OCCT history, tessellation, STEP/STL export). **The only code that may touch OCCT.** Every C allocation has a
  `*_free`; no C++ exception crosses into Swift.
- `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
  `.mcgraph` files, `DocumentModel`. Depends on `CreatorSketch` for the `ConstantValue.sketch` setting. A node's inputs
  are `NodeDefinition.inputs(for: node)` (default: the static `inputs`); the Evaluator and `connectionProblem` read
  it, so per-node sockets (the Sketch node's exposed dimensions) wire and gather like declared ones.
- `CreatorNodes`: the 28 built-in node definitions (`BuiltInNodes.registry`: the slice's 26 plus Plane from Face and
  Sketch), UI-free: inspector sections and handles are data. Non-socket settings (`NodeSetting` in CreatorGraph:
  parameter, picks, showHandle, sketch, face, and `projection(reference)` per projected edge) live in
  `Node.inputValues`; `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
- `CreatorStyle`: colour themes (spec §6.6, Dracula by default), the only place colour hex values are written.
  `ThemeColors` is a colour per role (never a hue); `ColorTheme` (not `Theme`: MetalUI exports one) has the built-ins
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
- `CreatorViewport`: the 3D viewport on MetalUI's `MetalView`.
  - A host takes the primary pointer through `ViewportModel.tool` (`ViewportTool`: hover, clicks, and plain primary
    drags it claims, each with a `ViewportProjector` for screen → plane), and draws over the scene with
    `showOverlay(_:)` (`ViewportOverlay`: world-space lines and points in `OverlayTint` roles, dashed construction, and
    a `gridPlane` that replaces the ground grid). Navigation (right/middle drags, Shift/⌥ drags, scroll, pinch, the
    cube, handles) always stays the viewport's; the face menu offers only Look At while a tool is set. A tool's
    `navigation` (`ViewportNavigation`, default `.free`) of `.planar` locks the orientation: drags that would orbit
    pan, the cube and its controls are hidden, turning commands and the face menu do nothing (`showsViewCube`,
    `isPlanar`; the first scene's framing never runs, and input finishes an animation instead of freezing it); a tool's
    `framingBounds` is what F frames, and `ViewportProjector.modelArea` the area its on-screen chrome stays in.
    `lookAt(_ plane:framing:)` faces a plane, orthographic.
  - `ViewportModel` (`@MainActor @Observable`, testable without a GPU) owns the camera, picking, the view cube,
    the context menu and handles. `ViewportRenderer`/`ViewportPicker` are the Metal side. `ViewportView` is the
    MetalUI glue.
  - It depends on Kernel, Geometry, CreatorStyle and MetalUI only, never CreatorGraph. The app shell turns graph outputs into
    `ViewportItem`s and `HandleSpec`s into `ViewportHandle`s.
- `CreatorEditor`: the graph panel and context inspector on MetalUI. `@MainActor @Observable EditorModel` holds all
  behaviour (selection, canvas transform, dock transpose, hit testing, wiring, clipboard, palette, inspector edits);
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`.
- `CreatorSketchEditor`: the sketch editor (sketcher spec §8). `@MainActor @Observable SketchEditorModel` holds the
  sketch being edited, its live solve (`solve(_:dragging:)` per drag step), the tool and its stroke, the selection, and
  the inspector's rows; it is the viewport's `ViewportTool` (planar navigation; F frames the sketch) and builds its
  `ViewportOverlay` and the pointer readout (`pointerReadout`, while drawing or dragging a point; placed by
  `ReadoutChip`, drawn by its `PointerReadoutView`, which the app puts over the viewport). Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  Depends on CreatorSketch, CreatorViewport, CreatorGeometry, CreatorStyle and MetalUI only. Its keys are toolbar
  button shortcuts (L, A, C, D, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons), which run before the graph panel's
  `onInput` keys; the Delete button and the hidden ⌦ one are never disabled, so ⌫ and ⌦ never fall through to deleting
  nodes (the graph's selection is the Sketch node being edited). Tests: `swift test --filter CreatorSketchEditorTests`.
- `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and the editors.
  Sketch mode is `AppModel.sketch` (`SketchSession`: the editor as the viewport's tool, its overlay followed), entered
  by the Sketch node's "Edit sketch" (`InspectorAction.editSketch`); the scene is ghosted and handle-free meanwhile,
  the top bar holds `SketchToolbar` and the inspector `SketchInspector`, each in `SketchChrome` (glass over an opaque
  backdrop, so a click on the chrome never reaches the editor beneath). `SketchStore` turns a commit into one batch:
  the `sketch` setting, a cleared constant under each exposed dimension's name (the value lives in the sketch alone),
  and a renamed exposed dimension's wire moved (dropped when it stops being exposed).
  `@MainActor @Observable AppModel` owns the open document's parts (document, editor, graph input, viewport; replaced
  together on New and Open), turns results into `ViewportItem`s (`SceneBuilder`) and `HandleSpec`s into
  `ViewportHandle`s (`HandleBuilder`), turns viewport events into graph commands (picking writes Edges by Tag rules),
  and opens, saves and exports. `AppInput` installs the window's input once and forwards to the current document.
  `MetalCreatorApp` is the executable (`OCCTKernel`). It makes the app's `ThemeStore` (`AppThemes.store()`: user
  defaults, `~/Library/Application Support/MetalCreator/Themes`) and its `ThemeEditorModel`, and opens the window on
  `AppWindowRoot`: `AppRoot` with the theme editor (`ThemeEditorDock`, a floating glass panel at the top right) over
  it, the store in the environment and `.theme(current.controlTheme)` for MetalUI's controls. View ▸ Theme is
  `ThemeMenu` (every theme, then Edit Themes…). `LaunchCommand` parses its command line: a file to open, or the
  headless `--version`, `--self-test` (`SelfTest`: OCCT, STEP/STL export, MetalUI's shaders) and `--info-plist`.
  `AppBundleInfo` is the version's one source; the packaged `Info.plist` is generated from it, never edited.

Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI,
never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.
All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids and meshing mutates it; never call the shim outside it (tests included).
Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a pick without one counts each recorded edge as a run) and warns only when both changed; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 4 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
4 added the `.sketch` and `.facePick` settings).
A `Segment2D.arc` with `end < start` runs clockwise (a sketch region's notch); the shim builds it reversed and
`length` is positive. Edges carry `EdgeInfo.curve` (`EdgeCurve`, lines and circles) for sketch projection; a
`FacePick` names faces by tag subset like `EdgePick`. The Sketch node solves on every evaluation from the stored
sketch's warm start; the editor writes `Sketch.remember` back into the setting with every commit (S5a). Node readers
of sockets use `inputs(for: node)` (canvas shape and rows, inspector, handles), never the static `inputs`.
`Profile2D` is `outer` + `holes` (loop 0 = outer, n = hole n); `segments` is the outer loop only, so code that
rebuilds a profile must keep `holes` (copy it and change `plane`, don't re-init from `segments`). Side tags are
`.side(loop:segment:)` and `.side(segment:)` means loop 0; never match `.side` with one binding (`case .side(let s)`
binds the tuple and only warns). The shim orients hole wires against the outer wire; history `operand` on segment
records is the loop. Loft refuses profiles with holes. Create nodes only with `NodeRegistry.makeNode`. Numbers in node messages use `Locale.messages` (`Double.display`, `Int.display`).
Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
MetalUI exports its own `Angle`: a file importing both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle`.
The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
`ViewportModel` (`dragChanged`/`dragEnded`, `click(at:)`, `contextMenuItems(at:)`, `scrolled(by:at:phase:)`,
`pinchChanged`, `cursor`), and `ViewportView` only forwards gesture values. Its keys stay window-wide stopgaps in
`ViewportKeyBindings` until MetalUI scopes keys to an element (C9).
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
drawing and hit testing agree. Node positions are stored left-to-right; the left dock draws their transpose.
The graph panel's insides (header, node library, canvas) are computed by `GraphPanelLayout` and the palette's size
by `PaletteLayout`; the host says where the panel is in its window through `EditorModel.placement` (the app:
`AppModel.panelPlacement`, from `AppLayout` and the viewport's size; the preview: `PreviewLayout`, a fixed-size
window). The add-node palette floats over the window: the host draws `SearchPaletteOverlay` last (the app inside
`PaletteDock`, for the `Panel` key context), then `LibraryDragOverlay`, never inside the canvas. A library row is a
`PaletteEntryLabel` under one `DragGesture(minimumDistance: 0, coordinateSpace: .global)`
(`GraphPanelInput.libraryGesture(for:)`; not a `Button`, whose click would hold the drag off), and the model tells a
click from a drag (`LibraryDrag.threshold`); never MetalUI drag and drop (it becomes a system drag outside the
window). The library's visibility is `ViewState.showsLibrary` (an optional key: no format bump).
The graph canvas's pointer input is MetalUI C7's, turned into `EditorModel` calls by `GraphPanelInput`: one
`DragGesture(minimumDistance: 0)` for clicks and drags, whose `value.modifiers` the model reads (a `SpatialTapGesture`
has none, gap GI-a), `.onScrollWheel` (`scrolled(by:at:modifiers:phase:)`: pan, ⌘ zooms) and `MagnifyGesture`
(`pinchChanged`); the cursor is `EditorModel.canvasCursor`. Its key, focus and palette stopgaps live only in
`GraphPanelInput` too, and `install(on:)` chains onto the window's existing handlers.
The app installs the window's input through `AppInput`, never `GraphPanelInput.install(on:)` (only
`GraphPanelPreview` still uses it), because New and Open replace the document's `GraphPanelInput`.
App-shell input stopgaps live only in `AppInput`: the viewport's keys carry the `!Panel` key context (the graph panel
and the inspector contribute `Panel`), and over the graph canvas + and − are declined so the graph's zoom keys work. The
camera reaches `ViewState` only through `cameraSettled`/`homeChanged`, never per frame. Regular Polygon is
`typeVersion` 2 (`rotation`).

## Commands

```sh
swift build                                  # build the library
swift build -c release
swift test                                   # run all tests
swift test --filter CreatorGraphTests        # one test target (also CreatorOCCTTests, CreatorGeometryTests, CreatorKernelTests, CreatorViewportTests)
swift test --filter CreatorOCCTTests         # kernel conformance + naming stability (needs OCCT)
swift test --filter 'CreatorGraphTests.EvaluatorTests/wiredValuesFlowDownstream'   # one test
swift test --filter CreatorNodesTests        # node definitions through the real Evaluator (OCCT where geometry matters)
swift test --filter BracketAcceptanceTests   # the §7.2 bracket, headless
swift test --filter CreatorViewportTests   # viewport model, maths and the offscreen ID pass (needs a Metal device)
swift run ViewportHarness                  # dev window for docs/verification/human-checks.md group V
swift test --filter CreatorEditorTests       # editor model + headless render tests
swift run GraphPanelPreview                   # graph panel + inspector, for docs/verification/human-checks.md (M5)
swift run MetalCreatorApp [file.mcgraph]   # the app (docs/verification/human-checks.md, group M6)
swift test --filter CreatorAppTests        # app model, scene, handles, picking, files, export, input; AppAcceptanceTests runs §7.2 on OCCT
swift test --filter CreatorStyleTests      # colour themes: built-ins, roles, .mctheme files, the folder, ThemeStore
swift test --filter CreatorSketchEditorTests   # the sketch editor: tools, inference, constraints, dimensions, overlay
scripts/package-app.sh                     # dist/MetalCreator.app: release build, OCCT bundled, signed ad hoc, verified (docs/packaging.md)
scripts/verify-app.sh [path.app]           # re-check a packaged app: signature, no Homebrew links, self-test with Homebrew unreadable
swift run MetalCreatorApp --self-test      # the same headless checks, unpackaged
```

## Linting

SwiftLint is configured in `.swiftlint.yml` (each non-default setting is documented there). Run `swiftlint lint --strict` before committing; it must report zero violations. Prefer fixing the code over adding `swiftlint:disable` comments, and give any disable a reason.

## Toolchain constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]` — full Swift 6 strict concurrency checking is on. Data-race violations are compile **errors**, not warnings. Shared mutable state needs an actor, `Sendable` conformance, or an explicit global-actor annotation; do not reach for `@unchecked Sendable` or `nonisolated(unsafe)` to silence a diagnostic without understanding it.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Keep new tests on Swift Testing.
- Local toolchain: Apple Swift 6.4, arm64 macOS.
- Swift 6.4 crashes in SILGen on a key path applied to an existential metatype (`BuiltInNodes.all.map(\.typeID)`); use a closure.
- OpenCascade 7.9 comes from Homebrew (`brew install opencascade`) and is linked from `/opt/homebrew/opt/opencascade`.
  Linker warnings about dylibs built for a newer macOS are expected.
- Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion`.
