# M0–M1 carry-over for later milestones

Deferred review findings from the M0–M1 subagent-driven run (final review triage, 2026-10-07).
Read this before writing the M2 and M3 plans.

## Before the first M2 OCCT operation
- ✅ (M2) STEP export sets the process-global `Interface_Static` unit; meshing writes triangulation into the shared TShape. Keep all OCCT access serialized inside `OCCTKernel` (dedicated serial executor recommended).
- ✅ (M2) Map `OCCTError` to `KernelError` so raw OCCT text never reaches users.
- ✅ (M2) Query sentinel `-1` is ambiguous for `occt_volume` (negative volumes exist): expose throwing/optional queries in `OCCTKernel`.
- ✅ (M2) Silence OCCT's STEP statistics on stdout (Message messenger level); add an unwritable-path STL test.
- `occt_edge_length` rebuilds the edge map per call (O(n²) loops).
- ✅ (M2) Implement `try Task.checkCancellation()` on entry to every `OCCTKernel` operation (protocol contract).
- ✅ (M2) Define a fallback tag for faces OCCT history leaves untagged; make `TopoTag`, `TopoRole`, `EdgeKey` Codable (needed by Edges by Tag) — remember: a new `ConstantValue` kind needs a `formatVersion` bump.

## Before M3 selection-rule and profile nodes
- ✅ (M3) FakeKernel and OCCTKernel both report a circle's axis as `direction` (by design); 'Edges by Direction' must require `kind == .line`. 2-segment profiles give vertical edges a shared `EdgeKey`; blend doesn't dedupe edges; centroid/area are zero placeholders; coverage gaps (chamfer, transform, union, intersect, tessellate). (Edges by Direction requires `kind == .line`; Edge Set Op dedupes; FakeKernel's zero centroids remain.)
- `Segment2D` arcs assume a CCW normalized sweep (reversed arc → negative length); `Profile2D.bounds` is conservative for partial arcs; `Plane.init` does not normalize.

## From M2
- All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids
  and meshing mutates it; never call the shim outside it (tests included).
- Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is
  prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
- Full revolves: OCCT's `Generated(edge)` is empty for planar swept faces; `BRepSweep_Revol::Shape(edge)` names them
  (cocct_build.cpp).
- Swift 6.4 crashes compiling typed-throws closures that return tuples or are passed to `serialized`; a few OCCTKernel
  closures use untyped `throws` with a comment — revert when the compiler is fixed.
- Deferred kernel items: multi-solid boolean results pass as one Solid (multi-body deferred, spec §11; see the
  `Kernel.boolean` doc comment); fillet `maxRadius` is always nil.
- Fillet/chamfer corner faces (generated from vertices) carry the `.blend` tags of every selected edge at that vertex.
  Booleans run non-destructively; inside-out solids are fixed with `BRepLib::OrientClosedSolid`, never `Reversed()`.
- `OCCTKernel` runs on the default actor executor; long OCCT calls occupy a cooperative-pool thread. Measure in M7.
- Fuse/cut call `SimplifyResult()`; if that ever drops history for a face it shows up as `.unnamed` (pinned by
  `noFaceIsUntaggedOrUnnamedInTheBracket`).

## Can wait
- `NodeID` init overlap; `EdgeKey` separators unescaped; linear topology lookups; 128-byte estimate constant.
- `NodeRegistry.all` tiebreak; `BroadcastPlan.inputs(at:)` precondition; NodeError strings not yet localised.
- Duplicate node IDs in a file collapse first-wins; O(N·L) link scans.
- Parameter commands don't mark parameter-reading nodes `.evaluating`; `setInput` doesn't check the socket exists (and must keep accepting `NodeSetting` names: a socket-only check would silently break every setting); undo coalescing is key-only; removing a parameter and undoing re-appends it at the end.
- `formatVersion` ≤ 0 accepted; partial `ViewState` untested; `GraphFileError` has no user-facing message (M6).
- `restoreLinks` doesn't guard duplicates within one call or occupied inputs (only reachable via hand-built commands).
- `CancelsTaskNode` test assumes nodes run in the caller's task — revisit with parallel evaluation.
- ✅ Hard-coded `/opt/homebrew` OCCT prefix: the build still links Homebrew's OCCT through `Package.swift`'s prefix, but `scripts/package-app.sh` bundles the libraries and removes that rpath, so the packaged app doesn't depend on it (Errata (Packaging)).
- M2 final review residuals: `oriented()` runs `BRepLib::OrientClosedSolid` on every extrude/revolve/loft even when the volume is already positive (only call it when negative — measure in M7); its boolean return is ignored; note that it works by reversing the solid, like the old code. The non-destructive-boolean test is a regression guard only — a stronger test would read max vertex/edge tolerance of a near-touching tool input (rises from 1e-7 in destructive mode).
- ✅ (M4) Before M4: build edge polylines from `BRep_Tool::PolygonOnTriangulation` so lines sit on the face mesh; meshes depend on earlier tessellations (BRepMesh reuses finer triangulation in shared TShapes).
- ✅ (M3) M3 notes from the M2 review: Edges by Tag should match "picked tags ⊆ face tags" per side (unions merge tag sets); Edges by Direction uses `abs(dot)` and `kind == .line`; Edge Set Op dedupes; Loft rejects sections with different segment counts (Rectangle → Circle) — show a clear message or plan resampling; warn when a picked key contains `.unnamed`.

## From M3
- `InspectorControl` gained `.vector(socket)` and `.parameterPicker(setting)` (spec §6.4's closed set + 2); M5 renders both.
- Graph Parameter uses optional outputs (`number`, `integer`, `bool`, `vector`); an integer parameter fills `integer` and `number`.
- `Grid Points.total` drives a fixed-row grid (Hole count 4 → 2×2, 6 → 3×2). Generators cap lists at 10,000 items.
- Fillet has no "Tangent chain" toggle (OCCT always follows tangent chains). "Show handle in view" is the `showHandle` setting, seeded `.bool(true)` by `NodeDefinition.defaultSettings` at creation; the M6 app shell reads it for the viewport.
- The settings contract is in CreatorGraph so M5 (no `CreatorNodes` import) can use it: `NodeSetting`, `ConstantValue.parameter(_:)` / `.parameterID`. Picks are `.edgePicks(topology.picks(for:))`; the M6 app shell wraps M4's picked `EdgeID`s (M4 never imports CreatorGraph).
- `NodeRegistry.makeNode` sets `isOutput` for `.output`-category nodes, so M5's palette and preview need no special case (the reconciled M5 plan sets no `isOutput` by hand).
- `setInput` must keep accepting non-socket names (`NodeSetting`); don't "fix" the "socket exists" item under Can wait by rejecting them.
- Edge Set Op accepts the same `Solid` instance or one with equal topology and bounds (covers an LRU eviction recomputing one side); solids from different nodes differ by their tags.
- `EdgePick.touchesUnnamedFace` looks inside `.blend(sourceEdge:)` keys recursively.
- Boolean passes the target through for a wired empty `tools` list (union, subtract); intersect keeps the kernel error.
- Node messages format numbers with `Locale.messages` (en_US). Switch to the user's locale when the string catalog arrives.
- `Topology.midpointOrder` uses a 1e-6 mm tolerance compare, which is not a strict weak ordering for pathological midpoints.
- M6 exports the solids of `isOutput` nodes; the Output node's `name` is the export name.
- **Owned by M6 (untracked until now): spec §8 naming stability, the polygon swap.** `BracketAcceptanceTests` covers Width 60→90 and Hole count 4→6, but not "a rectangle profile swapped for a polygon". The swapped profile is the L-flange's Rectangle, replaced by a Regular Polygon. The swap as written empties the fillet rule, because no polygon side is parallel to Z (spec Errata (M3)). M6 adds a polygon rotation, or uses a Polyline, then writes the test. The test asserts that the chamfer keys are unchanged, that nothing warns, and that the fillet count is pinned. The fillet's flange keys are expected to change.

## From M4
- Picking renders the ID pass on its own command queue and waits for it (`ViewportPicker`). It's re-rendered only when the camera
  or scene changes, and never during a drag. Measure against the §7.3 orbit target in M7.
- Every newly shown solid is tessellated on the kernel actor. A dragged fillet radius re-tessellates each step; measure
  the §7.3 100 ms target in M7. Tessellation now cleans the shape first (deterministic meshes), so each call meshes from scratch.
- M6 owns the glue the viewport can't see:
  - `DocumentModel` outputs → `ViewportItem` (ghosts from `lastGoodOutputs` of erroring nodes)
  - `HandleSpec` → `ViewportHandle` (Extrude: profile plane + normal; Fillet/Chamfer: an edge midpoint + bisector),
    only while the node's `NodeSetting.showHandle` reads `.bool(true)` (seeded by `defaultSettings`; missing counts as shown)
  - `handleChanged(.ended)` → `endCoalescing()`
  - `ViewState.camera`/`homeCamera` ↔ `ViewportModel.pose`/`homePose`. Sync the camera into `ViewState` on drag end,
    animation end and save, **not on every pose change**: writing `DocumentModel.viewState` invalidates every
    observer of it (M5's editor reads the dock and canvas transform from it), which would rebuild the graph panel at
    60 Hz during an orbit and threaten §7.3.
    To make that possible, M6 adds two events to `ViewportEvents`: `cameraSettled(pose)` (fired from `pointerUp`,
    the end of an animation, `zoom(by:)` and `.projection`) and `homeChanged(homePose)` (from `.setHome`), so
    `ViewState` is synced without observing `pose` at 60 Hz.
  - ✅ (viewport C7) Both input stopgaps take over `Window.onInput`: M4's `ViewportModifierTracker` and M5's
    `GraphPanelInput`. The viewport's tracker is gone (its drags read `DragGesture.Value.modifiers`), so only
    `GraphPanelInput` is left on `onInput`, through `AppInput`.
  - `selectEdgesOfFace` → an Edges by Tag node: `.setInput(node, NodeSetting.picks, .edgePicks(picks))` with the
    reported `[EdgePick]`, unchanged (the node warns on `.unnamed` picks itself); pick-mode clicks the same way,
    through `topology.picks(for:)`
  - a keymap context for the viewport's keys
- Stopgaps to delete when MetalUI C7 lands: `ViewportModifierTracker`, the hover-point context menu, window-wide viewport keys.
  ✅ (viewport C7, plan `2026-10-09-viewport-input-c7.md`) The tracker and the hover-point menu are gone: drags read
  `DragGesture.Value.modifiers`, and the face menu picks at the right press (`contextMenuItems(at:)`, the located
  `.contextMenu`). The keys stay window-wide (`!Panel` context) until MetalUI C9 scopes keys to an element.
  C7 also brought: two-finger scroll zooms toward the cursor (momentum ignored), pinch zooms about its centre,
  middle-drag pans, right-drag orbits (a right click still opens the menu), `SpatialTapGesture` clicks, and the
  crosshair and closed-hand cursors. The graph panel's own C7 swap (From M5) is done too (plan
  `2026-10-09-graph-input-c7.md`).
- `ViewportPalette` (GPU colours) duplicates spec §6.6 hex values that M5's `Palette` will also hold. M5 can't unify
  them (neither target may import the other); M6 decides on a shared home.
- Faces above 2²² − 1 and solids beyond 256 aren't pickable (`PickID`).

## From M5
- Inline node values are read-only text (spec §6.2 says "inline value fields"); editing is in the inspector, because
  a canvas `TextField` would fight the canvas-wide gesture and split keyboard focus. Revisit when MetalUI C7 lands.
  Revisited after C7 (plan `2026-10-09-graph-input-c7.md`): still read-only. C7 is pointer input; what makes a
  canvas field unsound is untouched by it. (1) Keys: Tab is a window-wide keymap binding that opens the palette
  whenever the pointer is over the canvas (gap M5-b), so in a node's field it would open the palette instead of
  moving focus; keys are scoped to an element only by MetalUI C9. (2) Hit testing: the canvas draws its layers with
  `allowsHitTesting(false)` and every hit is the model's (`EditorModel.hitTest`, computed from `NodeLayout`); a field
  needs its own MetalUI hit region under the canvas's scale, a second hit test that must agree with the model's at
  every zoom, and MetalUI gives a text field's press to the field before any gesture, so a node could no longer be
  dragged by its rows. (3) Cost: a field per unwired input on every node adds to the whole-window rebuild every drag
  step pays (PERF-b). Revisit with MetalUI C9 and PERF-b.
- Inspector settings rule: a control naming a non-socket is a setting (`NodeSetting`); new nodes carry their seeded
  `defaultSettings`, and a setting toggle with nothing stored reads On; `.parameterPicker` writes M3's
  `ConstantValue.parameter(id)` and reads `.parameterID` (one encoding, in CreatorGraph).
- `Palette` (CreatorEditor) and M4's `ViewportPalette` (CreatorViewport) hold the same spec §6.6 hex values; neither
  target may import the other, so M6 picks a shared home.
- CreatorGraph messages read `needs a \(type.rawValue)` ("needs a integer", "needs a edgeSet") in `Graph+Commands`,
  `NodeError` and `Evaluator`; give them the editor's `SocketType.indefiniteName` wording in one pass.
- Numbers are shown and parsed in `en_US_POSIX`; localised number entry is deferred with string localisation.
- Only the key mapping is unit-tested (MetalUI's `Window` init is internal); real-window routing is human checks
  M5-5, M5-9, M5-11, M5-12, and `GraphPanelInput.install(on:)` is untested glue. If MetalUI exposes a test window, add
  dispatch tests.
- Optional inputs with no default (Grid Points `total`, Edge Filter `maxLength`, Transform `axisDirection`) start
  unset ("Not set" in the inspector, "—" on the node row); emptying the field clears them (`EditorModel.clearInput`).
  Required inputs are never cleared.
- C7 swap points in `GraphPanelInput`: `spatialTapGesture()` → `SpatialTapGesture` (a return-type change, so
  `canvasGesture()` becomes a tap plus a nonzero-distance drag and its stand-in test is rewritten), `dragValueModifiers(_:)` →
  `DragGesture.Value.modifiers` (body-only; then `handle(_:)` stops tracking `.modifiersChanged`), and scroll/pinch get new
  handlers (`.onScrollWheel`, `MagnifyGesture`); the +/− keys and header buttons stay.
  ✅ (graph input C7) Done, with one change: `dragValueModifiers(_:)` is gone (the canvas drag reads
  `DragGesture.Value.modifiers` and `handle(_:)` stops tracking), and so is `spatialTapGesture()`, but the canvas
  keeps its zero-distance drag for clicks, since a `SpatialTapGesture`'s value has no modifiers (gap GI-a). Scroll
  pans and ⌘-scroll zooms (`EditorModel.scrolled(by:at:modifiers:phase:)`), a pinch zooms
  (`EditorModel.pinchChanged`), a pan shows the closed hand (`EditorModel.canvasCursor`), and a scroll, pinch,
  press or hover over the panel's chrome no longer reaches the viewport (`GraphPanel`'s opaque backdrop).
- With M4's viewport in the same window, M4's window-wide `=`/`+`/`-` keymap bindings win over the graph's zoom keys
  (keymap runs before `onInput`); M6 scopes the viewport's with a key context (gap M4-a).

## From M6
- Regular Polygon is `typeVersion` 2 (`rotation`). ✅ (naming-merged-faces plan) The §8 polygon swap's picks on faces
  a union merged now resolve with no warning: a key that matches nothing is retried `EdgeKey.narrowed`, and drift
  counts runs as well as edges (`EdgePick.runCount`). ✅ (kernel-invalid-blends plan) OCCT's R3 fillet of the hexagon
  returns a solid its checker rejects; the kernel now refuses it and the Fillet names the largest radius that works,
  2.5 mm, at which the Chamfer and the Output have their part (spec Errata (Kernel: invalid blends)). Face picks on
  merged faces: roadmap row "Naming: face picks on merged faces".
- `AppModel` replaces the document's parts on New and Open; `AppInput` is installed once and forwards. Nothing may
  capture a `GraphPanelInput`, `EditorModel` or `ViewportModel` for the window's lifetime.
- ✅ (viewport C7 plan) The first framing, F and Look At frame the part in the whole viewport, not the model area the
  panels leave, so a part can sit partly under the graph panel. Owner: roadmap row "Viewport: frame in the model
  area". Done: `CameraNavigation.frame(_:_:size:insets:)` centres and fits the part in `ViewportModel.modelArea`,
  and the arrows, the cube's regions, a cube drag and the +/− keys without a pointer turn or zoom about the model
  area's centre (`modelAreaPivot(_:)`), so the part stays there; insets the view can't honour are ignored for framing
  (`ViewportInsets.usable(in:)`), though `setModelArea` still takes them unvalidated (M7 item below).
- In Final preview a selected rule that feeds a feature glows nothing (spec Errata (M6)). Owner: roadmap row
  "Viewport: a selected rule's edges over the Final part".
- `AppModel.refreshScene()` re-shows only a changed scene or changed handles; the observation itself still wakes for
  every `viewState` change (it reads `editor.dock`). Narrow it if M7's 50-node pan measurement shows the wake-ups.
- The panel's size isn't saved with the file (add `ViewState` fields if wanted; optional keys, no format bump).
- Handles show only for the selected nodes; nodes not upstream of an Output (and not previewed) have no result, so they
  show no handle and no rule summary count.
- Stopgaps to delete when C7 merges, beyond M4's and M5's lists: the canvas hover veto in `AppInput.handleAction`
  (only if MetalUI also gains hover-scoped key contexts), and the resize edge's missing cursor (adopt
  `.pointerStyle(.columnResize)` / `.rowResize`, C7 `CI-H`). Key-routing dispatch tests wait for gap M6-e.
  ✅ (graph input C7) The resize edge's cursor is done (`PanelResizeHandle.pointerStyle(alongWidth:)`); the hover
  veto stays until MetalUI C9.
- `ViewportHarness` and `GraphPanelPreview` stay until human-check groups V and M5 have been run; delete them then.
- Themes (spec §6.6): the theme type is `ColorTheme` because MetalUI exports `Theme`. A view that draws a colour reads
  `@Environment(ThemeStore.self) var themes: ThemeStore?` and draws `Palette(themes)`; `Palette.dracula` in a view is a
  bug (only `GraphPanelPreview`, which has no store, uses it). The choice isn't remembered between launches
  (`InMemoryThemePreferences`). MetalUI's own controls follow only the theme's light or dark
  (`.preferredColorScheme`), not its colours: the Themes milestone can map roles onto MetalUI's scoped `.theme(_:)`
  tokens. Owner: roadmap row "Themes".
- Later items from the M6 final review:
  - `AppModel.load()` leaves the old parts' scene refresh task running; bump `observationGeneration` before writing
    the new parts so the orphaned task can't write them. Owner: M7.
  - A pick session isn't cancelled on undo or redo, or when its rule or its source node is deleted. Owner: M7.
  - `discardChanges()` should set `alert = nil` itself rather than rely on the caller. Owner: M7.
  - `AppAcceptanceTests` should also assert the fillet's edge-set count (4) and the chamfer's match count (7) after
    Width 90 / Hole count 6. Owner: M7.
  - Radial handles: the bisector has no fallback when the two face normals cancel, the normals are right only for
    planar faces, and the `0...1_000` fallback range in `HandleBuilder` wants a named constant. Owner: M7.
  - `ThemeRenderTests` should check each view's roles (not only that something changed), and a grep test should pin
    `Palette.dracula` to the places allowed to use it. Owner: Themes.
  - `ThemeStore`'s fallback `builtIns.first ?? .dracula` repeats the default; name it once. Owner: Themes.
  - `cameraSettled` can fire twice when a new camera animation starts mid-animation. Owner: M7.
  - `ViewportModel.setModelArea` doesn't validate its insets (negative, or larger than the view). Owner: M7.
  - `ViewportGlueTests` should assert that two separate drags are two undo steps (undo twice). Owner: M7.
  - No test pins that docking or resizing the panel doesn't re-show the scene (`ViewportItem.drawsTheSame`), as
    `panningTheCanvasOrSettlingTheCameraDoesntRebuildTheScene` does for a pan. Owner: M7.

## From naming: merged faces
- Edge runs join on curve-evaluated end points with a fixed 1e-6 mm tolerance, and join any two edges sharing an end
  point. After blends an edge's curve can end up to the vertex tolerance away, so a split edge may count as 2 runs (a
  spurious drift warning, fails safe); two matched edges meeting at a corner count as one run. Fix when touched: have
  the shim return vertex points (`BRep_Tool::Pnt` of `TopExp::FirstVertex/LastVertex`) or the vertex tolerance, and
  require tangent continuity at a joint (`Topology+EdgeRuns.swift`, `cocct_inspect.cpp`).
- Sketch projections with several references add edges and runs across solids while narrowing per solid; compare
  drift per solid if multi-reference projections become common (`SketchProjections.swift`).
