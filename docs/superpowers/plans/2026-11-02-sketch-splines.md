# G-c: Sketch splines — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Degree-5 fit-point splines in the sketcher, with tangent and curvature handles and a Curvature (G2) constraint, flowing as
exact B-splines through regions, profiles and the kernel.

**Architecture:** `CreatorGeometry` gets the curve maths (`SplineCurve2D`, quintic Hermite chains, the automatic-handle solve) and
`Segment2D.spline`; the shim builds a `Geom2d_BSplineCurve` edge; `CreatorSketch` gets the entity, handle columns in the solver and the
`.curvature` constraint; regions learn spline intersections; the editor gets the tool and handles.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 C++ shim.

**Spec:** `docs/superpowers/specs/2026-11-02-sketch-splines-design.md`.

## Global Constraints

- Swift Testing; `swiftlint lint --strict` 0 (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`); 12 "Test run with" lines on
  macOS and Linux; only the known `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine` failure.
- OCCT only behind `Kernel`, under `OCCTKernel.serialized` (tests too); shim portable (`cocct::kPi`, no POSIX headers, no
  `__attribute__`); every C allocation has a `*_free`; no C++ exception crosses into Swift.
- `CreatorSketch` imports only `CreatorGeometry` and Foundation; never iterate a dictionary where order reaches output.
- Solver residuals have analytic Jacobians (no finite differences in `Sources`).
- Copy is exact: "Trim doesn't work on splines yet.", "Extend doesn't work on splines yet.", "Fillet doesn't work on splines yet.",
  "A line and an arc can't meet with equal curvature.", "Spline N crosses itself, so it isn't part of a region.", undo names "Add
  Spline", "Move Handle", "Release Handle", "Add Curvature Constraint"; toolbar "Spline", key S; constraint button "Curvature".
- File format 11 (`GraphFile.currentFormatVersion`); files 1–10 open unchanged.

## Review Focus

1. A sketch saved, reopened and re-solved gives the same spline to 1e-12 (the automatic handles are a pure function of stored data).
2. The kernel's edge equals the sketch's curve: sample both at 200 parameters, within 1e-9 mm.
3. A two-point spline with automatic handles is the straight chord, and a region bounded by it behaves as a line would.
4. Deleting a line that a spline end is Curvature-constrained to removes the constraint and leaves the spline's handle active (not lost).
5. Mirror of a spline with active handles mirrors the handles (tangent reflected, curvature sign flipped).

---

### Task 1: The curve in CreatorGeometry and `Segment2D.spline`

**Files:** Create `Sources/CreatorGeometry/Spline/SplineCurve2D.swift`, `QuinticHermite.swift`, `SplineHandles.swift` (the
automatic-handle solve), `SplineCurve2D+Geometry.swift` (evaluate, derivatives, length, split, nearest, bounds); modify
`Segment2D.swift`, `Segment2D+Translated.swift`, `Profile2D+Contains.swift`, `Fields/ProfileDistance.swift`; give every other
`switch` over `Segment2D` (FakeKernel, FakeKernel+Holes, FaceRegion+Profile, EdgeChains, RegionTriangulator) a spline case
(sampling where a polyline is wanted, a worded refusal where a line/arc is required: EdgeChains → Curve Pattern "Curve Pattern
follows lines and arcs."). Tests in `Tests/CreatorGeometryTests/Spline*Tests.swift`.

**Produces:** `SplineHandle { tangent: Vector2?, curvature: Vector2? }` (nil = automatic); `SplineDefinition { points: [Vector2],
handles: [SplineHandle] }` with `func curve() -> SplineCurve2D` (runs the automatic-handle solve per the spec's maths);
`SplineCurve2D { degree 5, poles: [Vector2], knots: [Double], multiplicities: [Int] }` with `point(at:)`, `derivative(at:order:)`,
`curvature(at:)`, `length`, `split(at:)`, `nearestParameter(to:)`, `parameterRange`; `Segment2D.spline(SplineCurve2D)`.

- [ ] Failing tests: `hermiteToBSplineIsExact`, `chainIsC2`, `automaticHandlesReproduceAQuintic` (fit points on y = x⁵ − 2x³ + x,
  all automatic, interior: matches to 1e-9 away from the ends), `twoPointSplineIsTheChord`, `curvatureMatchesFiniteDifferences`,
  `oneActiveHandleKeepsTheLowerCondition`, `lengthAndBoundsAndSplit`, `nearestPoint`, every existing Segment2D switch's spline case.
- [ ] Implement; `swift test --filter 'CreatorGeometryTests'`, plus the consumers' targets; lint. Commit `feat(geometry): degree-5 fit-point splines`.

### Task 2: The kernel and shim

**Files:** `Sources/COCCT/include/cocct.h` (`occt_segment` kind 2 with `pole_offset`, `pole_count`, `knot_offset`, `knot_count`;
`occt_profile` gains `const double *spline_poles; const double *spline_knots; const int *spline_mults`), `cocct_build.cpp`
(`build_edge` kind 2 → `Geom2d_BSplineCurve` on the plane, `signed_area` exact per Bézier span), `Sources/CreatorOCCT/OCCTProfile.swift`.
Tests `Tests/CreatorOCCTTests/SplineProfileTests.swift`.

**Consumes:** Task 1's `SplineCurve2D`.

- [ ] Failing tests: `aSplineProfileExtrudes` (valid, volume vs the polygon area from Gauss quadrature × height, 1e-9 rel.),
  `theEdgeIsTheSketchCurve` (200 samples, 1e-9 mm), `holeOrientationWithASpline`, `revolveAndLoftASplineProfile`, `sideTagsUnchanged`
  (the spline's side face carries `.side(loop:segment:)`), `aLineSplineJointIsG2WhenTheCurveSaysSo` (build the profile directly from a
  line and a spline whose end tangent and curvature match the line's: `Kernel.continuity` of the side edge reads G2; with a curvature
  mismatch it reads G1).
- [ ] Implement; `swift test --filter CreatorOCCTTests`; Linux `XP_TRACK=g2c scripts/linux-test.sh test --filter CreatorOCCTTests`;
  lint. Commit `feat(occt): spline profile edges`.

### Task 3: The sketch entity, handles, the Curvature constraint and the solver

**Files:** `Sources/CreatorSketch/Model/SketchEntityKind.swift` (`.spline(points: [SketchEntityID], handles: [SplineHandleState])`,
`SplineHandleState { tangent: Bool, curvature: Bool }` = active flags), `SketchConstraint.swift` (`.curvature(SketchEntityID,
SketchEntityID)`), `SketchEntityKind+Points/+Finite/+Replacing`, `Sketch+Labels` ("Spline N", "Curvature"), `SolvedState`
(`.handle(Vector2)`), `Solver/UnknownLayout` (handle columns: 2 per active vector, keyed by (entity, fit index, kind)), `TermBuilder`
(Tangent and Curvature at spline ends; activating handles is the editor's job, the solver refuses a constraint on an inactive handle as
a validation error), `Equation` + `Equation+Rows` + `Equation+Columns` (`splineTangent`, `splineCurvature` rows), `Sketch+Solution`
(`remember` handle values), `DegenerateGeometry` (coincident consecutive fit points), `SketchFlipCheck`, `SketchMeasure`,
`Sketch+Curves.shape(of:)` (via `SplineDefinition.curve()`), `CreatorGraph/GraphFile.swift` (format 11 and its changelog line),
`ConstantValue` finiteness. Tests `Tests/CreatorSketchTests/Spline*Tests.swift`.

**Consumes:** Task 1.

- [ ] Failing tests: `jacobiansMatchFiniteDifferences` (each new row), `dofOfAnAutomaticSplineIsItsPoints`, `activeHandleAddsTwoDOF`,
  `tangentAtASplineEnd`, `curvatureToALineMakesZeroCurvature`, `curvatureToAnArcMatchesOneOverR` (turning sense), `curvatureBetweenSplines`,
  `lineToArcCurvatureIsRefused` (the spec's copy), `conflictsAreNamed`, `saveReopenSolveIsIdentical` (1e-12), `formatElevenRoundTrips`,
  `formatTenOpensUnchanged`, `deletingTheLineDropsTheConstraintKeepsTheHandle`.
- [ ] Implement; `swift test --filter 'CreatorSketchTests|CreatorGraphTests'`; lint. Commit `feat(sketch): spline entity, handles and the curvature constraint`.

### Task 4: Regions, the Sketch node and the G2 acceptance

**Files:** `Sources/CreatorSketch/Geometry/CurveShape.swift` (+ spline: every member), `CurveIntersection.swift` (spline × line /
arc / spline: Bézier-hull subdivision then Newton to 1e-10 mm), `Regions/LoopSegment`, `HalfEdge`, `RegionGraph.isSameGeometry`,
`LoopMeasure` (exact polynomial area and moments), the self-crossing warning (sketch warnings path used by the Sketch node), `SketchTrace`.
Tests `Tests/CreatorSketchTests/SplineRegionTests.swift`, `Tests/CreatorNodesTests/Sketch/SplineSketchNodeTests.swift`,
`Tests/CreatorOCCTTests/SplineContinuityAcceptanceTests.swift` (gated `canImport(CreatorOCCT)`).

**Consumes:** Tasks 1–3.

- [ ] Failing tests: `aLineAndASplineCloseARegion`, `twoSplinesCloseARegion`, `aSplineCrossingACircleSplitsRegions`,
  `selfCrossingWarnsAndIsLeftOut` (copy), `traceMapsSplineSegmentsToTheEntity`, and the acceptance
  `aCurvatureJoinedSketchExtrudesToAG2Edge`: a Sketch node with a line and a spline Curvature-constrained at both shared ends, extruded
  through the real Evaluator on OCCT; `Kernel.continuity` on each vertical joint edge reads G2; the same with Tangent reads G1 with a
  curvature jump.
- [ ] Implement; `swift test --filter 'CreatorSketchTests|CreatorNodesTests'`, `swift test --filter SplineContinuityAcceptance`; lint.
  Commit `feat(sketch): splines in regions and profiles`.

### Task 5: The editor

**Files:** `Sources/CreatorSketchEditor/SketchTool.swift` (`.spline`, title "Spline", key S in `SketchToolButton`), `DrawState`
(`.splineThrough([SketchAnchor])`), `SketchEditorModel+Drawing` (click, finish on Return / double click / last point again / Esc),
`SketchPreview.PreviewCurve.spline`, `SketchEditorModel+Inference` (Tangent inferred at a line or arc end; ⌘ suppresses),
`SketchOverlayBuilder` (spline polyline from `SplineCurve2D`, handle glyphs for a selected spline), `SketchPicker` (spline curve hits,
handle knob hits), `SketchEditorModel+Drag` (handle drag: activates, solves live with the knob as a soft target), `SketchInspector`
(the fit point's handle rows and Release; refused while a constraint uses it), `SketchConstraintKind.curvature` + `SelectionShape`
bucket `splines`, `SketchCommands` trim/extend/fillet refusals and `+Copy` (mirror reflects handles), `SketchStepName`
(`addSpline`, `moveHandle`, `releaseHandle`, `addCurvatureConstraint`). Tests `Tests/CreatorSketchEditorTests/Spline*Tests.swift`.

**Consumes:** Tasks 1, 3, 4.

- [ ] Failing tests: `drawingASplinePlacesFitPoints`, `finishingKeepsTwoOrMore`, `escWithOnePointDiscards`, `reusesExistingEndpoints`,
  `infersTangentAtAnArcEnd`, `commandSuppressesInference`, `draggingAHandleActivatesIt`, `releaseMakesItAutomatic`,
  `releaseIsRefusedWhileConstrained`, `curvatureButtonActivatesBothHandles`, `trimExtendFilletRefuse` (copy), `mirrorReflectsHandles`,
  `patternCopiesSplines`, `undoNames`, `overlayDrawsTheCurveAndHandles`, `keySPicksTheTool`.
- [ ] Implement; `swift test --filter 'CreatorSketchEditorTests|CreatorAppTests'`; lint. Commit `feat(sketch-editor): the spline tool and handles`.

### Task 6: Records

- [ ] CLAUDE.md: the sketcher paragraph and module lines (`CreatorGeometry` splines, `CreatorSketch` handles and `.curvature`,
  `Segment2D.spline`, the shim's kind 2, format 11 in the format paragraph). Human checks group **SP** (spec's list).
- [ ] Full `swift test` (12 lines), lint, `scripts/linux-test.sh test` (12 lines). Commit `docs(sketch): spline records`.
