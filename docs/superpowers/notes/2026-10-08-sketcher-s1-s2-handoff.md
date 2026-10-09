# Sketcher S1 + S2 handoff (for S3, S4 and S5)

S1 and S2 live in `CreatorSketch` (plan: `docs/superpowers/plans/2026-10-08-s1-s2-sketch-solver-regions.md`).
These are the items later milestones must pick up (S3 has merged; its items are done).

## S3 (Profile2D holes) — merged; picked up here
- `SketchRegion.profile(on:)` now returns `Profile2D(plane:outer:holes:)`, so holes are cut.
- Regions follow spec §5 step 5: every loop (holes included) is counter-clockwise and starts at the segment whose
  start point is lexicographically smallest (x, then y, 1e-9 mm); holes are sorted by area descending, then
  centroid x, then y. A hole's loop index (`TopoRole.side(loop:segment:)`) is its position plus one.

## S4 (Sketch node) — done; picked up as below (plan `docs/superpowers/plans/2026-10-09-sketcher-s4-sketch-node.md`)
- The clockwise-arc case is taken: the shim builds an arc with `end < start` clockwise, so notched regions extrude.
- Every item below is implemented by `SketchNode`, `SketchSolve`, `SketchProjections` and `SketchSockets` in
  `Sources/CreatorNodes`; the sketcher spec's Errata (S4) lists the choices.

## S4 → S5 (editor)
- Draw exposed-dimension sockets: `NodeShape(_:in:registry:)` and `InspectorBuilder` read `definition.inputs`; switch
  them to `definition.inputs(for: node)`.
- After each edit, store `Sketch.remember(SketchSolver.solve(sketch))` in the `sketch` setting as one `setInput`, so the
  node's solve warm-starts from what the user sees (the node itself never writes the setting).
- Project writes `.edgePicks(topology.picks(for: [edge]))` under `NodeSetting.projection(reference)` and wires the
  picked edge's solid into `references`. A new projection's `reference` must be unique in the sketch.
- "New sketch on face" writes `.facePick(topology.facePick(for: face))` into a new Plane from Face's `face` setting and
  wires its `plane` into a Sketch whose plane is `.wired`. `AppModel.handle(.pickFacesInView)` still refuses.
- Dimension names: `SketchSockets.isReserved` names the ones that can't be sockets; refuse them when renaming.

## S4 (Sketch node), as handed over by S1–S2
- Concave arcs: an arc a counter-clockwise loop runs along clockwise (a notch cut into an outline) is still stored as
  `Segment2D.arc` with `end < start`, which keeps the loop continuous (`Profile2D.isClosed` holds). `build_profile`
  throws "an arc in the profile has no sweep" for it, so a notched region does not extrude yet. Spec §6 defers this
  clockwise-arc case "unless S4 needs it": S4 should teach the shim to build such an arc from `end` to `start`
  (`BRepBuilderAPI_MakeWire` orients the edge) and make `Segment2D.length` use `abs`, or add an explicit clockwise
  arc segment. Convex arcs, full-circle holes and every hole loop are already counter-clockwise.
- `ProjectionSource.reference` is the key under which the node stores the projection's `EdgePick`. Refresh `curve`
  and set `isSuspended` on each evaluate before solving; suspended constraints come back in `SketchSolution.suspended`.
- Map statuses to node states. `.underConstrained` is `.warning`; `.overConstrained` (use `conflictMessages`) and
  `.failed(reason:)` are `.error`. Keep the last good output ghosted; unsatisfiable components keep their warm start.
- `conflictMessages` has one sentence per minimal conflict set, and a component reports every independent conflict
  (up to `ConflictSearch.setLimit`), so show them all: removing every listed set restores consistency.
- `Sketch` encodes deterministically (ID-keyed dictionaries are JSON objects); embed it with `.sortedKeys`.
- Angle dimensions are directed: `SketchDimension.angleSense` (chosen by `addDimension` from the geometry, or by
  `remember` after the first solve) says which of the four angles between the lines the value measures. Driving and
  reference angles both read in it, so switching one to reference keeps its number, and 120 on a 60° vee opens it.
- Auto dimension names come from the monotonic `Sketch.nextDimensionNumber` and are never reused, so a socket named
  `d1` keeps meaning the same dimension.
- `.failed(reason:)` also covers a solve that could only meet its constraints by collapsing or inverting a curve
  ("Circle 1 would shrink to nothing."); that component keeps its warm start. An arc counts as inside out only when
  its end lands on its start; a typed edit may carry the end past the start (30° to a 330° sweep).
- Wired values for exposed dimensions go into `SketchDimension.value`. NaN, ±∞ and non-positive lengths come back as
  plain `.failed` reasons. `measurements` holds reference dimensions; output them in name order.
- Call `Sketch.remember(_:)` after a usable solve so the next one warm-starts; re-solving a solved sketch is exact.
- `SketchRegionResult.warning` is the open-curve warning text.

## S5 (editor)
- Drag with `SketchSolver.solve(_:dragging:)` each frame, then `remember` the result.
- Freedom colours come from `SketchSolution.freedom`. Labels ("Line 3", "Angle d4 (30°)") come from `Sketch.label(of:)`.
- Commands return `SketchEdit` (sketch + undo description + `removed`, the constraints and dimensions the command
  deleted, for example a fillet's lengths and the corner's fix) or throw `SketchCommandError` with a plain message.
  A command that would remove an exposed dimension throws instead of removing it.
- Drag solves bound their pull (`ComponentSolver.pullIterationLimit`), but the solver is dense: a release drag solve
  of a fully constrained rectangle patterned 30 times takes about 0.3 s. Budget frames, or coalesce drags, for
  sketches of several hundred unknowns; `patternLimit` is 100. A sparse solver is future work.
- Patterns add construction connectors (linear) or spokes (circular) and their dimensions: one distance for a
  linear pattern, one angle per copied point for a circular one. Show them as pattern construction, not as user
  geometry, if the editor can tell them apart.
- Constraints that hold whatever the geometry is (concentric on circles sharing a centre) are dropped by the solver,
  not reported; the editor may skip creating them when it infers constraints.
