# Sketcher S1 + S2 handoff (for S3, S4 and S5)

S1 and S2 live in `CreatorSketch` (plan: `docs/superpowers/plans/2026-10-08-s1-s2-sketch-solver-regions.md`).
These are the items later milestones must pick up.

## S3 (Profile2D holes, after M3)
- Switch `SketchRegion.profile(on:)` to `Profile2D(plane:outer:holes:)`; until then holes are not cut.
- Regions store an arc traversed clockwise as `Segment2D.arc` with `end < start`, which keeps loops continuous
  (`Profile2D.isClosed` holds). Today `build_profile` throws "an arc in the profile has no sweep" for these, so a
  region with a concave arc (a notch) does not extrude. Teach the shim to build such an arc from `end` to `start`
  (`BRepBuilderAPI_MakeWire` orients the edge), and make `Segment2D.length` use `abs`.
- Outer loops run counter-clockwise and holes clockwise, matching spec §6's "hole wires clockwise".

## S4 (Sketch node)
- `ProjectionSource.reference` is the key under which the node stores the projection's `EdgePick`. Refresh `curve`
  and set `isSuspended` on each evaluate before solving; suspended constraints come back in `SketchSolution.suspended`.
- Map statuses to node states. `.underConstrained` is `.warning`; `.overConstrained` (use `conflictMessages`) and
  `.failed(reason:)` are `.error`. Keep the last good output ghosted; unsatisfiable components keep their warm start.
- `conflictMessages` has one sentence per minimal conflict set, and a component reports every independent conflict
  (up to `ConflictSearch.setLimit`), so show them all: removing every listed set restores consistency.
- `Sketch` encodes deterministically (ID-keyed dictionaries are JSON objects); embed it with `.sortedKeys`.
- Reference angles are measured between undirected lines, nearest their stored value (30° and 150° name the same
  pair of lines), so switching a driving angle to reference keeps its number.
- Wired values for exposed dimensions go into `SketchDimension.value`. NaN, ±∞ and non-positive lengths come back as
  plain `.failed` reasons. `measurements` holds reference dimensions; output them in name order.
- Call `Sketch.remember(_:)` after a usable solve so the next one warm-starts; re-solving a solved sketch is exact.
- `SketchRegionResult.warning` is the open-curve warning text.

## S5 (editor)
- Drag with `SketchSolver.solve(_:dragging:)` each frame, then `remember` the result.
- Freedom colours come from `SketchSolution.freedom`. Labels ("Line 3", "Angle d4 (30°)") come from `Sketch.label(of:)`.
- Commands return `SketchEdit` (sketch + undo description) or throw `SketchCommandError` with a plain message.
- Patterns add construction connectors (linear) or spokes (circular) and their dimensions: one distance for a
  linear pattern, one angle per copied point for a circular one. Show them as pattern construction, not as user
  geometry, if the editor can tell them apart.
- Constraints that hold whatever the geometry is (concentric on circles sharing a centre) are dropped by the solver,
  not reported; the editor may skip creating them when it infers constraints.
