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
- Hard-coded `/opt/homebrew` OCCT prefix (packaging deferred, spec §11).
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
  - Both input stopgaps take over `Window.onInput`: M4's `ViewportModifierTracker` and M5's `GraphPanelInput`.
    `ViewportModifierTracker.install(on:)` chains to the previous handler. Whichever is installed second must chain
    too (or share one modifier tracker), or the other silently stops seeing events.
  - `selectEdgesOfFace` → an Edges by Tag node: `.setInput(node, NodeSetting.picks, .edgePicks(picks))` with the
    reported `[EdgePick]`, unchanged (the node warns on `.unnamed` picks itself); pick-mode clicks the same way,
    through `topology.picks(for:)`
  - a keymap context for the viewport's keys
- Stopgaps to delete when MetalUI C7 lands: `ViewportModifierTracker`, the hover-point context menu, window-wide viewport keys.
- `ViewportPalette` (GPU colours) duplicates spec §6.6 hex values that M5's `Palette` will also hold. M5 can't unify
  them (neither target may import the other); M6 decides on a shared home.
- Faces above 2²² − 1 and solids beyond 256 aren't pickable (`PickID`).

## From M5
- Inline node values are read-only text (spec §6.2 says "inline value fields"); editing is in the inspector, because
  a canvas `TextField` would fight the canvas-wide gesture and split keyboard focus. Revisit when MetalUI C7 lands.
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
- With M4's viewport in the same window, M4's window-wide `=`/`+`/`-` keymap bindings win over the graph's zoom keys
  (keymap runs before `onInput`); M6 scopes the viewport's with a key context (gap M4-a).
