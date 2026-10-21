# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done. S5a (the sketch editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve) code is done; its human checks (group S5) are pending. S5b (trim, extend, fillet, mirror and pattern tools, 3-point arcs, point-on and tangent inference with glyphs, double-click to edit) code is done; its human checks (group S5b) are pending; S5c (Project, New sketch on face, dimension labels in the view, region fill) code is done; its human checks (group S5c) are pending. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
M6 (app shell) code is done; its human checks (group M6) are pending.
MetalUI C8 (the app shell: close and quit veto, window title and edited dot, open-document events) is
adopted, with the hidden title bar (gap M6-c) and MetalUI C22's window drag (gap C8-a; plan `docs/superpowers/plans/2026-10-12-adopt-c22.md`); its human checks (group AS; the drag is AS-5) are pending.
Editor polish (the floating add-node palette and the node library) code is done; its human checks (group EP) are pending.
Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
Multi-select polish (sub-project A of `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`) code is
done; its human checks (group MS) are pending.
MetalUI C10's looks and controls are adopted (plan `docs/superpowers/plans/2026-10-09-adopt-c10.md`; human checks group C10
pending): the inspector's sliders end an undo step with `Slider(onEditingChanged:)` (`EditorModel.sliderEditingChanged(_:)`),
a refused node shakes with `keyframeAnimator` (`RefusalShake`, `EditorModel.shakeCount(of:)`), an evaluating node's badge is
a `ProgressView`, the preview window's background is a `LinearGradient` (`WindowBackground`), and the glass panels kept the
theme's flat tint until MetalUI C21 gave materials a backdrop blur (next paragraph).
MetalUI C21's backdrop blur is adopted (gap C10-a; plan `docs/superpowers/plans/2026-10-12-adopt-c21.md`; human checks group C21
pending): every glass panel and sketch chip is a MetalUI material that blurs the viewport under the theme's `glass` tint
(`GlassStyle` in `CreatorStyle`: `GlassSurface` picks the thickness, the tint's opacity is lowered so the pair hides what the
role's opacity says, `GlassPanel(_ surface:)` and `glassBackground(_:in:)` draw it). MetalUI C27 is adopted too (gaps C21-a and C21-b; plan `docs/superpowers/plans/2026-10-13-adopt-c27.md`): the material's own opacity is read from `Material.tint(in:)`, and Reduce Transparency is honoured (MetalUI draws every material as an opaque grey with no blur; `GlassPanel` and the chips read `\.accessibilityReduceTransparency` into `GlassStyle(reducesTransparency:)`, which makes the theme's tint opaque). `SketchChrome` keeps its opaque backdrop (a material paints, it takes no pointer).
Themes (custom themes, `.mctheme` files, the theme editor) code is done; its human checks (group TH) are pending. Each role is edited with MetalUI C10's `ColorPicker` (plan Task 11).
M7 (measure and record) code is done: spec §7.3's numbers are in `docs/verification/performance.md`, taken by the
release benchmarks in `Tests/CreatorAppTests/Bench` (`scripts/bench.sh`); `docs/metalui-gaps.md` opens with a summary
table of every gap, its MetalUI item and its status; its human checks (group M7) are pending.
Canvas comments (sub-project B of the same spec, §7: sticky notes and comment frames, plan `2026-10-09-comments.md`)
code is done; its human checks (group CM) are pending.
Typing on the canvas (spec §8: a double click on a note or a frame's title bar edits it in place; plan
`2026-10-10-comments-canvas-typing.md`; the graph's keys and text focus on MetalUI C9's key regions) code is done; its human
checks (group CT) are pending. The field opens with a frame's title all selected and a note's caret at its end (MetalUI C25,
gap CT-b adopted by plan `2026-10-12-adopt-c25.md`; checks C25 pending). The canvas's node, wire and comment views skip their content while unchanged (MetalUI C14
slice 1, gap PERF-b partly fixed, plan `2026-10-13-adopt-c14.md`; checks C14 pending).
Groups C1 (model and evaluation, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §4–§5) is done.
Groups C2 (the editor, §6: entering a group, breadcrumbs, the + sockets, the group inspector, the library's Groups
section, the viewport and the clipboard inside groups) code is done; its human checks (group GR) are pending.
Named undo steps (plan `docs/superpowers/plans/2026-10-10-named-undo.md`) code is done; its human checks (group NU) are pending.
Final-review follow-ups (plans `docs/superpowers/plans/2026-10-10-followups-app.md`, `2026-10-10-followups-editor.md` and
`2026-10-10-followups-kernel.md`) code is done; the app track's human checks (group FA) are pending.
Data trees (sub-project 7a-1: spec `docs/superpowers/specs/2026-10-10-patterns-trees-design.md` §2 and §4's tree nodes, plan
`docs/superpowers/plans/2026-10-10-7a-trees.md`) code is done; its human checks (group TR) are pending.
Patterns, sub-project 7a-2 (Place, Points to Placements, the four shortcut nodes, the `Patterns` library category and the
200-instance benchmark; plan `docs/superpowers/plans/2026-10-10-7a-place.md`, spec `2026-10-10-patterns-trees-design.md` §3, §5,
§6, §7) code is done; its human checks (group PA) are pending and its benchmark numbers (`PatternBench`) await an idle run.
Patterns, sub-project 7a-3 part A (the five layout nodes, trees of placements through Place and the shortcuts, instance
tags by
tree path, layout previews in the viewport, Pattern on Face and the acceptance test; plan
`docs/superpowers/plans/2026-10-12-7a-layouts.md`,
spec `2026-10-10-patterns-trees-design.md` §3, §6, §8, §9 and its Errata (7a-3)) code is done; its human checks (group
PL) are pending.
Patterns, sub-project 7a-3 part B (variation and culling: Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values and
Jitter; plan `docs/superpowers/plans/2026-10-12-7a-variation.md`, spec `2026-10-10-patterns-trees-design.md` §4) code is done; its human
checks (group VA) are pending. The layouts, previews and acceptance test are part A (7a-layouts).
Fields, sub-project 7b-1 (the fields core: the `Field` value and `.field` sockets, `FieldSampler` and `FieldDistanceCache`,
`Kernel.distances`, the four sources, the six maths nodes, Sample Field and Cull by Field, the `Fields` library category and
`FieldBench` rows 1 to 3; plan `docs/superpowers/plans/2026-10-12-7b-core.md`, spec `docs/superpowers/specs/2026-10-12-fields-design.md`
§2 to §4, §7 and §9) is merged; its human checks (group FI-core) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`.
Fields, sub-project 7b-2 (images: the Image Field, `ImageReference` and `NodeSetting.image`, the document's `images` table,
`GreyImageDecoder`, choosing, linking, relinking and embedding a picture, file format 7, and a `field` socket on a group's edge; plan
`docs/superpowers/plans/2026-10-13-7b-2-images.md`, spec `docs/superpowers/specs/2026-10-12-fields-design.md` §5 and the 7b-1 Errata)
code is done; its human checks (group FI-img) are pending.
Fields, sub-project 7b-3 (Field Scatter, the surface tint, the slice plane and the legend, the three theme roles `fieldLow`,
`fieldMid` and `fieldHigh`, the acceptance test and `FieldBench` rows 3 and 4; plan
`docs/superpowers/plans/2026-10-13-7b-3-scatter-previews.md`, spec `docs/superpowers/specs/2026-10-12-fields-design.md` §3.3, §6, §7
and §8 and its Errata (7b-3)) code is done; its human checks (group FI) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`.
Implicit geometry, sub-project 7c-1 (the core: the `CreatorImplicit` module, the `implicit` and `mesh` socket types, the CPU and Metal
evaluators, the sparse octree, the manifold mesher, baked distances, the eleven Implicit and Mesh nodes, mesh items and the progressive
preview in the viewport, STL of meshes with the export sheet, file format 8 and `ImplicitBench` rows i-1 to i-4; plan
`docs/superpowers/plans/2026-10-13-7c-core.md`, spec `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §2 to §6 and the
7c-1 errata in the plan's header) code is done; its human checks (group IM) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`. The mappings (7c-4) are not built.
Implicit geometry, sub-project 7c-1g (meshing on the GPU, spec Errata D13: `ImplicitGPUEngine.meshBricks`, the Metal marching-cubes
kernels with a CPU-against-GPU mesh agreement suite, and rows i-1 and i-2 measured on that path; plan
`docs/superpowers/plans/2026-10-14-7c-1g-gpu-meshing.md`) code is done; its human check (IM-13) is pending and its benchmark numbers are
recorded in `docs/verification/performance.md`. The SDL3 engine for Linux and Windows is track xp-c.
Implicit geometry, sub-project 7c-3 (the mesh tools: Decimate, Check Thin Walls, Check Trapped Volumes, Drain Holes and Mesh to Solid;
3MF with our own `ZipWriter`; the streamed export of spec Errata D12; the Cut view; `ImplicitBench` rows i-4b to i-7; the lightweight
bracket acceptance test; plan `docs/superpowers/plans/2026-10-14-7c-3-mesh-tools.md`, spec `2026-10-13-implicit-lattices-design.md` §3.6,
§4.5 to §4.7, §5 and §7 with Errata D12 and D16) code is done; its human checks (group MT) are pending and its benchmark numbers are
recorded in `docs/verification/performance.md`. Mesh to Solid and the Cut view are macOS-only (OpenCascade, Metal); everything else runs on
Linux and Windows.
Implicit geometry, sub-project 7c-3f (spec Errata D18, resolving M5: the TPMS, Strut Lattice and Voronoi Lattice nodes gain a `blend` input, default 1 mm, the radius of the smooth union that joins the skin and the lattice, `typeVersion` 2 with a migration that gives a saved graph's node a blend of 0; Check Trapped Volumes decides inside by the mesh's generalized winding number, asked once per region of cells; Check Thin Walls skips a hit under 0.05 mm on a face of the start vertex's one-ring; the lightweight bracket acceptance test asserts 0 voids and 0 thin places, its `withKnownIssue`s gone; plan `docs/superpowers/plans/2026-10-20-7c-3f-skin-blend-and-robust-checks.md`) code is done; its human check IL-10 is pending.
Implicit lattices, sub-project 7c-2 (the TPMS, Strut Lattice and Voronoi Lattice nodes with the Straight mapping only, a region and a
skin, field grading of cell size, thickness and strut radius, a separate cell stretch vector, their warnings, and `ImplicitBench`'s sheet
swapped to a gyroid; plan `docs/superpowers/plans/2026-10-14-7c-2-lattices.md`, spec
`docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §3.4 and Errata D14) code is done; its human checks (group IL) are pending
and the benchmark rows have not been re-run with the gyroid. The mappings (7c-4) are not built, so the lattice nodes have no `mapping`
input yet.

Cross-platform, sub-project xp-1 (Linux and Windows on MetalUI's SDL backend: everything but the 3D view and OpenCascade; plan
`docs/superpowers/plans/2026-10-13-xp-1.md`, spec `docs/superpowers/specs/2026-10-13-cross-platform-design.md` §2) code is done and
the suite is green on Linux in CI (GitHub Actions, `.github/workflows/xp.yml`, x86_64 and aarch64; `scripts/linux-test.sh` runs the
same in Docker); its human checks (group XP) are pending. Window chrome on SDL (MetalUI S1, gap XP-G3, branch `xp-adopt-s1`, CI pin `ceca59f6`): the window is borderless and MetalUI draws minimise, zoom and close (`drawsWindowControls` stays at its default), `TopBar` pads by `titleBarInsets.left` (`AppLayout.topBarClearance`, macOS's traffic lights) and `.right` (`topBarTrailingClearance`, SDL's 138-point cluster), the bar stays at the margin inside the 32-point band as on macOS, and the drawn Close reaches `AppModel.closeRequested()` through `installCloseHandling`; `SDLChromeWindowTests` pins both shapes (MetalUI's `Options.sdlChrome`); the drag regions are published with the real viewport behind the bar (gap XP-G11 fixed by MetalUI S1b, PR #87, branch `xp-adopt-s1b`, CI pin `a4ebe288`: a hitbox carves a handle only if it ranks above it, and a window-wide backdrop does not carve the band; divergence 425 amended, a viewport press inside the 32-point band drags the window, which nothing relies on), human checks XP-11..XP-14. The Windows job (CI run 38546048595) is green once: it builds, the suite passes (10 "Test run with" lines), and `--self-test` and
`--smoke-test 20` pass. Two failures that had been Windows-only were MetalCreator's own: the slice's starting axis chose YZ over XY on a
last-bit tie of the default camera's view direction (`SlicePose.startingChoice` now treats near-equal alignments as a tie), and the window
root, taller than the window with Windows' text metrics, was centred upward by the window's wrapper, so the top bar and the drag strip
sat 3 points high (`AppWindowRoot` now pins the root to the window's top left). The Windows job stays `continue-on-error`, with a
`::warning::` step and a summary line when its suite is red. On the way: `ImageResolver.read` has a Windows branch, the named-pipe and
device tests and `PackagingScriptTests` are not run on Windows, and the test executables reserve a 16 MB stack (`-Xlinker /STACK:16777216`;
a layout tree overflowed Windows' 1 MB default thread stack).
`Package.swift` has two lists, like MetalUI's: the targets that import no Apple
framework are declared everywhere (`CreatorViewport` too: its model, camera and tools are portable and only the Metal renderer files
are behind `#if canImport(Metal)`); `COCCT`, `CreatorOCCT`, `ViewportHarness`, `GraphPanelPreview` and `CreatorOCCTTests` are
declared on macOS only until xp-2. On Linux and Windows the MetalUI dependency asks for the `SDL` and `AccessKit` traits and
`MetalCreatorApp` links `MetalUISDL` (`main.swift` picks `SDLPlatform` with `PortableTextSystem` over the installed fonts under
`canImport(MetalUISDL)`). Off macOS the app runs over `KernelUnavailable` (every operation answers "Geometry isn't available on this
platform yet.") and the viewport's place shows `ViewportPlaceholder` ("The 3D view isn't available on this platform yet."). The Image
Field works everywhere: `GreyImageDecoder` decodes through MetalUI's `DecodedImage` (S2, gap XP-G4) on every platform. Rules
for new code: no CryptoKit (use `SHA256`/`SHA1` in `CreatorGraph/Hashing`), no CoreGraphics, ImageIO, CoreText or Metal outside a
`#if canImport(…)` file or block, keyboard shortcuts and modifier checks on MetalUI events say `.primary` (⌘ on macOS, Ctrl
elsewhere), and a file dialog's `ContentType` declares its `filenameExtensions`. Tests: a test that needs Metal, OpenCascade,
CoreText is gated with `#if canImport(Metal)`, `canImport(CreatorOCCT)` or `canImport(CoreText)` and so is absent from the Linux
count, never from macOS's; render tests take their text system from `testTextSystem()` in each target's
`Support/TestTextSystem.swift`; picture fixtures come from `TestImages` (ImageIO on macOS, `PNGWriter` elsewhere; JPEG, GIF and
TIFF fixtures need ImageIO, so those tests are `#if canImport(CoreGraphics)`, and `GreyImageDecoderPinnedTests` carries JPEGs as
bytes for every platform) and `AppTestImages` (plain Swift). Pass
rules: macOS, exit 0 and 12 "Test run with" lines; Linux, exit 0 and 11 (`CreatorOCCTTests` is macOS's twelfth; `CreatorImplicitTests` joined in 7c), and neither
may print "recorded an issue" or "failed after".

Module boundaries (dependency order):
- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
- `CreatorSketch`: the constraint sketch model, `SketchSolver` (numeric Levenberg–Marquardt with analytic Jacobians,
  DOF and minimal conflicts), `SketchRegions` and `SketchCommands`. Imports only `CreatorGeometry` and Foundation;
  never iterate a dictionary where order reaches output. Tests: `swift test --filter CreatorSketchTests`.
- `CreatorKernel`: the `Kernel` protocol, `Solid`, tagged topology tables, `FakeKernel` for tests (it refuses extruded holes that lie outside
  the outline's bounds, as OCCT refuses strays). `Kernel.place(_:at:qualifying:tag:)` makes every placed copy of a pattern in one
  call: copy `i` is a tool moved by a `Transform`, its tags requalified (`Topology.qualified(item:_:)`: node → `qualify(node)`,
  item → `i`, nested blend source edges too). A pattern over a tree renames each copy afterwards
  (`Topology.withInstanceItem(_:)`,
  no kernel call): `InstancePath` is the one place a path becomes a tag item and back, `{i}` being the item `i` (so a
  pick saved
  before trees resolves unchanged) and `{a;b}` to `{a;b;c;d}` (indices up to 32,767) one negative `Int`.
  `NodeID.isInstanceQualified` (a version-8 UUID) tells those nodes from any other,
  and `Topology.vanishedInstances(in:)` finds the copies a pick names that a topology no longer has.
  `Kernel.distances(from:to:signed:)` measures a batch of points to a `DistanceTarget` (`.solid`, `.faces`, `.edges`; fields
  spec §3.1): millimetres to the surface, negative inside a solid when signed (the sign is ignored for faces and edges);
  `DistanceTarget.validate()` gives every kernel the same refusals and `.identity` is what the field cache keys on. `FakeKernel`
  is exact for its boxes, for planar faces measured to their infinite plane and for straight or circular edges
  (`EdgeCurve.distance(from:)`, shared with Cull by Region), and throws `unsupported` for the rest.
- `COCCT` + `CreatorOCCT`: the OpenCascade C shim and `OCCTKernel: Kernel` (topology tables, face tags carried through
  OCCT history, tessellation, STEP/STL export). **The only code that may touch OCCT.** Every C allocation has a
  `*_free`; no C++ exception crosses into Swift. `occt_distances` (`cocct_distance.cpp`) measures points to a solid's faces,
  picked faces or picked edges: planes and cylinders bounded by lines and circle arcs by exact formulas (`cocct_distance_analytic.hpp`),
  every other face with `BRepExtrema_DistShapeShape` (to the faces, not the solid: OCCT answers 0 for a point
  inside a solid; `occt_distances_reference` is the Extrema-only path `DistanceFastPathTests` compares to at 1e-9) and signs a solid's distance with `BRepClass3d_SolidClassifier`, only for a point inside the solid's bounds; it
  shares the points out in blocks of 64 over OCCT's thread pool while `OCCTKernel.serialized` is held, and the caller's buffer
  is the output, so it allocates nothing to free. `OCCTKernel` calls it 1,024 points at a time, checking for cancellation between.
- `CreatorImplicit`: implicit solids and meshes (implicit spec §2 to §4): the `ImplicitSolid` value, the CPU batch evaluator, the Metal
  compiler (gated with `#if canImport(Metal)`), the sparse octree (`BrickPlan`), `MeshingBudget` and the mesher. Portable (declared on every
  platform); depends on `CreatorGraph` for `Field`, which holds these only as `ImplicitPayload` and `MeshPayload`. Tests:
  `swift test --filter CreatorImplicitTests`.
- `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
  `.mcgraph` files, `DocumentModel`. Depends on `CreatorSketch` for the `ConstantValue.sketch` setting. A node's sockets
  are `NodeRegistry.inputs(for:)`/`outputs(for:)`: `NodeDefinition.inputs(for:)`/`outputs(for:)` of its type
  (default: the static lists), or, for a group node, Group Input or Group Output, its definition's (the registry
  carries the document's definitions: `DocumentModel.registry`, `withGroups(_:)`). Every reader (the Evaluator,
  `connectionProblem`, the canvas, the inspector) asks the registry, so per-node sockets wire and gather like declared
  ones.
  - Undo names: every undo step carries a short English name (`UndoStack.Entry.name`), given where the edit is made:
    `DocumentModel.perform(_:at:coalescingKey:name:)` takes one of `UndoName`'s constants ("Add Note", "Move", "Delete");
    without one (or a blank one) the step is "Edit", so a forgotten name shows as "Undo Edit" and fails the test of its
    call site. A coalesced run keeps its first record's name. Names have no numbers and never include text the person
    typed (a note, a group's or dimension's name); an input is named by its fixed label ("Change Width"), a node by its
    type ("Add Box"). The sketch editor (graph-free) gives each `SketchCommit` a fixed `name` from `SketchStepName`
    ("Add Line", "Change Dimension", "Fillet"; `SketchEditorModel.commit` requires `named:`, `SketchCommit.init` and
    `EditorModel.edit` require `name:`), which `AppModel.storeSketch`
    passes through `UndoName.sketch(_:)`; `SketchCommit.description` ("Rename d1 to Plate width") holds typed text and
    numbers and is never a name. `DocumentModel.undoName` and `redoName` feed `AppModel.undoTitle` and `redoTitle`, which
    the Edit menu (`AppCommands`) and the top bar (`TopBar`) show as "Undo <name>" and "Redo <name>" (plain "Undo"/"Redo"
    with nothing to take back). Names are in memory only and not part of `.mcgraph`. Tests: `UndoNameTests`,
    `EditorUndoNameTests`, `SketchStepNameTests`, `AppUndoNameTests`, `UndoTitleTests`.
  - Groups (`Sources/CreatorGraph/Groups`): `GroupDefinition`s live in `GraphContent.definitions` beside the top-level
    graph (`DocumentModel.content`); a group node is type `group` with `NodeSetting.group`, and every `NodeRegistry`
    registers `group`, `groupInput` and `groupOutput` itself (`NodeRegistry.all`, the palette's list, leaves them out).
    Edits go through `GraphContent.apply`: graph commands on the top level, `.inDefinition(id, …)` (or
    `DocumentModel.perform(_:at:)`) inside a definition, plus `addDefinition`/`removeDefinition`/`setInterface`; it
    refuses a group inside itself (`GroupDependencies`), an Output node in a group and a stray or missing Group
    Input/Output, and (after the whole command) a socket removed or retyped while still wired. `GroupCommands`
    builds Group, Ungroup, Make Unique and the definition edits as `GroupEdit`s (one undo step). The Evaluator runs
    a group node's definition level by level (`Evaluator+Groups`): values pass through, inner nodes evaluate and
    cache under `NodeID.scoped(instance path + id)`, so their tags differ per instance and stay put when the
    definition is edited; inner messages read "Rib › Fillet: …". A pick stored inside a definition names faces as
    if the definition were the top level (`GroupScopes.identity`), and `EvaluationScope.naming` reads it as each
    instance's; Group, Ungroup and Make Unique rename every pick whose faces they move (`GroupScopes.renamingPicks`),
    so no pick drifts. Dirty state compares `DocumentModel.content` (definitions too).
    The editor's levels (`GraphContent.path(entering:)`, `existingLevels(_:)`, `relativeToLevel(_:levels:)`: a level is
    the group nodes entered from the top level, each by its ID in the graph before it) and
    `DocumentModel.inspectedLevel` (the level the panel shows, which `Evaluator.evaluate(…inspecting:)` evaluates
    whole, so `innerResults` has a state for every node there; a node asked for that way never changes its group
    node's result). `GroupCommands.exposeOutput/exposeInput` (the + sockets) and `GroupMerge` (the clipboard's
    definitions, merged by content) build one command each. `GroupNaming.plusSocket` ("+") is a reserved name.
  - Data trees (`DataTree`, `TreePath`, `Value.tree`; 7a spec §2): `Value` is `.one`, `.list` or `.tree`. A `DataTree` has a
    `depth` (1 is a flat list, which is why `Value(_ tree:)` makes a `.list` of it, except a culled list, below), every branch at a level has the same depth,
    and a gap is an empty branch. `TreePath` (`{0;3}`, `TreePath(parsing:)`) is the one path type: derived, never stored, and
    what later instance names adopt. Broadcasting stays flat (the old code, unchanged) until a `.tree` meets an item or list
    socket; then `BroadcastPlan.nestedPlan` matches level by level: the outermost level first, the shorter side repeating its
    last branch, a `.one` or flat list applying to every branch, a `list` socket using up one level (one branch per run),
    trees of different depth matched from the outside with one warning naming both shapes, and more than
    `maximumTreeIterations` runs refused. Outputs keep the deepest nesting (`BroadcastPlan.assemble`). A `tree`-access socket
    (`SocketSpec.Access.tree`, `NodeInputs.tree`) gets the whole value as a `DataTree` and never broadcasts; a node returns
    trees through `NodeOutputs(trees:)` and must run once (other inputs single values;
    `NodeDefinition.singleValuesRefusal` lets a node, the layouts, refuse a list
    there in its own words before it runs). `SocketType.any` is for the tree
    nodes' sockets only. Iteration `item` numbers (the tag's item) are flat, row by row.
    Culling keeps paths (patterns spec §4): a flat list or branch that has had items taken out holds the survivors at the indices
    they had (`DataTree.culledList(_:at:)`, `isCulled`, `itemPositions`; `DataTree.keepingItems(where:)` and
    `mappingItems(_:)` are how nodes cull and refill, `replacingItems(_:)` keeps the indices), and since a `.list` cannot say which
    indices its items keep, such a list is a `Value.tree` of depth 1 (`Value(_:)` makes every other flat tree a `.list`). It broadcasts as a list: an item or list socket sees
    the survivors in order, as a rank, and a `tree` socket gets the tree whole with its indices, which is how `InstanceGrid` reads
    them. Reshaping nodes (Flatten, Graft, Partition, Path Mapper) renumber, as reshaping does, and List Item, Branch by Path and
    Tree Statistics count a culled list's survivors by rank; Cull Index alone names the places items had.
- `CreatorImplicit` (depends on Graph, Kernel and Geometry; implicit spec §2 to §4): `ImplicitSolid` (an indirect enum of sphere, box,
  cylinder, rigid move, union / subtract / intersect with a graded blend, offset, shell, baked distance blocks, isosurface and the three
  lattices `tpms`, `struts` and `voronoi` (`Lattice/`: `TPMSLattice`, `StrutLattice`, `VoronoiLattice` with their `LatticeCells`,
  `TPMSType`, `StrutCell` and `VoronoiSeeds`; each is cut to its region's box and the lattice nodes intersect it with the region); every
  case has `bounds`, `lipschitz`, `exactReach` and a one-line `description`, in `Solid/`), `Grading` (a setting that may vary over space:
  a `Field` with the kernel distances in it baked, and its range and slope), `DistanceBlocks` (sparse 8³ blocks of `Float` distances,
  trilinear, with a conservative bound for unstored blocks) and `TriangleMesh` (positions, normals, triangles, `resolution`, `quality`,
  optional `MeshSource` for the progressive preview; `MeshTopology` checks closed, oriented and manifold). `CPUEvaluation` (`Double`) is
  a complete engine on every platform, and the reference the GPU is held to; `ImplicitCompiler` generates Metal source whose text depends
  on the tree's shape only (numbers go in the buffers) and imports nothing. **The module builds on Linux and Windows (Errata D11):** the
  GPU sits behind `ImplicitGPUEngine` (`GPU/`: prepare, compile, evaluate a batch, mesh bricks, cancel), whose only
  implementation is `MetalImplicitEngine` (an actor that compiles each shape once; the one file that imports Metal, compiled only under
  `#if canImport(Metal)`), `ImplicitGPUEngines.platformDefault` is the machine's engine or `nil`, and `ImplicitPortabilityTests` fails
  on an Apple-only import or a Metal type anywhere else in the module. The agreement suite `GPUAgreementTests` holds Metal to the CPU
  within 1e-4 mm (skipped without a Metal device). `ImplicitEvaluators.make` picks the engine and falls back to the CPU, warning
  "Running on the CPU" when a solid will not compile (the reason is `Selection.diagnostic`, not shown). `BrickPlan` is the sparse octree (prune by |f| / lipschitz; 8³-voxel
  bricks), `MarchingCubesTable` is generated by a fixed rule (never join inside corners across a face; no triangle flat in a face), and
  `ImplicitMesher` meshes brick batches into a watertight, manifold mesh (global edge keys, a Newton snap, the memory refusal
  `MeshingBudget`); `PreviewSchedule` is the passes of the progressive preview (Auto goes on while four times the last pass is under a
  second and four times its triangles are within `maximumTriangles`, 2,000,000: the cap of Errata D15). **Meshing on the GPU (Errata D13):** `ImplicitMesher`
  first offers the plan's bricks to the evaluator (`ImplicitBatchEvaluator.meshBricks`, which `GPUBatchEvaluator` passes to
  `ImplicitGPUEngine.meshBricks(_:_:progress:)`: a `BrickMeshRequest` in, a `BrickMesh` of flat arrays out, no GPU type in either). The
  default requirement returns `nil`, and the mesher then meshes on the CPU, which stays the reference and the fall-back: it also
  takes over when the engine fails, returns arrays that do not fit (`BrickMesh.isConsistent`), or a request is beyond the engine's
  limits (a window of more than 32-bit edge keys, a table over `largestTable`). **That fall-back is silent: test and measure
  `ImplicitMesher.meshReportingPath(...).path` (or `MetalImplicitEngine.meshesMade`), never just the mesh.**
  `MetalImplicitEngine+Meshing` runs the five kernels of `ImplicitMeshShaderLibrary` (Metal source as text, so an SDL3 engine
  translates it) over `BrickLattice`'s window with `MarchingCubesBuffers`, the CPU's table as a buffer; the order of vertices and
  triangles is the threads', the set is fixed. `GPUMeshAgreementTests` holds the GPU mesher to the CPU mesher's topology, triangle
  count, vertices (1e-4 mm on the same samples, for parts near the origin), normals and enclosed volume. `SignedDistanceMesh` (BVH; `signedDistance(at:)` takes its sign from the pseudonormal, for the bake, and `isInside(_:)`, `robustSignedDistance(at:)` and `windingNumber(at:)` from `WindingNumber`, the generalized winding number summed exactly near the point and as dipoles of BVH clusters far from it, which the checks use; `LazyWindingNumber` builds its clusters on the first such question, so the bake never does),
  `DistanceBaker`, `ImplicitBakeCache` (actor, 512 MB, LRU, keyed by solid identity and tolerance) and `GradingBaker` bake a solid or a
  field's kernel distances. `STLWriter` writes binary STL. CreatorGraph cannot name `ImplicitSolid` (it depends on Graph for `Field`), so
  a value on a wire is an `ImplicitPayload` in an `ImplicitReference` (`Scalar.implicit`, `Field.implicit`) and a mesh a `MeshPayload`
  (`Scalar.mesh`); `ImplicitReference.solid` reads the solid back. `Scalar.converted(to: .mesh)` leaves an implicit as it is: the node
  that takes a mesh socket meshes it (`MeshInput` in CreatorNodes). `EvalContext` carries `meshQuality` (`.preview` / `.export`;
  `NodeDefinition.readsMeshQuality` puts it in a node's cache key), `implicitEngine` and `meshProgress`. Tests:
  `swift test --filter CreatorImplicitTests`.
  The mesh tools (7c-3, `Mesh/`): `MeshDecimator` is quadric error edge collapse (`Quadric`, `EdgeHeap`, `MeshDecimationState`): a
  collapse is refused when it breaks the link condition, flips a face or costs more than the tolerance (the cost is the quadric error
  at the new vertex, so its square root bounds the distance to every triangle plane absorbed), vertices on an open edge are pinned, and
  a closed mesh stops at a tetrahedron. `ThinWallCheck` (a ray inwards from each vertex against `TriangleBVH`, the far side must
  face back; the two sides of a wall are one place; a hit under 0.05 mm on a face that touches the vertex's one-ring is the mesh folding on itself and is skipped, Errata D18), `TrappedVolumeCheck` over `OccupancyGrid` (0.5 mm cells within a 32-million-cell
  budget, Errata D16; solid within half a cell of the surface, the cells near the surface from `unsignedDistance`) and `EnclosedVoids` (flood fill from the padded corner; with `isInside` it asks the winding number about five cells of each pocket, judged once the pocket has 4,096 cells listed, and drops a pocket that is inside the material, once per pocket and never per cell: per cell it is 23 to 35 times slower, Errata D18), and `DrainHoles`
  (the same test on the implicit, whose inside is the sign of its own field; a hole is `subtract` of a moved `cylinder`, so no new `ImplicitSolid` case). `MeshWelder` merges
  vertices before `Kernel.meshToSolid` (the OCCT shim `occt_mesh_to_solid`: a planar face per triangle sharing vertices by index,
  `ShapeUpgrade_UnifySameDomain`, voids as inner shells, `BRepCheck_Analyzer`; no `BRepBuilderAPI_Sewing`). Export (spec Errata D12):
  `StreamingMesher` takes the plan's bricks in runs of whole columns (windows), meshes and snaps each on the CPU over the evaluator's
  values (GPU values when the engine is a GPU's), may decimate it (`MeshStage`), and hands it to a `MeshSink` as a `MeshWindow` whose
  vertices carry their number in the file; a vertex on the plane two windows share is matched by its bits and written once, and when the
  new window has triangles on that plane every vertex the previous window made exactly on it must be matched, or the export stops with
  `seamsDidNotJoin` (a separate body that stops short of the plane needs nothing). `STLFileWriter` and `ThreeMFWriter` are the sinks (the
  3MF writes each object's vertices and triangles to two temporaries and joins them in the zip); `ZipWriter` streams with data
  descriptors, dates fixed, Zip64 where a size, offset or count reaches 4 GB, and deflates through `RawDeflater` where
  `canImport(Compression)`, else stores. `MeshStream` is what a Mesh node returns while `EvalContext.meshQuality` is
  `.streamedExport`: the implicit, the resolution and the stages.
- `CreatorNodes`: the 85 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch,
the fourteen `Fields` nodes below, the fourteen `Implicit` nodes and the five Mesh nodes (`Implicit/`, categories `NodeCategory.implicit` and
`.mesh`: Sphere, Box, Cylinder, Union, Subtract, Intersect, Shell, Offset, To Implicit, Isosurface, Drain Holes, TPMS, Strut Lattice, Voronoi Lattice
(`Implicit/Lattices/`: they share `LatticeSetup` and `LatticeFill`, which joins the skin and the lattice by a smooth union of the `blend` input, 0 on a graph saved before 7c-3f; the built-in Voronoi seeds are `VoronoiSeedSource`, drawn with
`SeededRandom.Purpose.voronoi`); Mesh, Decimate, Check Thin Walls, Check Trapped Volumes, Mesh to Solid in `Implicit/MeshTools`), the seventeen
  `Patterns` nodes below, and the seven Lists & Trees nodes in `Lists/`: Flatten, Graft, Partition, Tree Statistics, List Item, Branch by Path and Path
  Mapper, whose rule syntax is `Lists/PathMapper/PathRule`), UI-free: inspector sections and handles are data. Non-socket settings (`NodeSetting` in CreatorGraph:
  parameter, picks, showHandle, sketch, face, groupID, pathRule, branchPath, itemPath, cullPattern, cullIndices, image, and `projection(reference)` per projected edge) live in
  `Node.inputValues`; `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
  - Patterns (`Sources/CreatorNodes/Patterns`, category `NodeCategory.patterns`, library section "Patterns"; patterns spec §3, §5–§7):
    The layouts (`Patterns/Layouts`): Linear Pattern (a flat list), Grid Pattern (a tree, a branch per row), Circular
    Pattern (a
    branch per ring; `countStep`, `radiusStep`, `startAngle`), Curve Pattern (a branch per chain of straight or circular
    edges,
    `EdgeChains`, or per loop of a profile) and Face Pattern (a picked flat face, `FaceRegion` clipping to its holes and
    a margin; a
    branch per row holding a branch per grid cell, counted from the lowest row and column its box reaches, so a vent
    keeps its path
    as the margin or a hole changes (a face growing at its lower left renumbers)), each refusing over 2,000
    (`PatternLimit`). A layout that is a tree is one even for one row or ring, so a ring added later renames no path. A
    list wired into
    a layout's input is refused in its own words (`NodeDefinition.singleValuesRefusal`, before it runs).
    Place (a tool built at the origin facing +Z and `Plane` placements, matched by `InstanceGrid`: the longer flat list
    sets the
    count and the shorter repeats its last item; a tree of placements gives a tree of copies, a flat list applying to
    every
    branch and a tree as deep as the shape matching level by level, so a Graft of one size per ring sizes the rings),
    Points to Placements, and the shortcuts Hole Pattern, Boss / Pin
    Pattern, Slot Pattern and Pattern Feature, each Place + Boolean underneath through `PatternApply`: tools built once per
    distinct size (`ToolPlan`), one `Kernel.place` and one `Kernel.boolean`, never a boolean per instance. A shortcut's sizes
    are `.tree` sockets matched to the placements by `InstanceGrid` (inside the node, so it can make one kernel call).
    Over 2,000
    instances refuses ("Patterns are limited to 2,000 instances.", `PatternLimit`); a tree on the part or the operation
    is refused
    (`EvalContext.isTreeRun`, `PlacementMoves.requireSingleValues`); placements, sizes and tools are read whole, one
    kernel call for a tree; an instance that did nothing to the part
    warns with the count (`PatternMisses`: a cut leaves no face tagged with its item, a union's bounds don't touch the
    part's). A copy's tags are its tool's, qualified: node `NodeID.instanceScoped([placer, toolNode])` and item the copy's
    path (`InstancePath.item(for:)`: `{i}` is the item `i`, `{row;i}` one packed negative number), so a pick follows its
    instance through
    count, spacing and size changes; `EdgeTagMatch` and Plane from Face say "Instance {4} no longer exists…" (several,
    in path order) when it is gone
    and never fall back to a neighbour. In a group, `EvaluationScope.entering` lifts its renaming table to the placer/tool
    pairs (`GroupScopes.lifting`, `NodeDefinition.placesInstances`), and `GraphContent.relativeToLevel(_:levels:registry:)`
    does the same for a pick made in the viewport inside one. Group, Ungroup and Make Unique rename instance picks too
    (`GroupScopes.names` lifts its table with the registry); not lifted yet: a Place inside a group whose tool comes from
    outside it keeps instance picks stored in the definition from matching.
  - Variation (`Sources/CreatorNodes/Patterns/Variation`, category `Patterns`; patterns spec §4): Cull Pattern (a text mask `1 0 1`
    or a wired `keep` list, repeated along each branch, or with scope Overall along the whole tree, over the items it has now), Cull Index (indices and `{0;3}` paths as text, or
    wired numbers; an index or path names the place an item had before any cull; a bare index is a place within a branch, so on a
    `{row;column;0}` tree of one item per branch use paths), Cull by Region (placements inside or outside a
    profile, within or beyond a distance of a point, an edge set's straight and circular edges, or flat faces' planes;
    `RegionDistance`, `Profile2D.contains`), Random Reduce (`RandomReduction`; scope Overall by default), Random Values (reals and `integers`, in the shape of
    a tree or a count) and Jitter (`PlaneJitter`). Each takes a tree whole (`tree` access) and returns the same nesting with a
    culled list where items went. **All randomness is `SeededRandom`: SplitMix64, written out in the repo and pinned by
    `SeededRandomTests`, never the system's generator.** A draw depends on the seed, the item's branch ordinal (the stream) and its
    index in the branch, never on how many items there are, so a cull or a longer list reshuffles nothing; a seed never warns.
    Each node draws for its own `SeededRandom.Purpose` (the seed is mixed with a fixed per-node constant), so equal seeds on
    different nodes give unrelated numbers; the constants are pinned like the algorithm. `InstanceGrid` makes exactly the instances
    a culled list or branch of placements holds, at the paths they had (`{0;2}` is still `{0;2}` when `{0;1}` is gone: the tag
    item is `InstancePath.item(for:)` of the item's branch path and the index it kept), reads every other input at an instance's
    index (its own value, else the nearest one before it, else its first; a culled size or tool list that is not the lead sets no
    number of instances, however many survivors it holds) and gives Place's copies back in the placements' shape with the same
    gaps. Points to Placements takes `points` and `direction` whole and returns placements at the same paths, so a cull may sit
    anywhere before it. So a pick on one instance survives a cull of another and a pick on a culled one warns naming its path.
  - Fields (`Sources/CreatorNodes/Fields`, category `NodeCategory.fields`, library section "Fields", after Lists & Trees; fields spec
    §3): `FieldSampler.sample(_:at:kernel:cache:)` is the one way to read a field: it walks the expression once per batch over
    structure-of-arrays `[Double]`s, checks cancellation every 1,024 points, asks the kernel once per distance leaf (through the
    evaluator's `FieldDistanceCache` when given), and never lets a value depend on the rest of the batch; its one `switch` over
    `Field` has no `default`, so a new case (the Image Field's `.image`, 7b-2, was the first) is a compile error there, in `Field.children`, `Field.description` and
    `Field.ownPlane`. `FieldNoise` is 3D simplex noise hashed with `SeededRandom` (purpose `.fieldNoise`, the octave as the stream;
    `.fieldCull` is Cull by Field's; both pinned in `FieldNoiseTests` like the others). The sources are Distance Field (`target` is
    an `any` socket: a vector, edge set, profile, face set or solid; `mode` Unsigned / Signed matters to a solid only), Linear
    Gradient, Radial Gradient and Noise Field; the maths nodes (`Maths/`) are Add, Multiply, Min / Max, Remap, Clamp and Smooth
    Blend, each over `.field` item sockets, so a list of fields broadcasts and a number typed or wired in is a constant field.
    Sample Field (`at` is a `plane` socket with `tree` access, so points and placements both wire) returns numbers in the shape of
    `at`, culled gaps and paths included, from one sampler call; a single plane gives a list of one. Cull by Field keeps placements
    by Threshold (Above and Below both keep a value exactly on the level) or Probability (a `.fieldCull` draw at the item's kept
    index, stream = branch ordinal, below the field held to 0…1, as Random Reduce draws), keeping paths; both refuse a list in any
    input in the layouts' words (`singleValuesRefusal` = `LayoutChecks.singleValues`). The graded-sizes chain is a field → Remap →
    Sample Field → a shortcut's size socket (Remap takes and returns a field, so the spec's reverse order cannot be wired; fields
    spec Errata (7b-1)). Fields are computed, never saved; a group interface may carry a `field` socket (format 7: under 6 `"field"`
    would not decode in an older build, so 7b-1 refused it with `GroupRefusal.fieldSocket`, now gone). The distance cache counts the
    solids its entries keep alive. `FieldBench`
    (`Tests/CreatorAppTests/Bench`): rows 1 and 2 are the spec's (row 2's 100 ms is for analytic solids and gates the merge;
    `field-2b` records a smooth loft); row 3 is Field Scatter over a face (`field-3b` keeps 7b-1's Sample Field and Cull by Field
    over 2,000 placements); row 4 (`FieldBenchPreview`) is the edit to a tinted preview on the bracket. Timings taken on a loaded
    Mac are recorded as saturated, never as a verdict.
  - Images (fields spec §5; plan `2026-10-13-7b-2-images`): the Image Field (`Fields/Sources/ImageFieldNode`) projects a picture along a
    plane (centred, `width` × `height` mm, row 0 at the plane's +y, Tile or Clamp, bilinear grey in 0…1) as `Field.image(GreyImage,
    plane:width:height:edges:)`. The picture is the node's `NodeSetting.image`, a `ConstantValue.image(ImageReference)`: `.embedded(ImageHash)`
    (the SHA-256 of the file's bytes) or `.linked(relativePath:absolutePath:)`. **Images are untrusted input**: `ImageLimits` (16 MB, 8,192 px
    a side, PNG and JPEG only) are checked from the header before a pixel is decoded (`GreyImageDecoder.inspect` over MetalUI's `ImageInfo(data:)`, S9, gap XP-G10, with `OtherPictureSignature` for
    GIF and the like, gap XP-G12; `PNGStructure.isWhole` still refuses a cut-short PNG), `decode` runs off the caller's actor and
    decodes through MetalUI's `DecodedImage(data:format: .rgba)` on every platform (S2, gap XP-G4; ImageIO is not used anywhere in `Sources`),
    then converts to grey in 32 MB bands, checking for cancellation between them and applying the orientation as it indexes the stored
    pixels (no oriented copy). Peak memory at 8,192²: the file (16 MB), MetalUI's whole decoded RGBA (256 MB, whatever the bit depth) and the 128 MB result,
    so about 0.4 GB, plus any transient copy inside MetalUI's decode; the decode itself cannot be cancelled. A 16-bit PNG is read to the
    nearest 8-bit level (S2 rounds), a PNG with a bad CRC and a truncated JPEG are refused. A linked path must be
    a regular file, opened without blocking and checked again on the descriptor, and is read at most 16 MB + 1 byte (`ImageResolver`),
    and every failure is an `ImageProblem` with its sentence. Colour becomes Rec. 709 luminance of the straight-alpha colour composited against black (our conversion, not S2's `.grey`, which is Rec. 601
    with alpha dropped); EXIF orientation is applied. `DocumentModel.images` is the session's pool of embedded bytes by hash (`addImage`; unused ones are dropped on save, not
    before, so undo works); `ImageResolver` (the pool and the document's folder) goes to every evaluation, and `gather` adds
    `ImageStamp` (a linked file's path, modification date and size, or an embedded hash) to a node's cache key, so a file edited on disk
    runs the node again at the next evaluation and nothing else does. `GreyImageCache` keeps decoded pictures by that stamp (256 MB, LRU) and, under the same stamp, the pictures that
    failed to decode (at most 256), so a damaged file fails at once until it changes; a read error is not remembered.
    `fileData(savingTo:)` writes the linked paths as they will be found from the new folder, and `DocumentModel.didSave(to:)` brings the
    open document's paths into line with them (no undo step, no edit). `Field.ownPlane` is the plane of the first linear gradient or
    image in a field (the slice plane of 7b-3 starts there). `NodeSetting.image` is the one setting not in `NodeSetting.reservedForSockets` (the names a group socket or an exposed Sketch
    dimension may not take), so one called "image" in an older file keeps working. The inspector's `.image` control makes a
    status line and the buttons that fit (Choose Image…, Link Image…, Relink…, Embed Image: `InspectorAction`s carried out by
    `AppModel.performImage`, which owns the panels); the clipboard carries the embedded pictures its nodes use.
    Field Scatter (7b-3, `Using/FieldScatterNode`) is the layout node for density: `solid` (a picked flat face, the `face` setting, read
    as Face Pattern reads it, holes and margin respected) or `profile` (exactly one), `field` (a number is a constant field),
    `minSpacing`, `maxSpacing`, `margin` and `seed`. `PoissonScatter` is variable-radius Bridson sampling: rounds of candidates in
    the annulus `r`…`2r` round each active point, the field asked once per round for all that survive the cheap tests, each active
    point taking its first candidate at least its own spacing from every placed point, a new seed drawn when nothing is active (islands,
    jumps in spacing), every draw `SeededRandom` under `Purpose.scatter`; the spacing at a point is
    `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`, so no two points are closer than `minSpacing`. It makes one flat
    list of placements on the region's plane in generation order, refuses over 2,000 ("Field Scatter would place N points; …", "more
    than 8,000" when it stopped at its ceiling) and renumbers when the field, region or seed changes: a pick on a scattered instance
    then warns "Instance {n} no longer exists". `InspectorControl.note(_:)` carries its help line, and the face menu's Scatter on Face
    (`AppModel.scatterOnFace`, `FaceLayout`) inserts one wired to the part.
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
    `lookAt(_ plane:framing:)` faces a plane, orthographic. A tool also takes the face or edge under a click it declined
    (`clickedModel`: the sketch editor's Project). `ViewportOverlay` also carries `fills` (`OverlayFill`: world triangles
    in the `.region` tint, one blended pipeline drawn under the lines, never in the ID pass) and `labels` (`OverlayLabel`:
    text anchored in world space, placed by `overlayLabels(measuring:)` and drawn as MetalUI text over the surface, hidden while
    the camera animates: gap S5-c; each box is its text's measured width, MetalUI C23: see below). The face menu adds New Sketch on Face (`ViewportEvents.newSketchOnFace`) on a flat
    face that has a normal, outside sketch mode.
  - `ViewportModel` (`@MainActor @Observable`, testable without a GPU) owns the camera, picking, the view cube,
    the context menu and handles. `ViewportRenderer`/`ViewportPicker` are the Metal side. `ViewportView` is the
    MetalUI glue. A `ViewportItem` with `isGuide` is no part of the scene: only its selected edges are drawn, after the
    solids and ghosts (faded where the part hides them), and it never frames, orbits, picks or opens the face menu
    (`ViewportRenderer+Guides`). The renderer keeps the triad's, the overlay's and the region fills' GPU buffers between
    frames: the overlay's key holds the grid's extent and the dashes' zoom, not the pose, so an orbit allocates none, and
    the fills' buffer is dropped once a frame has no fills (`RendererCacheTests`). `handleLabels(measuring:)` reads the size through
    the tracked `viewSize`, as `overlayLabels(measuring:)` does. Text sizes are measured, never estimated from a character count:
    `ViewportView` (and the sketch editor's `PointerReadoutView`) read MetalUI's `@Environment(\.textMeasurer)`, wrap it as a
    `TextMeasure` (`ProposalText` in `.caption`) and pass it into the model calls that place labels and chips; a model test passes a
    fake measure, a view test the real one (`TextMeasure.real()` in each test target's `Support/TextMeasureSupport.swift`).
    There is no default measure and no fallback estimate. Every scroll or pinch event stops a camera animation started mid-gesture.
    The field preview's half of the viewport knows numbers and colours only. A `ViewportItem` may carry `fieldValues` (one per vertex
    of `ViewportModel.displayMesh(of:)`) and a `FieldRamp` (three colours at three values; `FieldRamp.color(at:)` is the Swift twin of
    the shader's `field_ramp`): the renderer draws it with a second pipeline (`FieldShaders`: `field_mesh_*`, a float per de-indexed
    corner in a buffer `GPUMesh` keeps until the values change, `GPUGeometry.fieldCorners`), lit like the plain surface, never on a
    ghost, and wrong-sized values draw the plain surface. A `ViewportSlice` (`ViewportModel.showSlice`) is a translucent quad over the
    scene showing a grid of values (`r32Float`, read with a bilinear blend in `slice_fragment`, kept by `SliceTextures` until its
    `generation` changes); it is equal and hashed by `generation`, never by its values, is drawn ignoring depth (it passes through the
    part) and is never in the ID pass or `sceneBounds`. The viewport's shader source is `ViewportShaders.source + LineShaders.source + FieldShaders.source`.
    The cut view (implicit spec §5.1) is a `ViewportClip` (`ViewportModel.showClip`): the fragment shaders discard what lies on the
    side its normal points to, for faces, B-rep edges, field tints and the ID pass (`ClipUniforms` at fragment buffer 3, 4 for the
    tint, 0 for lines, off for handles), and a back face seen while cutting is the part's colour darkened. A `ViewportItem`'s
    `warningFaces` take the theme's warning colour (`ShadeUniforms.warning`, face-flag bit 4): a check's highlighted triangles.
  - It depends on Kernel, Geometry, CreatorStyle and MetalUI only, never CreatorGraph. The app shell turns graph outputs into
    `ViewportItem`s and `HandleSpec`s into `ViewportHandle`s.
- `CreatorEditor`: the graph panel and context inspector on MetalUI. `@MainActor @Observable EditorModel` holds all
  behaviour (selection, canvas transform, dock transpose, hit testing, wiring, clipboard, palette, inspector edits);
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
  Its input (MetalUI C7 gestures, C9 key scoping, C16 click counts and cancellation, and the palette's stopgaps) lives only
  in `GraphPanelInput`. A double click on a node (a plain second click on its body that the platform counts 2:
  `DragGesture.Value.clickCount`, so the user's double-click speed decides, not a time of ours; gap S5-b) presses its first
  inspector button in `doubleClickActions` ("Edit sketch"; `nodeDoubleClicked(_:)`); the same on a note or a frame's title
  bar, not its edge band (a `ClickTarget`, kept in `lastClick` by the first click), starts editing it in place
  (`beginEditing(_:)`). While a sketch is open the app ignores it (`AppModel.handle(_:)`'s guard).
  The canvas builds only what can show (`EditorModel.drawnNodes`, `drawnCanvasRect`: the visible canvas grown by
  `cullingMargin`, everything while unplaced), and below zoom `rowsMinimumZoom` draws nodes without their rows
  (`drawsNodeRows`); hit testing, selection and edits always see the whole graph. A
  `ForEach` over nodes keys them `id: \.id.rawValue` (the whole UUID; a `NodeID` prints only 8 hex digits, and before
  MetalUI C20 a `ForEach` named elements by their description: gap M7-a, fixed). The graph panel measures itself: `GraphPanel`'s
  `onGeometryChange` writes `EditorModel.panelPlacement` (its frame in the window and `\.windowSize`, gaps EP-a and M4-a),
  tracked, so a resize or a move rebuilds the canvas; nothing computes the panel's place from `AppLayout`.
  The graph panel shows a level (`EditorModel+Levels`: `enteredGroups`/`levelPath`, `enterGroup(_:)`, `exitGroup()`,
  `goToLevel(_:)`, `breadcrumbs`, `refreshLevel()` after anything that undoes): `EditorModel.graph` is the level's
  graph, so every reader (hit testing, drawing, the inspector, selection) sees it, and every edit goes through
  `edit(_:coalescingKey:)`, which addresses `graphPath` (comments' edits too); the document's parameters stay on
  `rootGraph`. Each level keeps its own pan and zoom in the model (not saved), and changing level clears the selection.
  A group node's Edit Group, Make Unique and Ungroup are its inspector buttons (`InspectorAction`), carried out by
  `EditorModel.press`; a double click on a group node presses Edit Group through S5b's recogniser; ⌘↓/⌘↑ enter and
  leave. Group Input/Output draw a "+" socket (a `NodeShape` socket named `GroupNaming.plusSocket`); a wire between it
  and another socket exposes a socket (`EditorModel+Expose`). `GroupPanel` (`EditorModel.groupPanel`, `GroupPanelView`)
  is the inspector's definition part; the library's "Groups" section carries a group by the key `GroupLibraryEntry.key`
  through the library's one gesture. `NodeClipboard.definitions` carries the definitions copied group nodes use.
  Data trees show in two places (`EditorModel+TreeDisplay`): a socket carrying a tree has a tooltip, "Tree 3 × 8"
  (`socketHelp(of:)`, drawn by `SocketLayer`), and the inspector gets a "Data" section (`TreeShapeRow`: the shape, and a
  list of branch paths with item counts that `toggleShapeList(_:)` opens, cut after 50) only when the node has a tree on
  an input or output. A `.text` setting (the Path Mapper's rule, Branch by Path's and List Item's paths) is an `InspectorControl.text`.
  Fields show the same way: a socket carrying a field has a tooltip with its recipe cut to 80 characters (`Value.fieldSummary(limit:)`,
  "3 fields" for a list), and a node with a field output gets a last "Field" section (`InspectorRow.recipe`, which puts the text
  under its label so a long recipe wraps; `InspectorBuilder.fieldSection`). A field socket's dot borrows the Feature header colour
  (`Palette.header(for: .fields)`) until the theme has a role of its own. A node's `InspectorControl.note(_:)` is a line of help
  (Field Scatter's note on renumbering), shown as an `InspectorRow.recipe(label: "Note", …)`.
  The selection is `canvasSelection` (`CanvasSelection`: nodes and comments); `selection`
  is its nodes, and assigning it replaces the whole selection (selected comments too). Every gesture and key goes through
  `EditorModel+Selection` (`select(_:mode:)` with `SelectionMode`: none replaces, ⇧ adds, ⌘ toggles; `allItems`,
  `items(for:)`, `items(intersecting:)`, `positions(of:)`, `moveCommands(from:by:)`, `bounds(of:)`), the only members
  comments extend (spec 2026-10-09 Errata (A)).
  Canvas comments (`StickyNote`, `CommentFrame`, `CommentID`, `CanvasRect`: `Sources/CreatorGraph/Comments`) are per
  `Graph` (`stickies`, `frames`; a definition's inside has its own), saved sorted by ID and only when present (format 5,
  keys optional), edited by the four commands `setSticky`/`removeSticky`/`setFrame`/`removeFrame` (a set adds or
  replaces whole, so a move, resize or edit is one command), and never affect evaluation (`affectsResults` is false).
  A comment's `frame` is stored left-to-right like a node's position; the left dock draws the transpose of origin and
  size (`CanvasFlow.display(_:)`). Geometry is `CommentLayout` (computed, never measured); a frame holds the nodes whose
  drawn centres lie inside it (`EditorModel.members(of:)`, never stored), and a moved or nudged frame carries them
  (`carried(by:)`). Hits: `CanvasHit.note`/`.frame` (title bar and 6 pt edge band only)/`.resize` (the 12 pt
  bottom-right handle of a selected comment, begins `CanvasInteraction.resizing`); draw order frames, wires, notes,
  nodes with the selected last in each kind (`drawOrderFrames`, `drawOrderNotes`, culled as `drawnFrames`/`drawnNotes`).
  Add Note and Frame Selection are `addNote(atScreen:)`, `addNoteAtPointer()` and `addFrameAroundSelection()`, on ⌘⇧N,
  ⌘⇧C and the canvas's context menu (`CanvasMenuItem`); ⌘X cuts. The inspector's comment page is `CommentPage`
  (`CommentInspectorView`); text commits through `PendingEntry.textCommit`, on ⌘↩ (⌃↩ off macOS; `CommentKeys.commitsNote`, an
  `onKeyPress` on the box: MetalUI C9, gap CM-a), on focus loss or any model commit.
  Typing on the canvas: `EditorModel.commentEdit` (`CommentEdit`) is the comment being edited in place, `commentEditor`
  (`CommentEditor`) where its field goes (a note's rectangle, a frame's title bar, in display canvas points). Its draft
  rides the model's one `pendingEntry` (`EditorModel+CommentEditing`: `beginEditing`, `commentDraftChanged`,
  `commitCommentEdit`, `cancelCommentEdit`, `commentSelectionChanged`), so a canvas press, a selection or level change, hiding the panel, undo, save
  and export commit it, as one `setNoteText` / `setFrameTitle` step (the inspector's own paths), and a field typed into
  elsewhere (`notePendingEntry`) commits it first. `CommentEditorLayer` draws the field (`CommentEditorField`: a
  `TextEditor`, ⌘↩ commits, or a `TextField`, Return commits; Esc cancels; losing focus commits; both bind
  `CommentEdit.selection`, which `beginEditing` sets to the whole title or the end of the note, `Kind.openingSelection(in:)`,
  and the field writes back, `commentSelectionChanged`; read it as Character offsets with `selectedOffsets`) under the canvas's own
  zoom and pan, as the sibling of `CanvasSurface`, the canvas's key region: never inside it, or the field's keys would
  reach the canvas's handler. Comment views draw no shadows and few rects (`StickyView`, `CommentFrameView`). Make Unique copies a definition's
  comments (`GroupCommands+MakeUnique`); Ungroup splices them into the level. ⌘A, arrows (one undo step per key-down run) and F act only while the
  panel shows; Esc closes the palette, then cancels a drag, then clears the selection.
- `CreatorSketchEditor`: the sketch editor (sketcher spec §8). `@MainActor @Observable SketchEditorModel` holds the
  sketch being edited, its live solve (`solve(_:dragging:)` per drag step), the tool and its stroke, the selection, and
  the inspector's rows; it is the viewport's `ViewportTool` (planar navigation; F frames the sketch) and builds its
  `ViewportOverlay` and the pointer readout (`pointerReadout`, while drawing or dragging a point; placed by
  `ReadoutChip`, drawn by its `PointerReadoutView`, which the app puts over the viewport, with the inference glyphs'
  `InferenceChip`; both are as wide as their measured text: `readoutChip(measuring:)`, `inferenceChip(measuring:)`). The command tools (Trim, Extend, Fillet, Mirror, Pattern) run `SketchCommands` on a click and show
  a refused command's message as `refusal`; their settings are `SketchToolOptions`. A click within the pick radius of
  a curve (not a point) holds a new point on it (point-on); a line leaving an arc's end snaps tangent; ⌘ suppresses
  both, never a shared point. Project (P) declines the plane click and takes the viewport's pick: the host resolves it
  (`events.projection`) into `ProjectionCandidate`s, each becomes a fixed `.projected` entity with a reference `edgeN`, and
  the commit's `projections` carry the picks to store. The overlay also carries a fill per closed region
  (`RegionTriangulator`, found again only when the sketch changes) and a read-only label per dimension
  (`SketchDimensionLabels`). Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  Depends on CreatorSketch, CreatorViewport, CreatorKernel (Project's `EdgePick`), CreatorGeometry, CreatorStyle and
  MetalUI only. Its keys are toolbar
  button shortcuts (L, A (again: 3-point arc), C, D, T, P, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons; Fillet has no
  key because F frames the sketch), which run before the graph panel's
  `onInput` keys; the Delete button and the hidden ⌦ one are never disabled, so ⌫ and ⌦ never fall through to deleting
  nodes (the graph's selection is the Sketch node being edited). Tests: `swift test --filter CreatorSketchEditorTests`.
- `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and the editors.
  Sketch mode is `AppModel.sketch` (`SketchSession`: the editor as the viewport's tool, its overlay followed), entered
  by the Sketch node's "Edit sketch" (`InspectorAction.editSketch`); the scene is ghosted and handle-free meanwhile,
  the top bar holds `SketchToolbar` and the inspector `SketchInspector`, each in `SketchChrome` (glass over an opaque
  backdrop, so a click on the chrome never reaches the editor beneath). `SketchStore` turns a commit into one batch:
  the `sketch` setting, a cleared constant under each exposed dimension's name (the value lives in the sketch alone),
  and a renamed exposed dimension's wire moved (dropped when it stops being exposed). A Project commit also stores each pick
  under `NodeSetting.projection(reference)` and wires the solid's producer into `references` (one wire: `resolveProjection`
  refuses another part, or one made from the sketch); a removed projection clears its pick. The face menu's New Sketch on
  Face (`newSketchOnFace`) inserts Plane from Face and a wired Sketch as one batch and opens the sketch on
  `PlaneFromFaceNode.plane(of:)`.
  `@MainActor @Observable AppModel` owns the open document's parts (document, editor, graph input, viewport; replaced
  together on New and Open), turns results into `ViewportItem`s (`SceneBuilder`; in Final preview a selected rule's edges on a solid no shown
  part holds come as guide items, Errata (Viewport: a rule's edges over the Final part)) and `HandleSpec`s into
  `ViewportHandle`s (`HandleBuilder`), turns viewport events into graph commands (picking writes Edges by Tag rules),
  and opens, saves and exports (`ExportKind`: STEP and STL of solids are the kernel's; any mesh, and every 3MF, is streamed by
  `StreamedExport`: the graph is evaluated with `MeshQuality.streamedExport`, each Output node is one 3MF object, each `MeshStream` is
  meshed window by window into the file, and the export sheet's Cancel removes the half-written file). The cut view is `CutViewModel`
  (`AppModel.cutView`; the top bar's toggle and View ▸ Show Cut View, only where `CutViewModel.isAvailable`, which is the Metal
  viewport): 7b's `SlicePose` and handle, view state. A selected layout node is evaluated even before anything is wired to it and shows its
  placements
  as an overlay of axis triads (`LayoutPreview`, `OverlayTint.axisX/Y/Z`; Face Pattern also dashes the area it fills),
  which never
  picks, frames or opens a menu; the face menu's Pattern on Face (`AppModel.patternOnFace`) inserts a Face Pattern
  holding the
  face's pick, wired from the part (Scatter on Face does the same for a Field Scatter; `FaceLayout` is what the two differ by).
  The field preview (`AppModel.fieldPreview`, a `FieldPreviewModel` replaced with the document) follows the one selected Fields node:
  `refreshScene()` hands it `fieldPreviewRequest(for:)` (`FieldPreviewSelection`: the field a node makes, or the first field wired
  into one that takes a field; nothing while picking or sketching), tints the opaque items it has a tint for
  (`tinted(_:colors:)`; `ViewportItem.drawsTheSame` compares tints), shows its slice (`viewportSlice(colors:)`) and appends the
  slice's handle (`FieldPreviewModel.sliceHandleID`; `handleChanged` moves it as view state: no command, no undo step, not an edit).
  Sampling runs off the main actor in two tasks, the tint (every shown solid's mesh vertices from `ViewportModel.displayMesh(of:)`)
  and the slice grid (256² or, for a field that measures with the kernel, 64²: `SlicePose.resolution`), through the evaluator's
  distance cache (`DocumentModel.fieldDistances`) so an orbit, a toggle or an edit downstream of a distance asks the kernel for
  nothing; a newer request cancels the older and the old tint and slice stay until the new are ready; over 200,000 vertices a
  deterministic subset is sampled and the rest take the nearest's value (`CoarseSampling`); a failed sampling is the kernel's own
  words in the legend. The range is automatic, centred on 0 for a signed distance, or fixed 0…1 (`FieldPreviewRange`); the slice
  starts shown, on the field's own plane (`Field.ownPlane`) or the axis plane nearest the camera (`SlicePose`). The legend
  (`FieldLegendView` in `FieldLegendDock`, placed above the axis triad by `AppLayout.legendInsets`) draws the ramp, three numbers
  with "mm" for a distance (`Field.unit`), the "0…1" toggle, the slice buttons and "Preview sampled coarsely". `Field` is `Hashable`
  (a distance to a solid, faces or edges by `DistanceTarget.identity`), which is how the preview tells an edit from a repeat.
  `settle()` also waits for the sampling. Inside a group `AppModel` reads the level through `editor.graph`/`levelResults`:
  Selected
  node previews the level's selected node, handles and picking work there, and a pick is written through
  `GraphContent.relativeToLevel` (Done and a viewport click drop a pick whose level is no longer the one shown); Final
  preview and export stay on the top level. Sketch mode is top-level only
  ("Edit sketch" and New Sketch on Face inside a group say so). The open sketch follows a wired plane: when it moves the
  camera looks at it again (`viewport.lookAt`), and when its node fails or its wire goes the sketch stays on the last plane
  and says so once (`SketchSession.hasPlane`; a plane that is only evaluating again is waited for). `AppInput` installs the window's input once and forwards to the current document.
  The window shell is MetalUI C8's, wired in `MetalCreatorApp`: `Window.onCloseRequest` is `AppModel.closeRequested()`
  (`CloseDecision`; `.later` with unsaved changes, the Save / Don't Save / Cancel alert, `answerSaveChanges(_:)` replying
  through `replyToCloseRequest`; ⌘Q asks the same handler because the app sets no `onTerminateRequest`),
  `WindowChromeSync` keeps `Window.title`, `isDocumentEdited` and `representedURL` on the document
  (`AppModel.windowChrome`), the window opens with the hidden title bar (`AppLayout.windowStyle`, gap M6-c; check AS-5): `TopBar` pads
  by `AppLayout.topBarClearance` and `topBarTrailingClearance` of the window's `titleBarInsets` (left: AppKit's traffic lights; right: MetalUI's drawn buttons on SDL; zero in full screen), and the window is dragged by `WindowDragHandle`
  (CreatorStyle; MetalUI C22's `WindowDragGesture`, gap C8-a): the strip `AppLayout.windowDragStripHeight` along the top, and the top
  bar's empty space (its label and the gap beside the controls; the sketch toolbar's too), never behind a control (a disabled one would
  pass the press to a handle behind it), and
  `App.onOpenURL` is `AppModel.openRequested(_:)` (the path argument goes through `App.open(_:)`; a file that arrives while
  any alert is up is ignored).
  `MetalCreatorApp` is the executable (`OCCTKernel`). It makes the app's `ThemeStore` (`AppThemes.store()`: user
  defaults, `~/Library/Application Support/MetalCreator/Themes`) and its `ThemeEditorModel`, and opens the window on
  `AppWindowRoot`: `AppRoot` with the theme editor (`ThemeEditorDock`, a floating glass panel at the top right) over
  it, the store in the environment and `.theme(current.controlTheme)` for MetalUI's controls. View ▸ Theme is
  `ThemeMenu` (every theme, then Edit Themes…). `LaunchCommand` parses its command line: a file to open, or the
  headless `--help`, `--version`, `--self-test` (`SelfTest`: OCCT, STEP/STL export, MetalUI's shaders) and `--info-plist`.
  `AppBundleInfo` is the version's one source; the packaged `Info.plist` is generated from it, never edited.

Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI,
never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.
All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids and meshing mutates it; never call the shim outside it (tests included).
Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a run is edges that continue each other end to end, ends within 1e-4 mm leaving that point in opposite directions to within 0.01 rad, so two edges meeting at a corner are two runs; a pick without one counts each recorded edge as a run) and warns only when both changed; a key that still matches nothing is split by operand (`EdgeKey.operandKeys`, for an edge between a merged face and a third operand's face) and warns when two operands both fit; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 8 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
4 added the `.sketch` and `.facePick` settings; 5 added `definitions`, group definitions, optional on decode; canvas comments' `stickies` and `frames` keys, written only when present and optional on decode, are also under 5; 6 added the tree nodes' text settings `pathRule`, `branchPath` and `itemPath`; trees themselves are computed, never saved; 7 added the Image Field's `image` setting, the optional top-level `images` table (base64 bytes keyed by SHA-256, sorted, written only when used; a damaged entry is dropped on reading) and the `field` socket type in group interfaces; 8 added the `implicit` and `mesh` socket types in group interfaces and the Implicit and Mesh nodes' settings (Shell's `side`, Mesh's resolutions: existing integer and number kinds); implicit solids and meshes are computed, never saved; files of format 1 to 7 open unchanged and are written as 8).
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
records is the loop. Loft refuses profiles with holes, before it compares segment counts (`KernelError.loftWithHoles`).
Create nodes only with `NodeRegistry.makeNode`. Numbers in node and kernel messages use `Locale.messages` (defined in
CreatorKernel; `Double.display`, `Int.display` in CreatorNodes; `KernelError.userMessage` uses it too).
Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
Every fillet and chamfer result is checked with OCCT's `BRepCheck_Analyzer` (`OCCTShape.isValid`) and never returned when
the check rejects it: the blend fails naming the largest size that works (`OCCTKernel.largestValidBlend`, spec Errata
(Kernel: invalid blends)). A blend OCCT can't build names one too, and a checker that itself throws
(`OCCTValidity.unchecked`) gives the generic message with no search (Errata (Kernel: largest size for blends OCCT can't
build)); a refused blend costs tens of milliseconds more than one that works (`BlendRefusalBench`,
`docs/verification/performance.md`).
MetalUI exports its own `Angle`: a file importing both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle`.
The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
`ViewportModel` (`dragChanged`/`dragEnded`/`dragCancelled(button:)`, `click(at:modifiers:)`, `modifiersChanged(_:)`,
`contextMenuItems(at:)`, `scrolled(by:at:phase:)`, `pinchChanged`/`pinchEnded`, `cursor`), and `ViewportView` only forwards
gesture values. MetalUI C16 adds a tap's modifiers, `onModifierKeysChanged` (⌘ over a still pointer reaches a tool through
`ViewportTool.pointerMoved(to:modifiers:projector:)`: the sketch editor drops its inference while ⌘ is held), `onCancelled`
on drags and pinches (a dropped gesture ends where it was, a lost primary release too since MetalUI C26: the next press cancels it; one gap is left,
VI-c, a plain pointer move doesn't) and wheel latching. Its keys stay
window-wide stopgaps in `ViewportKeyBindings` until MetalUI scopes keys to an element (C9).
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
drawing and hit testing agree. Node positions are stored left-to-right; the left dock draws their transpose.
The graph panel's insides (header, node library, canvas) are computed by `GraphPanelLayout` and the palette's size
by `PaletteLayout`; the panel says where it is in its window itself (`EditorModel.panelPlacement`, from `onGeometryChange`;
`AppModel.panelPlacement` forwards it; tests that draw one cold `renderFrame` run no layout callbacks and set it with
`ExpectedLayout.place`). The add-node palette floats over the window as MetalUI's `anchoredOverlay` (gap EP-b), opening at the
pointer's window point (`EditorModel.pointerWindowLocation`, the canvas container's `.global` hover): the host draws
`SearchPaletteOverlay` last (the app inside `PaletteDock`, for the `Panel` key context), then `LibraryDragOverlay`, never
inside the canvas. MetalUI places it (flip and clamp), closes it (any outside press, Escape) and keeps presses and the wheel
on it from what lies beneath; the model holds no palette geometry. A library row is a
`PaletteEntryLabel` under one `DragGesture(minimumDistance: 0, coordinateSpace: .global)`
(`GraphPanelInput.libraryGesture(for:)`; not a `Button`, whose click would hold the drag off), and the model tells a
click from a drag (`LibraryDrag.threshold`); never MetalUI drag and drop (it becomes a system drag outside the
window). The library's visibility is `ViewState.showsLibrary` (an optional key: no format bump).
The graph canvas's pointer input is MetalUI C7's, turned into `EditorModel` calls by `GraphPanelInput`: one
`DragGesture(minimumDistance: 0)` for clicks and drags, whose `value.modifiers` and `value.clickCount` the model reads (it
stays a drag though a `SpatialTapGesture` carries modifiers since C16, gap GI-a: a press must be able to become a box, a wire
or a move; a drag on empty canvas box-selects and never pans; a press MetalUI drops ends through `onCancelled` →
`pointerCancelled()`), a `DragGesture(minimumDistance: 0, button:
.middle)` (`middlePanGesture()` → `middleDragged`: pans, as the viewport's middle drag does; the user's Gate G answer
(b), 2026-10-09), `.onScrollWheel` (`scrolled(by:at:modifiers:phase:)`: pan, ⌘ zooms; MetalUI latches a scroll to where it
began, glide included, gap GI-b) and `MagnifyGesture`
(`pinchChanged`/`pinchEnded`); the cursor is `EditorModel.canvasCursor` (a closed hand while a middle drag pans). Its keys and text
focus are MetalUI C9's: `CanvasSurface` is a `hoverKeyRegion` whose one `onKeyPress` runs the graph's keys
(`GraphPanelInput.keyPressed(_:)`), so with nothing focused they act where the pointer is, a focused field (the inspector's,
the library's, the canvas's comment editor) keeps every key wherever the pointer is, and a canvas press clears a field's focus.
A press anywhere else does too: `AppWindowRoot` (and `GraphPanelPreview`'s root) carries MetalUI C24's `.resignsFocusOnPress()`
(gap CT-a), which resigns on a primary press on inert chrome, the viewport included, and routes no keys; it is why a canvas edit
and a typed inspector value end, committing through their focus-loss handlers, on a press on the glass, a header gap or the
viewport. The shell has no `window.focus(nil)` hook of its own any more; a viewport press only commits a pending entry.
The open palette's ↑/↓ (a keymap action, gap M5-h) and its keys on `onInput` are the stopgap left in `GraphPanelInput`, and
`install(on:)` chains onto the window's existing handlers.
The app installs the window's input through `AppInput`, never `GraphPanelInput.install(on:)` (only
`GraphPanelPreview` still uses it), because New and Open replace the document's `GraphPanelInput`.
App-shell input stopgaps live only in `AppInput`: the viewport's keys carry the `!Panel` key context (the graph panel
and the inspector contribute `Panel`), and over the graph canvas F, + and − are declined so the graph's own keys work
(F frames the graph's selection there). The
camera reaches `ViewState` only through `cameraSettled`/`homeChanged`, never per frame. Regular Polygon is
`typeVersion` 2 (`rotation`), and so are TPMS, Strut Lattice and Voronoi Lattice (`blend`: their `migrate` stores 0, the sharp join they were saved with, while a new node reads the socket's 1 mm).

## Commands

```sh
swift build                                  # build the library
swift build -c release
swift test                                   # run all tests (twelve test targets: twelve "Test run with" lines)
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
swift test --filter CanvasContentSkipWindowTests   # the canvas's .equatable() views: what a drag, theme or selection change evaluates
swift test --filter CreatorStyleTests      # colour themes: built-ins, roles, .mctheme files, the folder, ThemeStore
swift test --filter CreatorSketchEditorTests   # the sketch editor: tools, inference, constraints, dimensions, overlay
swift test --filter CreatorImplicitTests       # implicit solids: evaluators, octree, mesher, bakes, the GPU agreement suite (Metal device)
scripts/package-app.sh                     # dist/MetalCreator.app: release build, OCCT bundled, signed ad hoc, verified (docs/packaging.md)
scripts/verify-app.sh [path.app]           # re-check a packaged app: signature, no Homebrew links, self-test with Homebrew unreadable
swift run MetalCreatorApp --self-test      # the same headless checks, unpackaged
scripts/bench.sh [suite]                   # spec §7.3 benchmarks, release build; numbers go in docs/verification/performance.md
scripts/bench.sh PatternBench              # patterns spec §7: 200 holes in a plate, edit-to-preview (idle Mac only)
scripts/linux-test.sh [build|test|smoke|all]   # the suite on Linux in Docker (OrbStack): swift build, swift test (11 "Test run with" lines), --self-test, --smoke-test 20
swift run MetalCreatorApp --smoke-test 5   # a Linux or Windows build: the real window over SDL's offscreen renderers; exit 0 if a first frame was drawn
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
  image, built from `../MetalUI/Backends/SDL/linux/Dockerfile`, plus a font, `scripts/linux/Dockerfile`); build products live in a Docker
  volume named for the track (`XP_TRACK`, default `xp-1`), and a run stops only its own container. MetalUI must be a sibling checkout.
  Windows cannot be run here: it is CI's job (`.github/workflows/xp.yml`; it builds and launches, two tests are red, see the xp-1 paragraph).
- The Windows Swift 6.4 toolchain asserts in LLVM's coroutine splitting (`CoroFrame.cpp`, "Layout->getElementOffset") on an `async` function that holds a loop's locals across an `await` (`DrainHoles.drainPoints` did); keep the synchronous work in a non-async helper.
- Swift 6.4 crashes in SILGen on a key path applied to an existential metatype (`BuiltInNodes.all.map(\.typeID)`); use a closure.
- OpenCascade 7.9 comes from Homebrew (`brew install opencascade`) and is linked from `/opt/homebrew/opt/opencascade`.
  Linker warnings about dylibs built for a newer macOS are expected.
- Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion`.
