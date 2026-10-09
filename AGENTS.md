# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project state

MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes) and S3 (profile holes) are done. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
M6 (app shell) code is done; its human checks (group M6) are pending.

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
  `.mcgraph` files, `DocumentModel`.
- `CreatorNodes`: the 26 built-in node definitions (`BuiltInNodes.registry`), UI-free: inspector sections and handles
  are data. Non-socket settings (`NodeSetting` in CreatorGraph: parameter, picks, showHandle) live in `Node.inputValues`;
  `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
- `CreatorStyle`: colour themes (spec §6.6, Dracula by default), the only place colour hex values are written.
  `ThemeColors` is a colour per role (never a hue); `ColorTheme` (not `Theme`: MetalUI exports one) has the built-ins
  `.dracula`, `.alucard` and `.nord`; `@MainActor @Observable ThemeStore` holds `current` and `select(_:)`, with injected
  `ThemePreferences`. Editor and app views read `@Environment(ThemeStore.self) var themes: ThemeStore?` and draw
  `Palette(themes)` (Dracula without a store); the viewport draws `ViewportModel.theme`, which the app shell sets.
  Themes are app-level, never in `.mcgraph`. Tests: `swift test --filter CreatorStyleTests`.
- `CreatorViewport`: the 3D viewport on MetalUI's `MetalView`.
  - `ViewportModel` (`@MainActor @Observable`, testable without a GPU) owns the camera, picking, the view cube,
    the context menu and handles. `ViewportRenderer`/`ViewportPicker` are the Metal side. `ViewportView` is the
    MetalUI glue.
  - It depends on Kernel, Geometry, CreatorStyle and MetalUI only, never CreatorGraph. The app shell turns graph outputs into
    `ViewportItem`s and `HandleSpec`s into `ViewportHandle`s.
- `CreatorEditor`: the graph panel and context inspector on MetalUI. `@MainActor @Observable EditorModel` holds all
  behaviour (selection, canvas transform, dock transpose, hit testing, wiring, clipboard, palette, inspector edits);
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
  Stopgap input (pending MetalUI C7) lives only in `GraphPanelInput`.
- `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and Editor.
  `@MainActor @Observable AppModel` owns the open document's parts (document, editor, graph input, viewport; replaced
  together on New and Open), turns results into `ViewportItem`s (`SceneBuilder`) and `HandleSpec`s into
  `ViewportHandle`s (`HandleBuilder`), turns viewport events into graph commands (picking writes Edges by Tag rules),
  and opens, saves and exports. `AppInput` installs the window's input once and forwards to the current document.
  `MetalCreatorApp` is the executable (`OCCTKernel`). It owns the app's `ThemeStore` (View ▸ Theme) and provides it
  to every view with `.environment(model.themes)`.

Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI,
never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.
All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids and meshing mutates it; never call the shim outside it (tests included).
Edge picks (`EdgePick`) match by tag subsets per side and warn on count drift; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 3 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero).
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
Graph panel input stopgaps live only in `GraphPanelInput`. Each C7 stand-in is one function named after its
provisional C7 API (`spatialTapGesture()`, `dragValueModifiers(_:)`), and `install(on:)` chains onto the window's
existing handlers.
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
swift test --filter CreatorStyleTests      # colour themes: the built-ins, legibility, ThemeStore
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
