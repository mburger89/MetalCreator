# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone plans live in
`docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and
S4 (the Sketch and Plane from Face nodes) are done; S5a to S5c (the sketch editor), M4 (viewport), M5 (graph panel and
inspector), M6 (app shell), M7 (measure and record) and every later sub-project have their code done, with human checks pending.

## Where the notes live

Each module's notes are in a `CLAUDE.md` in its folder, which Claude Code loads only when it reads a file there; the test
targets' folders import their module's. Read the one you need before working across modules (from `Tests/`, a script or
a doc), or when a question is about a module you have not opened yet:

- `CreatorGeometry` (`Sources/CreatorGeometry/CLAUDE.md`): value types (vectors, planes, profiles, bounds), millimetres.
- `CreatorSketch` (`Sources/CreatorSketch/CLAUDE.md`): the constraint sketch and its solver; imports only `CreatorGeometry` and Foundation.
- `CreatorKernel` (`Sources/CreatorKernel/CLAUDE.md`): the `Kernel` protocol, `Solid`, tagged topology, `FakeKernel`.
- `COCCT` (`Sources/COCCT/CLAUDE.md`): `COCCT` + `CreatorOCCT`: the OpenCascade shim and `OCCTKernel`, **the only code that may touch OCCT**.
- `CreatorGraph` (`Sources/CreatorGraph/CLAUDE.md`): graph model, `Evaluator`, commands and undo, `.mcgraph` files, groups, trees; depends on `CreatorSketch`.
- `CreatorImplicit` (`Sources/CreatorImplicit/CLAUDE.md`): implicit solids and meshes; depends on Graph, Kernel and Geometry; portable.
- `CreatorNodes` (`Sources/CreatorNodes/CLAUDE.md`): the built-in node definitions, UI-free (`CreatorNodes/Surfaces/CLAUDE.md` holds NS-1 to NS-5).
- `CreatorPCB` (`Sources/CreatorPCB/CLAUDE.md`): the KiCad board reader; depends on `CreatorGeometry` only.
- `CreatorMCP` (`Sources/CreatorMCP/CLAUDE.md`): the MCP server and bridge; depends on Graph, Kernel and Geometry, never the editor or the app.
- `CreatorStyle` (`Sources/CreatorStyle/CLAUDE.md`): colour themes and glass; the only place colour hex values are written.
- `CreatorViewport` (`Sources/CreatorViewport/CLAUDE.md`): the 3D viewport (Metal, SDL GPU); depends on Kernel, Geometry, Style and MetalUI only, never CreatorGraph.
- `CreatorEditor` (`Sources/CreatorEditor/CLAUDE.md`): the graph panel and inspector; depends on Graph, Kernel, Geometry, Style and MetalUI, not `CreatorNodes`.
- `CreatorSketchEditor` (`Sources/CreatorSketchEditor/CLAUDE.md`): the sketch editor; depends on Sketch, Viewport, Kernel, Geometry, Style and MetalUI only.
- `CreatorDrawing` (`Sources/CreatorDrawing/CLAUDE.md`): drawings DR-1 to DR-5; depends on Geometry and Kernel only (never OCCT, MetalUI or CreatorGraph).
- `CreatorDrawingEditor` (`Sources/CreatorDrawingEditor/CLAUDE.md`): the drawing editor; depends on Drawing, Kernel, Geometry, Style and MetalUI only, never CreatorGraph.
- `CreatorApp` (`Sources/CreatorApp/CLAUDE.md`): `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and the editors.

Specs are in `docs/superpowers/specs/`, plans in `docs/superpowers/plans/`, human checks by group in
`docs/verification/human-checks.md` (every sub-project's code is done and its checks are pending unless its notes say
otherwise), benchmark numbers in `docs/verification/performance.md` and MetalUI gaps in `docs/metalui-gaps.md`.

## Cross-platform rules

`Package.swift` has two lists, like MetalUI's: the targets that import no Apple
framework are declared everywhere (`CreatorViewport` too: its model, camera and tools are portable, its Metal renderer files
are behind `#if canImport(Metal)` and its SDL GPU ones behind `#if canImport(MetalUISDLGPU)`); `ViewportHarness` and `GraphPanelPreview` are declared on macOS only, while `COCCT`,
`CreatorOCCT` and `CreatorOCCTTests` are declared everywhere since xp-2 (OpenCascade 7.9 on every platform: `Package.swift` reads its
install prefix from `OCCT_PREFIX`, default Homebrew's on macOS, `/opt/occt` on Linux, `C:/occt` on Windows, with per-platform linker
flags: an `$ORIGIN/lib` rpath on Linux, DLLs on `PATH` or beside the executable on Windows). On Linux and Windows the MetalUI dependency asks for the `SDL` and `AccessKit` traits and
`MetalCreatorApp` links `MetalUISDL` (`main.swift` picks `SDLPlatform` with `PortableTextSystem` over the installed fonts under
`canImport(MetalUISDL)`). The app runs over `OCCTKernel` on every platform (xp-2; `KernelUnavailable`, which answers "Geometry isn't available on this
platform yet.", stays in `CreatorKernel` for tests of a platform without a kernel) and, off macOS, the viewport draws on SDL GPU (xp-3; `ViewportPlaceholder` is gone). The Image
Field works everywhere: `GreyImageDecoder` decodes through MetalUI's `DecodedImage` (S2, gap XP-G4) on every platform. Rules
for new code: no CryptoKit (use `SHA256`/`SHA1` in `CreatorGraph/Hashing`), no CoreGraphics, ImageIO, CoreText or Metal outside a
`#if canImport(…)` file or block, keyboard shortcuts and modifier checks on MetalUI events say `.primary` (⌘ on macOS, Ctrl
elsewhere), and a file dialog's `ContentType` declares its `filenameExtensions`. Tests: a test that needs Metal, OpenCascade,
CoreText is gated with `#if canImport(Metal)`, `canImport(CreatorOCCT)` or `canImport(CoreText)` and so is absent from the Linux
count, never from macOS's; render tests take their text system from `testTextSystem()` in each target's
`Support/TestTextSystem.swift`; picture fixtures come from `TestImages` (ImageIO on macOS, `PNGWriter` elsewhere; JPEG, GIF and
TIFF fixtures need ImageIO, so those tests are `#if canImport(CoreGraphics)`, and `GreyImageDecoderPinnedTests` carries JPEGs as
bytes for every platform) and `AppTestImages` (plain Swift). Pass
rules: macOS, Linux and Windows, exit 0 and 16 "Test run with" lines (`CreatorOCCTTests` joined Linux and Windows in xp-2;
`CreatorImplicitTests` joined in 7c; a shim, kernel or test that needs OpenCascade is no longer gated by `canImport(CreatorOCCT)`
alone: one that also needs Metal says `canImport(Metal) && canImport(CreatorOCCT)`), and none may print "recorded an issue" or "failed after".

## Rules

Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI,
never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.
All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids and meshing mutates it; never call the shim outside it (tests included).
Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a run is edges that continue each other end to end, ends within 1e-4 mm leaving that point in opposite directions to within 0.01 rad, so two edges meeting at a corner are two runs; a pick without one counts each recorded edge as a run) and warns only when both changed; a key that still matches nothing is split by operand (`EdgeKey.operandKeys`, for an edge between a merged face and a third operand's face) and warns when two operands both fit; selection rules never select seams. Segmented controls bind integer sockets (option index).
File format is version 21; its history (what each version added) is in `Sources/CreatorGraph/CLAUDE.md`.
A `Segment2D.arc` with `end < start` runs clockwise (a sketch region's notch); the shim builds it reversed and
`length` is positive. Edges carry `EdgeInfo.curve` (`EdgeCurve`, lines and circles) for sketch projection; a
`FacePick` names faces by tag subset like `EdgePick`; one that matches nothing is retried per operand and ranked by the normal and centroid it recorded (optional keys, no format bump; `Topology.resolution(of:)`), and warns when it can only guess. The Sketch node solves on every evaluation from the stored
sketch's warm start (a constraint or dimension on a projected edge of the wrong kind is skipped and named in a warning,
like one on a suspended edge); the editor writes `Sketch.remember` back into the setting with every commit (S5a). Node readers
of sockets use `inputs(for: node)` (canvas shape and rows, inspector, handles), never the static `inputs`.
`Profile2D` is `outer` + `holes` (loop 0 = outer, n = hole n); `segments` is the outer loop only, so code that
rebuilds a profile must keep `holes` (copy it and change `plane`, don't re-init from `segments`). Side tags are
`.side(loop:segment:)` and `.side(segment:)` means loop 0; never match `.side` with one binding (`case .side(let s)`
binds the tuple and only warns). The shim orients hole wires against the outer wire; history `operand` on segment
records is the loop. Loft refuses profiles with holes, before it compares segment counts (`KernelError.loftWithHoles`). The Loft node is `typeVersion` 2 (migration: identity; a version 1 loft has no faces and builds as before): an optional `solid` input, `startFace` / `endFace` (`NodeSetting`, `FacePick`s, picked by "Pick Start/End Face in View…", cleared by "Clear … Face"; each is one named undo step, "Pick Loft Face" / "Clear Loft Face"; refused inside a group), `startContinuity` / `endContinuity` (Free, Tangent (G1), Curvature (G2); shown only for an end with a face) and `startWeight` / `endWeight` (0.1 to 2; shown for Tangent and Curvature). `sections` is optional: a loft needs two sections in all, and a face end counts as one ("A loft needs at least two sections…" otherwise), so a bridge between two faces needs no profile. A pick that is merged, matches several faces or has no stable name warns in the words Face Pattern and Plane from Face use (`FacePickWording`); a vanished pattern instance, a missing face or a missing part is an error in words (`LoftEndSetup`).
Create nodes only with `NodeRegistry.makeNode`. Numbers in node and kernel messages use `Locale.messages` (defined in
CreatorKernel; `Double.display`, `Int.display` in CreatorNodes; `KernelError.userMessage` uses it too).
Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
MetalUI exports its own `Angle`: a file importing both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle`.

## Commands

```sh
swift build                                  # build the library
swift build -c release
swift test                                   # run all tests (sixteen test targets: sixteen "Test run with" lines)
swift test --filter CreatorGraphTests        # one test target (also CreatorOCCTTests, CreatorGeometryTests, CreatorKernelTests, CreatorViewportTests)
swift test --filter CreatorOCCTTests         # kernel conformance + naming stability (needs OCCT)
swift test --filter 'CreatorGraphTests.EvaluatorTests/wiredValuesFlowDownstream'   # one test
swift test --filter CreatorNodesTests        # node definitions through the real Evaluator (OCCT where geometry matters)
swift test --filter BracketAcceptanceTests   # the §7.2 bracket, headless
swift test --filter CreatorDrawingTests         # drawings: model, styles, sheet geometry, projection cache, composer, PDF and DXF writers
swift test --filter CreatorDrawingEditorTests   # the drawing editor model and its views
swift test --filter CreatorViewportTests   # viewport model, maths, the HLSL struct sizes, the build's shaders (Linux, Windows) and the offscreen render and ID passes (a GPU: Metal, or SDL_GPU on Linux and Windows)
swift run ViewportHarness                  # dev window for docs/verification/human-checks.md group V
swift test --filter CreatorEditorTests       # editor model + headless render tests
swift run GraphPanelPreview                   # graph panel + inspector, for docs/verification/human-checks.md (M5)
swift run MetalCreatorApp [file.mcgraph]   # the app (docs/verification/human-checks.md, group M6)
swift test --filter CreatorAppTests        # app model, scene, handles, picking, files, export, input; AppAcceptanceTests runs §7.2 on OCCT
swift test --filter CanvasContentSkipWindowTests   # the canvas's .equatable() views: what a drag, theme or selection change evaluates
swift test --filter CreatorStyleTests      # colour themes: built-ins, roles, .mctheme files, the folder, ThemeStore
swift test --filter CreatorSketchEditorTests   # the sketch editor: tools, inference, constraints, dimensions, overlay
swift test --filter CreatorPCBTests            # the KiCad board reader: S-expressions, outline chaining, keys, limits
swift test --filter CreatorImplicitTests       # implicit solids: evaluators, octree, mesher, bakes, the GPU agreement suite (Metal device)
scripts/package-app.sh                     # dist/MetalCreator.app: release build, OCCT bundled, signed ad hoc, verified (docs/packaging.md)
scripts/verify-app.sh [path.app]           # re-check a packaged app: signature, no Homebrew links, self-test with Homebrew unreadable
swift run MetalCreatorApp --self-test      # the same headless checks, unpackaged
scripts/bench.sh [suite]                   # spec §7.3 benchmarks, release build; numbers go in docs/verification/performance.md
scripts/bench.sh PatternBench              # patterns spec §7: 200 holes in a plate, edit-to-preview (idle Mac only)
scripts/linux-test.sh [build|test|smoke|package|all|clean]   # the suite on Linux in Docker (OrbStack): swift build, swift test (16 "Test run with" lines), --self-test, --smoke-test 20
scripts/linux-test.sh test --filter CreatorOCCTTests   # one target on Linux (no count rule); XP_TRACK=xp-2 IMAGE=metalcreator-linux:xp-2 keep a track's volume and image apart
scripts/linux-test.sh kernels              # Linux: compile the generated implicit kernels offline into .build/generated-kernels (xp-c)
scripts/linux-test.sh package              # the tarball and the AppImage in dist/, each run in a clean ubuntu:24.04 (docs/packaging.md)
swift run MetalCreatorApp --smoke-test 5   # a Linux or Windows build: the real window over SDL's offscreen renderers; exit 0 if a first frame was drawn and the 3D viewport drew
METALUI_SHADERCROSS=/path/to/shadercross swift build   # Linux or Windows: the CompileShadersOnBuild plugin compiles Sources/CreatorViewport/Shaders with the pinned SDL_shadercross (scripts/shadercross.env); macOS needs none
```

Benchmarks (`Tests/CreatorAppTests/Bench`) are Swift Testing suites that print `BENCH …` lines and assert no time; a
plain `swift test` skips them (`.enabled(if: Bench.isRequested)`), and one run in a debug build records an issue
instead of printing debug numbers (MetalUI draws about 45× slower in debug). Their fixtures (`BenchSamples`,
`BenchRenderer`, `FiftyNodeGraph`, the bracket) are checked in the default run. Measure release, on an idle Mac.

## Linting

SwiftLint is configured in `.swiftlint.yml` (each non-default setting is documented there). Run `swiftlint lint --strict` before committing; it must report zero violations. Prefer fixing the code over adding `swiftlint:disable` comments, and give any disable a reason.

## Toolchain constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]` — full Swift 6 strict concurrency checking is on. Data-race violations are compile **errors**, not warnings. Shared mutable state needs an actor, `Sendable` conformance, or an explicit global-actor annotation; do not reach for `@unchecked Sendable` or `nonisolated(unsafe)` to silence a diagnostic without understanding it.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Keep new tests on Swift Testing.
- Local toolchain: Apple Swift 6.4, arm64 macOS. Linux runs in Docker on this Mac (`scripts/linux-test.sh`: MetalUI's `metalui-portable`
  image (tagged by a hash of its recipe), built from `../MetalUI/Backends/SDL/linux/Dockerfile` (SDL with X11 and Wayland; the image sets `SDL_VIDEO_DRIVER=offscreen`, and the clean-Ubuntu package checks set it themselves), plus a font, `scripts/linux/Dockerfile`); build products live in a Docker
  volume named for the track (`XP_TRACK`, default `xp-1`), and a run stops only its own container. MetalUI must be a sibling checkout.
  The image also holds OpenCascade 7.9 (xp-2); its first build takes minutes, then Docker's layer cache keeps it.
  Windows cannot be run here: it is CI's job (`.github/workflows/xp.yml`; it builds, tests with OpenCascade from vcpkg, launches and packages).
- The Windows Swift 6.4 toolchain asserts in LLVM's coroutine splitting (`CoroFrame.cpp`, "Layout->getElementOffset") on an `async` function that holds a loop's locals across an `await` (`DrainHoles.drainPoints` did); keep the synchronous work in a non-async helper. In a release build it also crashes splitting the closure-specialised clone of an `async` function that takes a closure (`OccupancyGrid.fill(lipschitz:awaiting:)` did): mark such a thin wrapper `@_optimize(none)` with a comment and keep the heavy work in optimised synchronous helpers; pass no typed-throws closure to a generic helper. CI's Windows release build ("Build release (for the zip)") is the check; on this Mac the 6.4 asserts snapshot reproduces the crashes: `TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release`.
- Swift 6.4 crashes in SILGen on a key path applied to an existential metatype (`BuiltInNodes.all.map(\.typeID)`); use a closure.
- OpenCascade 7.9 comes from Homebrew on macOS (`brew install opencascade`, linked from `/opt/homebrew/opt/opencascade`; linker
  warnings about dylibs built for a newer macOS are expected), from source on Linux (the `occt` stage of `scripts/linux/Dockerfile`,
  V7_9_3 at a pinned commit, installed in `/opt/occt`) and from vcpkg on Windows (the `opencascade` port at 7.9.3 in CI, release and debug libraries, triplet `x64-windows`: a debug
  build links `debug/lib`, a release build `lib`, so the C runtime matches; pinned by `VCPKG_COMMIT` in `.github/workflows/xp.yml` and
  `packaging/windows/vcpkg.json`). The shim (`Sources/COCCT`) must stay portable:
  no `M_PI` (use `cocct::kPi`), no POSIX headers, no `__attribute__`; `ShimPortabilityTests` scans for them. Release packages:
  `scripts/package-linux.sh` (tarball), `scripts/package-appimage.sh` (AppImage, packed from the tarball's tree; its appimagetool and runtime are pinned build-time downloads, not dependencies), `scripts/package-windows.ps1` (zip, CI only). Text that a test reads or a script runs
  (`packaging/`, `scripts/`, `.github/`, `Sources/COCCT/`, `CLAUDE.md`) is checked out with LF on Windows too (`.gitattributes`,
  pinned by `CIPinTests`): Swift reads "\r\n" as one Character, so a test that splits on "\n" finds nothing in a CRLF file; a test
  that reads such a file replaces "\r\n" with "\n" first.
- Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion`.
