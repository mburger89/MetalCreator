# CreatorSketch

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

Driving dimensions (spec `docs/superpowers/specs/2026-10-27-driving-dimensions-design.md`, plans `2026-10-27-dim-overview.md` and
`dim-1`…`dim-4`) code is done; its human checks (group DIM) are pending.

Sketch splines (G-c of `docs/superpowers/specs/2026-11-01-g2-surfacing-design.md`: spec `docs/superpowers/specs/2026-11-02-sketch-splines-design.md`, plan `docs/superpowers/plans/2026-11-02-sketch-splines.md`; fit-point degree-5 splines with optional tangent and curvature handles, a Curvature constraint, file format 11) code is done; its human checks (group SP) are pending.

- `CreatorSketch`: the constraint sketch model, `SketchSolver` (numeric Levenberg–Marquardt with analytic Jacobians,
  DOF and minimal conflicts), `SketchRegions` and `SketchCommands`. Imports only `CreatorGeometry` and Foundation;
  never iterate a dictionary where order reaches output. Tests: `swift test --filter CreatorSketchTests`.
  Splines: the `.spline(points:handles:)` entity (`SplineHandleState` flags; the handle values live in `SolvedState.splineHandles`, so a handle is automatic until activated, and activating captures the current value so the curve doesn't move); the solver has two columns per ACTIVE handle only; `.curvature` is G2 between two curves (Tangent plus equal signed curvature) and a Tangent or Curvature joint applies at every end the two share (one constraint closes a loop); deleting a fit point keeps the spline while two remain; a spline that crosses itself warns "Spline N crosses itself, so it isn't part of a region." and is left out of regions.
  Driving dimensions: `SketchRegion.sources` (each segment's source entity), `SketchTrace` (which entity made which profile segment; evaluation
  output, never saved), `ModelDimensionKind` (the kind a pair of picked entities gets) and `MeasuredDimension` (a dimension added at its measured
  value, as a reference when it would over-define).
