# MetalCreator S1 + S2: Constraint Sketch Solver, Regions and Commands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure-Swift `CreatorSketch` target. It holds the constraint sketch model and `SketchSolver`: a numeric Levenberg–Marquardt solver with analytic Jacobians, component decomposition, warm start, drag mode, rank-revealing DOF and freedom analysis, and minimal conflict sets in plain language. It also finds closed regions (`SketchRegions`) and provides the trim, extend, fillet, mirror and pattern commands (`SketchCommands`). These are milestones S1 and S2 of the sketcher spec.

**Architecture:**
- `CreatorSketch` depends only on `CreatorGeometry` and Foundation. It has four folders:
  - `Model/` holds the `Sketch` value and its parts.
  - `Solver/` covers sketch → equations → components → LM → analysis.
  - `Geometry/` holds curve shapes and exact intersections.
  - `Regions/` and `Commands/` hold the S2 features.
- **Solver pipeline:**
  - Every constraint, driving dimension and arc becomes an `Equation`: residual rows over global unknown columns, each with an analytic gradient.
  - A union–find over the columns splits the equations into components.
  - Each component is solved by LM (dense Householder QR of the damped system) from the warm start, then analysed with a column-pivoted QR of Jᵀ.
- **Regions pipeline:** split every non-construction curve at its exact intersections, walk the faces of the planar graph, nest them even–odd, then sort.
- **Commands** are pure `(Sketch, arguments) -> SketchEdit` functions.

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, Foundation only. No new packages.

**Spec:** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (§2 boundary rules, §3 model and commands, §4 solver, §5 regions, §9 S1–S2, §10 tests). The project-wide rules in `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` also bind this plan. `CLAUDE.md` has the repository rules.

**Where to work:** the git worktree `/Users/maxburger/Developer/worktrees/MetalCreator-sketcher`, branch `spec/sketcher`. Run every command from that directory, and never `cd` to `/Users/maxburger/Developer/MetalCreator`, where M3 is in progress. `swift test --filter CreatorSketchTests` also builds the other test targets, so Homebrew OCCT must be installed, as it already is for M2.

**Verified:** every code block below was compiled and run before this plan was written. That covers each task boundary on its own and the full repository with this plan's `Package.swift` edit (143 tests). A task's code is meant to go in as written.

**Decisions made in this plan** (each is an interpretation of the spec, or a gap the spec leaves open):

*Model*
- **Conflicts are `[SketchConstraintRef]`, not `[SketchConstraintID]`.** `SketchConstraintRef` is `.constraint(id)` or `.dimension(id)`. The spec's own example message names a dimension ("Angle d4"), so the list must be able to hold one. Constraints sort before dimensions, each in ID order.
- **`ProjectionSource` stores a `reference: String`, not an `EdgePick`.** `CreatorSketch` may not import `CreatorKernel`, where M3's `EdgePick` lives. The Sketch node (S4) keeps the pick in its settings under that key (spec §7: "the `Sketch` value, plus pick data for projected edges"). The source also caches the 2D `curve`, plus `isSuspended`. The solver skips every constraint on a suspended edge and reports it in `SketchSolution.suspended`, and regions ignore that edge.
- **IDs are `Int`-backed, share one counter (`Sketch.nextID`) and are never reused**, so sorting by ID is the fixed iteration order. Labels number each kind by ordinal ("Line 3" is the third line in ID order), and S5 shows the same labels.
- **`fix` stores its target** (`.fix(point, at:)`), so a fix is an ordinary residual and can be named in a conflict.
- **Reference dimensions are measured** into `SketchSolution.measurements`, ready for S4's `measurements` output. **Angles are between undirected lines**, as a driving angle's residual is (it is met by θ or 180° − θ depending on which way each line was drawn). So a measured angle reports whichever of α and 180° − α is nearer the dimension's own stored value, and a driving angle switched to reference reads back what the user typed.
- **The three ID types are `CodingKeyRepresentable`** (key: the decimal raw value), so `entities`, `constraints`, `dimensions` and `solved` encode as JSON objects, not as `[key, value, …]` arrays in hash order. With `.sortedKeys` (which `GraphFileIO` uses) a sketch encodes to the same bytes every time, which S4's `.mcgraph` files need. Changing this after S4 ships would break saved files.

*Equations*
- **Lines are infinite and arcs are full circles inside constraints.** That makes trim, extend and fillet safe: a constraint never depends on where a curve stops, except length, equal length and midpoint, and the commands remove those.
- **Angle-type residuals are scaled by the mean length of their lines at the warm start** (spec §4, "comparable weight"). **Horizontal and vertical on a line are angle-based too** (`scale · d.y/|d|`), as are parallel, perpendicular and angle. A zero-length line gives an angle-type residual of 1, never 0. Verification found that a solve could otherwise "meet" horizontal plus a 30° angle by shrinking the line to 1e-8 mm.
- **Tangency at a shared endpoint uses first-order forms.**
  - Line–arc: the radius is perpendicular to the line at the shared point.
  - Arc–arc: the shared point is on the line through both centres.
  - The distance form (`|distance(centre, line)| = r`) is second order at a shared point, which made the fillet's tangent points undetermined to the rank test. It is used only for curves that don't share an endpoint.
- **Branch choices are read from the warm start**, which is what makes solves branch-stable: the side of a line for point–line distances and line–circle tangency, the sign of an angle, and internal or external tangency.
- **Rows that hold whatever the geometry is are dropped** (`TermBuilder.isTriviallyMet`): the same point twice (coincident, horizontal or vertical points; concentric curves that already share a centre), the same line or circle twice (parallel, equal, a 0° or 180° angle), and constant-only rows that already agree (horizontal on a projected edge that is horizontal). Their Jacobian row is identically zero, so kept they would always read as redundancy and turn a satisfied sketch into a node error. Constant rows that disagree are kept and reported as "… can't be met." Editor inference (S5) and pattern or mirror sharing make the shared-centre case likely.

*Convergence and analysis*
- **Convergence:**
  - LM stops when max |residual| ≤ 1e-9 mm, when a step is ≤ 1e-12, or after 200 iterations.
  - It then **polishes**: at most two more steps, each kept only if it lowers the residual, stopping at 1e-12.
  - Without the polish, coincident points could be up to ~1e-9 mm apart, the same as the regions' merge tolerance (measured at 8.6e-10). Polishing only above 1e-12 means re-solving a solved sketch returns it bit for bit.
  - A component counts as **satisfied** when max |residual| ≤ 1e-7 mm.
- **Redundancy counts only user rows.** The implicit arc row (|end − c| = |start − c|) may be implied by user rows without being flagged. Otherwise a mirrored arc, or an arc with three fixed points, would always read as over-constrained.
- **Conflicts are minimal conflicting sets, found by a deletion filter** (the spec's "removing each candidate in turn and re-checking"), in `ConflictSearch`. Every member of a set is necessary: removing any one member breaks that conflict.
  - **One set per independent conflict.** After a set is found it is set aside and the rest re-checked; if it still can't be met (or is still dependent) the search goes on, up to `ConflictSearch.setLimit` (8) sets per component. Removing every reported set leaves the component consistent and independent, so fixing one conflict never just uncovers another that was already there. Sets are listed in member order, and each gets its own message. Conflicts that share a constraint are one conflict: once a set is removed the other is gone too, so it isn't reported.
  - **An unsatisfiable component is narrowed before filtering.** The refs whose rows still carry residual (≥ 1e-3 of the largest) at the stalled least-squares point are where the misfit sits. One trial solve checks that they alone can't be met; if so the filter runs on them only, otherwise on everything left. Each trial solves only the chosen refs and the columns they touch, from the warm start. That keeps a conflict interactive (spec §8 re-solves every frame): 30 fully constrained squares plus one conflicting length took 3.8 s in release with a per-ref filter, and takes 0.09 s now (the consistent strip solves in 0.04 s).
  - A redundant (satisfied) component is re-checked by rank.
  - If an unsatisfiable component's remainder can be met but repeats itself, those dependent sets are reported too.
  - An unsatisfiable component keeps its warm-start positions, so S4 can ghost the last good geometry.
- **`.failed(reason:)` is for sketches refused before solving:**
  - a non-positive or non-finite value
  - an angle outside 0–180°
  - the wrong kind of entity
  - a reference to a missing entity
  - a degenerate line or arc
  An impossible triangle is `.overConstrained` and names its three sides. Both become a node `.error` (spec §4 "Plain errors").
- **Drag mode** has two phases. First LM runs with the drag targets as extra rows (weight 1; the other unknowns are unweighted, so the dragged point wins along any freedom). Then LM runs again with only the hard constraints, from that result, so every constraint holds exactly. If the second phase fails, the solve is redone without the drag.

*Regions and commands*
- **Regions output `SketchRegion` (outer loop + hole loops of `Segment2D`), local to `CreatorSketch`.**
  - The outer loop runs counter-clockwise and holes run clockwise. An arc traversed clockwise is stored with `end < start`, which keeps every loop continuous (`Profile2D.isClosed` holds).
  - `SketchRegion.profile(on:)` returns today's `Profile2D(plane:segments:)` for the **outer loop only**. **S3** gives `Profile2D` holes and switches this to `Profile2D(plane:outer:holes:)`. It must also let the shim build arcs with `end < start`: today `build_profile` throws "an arc in the profile has no sweep" for them, so a region with a concave arc won't extrude until S3. Task 12 records this in the handoff notes.
  - **Reconciled after S3 merged (spec §5 step 5):** regions now emit every loop counter-clockwise (a hole walked clockwise is reversed, its arcs turned counter-clockwise), rotated to start at the lexicographically smallest start point, with holes sorted by area descending then centroid x, y; `profile(on:)` passes the holes to `Profile2D(plane:outer:holes:)`. The `end < start` storage survives only for an arc a counter-clockwise loop runs along clockwise (a notch); the shim still rejects it, which spec §6 defers ("a clockwise-arc segment case is deferred unless S4 needs it"). The handoff note carries it to S4. The code blocks below show the pre-S3 version.
- **An "open curve"** is a non-construction curve that no face uses. A line crossing a square bounds two regions, so its overhanging ends don't make it open.
- **Commands read geometry at current positions** (solved, else drawn) and give new points matching drawn and warm-start positions, so their result solves without moving anything.
  - Endpoints are shared with the cutting curve's endpoint when one is there; otherwise they are held on it by point-on.
  - Trim, extend and fillet remove the trimmed curve's length dimensions and its equal-length and midpoint constraints.
- **Pattern constraints follow spec §3, holding every instance rigidly with exactly two rows per copied point.** Per-curve equal and parallel would not do: for a closed loop of lines those rows depend on each other (the edge vectors sum to zero), so a patterned rectangle came out over-constrained, while equal-only copies could shear. Patterning therefore never changes a sketch's status: `.solved` stays `.solved`, and a sketch with *n* DOF keeps *n*.
  - Linear: a construction connector joins each point to its copy in the next instance. The first connector, from the selection's first point, gets a distance dimension of `spacing`, and its direction is held: horizontal or vertical when the pattern direction is, otherwise parallel, perpendicular or at a measured angle dimension to the selection's first line. (With no line in the selection, an oblique direction stays free: one DOF.) Every other connector is held parallel and equal to the first, so editing the spacing moves every copy.
  - Circular: each point away from the centre gets a construction spoke from the centre, and so does each copy. A copy's spoke is held equal to the original point's spoke, with an angle dimension of one step from the previous instance's spoke.
  - Copied circles are held equal to their originals (a radius is its own unknown); copied lines and arcs need nothing more.
  - The spec's "concentric" is met by sharing any point at the pattern centre, so arcs and circles centred there stay concentric.
  - Counts run from 2 to 1000.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency. No `@unchecked Sendable` and no `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- **`CreatorSketch` imports only `CreatorGeometry` and Foundation** (spec §2). It has no graph, kernel, MetalUI or OCCT dependency. Do not modify `CreatorGeometry` or any other existing target. S3 changes `Profile2D`.
- **`Package.swift` changes are two additive, in-place insertions only**: the target after `.target(name: "CreatorGeometry"),` and the test target after the `CreatorGeometryTests` line. Another branch (M3) edits other lines of the same file.
- All model types are `Sendable`, `Hashable` and `Codable` (spec §3). Units are millimetres and degrees in the model and radians inside the solver.
- **Deterministic:** nothing that affects output may depend on `Dictionary` or `Set` iteration order. Iterate sorted IDs, sorted keys or arrays.
- One type per Swift file, named after the type. Extensions go in `Type+Purpose.swift`. Test fixture files may hold several helpers and must say so in a header comment.
- No force unwraps and no force `try`. No GCD. No third-party packages. No `Formatter` subclasses or `String(format:)`: numbers in messages use `FormatStyle` with the `en_US_POSIX` locale (`Double.sketchDisplay`).
- User-facing text (`SolveFailure.reason`, conflict messages, `SketchCommandError.message`, region warnings) is plain language that names entities by label ("Line 3", "Angle d4 (30°)").
- Every commit message ends with a blank line, then the implementing model's harness-provided `Co-Authored-By:` and `Claude-Session:` lines.

## Review Focus

These are inputs the spec implies but no task would otherwise exercise. Each has a test in the named task.

1. **Corners joined by coincident constraints instead of shared points** (an editor or importer that doesn't share points). After a solve, the loop must close into a region, with no "3 curves don't form a closed region." The solver's stopping tolerance equals the regions' merge tolerance, so this needs the polish step. *Task 5: `ConvergenceTests.solvedCoincidentPointsAgreeToRoundOff`; Task 9: `RegionTests.cornersJoinedByCoincidentConstraintsCloseARegionOnceSolved`.*
2. **Re-solving a solved sketch every frame** (S5 re-solves while dragging and typing) must not creep, even by a bit. *Task 5: `ConvergenceTests.reSolvingASolvedSketchMovesNothing`.*
3. **A line shrinking to nothing** must never satisfy an angle or orientation constraint. A conflicting sketch then reports a conflict and keeps its geometry, instead of collapsing a line. *Task 3: `ResidualTests.zeroLengthLinesNeverLookSatisfied`; Task 6: `ConflictTests.horizontalLineAgainstAnAngleToAProjectedEdge` (the line keeps its warm start).*
4. **A constraint that names an entity the sketch no longer has**, from a hand-edited, merged or damaged `.mcgraph`, gets a plain refusal, not a crash or a silent solve around it. *Task 4: `TermBuilderTests.aConstraintOnAMissingEntityIsRefusedNotSolvedAround`.*
5. **A wired dimension value that is NaN or ±∞** (S4 wires graph numbers into exposed dimensions) gets a plain refusal ("Length d1 is not a number."). *Task 4: `TermBuilderTests.aWiredValueThatIsNotANumberIsRefused`.*
6. **Typing an impossible value into a mid-sized sketch** must not freeze the editor, which re-solves every frame. *Task 6: `ConflictTests.aConflictInALargeComponentIsNarrowedBeforeFiltering` pins the number of trial solves, so it holds in debug and release alike.*
7. **Two independent conflicts in one component** are both reported, so fixing one doesn't just reveal the other. *Task 6: `ConflictTests.independentConflictsInOneComponentAreEachReported`, `independentRedundanciesInOneComponentAreEachReported`.*
8. **Patterning a closed loop** (the most common pattern) keeps the sketch's status. *Task 12: `MirrorPatternTests.linearPatternsOfClosedLoopsKeepTheirStatus`, `circularPatternsOfClosedLoopsKeepTheirStatus`, `linearCopiesFollowTheOriginalRigidly`.*
9. **Saving the same sketch twice gives the same bytes.** *Task 1: `ModelTests.sketchesEncodeDeterministicallyAsKeyedObjects`.*

---

## File Structure

```
Package.swift                                   (Task 1) + CreatorSketch, CreatorSketchTests (two insertions)
CLAUDE.md                                       (Task 1) + CreatorSketch module bullet
Sources/CreatorSketch/
  Model/                                        (Task 1) the Sketch value
    SketchEntityID, SketchConstraintID, DimensionID     Int-backed IDs, bare-integer Codable, CodingKeyRepresentable
    IDKey                                                the coding key those IDs use as dictionary keys
    SketchPlaneSource, SketchEntity, SketchEntityKind, SketchEntityKind+Points
    ProjectionSource, ProjectedCurve, SketchConstraint, DimensionKind, SketchDimension, SolvedState
    SketchConstraintRef                                  constraint or dimension (conflict lists)
    Sketch, Sketch+Editing, Sketch+Labels, Double+SketchDisplay
  Solver/
    DenseMatrix, HouseholderQR, RankRevealingQR          (Task 2) dense linear algebra
    PointOperand, RadiusOperand, CircleOperand, LineOperand, RowBuilder,
    Equation, Equation+Rows, Equation+Columns            (Task 3) residuals + analytic Jacobians
    SolveFailure, SolverTerm, UnknownLayout, TermBuilder (Task 4) sketch → equations, validation
    ComponentSystem, ComponentPartition, LevenbergMarquardt, ComponentSolver,
    SketchSolveStatus, EntityFreedom, SketchSolution, SketchMeasure, SketchSolver,
    Sketch+Solution                                      (Task 5; ComponentSolver grows in 6, 7; SketchSolver in 7)
    ConflictSearch                                       (Task 6) minimal conflict sets
  Geometry/
    SketchMath                                           (Task 3) 2D helpers
    CurveShape, CurveIntersection, SketchCurve, Sketch+Curves   (Task 8)
  Regions/                                      (Task 9)
    LoopSegment, LoopMeasure, RegionGraph, HalfEdge, RegionGraph+Faces,
    SketchRegion, SketchRegionResult, SketchRegions
  Commands/
    SketchEdit, SketchCommandError, SketchCommands, SketchEntityKind+Replacing,
    SketchCommands+Trim, SketchCommands+Extend           (Task 10)
    SketchCommands+Fillet                                (Task 11)
    SketchCommands+Copy, SketchCommands+Mirror, SketchCommands+Pattern   (Task 12)
Tests/CreatorSketchTests/
  Support/SketchTestSupport.swift (1), Support/SketchFixtures.swift (5), Support/SketchTestSupport+Commands.swift (10)
  ModelTests (1), LinearAlgebraTests (2), ResidualTests (3), TermBuilderTests (4),
  PartitionTests, ConstraintFixtureTests, ClassicSketchTests, FreedomTests, ConvergenceTests (5),
  ConflictTests (6), SolverBehaviourTests (7), IntersectionTests (8), LoopMeasureTests, RegionTests (9),
  TrimExtendTests (10), FilletTests (11), MirrorPatternTests (12)
docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md, docs/superpowers/roadmap.md   (Task 12)
```

---
### Task 1: Package target and the sketch model
**Files:**
- Create: `Sources/CreatorSketch/Model/SketchEntityID.swift`, `Sources/CreatorSketch/Model/SketchConstraintID.swift`, `Sources/CreatorSketch/Model/DimensionID.swift`, `Sources/CreatorSketch/Model/IDKey.swift`, `Sources/CreatorSketch/Model/SketchPlaneSource.swift`, `Sources/CreatorSketch/Model/SketchEntity.swift`, `Sources/CreatorSketch/Model/SketchEntityKind.swift`, `Sources/CreatorSketch/Model/SketchEntityKind+Points.swift`, `Sources/CreatorSketch/Model/ProjectionSource.swift`, `Sources/CreatorSketch/Model/ProjectedCurve.swift`, `Sources/CreatorSketch/Model/SketchConstraint.swift`, `Sources/CreatorSketch/Model/DimensionKind.swift`, `Sources/CreatorSketch/Model/SketchDimension.swift`, `Sources/CreatorSketch/Model/SolvedState.swift`, `Sources/CreatorSketch/Model/SketchConstraintRef.swift`, `Sources/CreatorSketch/Model/Sketch.swift`, `Sources/CreatorSketch/Model/Sketch+Editing.swift`, `Sources/CreatorSketch/Model/Sketch+Labels.swift`, `Sources/CreatorSketch/Model/Double+SketchDisplay.swift`, `Tests/CreatorSketchTests/Support/SketchTestSupport.swift`, `Tests/CreatorSketchTests/ModelTests.swift`
- Modify: `Package.swift`, `CLAUDE.md`
- Test: `Tests/CreatorSketchTests/ModelTests.swift`

**Interfaces:**
- Consumes: `Vector2`, `Plane`, `Angle` from `CreatorGeometry` (existing).
- Produces (all `public`, `Hashable, Sendable, Codable` unless noted):
  - `SketchEntityID`, `SketchConstraintID`, `DimensionID`: `init(_ rawValue: Int)`, `rawValue`, `Comparable`, `CodingKeyRepresentable`. Each encodes as a bare integer, and as a dictionary key as its decimal string, so dictionaries keyed by them encode as JSON objects. Internal `IDKey` is the shared `CodingKey`.
  - `SketchPlaneSource { .fixed(Plane), .wired }`, `SketchEntity { kind: SketchEntityKind; isConstruction: Bool; init(_:isConstruction: = false) }`
  - `SketchEntityKind { .point(Vector2), .line(start:end:), .arc(center:start:end:), .circle(center:radius:), .projected(ProjectionSource) }` with `referencedPoints: [SketchEntityID]` and internal `isPoint`
  - `ProjectionSource { reference: String; curve: ProjectedCurve; isSuspended: Bool }`, `ProjectedCurve { .line(Vector2, Vector2), .arc(center:radius:start:end:), .circle(center:radius:) }`
  - `SketchConstraint`: coincident, pointOn(point:curve:), horizontal, vertical, horizontalPoints, verticalPoints, parallel, perpendicular, tangent, equal, midpoint(point:line:), concentric, symmetric(_:_:about:), fix(_:at:). Each has `entities: [SketchEntityID]`.
  - `DimensionKind { .distance(a, b), .length, .radius, .diameter, .angle(a, b) }` with `entities`, and `SketchDimension { kind, name, value, isExposed, isDriving }`
  - `SolvedState { .point(Vector2), .radius(Double) }`, `SketchConstraintRef { .constraint(id), .dimension(id) }` (`Comparable`: constraints first)
  - `Sketch { plane, entities, constraints, dimensions, solved, nextID; init(plane: = .fixed(.xy)); entityIDs, constraintIDs, dimensionIDs }` (each list sorted)
  - Editing (`Sketch+Editing`):
    - adding: `add(_: SketchEntity)`, `addPoint(_:isConstruction:)`, `addLine(from:to:isConstruction:)`, `addLine(_:_:isConstruction:)`, `addArc(center:start:end:isConstruction:)`, `addCircle(center: SketchEntityID | Vector2, radius:isConstruction:)`, `add(_: SketchConstraint)`, `addDimension(_:value:isDriving:)`
    - names: `nextDimensionName()`, `renameDimension(_:to:) -> Bool`
    - removing: `removeEntity(_:)` (cascades), `removeOrphanPoints(_:)`, internal `isOrphan(_:)`, internal `takeNextID()`
    - positions: `position(of:) -> Vector2?`, `radius(of:) -> Double?` (solved, else drawn), `move(_:to:)`, `constraintRefs`
  - Labels (`Sketch+Labels`): `label(of: SketchEntityID)`, `label(of: SketchConstraintRef)`, `conflictMessage(_:) -> String`. Internal: `label(of: SketchConstraint)`, `label(of: SketchDimension)`, `title(of: SketchDimension)`, `static kindName(_:)`, `static joined(_:)`.
  - internal `Double.sketchDisplay: String`
  - Test helpers (`SketchTestSupport.swift`): `isClose` (Double and Vector2), `isNear`, `Sketch.ends(_:)`, `arcPoints(_:)`, `centerOf(_:)`, `ids(ofKind:)`, `addPolygon(_:_:isConstruction:)`.

- [ ] **Step 1: Add the targets and the module note**

In `Package.swift`, insert one line directly after `.target(name: "CreatorGeometry"),`:
```swift
        .target(name: "CreatorSketch", dependencies: ["CreatorGeometry"]),
```
and one line directly after `.testTarget(name: "CreatorGeometryTests", dependencies: ["CreatorGeometry"]),`:
```swift
        .testTarget(name: "CreatorSketchTests", dependencies: ["CreatorSketch", "CreatorGeometry"]),
```
Change no other line: M3 also edits this file, after `CreatorGraph` and `CreatorGraphTests`, so these two hunks merge cleanly.

In `CLAUDE.md`, under "Module boundaries", insert this bullet directly after the `CreatorGeometry` bullet:
```markdown
- `CreatorSketch`: the constraint sketch model, `SketchSolver` (numeric Levenberg–Marquardt with analytic Jacobians,
  DOF and minimal conflicts), `SketchRegions` and `SketchCommands`. Imports only `CreatorGeometry` and Foundation;
  never iterate a dictionary where order reaches output. Tests: `swift test --filter CreatorSketchTests`.
```

- [ ] **Step 2: Write the failing tests**

`Tests/CreatorSketchTests/Support/SketchTestSupport.swift`:
```swift
// Test fixture file: shared helpers and sketch builders for CreatorSketchTests (several helpers by design).
import CreatorGeometry
@testable import CreatorSketch

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-7) -> Bool { abs(a - b) <= tolerance }
func isClose(_ a: Vector2, _ b: Vector2, tolerance: Double = 1e-7) -> Bool { (a - b).length <= tolerance }
/// For "which solution did it pick" checks: LM's damped steps may slide a little along freedom
/// the constraints leave, so positions along a free direction are only near the minimal move.
func isNear(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length <= 1e-3 }

extension Sketch {
    /// The (start, end) point IDs of a line.
    func ends(_ line: SketchEntityID) -> (SketchEntityID, SketchEntityID) {
        guard case .line(let start, let end) = entities[line]?.kind else { preconditionFailure("not a line") }
        return (start, end)
    }

    /// The (center, start, end) point IDs of an arc.
    func arcPoints(_ arc: SketchEntityID) -> (SketchEntityID, SketchEntityID, SketchEntityID) {
        guard case .arc(let center, let start, let end) = entities[arc]?.kind else { preconditionFailure("not an arc") }
        return (center, start, end)
    }

    /// The center point ID of a circle.
    func centerOf(_ circle: SketchEntityID) -> SketchEntityID {
        guard case .circle(let center, _) = entities[circle]?.kind else { preconditionFailure("not a circle") }
        return center
    }

    /// The entities of one kind, in ID order.
    func ids(ofKind name: String) -> [SketchEntityID] {
        entityIDs.filter { entities[$0].map { Sketch.kindName($0.kind) == name } ?? false }
    }
}

/// A closed polyline through `corners`, counter-clockwise if they are. Returns the lines in order;
/// line i runs from corner i to corner i + 1.
@discardableResult
func addPolygon(_ sketch: inout Sketch, _ corners: [Vector2], isConstruction: Bool = false) -> [SketchEntityID] {
    let points = corners.map { sketch.addPoint($0) }
    return points.indices.map { sketch.addLine(from: points[$0], to: points[($0 + 1) % points.count], isConstruction: isConstruction) }
}
```
`Tests/CreatorSketchTests/ModelTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

struct ModelTests {
    @Test func idsAreHandedOutInOrderAndNeverReused() {
        var sketch = Sketch()
        let a = sketch.addPoint(.zero)
        let b = sketch.addPoint(Vector2(1, 0))
        let line = sketch.addLine(from: a, to: b)
        let constraint = sketch.add(.horizontal(line))
        #expect([a.rawValue, b.rawValue, line.rawValue, constraint.rawValue] == [1, 2, 3, 4] as [Int])
        sketch.removeEntity(line)
        #expect(sketch.addPoint(.zero).rawValue == 5)
    }

    @Test func sketchRoundTripsThroughJSON() throws {
        var sketch = Sketch(plane: .fixed(.xz))
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let center = sketch.addPoint(Vector2(5, 5))
        let (start, end) = sketch.ends(line)
        let arc = sketch.addArc(center: center, start: end, end: start, isConstruction: true)
        sketch.addCircle(center: Vector2(20, 20), radius: 3)
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge-1", curve: .line(.zero, Vector2(0, 9))))))
        sketch.add(.tangent(line, arc))
        sketch.add(.fix(start, at: .zero))
        let angle = sketch.addDimension(.angle(line, line), value: 30, isDriving: false)
        sketch.dimensions[angle]?.isExposed = true
        sketch.solved[start] = .point(Vector2(0.5, 0))
        let decoded = try JSONDecoder().decode(Sketch.self, from: try JSONEncoder().encode(sketch))
        #expect(decoded == sketch)
    }

    @Test func idsEncodeAsBareIntegers() throws {
        let data = try JSONEncoder().encode(SketchEntityID(7))
        #expect(String(decoding: data, as: UTF8.self) == "7")
    }

    @Test func sketchesEncodeDeterministicallyAsKeyedObjects() throws {
        func build() -> Sketch {
            var sketch = Sketch()
            let lines = addPolygon(&sketch, [.zero, Vector2(10, 0), Vector2(10, 5), Vector2(0, 5)])
            for line in lines { sketch.add(.horizontal(line)) }
            for line in lines { sketch.addDimension(.length(line), value: 10) }
            for id in sketch.ids(ofKind: "Point") { sketch.solved[id] = .point(Vector2(1, 2)) }
            return sketch
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Two separately built (separately hashed) sketches give the same bytes.
        let first = try encoder.encode(build())
        let second = try encoder.encode(build())
        #expect(first == second)
        let object = try #require(try JSONSerialization.jsonObject(with: first) as? [String: Any])
        for key in ["entities", "constraints", "dimensions", "solved"] {
            #expect(object[key] is [String: Any], "\(key) encodes as a JSON object")
        }
        let entities = try #require(object["entities"] as? [String: Any])
        #expect(entities.keys.sorted() == (1...8).map(String.init).sorted())
        #expect(try JSONDecoder().decode(Sketch.self, from: first) == build())
    }

    @Test func dimensionsAreNamedD1D2AndRenamesStayUnique() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let first = sketch.addDimension(.length(line), value: 10)
        let second = sketch.addDimension(.length(line), value: 10)
        #expect(sketch.dimensions[first]?.name == "d1")
        #expect(sketch.dimensions[second]?.name == "d2")
        let taken = sketch.renameDimension(second, to: "d1")
        let blank = sketch.renameDimension(second, to: "  ")
        let renamed = sketch.renameDimension(second, to: " width ")
        #expect(taken == false)
        #expect(blank == false)
        #expect(renamed)
        #expect(sketch.dimensions[second]?.name == "width")
        sketch.addDimension(.length(line), value: 1)
        #expect(sketch.dimensions.values.map(\.name).sorted() == ["d1", "d2", "width"])
    }

    @Test func removingAPointRemovesItsCurvesAndTheirConstraints() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        let other = sketch.addLine(from: end, to: sketch.addPoint(Vector2(10, 10)))
        sketch.add(.horizontal(line))
        let kept = sketch.add(.vertical(other))
        sketch.addDimension(.length(line), value: 10)
        sketch.solved[start] = .point(.zero)
        sketch.removeEntity(start)
        #expect(sketch.entities[line] == nil)
        #expect(sketch.entities[other] != nil)
        #expect(Array(sketch.constraints.keys) == [kept])
        #expect(sketch.dimensions.isEmpty)
        #expect(sketch.solved.isEmpty)
    }

    @Test func positionsPreferTheLastSolve() {
        var sketch = Sketch()
        let p = sketch.addPoint(Vector2(1, 2))
        let circle = sketch.addCircle(center: p, radius: 4)
        #expect(sketch.position(of: p) == Vector2(1, 2))
        #expect(sketch.radius(of: circle) == 4)
        sketch.solved[p] = .point(Vector2(3, 3))
        sketch.solved[circle] = .radius(5)
        #expect(sketch.position(of: p) == Vector2(3, 3))
        #expect(sketch.radius(of: circle) == 5)
    }

    @Test func labelsCountEachKindInIDOrder() {
        var sketch = Sketch()
        let first = sketch.addLine(.zero, Vector2(1, 0))
        let second = sketch.addLine(Vector2(0, 1), Vector2(1, 1))
        let horizontal = sketch.add(.horizontal(second))
        let angle = sketch.addDimension(.angle(first, second), value: 30)
        #expect(sketch.label(of: second) == "Line 2")
        #expect(sketch.label(of: sketch.ends(second).0) == "Point 3")
        #expect(sketch.label(of: .constraint(horizontal)) == "Horizontal on Line 2")
        #expect(sketch.label(of: .dimension(angle)) == "Angle d1 (30°)")
        #expect(sketch.conflictMessage([.constraint(horizontal), .dimension(angle)])
            == "Horizontal on Line 2 conflicts with Angle d1 (30°).")
    }
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.ModelTests`
Expected: the build fails. SwiftPM reports that target `CreatorSketch` has no source files (an empty `Sources/CreatorSketch` folder), or the compiler reports `cannot find 'Sketch' in scope`.

- [ ] **Step 4: Implement**

`Sources/CreatorSketch/Model/SketchEntityID.swift`:
```swift
/// Identifies one entity (point, line, arc, circle or projected edge) inside a sketch.
/// IDs are handed out by `Sketch` in increasing order and never reused, so sorting by ID is
/// the sketch's fixed iteration order.
public struct SketchEntityID: Hashable, Sendable, Comparable, Codable, CodingKeyRepresentable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: SketchEntityID, rhs: SketchEntityID) -> Bool { lhs.rawValue < rhs.rawValue }

    // Lets `[SketchEntityID: …]` encode as a JSON object keyed by the decimal ID, not as a flat
    // [key, value, …] array in hash order, so `.sortedKeys` makes files byte-identical.
    public var codingKey: any CodingKey { IDKey(rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        guard let rawValue = codingKey.intValue ?? Int(codingKey.stringValue) else { return nil }
        self.init(rawValue)
    }
}
```
`Sources/CreatorSketch/Model/SketchConstraintID.swift`:
```swift
/// Identifies one geometric constraint inside a sketch.
/// IDs are handed out by `Sketch` in increasing order and never reused, so sorting by ID is
/// the sketch's fixed iteration order.
public struct SketchConstraintID: Hashable, Sendable, Comparable, Codable, CodingKeyRepresentable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: SketchConstraintID, rhs: SketchConstraintID) -> Bool { lhs.rawValue < rhs.rawValue }

    // Lets `[SketchConstraintID: …]` encode as a JSON object keyed by the decimal ID, not as a flat
    // [key, value, …] array in hash order, so `.sortedKeys` makes files byte-identical.
    public var codingKey: any CodingKey { IDKey(rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        guard let rawValue = codingKey.intValue ?? Int(codingKey.stringValue) else { return nil }
        self.init(rawValue)
    }
}
```
`Sources/CreatorSketch/Model/DimensionID.swift`:
```swift
/// Identifies one named dimension inside a sketch.
/// IDs are handed out by `Sketch` in increasing order and never reused, so sorting by ID is
/// the sketch's fixed iteration order.
public struct DimensionID: Hashable, Sendable, Comparable, Codable, CodingKeyRepresentable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: DimensionID, rhs: DimensionID) -> Bool { lhs.rawValue < rhs.rawValue }

    // Lets `[DimensionID: …]` encode as a JSON object keyed by the decimal ID, not as a flat
    // [key, value, …] array in hash order, so `.sortedKeys` makes files byte-identical.
    public var codingKey: any CodingKey { IDKey(rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        guard let rawValue = codingKey.intValue ?? Int(codingKey.stringValue) else { return nil }
        self.init(rawValue)
    }
}
```
`Sources/CreatorSketch/Model/IDKey.swift`:
```swift
/// The coding key for a sketch ID used as a dictionary key: the decimal raw value as a string
/// (and as an int), so `[SketchEntityID: …]` and friends encode as JSON objects.
struct IDKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ rawValue: Int) {
        stringValue = String(rawValue)
        intValue = rawValue
    }

    init?(stringValue: String) {
        guard let rawValue = Int(stringValue) else { return nil }
        self.init(rawValue)
    }

    init?(intValue: Int) {
        self.init(intValue)
    }
}
```
`Sources/CreatorSketch/Model/SketchPlaneSource.swift`:
```swift
import CreatorGeometry

/// Where a sketch's plane comes from (spec §3).
public enum SketchPlaneSource: Hashable, Sendable, Codable {
    /// A plane stored in the sketch itself.
    case fixed(Plane)
    /// The plane wired into the Sketch node's `plane` socket (resolved by the node in S4).
    case wired
}
```
`Sources/CreatorSketch/Model/SketchEntity.swift`:
```swift
/// One piece of sketch geometry plus its construction flag. Construction geometry is solved
/// like any other geometry but never becomes part of a region.
public struct SketchEntity: Hashable, Sendable, Codable {
    public var kind: SketchEntityKind
    public var isConstruction: Bool

    public init(_ kind: SketchEntityKind, isConstruction: Bool = false) {
        self.kind = kind
        self.isConstruction = isConstruction
    }
}
```
`Sources/CreatorSketch/Model/SketchEntityKind.swift`:
```swift
import CreatorGeometry

/// The geometry of a sketch entity (spec §3). Lines and arcs reference shared point entities,
/// so coincidence at a shared endpoint is structural.
public enum SketchEntityKind: Hashable, Sendable, Codable {
    /// A point; the vector is its drawn position. Unknowns: x, y.
    case point(Vector2)
    /// A line between two point entities. No unknowns of its own.
    case line(start: SketchEntityID, end: SketchEntityID)
    /// A counter-clockwise arc around `center` from `start` to `end`, all point entities.
    /// The solver adds the implicit constraint |end − center| = |start − center|.
    case arc(center: SketchEntityID, start: SketchEntityID, end: SketchEntityID)
    /// A full circle around a point entity. Unknown: the radius (this value is the drawn radius).
    case circle(center: SketchEntityID, radius: Double)
    /// A model edge projected onto the sketch plane. Fixed: it has no unknowns.
    case projected(ProjectionSource)
}
```
`Sources/CreatorSketch/Model/SketchEntityKind+Points.swift`:
```swift
extension SketchEntityKind {
    /// The point entities this entity is built on, in declaration order.
    public var referencedPoints: [SketchEntityID] {
        switch self {
        case .point, .projected: []
        case .line(let start, let end): [start, end]
        case .arc(let center, let start, let end): [center, start, end]
        case .circle(let center, _): [center]
        }
    }

    var isPoint: Bool {
        if case .point = self { return true }
        return false
    }
}
```
`Sources/CreatorSketch/Model/ProjectionSource.swift`:
```swift
/// A projected model edge (spec §3). The edge pick itself (an M3 `EdgePick`) lives in the Sketch
/// node's settings under `reference`, because `CreatorSketch` may not import `CreatorKernel`;
/// the node resolves the pick and refreshes `curve` before solving (S4).
public struct ProjectionSource: Hashable, Sendable, Codable {
    /// The key under which the Sketch node stores this projection's edge pick.
    public var reference: String
    /// The 2D geometry from the last successful resolve, in plane coordinates.
    public var curve: ProjectedCurve
    /// True when the last resolve matched no edge or several. The solver then skips every
    /// constraint on this entity (suspended, not deleted) and regions ignore it.
    public var isSuspended: Bool

    public init(reference: String, curve: ProjectedCurve, isSuspended: Bool = false) {
        self.reference = reference
        self.curve = curve
        self.isSuspended = isSuspended
    }
}
```
`Sources/CreatorSketch/Model/ProjectedCurve.swift`:
```swift
import CreatorGeometry

/// The cached plane-coordinate geometry of a projected model edge.
public enum ProjectedCurve: Hashable, Sendable, Codable {
    case line(Vector2, Vector2)
    /// A counter-clockwise arc from `start` to `end` (`end > start`).
    case arc(center: Vector2, radius: Double, start: Angle, end: Angle)
    case circle(center: Vector2, radius: Double)
}
```
`Sources/CreatorSketch/Model/SketchConstraint.swift`:
```swift
import CreatorGeometry

/// A geometric constraint (spec §3). Lines are treated as infinite and arcs as full circles
/// wherever a constraint refers to "the line" or "the circle", so trimming a curve never
/// changes what its constraints mean.
public enum SketchConstraint: Hashable, Sendable, Codable {
    /// Two point entities at the same place.
    case coincident(SketchEntityID, SketchEntityID)
    /// A point on a line, arc, circle or projected edge.
    case pointOn(point: SketchEntityID, curve: SketchEntityID)
    /// A line (or projected line) parallel to the x axis.
    case horizontal(SketchEntityID)
    /// A line (or projected line) parallel to the y axis.
    case vertical(SketchEntityID)
    /// Two points at the same y.
    case horizontalPoints(SketchEntityID, SketchEntityID)
    /// Two points at the same x.
    case verticalPoints(SketchEntityID, SketchEntityID)
    case parallel(SketchEntityID, SketchEntityID)
    case perpendicular(SketchEntityID, SketchEntityID)
    /// Line–arc/circle or arc/circle–arc/circle. When the two curves share an endpoint the
    /// tangency is at that point; otherwise it is wherever the curves touch.
    case tangent(SketchEntityID, SketchEntityID)
    /// Equal lengths (two lines) or equal radii (two arcs/circles).
    case equal(SketchEntityID, SketchEntityID)
    /// A point at the midpoint of a line.
    case midpoint(point: SketchEntityID, line: SketchEntityID)
    /// Two arcs/circles sharing a centre.
    case concentric(SketchEntityID, SketchEntityID)
    /// Two points mirrored about a line.
    case symmetric(SketchEntityID, SketchEntityID, about: SketchEntityID)
    /// A point held at `at`.
    case fix(SketchEntityID, at: Vector2)

    /// Every entity this constraint refers to, in declaration order.
    public var entities: [SketchEntityID] {
        switch self {
        case .coincident(let a, let b), .horizontalPoints(let a, let b), .verticalPoints(let a, let b),
             .parallel(let a, let b), .perpendicular(let a, let b), .tangent(let a, let b),
             .equal(let a, let b), .concentric(let a, let b):
            [a, b]
        case .pointOn(let point, let curve): [point, curve]
        case .midpoint(let point, let line): [point, line]
        case .horizontal(let a), .vertical(let a), .fix(let a, _): [a]
        case .symmetric(let a, let b, let line): [a, b, line]
        }
    }
}
```
`Sources/CreatorSketch/Model/DimensionKind.swift`:
```swift
/// What a dimension measures (spec §3).
public enum DimensionKind: Hashable, Sendable, Codable {
    /// Point–point, or point–line (the line taken as infinite), in either order.
    case distance(SketchEntityID, SketchEntityID)
    /// The length of a line.
    case length(SketchEntityID)
    case radius(SketchEntityID)
    case diameter(SketchEntityID)
    /// The angle between two lines, 0–180 degrees.
    case angle(SketchEntityID, SketchEntityID)

    public var entities: [SketchEntityID] {
        switch self {
        case .distance(let a, let b), .angle(let a, let b): [a, b]
        case .length(let a), .radius(let a), .diameter(let a): [a]
        }
    }
}
```
`Sources/CreatorSketch/Model/SketchDimension.swift`:
```swift
/// A named dimension (spec §3).
public struct SketchDimension: Hashable, Sendable, Codable {
    public var kind: DimensionKind
    /// `d1`, `d2`, … by default; unique within the sketch.
    public var name: String
    /// Millimetres, or degrees for `.angle`.
    public var value: Double
    /// When true the Sketch node shows an input socket named `name` (S4).
    public var isExposed: Bool
    /// When false the dimension only measures (a reference dimension) and adds no residual.
    public var isDriving: Bool

    public init(kind: DimensionKind, name: String, value: Double, isExposed: Bool = false, isDriving: Bool = true) {
        self.kind = kind
        self.name = name
        self.value = value
        self.isExposed = isExposed
        self.isDriving = isDriving
    }
}
```
`Sources/CreatorSketch/Model/SolvedState.swift`:
```swift
import CreatorGeometry

/// The warm-start value of one entity's unknowns from the last good solve.
public enum SolvedState: Hashable, Sendable, Codable {
    case point(Vector2)
    case radius(Double)
}
```
`Sources/CreatorSketch/Model/SketchConstraintRef.swift`:
```swift
/// A constraint or a dimension: anything that adds residuals to the solve. Conflict lists hold
/// these because the spec's own example names a dimension ("Angle d4") as a conflict.
/// Constraints sort before dimensions, then by ID.
public enum SketchConstraintRef: Hashable, Sendable, Comparable, Codable {
    case constraint(SketchConstraintID)
    case dimension(DimensionID)

    public static func < (lhs: SketchConstraintRef, rhs: SketchConstraintRef) -> Bool {
        switch (lhs, rhs) {
        case (.constraint(let a), .constraint(let b)): a < b
        case (.dimension(let a), .dimension(let b)): a < b
        case (.constraint, .dimension): true
        case (.dimension, .constraint): false
        }
    }
}
```
`Sources/CreatorSketch/Model/Sketch.swift`:
```swift
import CreatorGeometry

/// A 2D constraint sketch on a plane (spec §3): entities, constraints, named dimensions and the
/// warm-start positions from the last good solve. A plain value: every edit makes a new sketch.
public struct Sketch: Hashable, Sendable, Codable {
    public var plane: SketchPlaneSource
    public var entities: [SketchEntityID: SketchEntity]
    public var constraints: [SketchConstraintID: SketchConstraint]
    public var dimensions: [DimensionID: SketchDimension]
    /// Warm-start values from the last good solve. Entities without an entry use their drawn values.
    public var solved: [SketchEntityID: SolvedState]
    /// The raw value of the next ID handed out. Entity, constraint and dimension IDs share this
    /// counter, so no two IDs in a sketch have the same raw value and none is ever reused.
    public var nextID: Int

    public init(plane: SketchPlaneSource = .fixed(.xy)) {
        self.plane = plane
        entities = [:]
        constraints = [:]
        dimensions = [:]
        solved = [:]
        nextID = 1
    }

    /// Entity IDs in ascending order, the sketch's fixed iteration order.
    public var entityIDs: [SketchEntityID] { entities.keys.sorted() }
    public var constraintIDs: [SketchConstraintID] { constraints.keys.sorted() }
    public var dimensionIDs: [DimensionID] { dimensions.keys.sorted() }
}
```
`Sources/CreatorSketch/Model/Sketch+Editing.swift`:
```swift
import CreatorGeometry
import Foundation

extension Sketch {
    /// Reserves the next raw ID value.
    mutating func takeNextID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Adds an entity and returns its ID.
    @discardableResult
    public mutating func add(_ entity: SketchEntity) -> SketchEntityID {
        let id = SketchEntityID(takeNextID())
        entities[id] = entity
        return id
    }

    @discardableResult
    public mutating func addPoint(_ position: Vector2, isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.point(position), isConstruction: isConstruction))
    }

    /// Adds a line between two existing points.
    @discardableResult
    public mutating func addLine(from start: SketchEntityID, to end: SketchEntityID, isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.line(start: start, end: end), isConstruction: isConstruction))
    }

    /// Adds two new points and the line between them.
    @discardableResult
    public mutating func addLine(_ start: Vector2, _ end: Vector2, isConstruction: Bool = false) -> SketchEntityID {
        let a = addPoint(start)
        let b = addPoint(end)
        return addLine(from: a, to: b, isConstruction: isConstruction)
    }

    /// Adds a counter-clockwise arc through existing points.
    @discardableResult
    public mutating func addArc(center: SketchEntityID, start: SketchEntityID, end: SketchEntityID,
                                isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.arc(center: center, start: start, end: end), isConstruction: isConstruction))
    }

    /// Adds a circle around an existing centre point.
    @discardableResult
    public mutating func addCircle(center: SketchEntityID, radius: Double, isConstruction: Bool = false) -> SketchEntityID {
        add(SketchEntity(.circle(center: center, radius: radius), isConstruction: isConstruction))
    }

    /// Adds a centre point and a circle around it.
    @discardableResult
    public mutating func addCircle(center: Vector2, radius: Double, isConstruction: Bool = false) -> SketchEntityID {
        addCircle(center: addPoint(center), radius: radius, isConstruction: isConstruction)
    }

    @discardableResult
    public mutating func add(_ constraint: SketchConstraint) -> SketchConstraintID {
        let id = SketchConstraintID(takeNextID())
        constraints[id] = constraint
        return id
    }

    /// Adds a dimension named with the first free `d1`, `d2`, … name.
    @discardableResult
    public mutating func addDimension(_ kind: DimensionKind, value: Double, isDriving: Bool = true) -> DimensionID {
        let id = DimensionID(takeNextID())
        dimensions[id] = SketchDimension(kind: kind, name: nextDimensionName(), value: value, isDriving: isDriving)
        return id
    }

    /// The first name `dN` (N = 1, 2, …) that no dimension uses.
    public func nextDimensionName() -> String {
        let used = Set(dimensions.values.map(\.name))
        var number = 1
        while used.contains("d\(number)") { number += 1 }
        return "d\(number)"
    }

    /// Renames a dimension. Returns false, changing nothing, when `name` is empty after trimming
    /// spaces or another dimension already uses it.
    @discardableResult
    public mutating func renameDimension(_ id: DimensionID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, dimensions[id] != nil,
              !dimensions.contains(where: { $0.key != id && $0.value.name == trimmed }) else { return false }
        dimensions[id]?.name = trimmed
        return true
    }

    /// Removes an entity, every entity built on it (a line loses a point → the line goes), and
    /// every constraint, dimension and warm-start value that refers to anything removed.
    public mutating func removeEntity(_ id: SketchEntityID) {
        var doomed: Set<SketchEntityID> = [id]
        var changed = true
        while changed {
            changed = false
            for (other, entity) in entities where !doomed.contains(other) && !doomed.isDisjoint(with: entity.kind.referencedPoints) {
                doomed.insert(other)
                changed = true
            }
        }
        for entity in doomed {
            entities[entity] = nil
            solved[entity] = nil
        }
        constraints = constraints.filter { doomed.isDisjoint(with: $0.value.entities) }
        dimensions = dimensions.filter { doomed.isDisjoint(with: $0.value.kind.entities) }
    }

    /// Removes point entities that no curve uses and no constraint or dimension mentions.
    public mutating func removeOrphanPoints(_ candidates: [SketchEntityID]) {
        for point in candidates where isOrphan(point) {
            removeEntity(point)
        }
    }

    func isOrphan(_ point: SketchEntityID) -> Bool {
        guard case .point = entities[point]?.kind else { return false }
        if entities.values.contains(where: { $0.kind.referencedPoints.contains(point) }) { return false }
        if constraints.values.contains(where: { $0.entities.contains(point) }) { return false }
        return !dimensions.values.contains(where: { $0.kind.entities.contains(point) })
    }

    /// The point's current position: the last solve's value, or the drawn one.
    public func position(of point: SketchEntityID) -> Vector2? {
        if case .point(let solvedPosition) = solved[point] { return solvedPosition }
        if case .point(let drawn) = entities[point]?.kind { return drawn }
        return nil
    }

    /// The circle's current radius: the last solve's value, or the drawn one.
    public func radius(of circle: SketchEntityID) -> Double? {
        if case .radius(let solvedRadius) = solved[circle] { return solvedRadius }
        if case .circle(_, let drawn) = entities[circle]?.kind { return drawn }
        return nil
    }

    /// Moves a point: sets its drawn position and its warm start.
    public mutating func move(_ point: SketchEntityID, to position: Vector2) {
        guard case .point = entities[point]?.kind else { return }
        entities[point]?.kind = .point(position)
        solved[point] = .point(position)
    }

    /// Every constraint and driving or reference dimension, constraints first, each by ID.
    public var constraintRefs: [SketchConstraintRef] {
        constraintIDs.map(SketchConstraintRef.constraint) + dimensionIDs.map(SketchConstraintRef.dimension)
    }
}
```
`Sources/CreatorSketch/Model/Sketch+Labels.swift`:
```swift
extension Sketch {
    /// A plain-language name such as "Line 3": the kind, then the entity's 1-based position among
    /// entities of that kind in ID order. Construction geometry is counted with its kind.
    public func label(of id: SketchEntityID) -> String {
        guard let entity = entities[id] else { return "a deleted entity" }
        let kindName = Self.kindName(entity.kind)
        let sameKind = entityIDs.filter { other in entities[other].map { Self.kindName($0.kind) == kindName } ?? false }
        let ordinal = (sameKind.firstIndex(of: id) ?? 0) + 1
        return "\(kindName) \(ordinal)"
    }

    /// "Horizontal on Line 3", "Tangent on Line 1 and Arc 2", "Angle d4 (30°)".
    public func label(of ref: SketchConstraintRef) -> String {
        switch ref {
        case .constraint(let id):
            guard let constraint = constraints[id] else { return "a deleted constraint" }
            return label(of: constraint)
        case .dimension(let id):
            guard let dimension = dimensions[id] else { return "a deleted dimension" }
            return label(of: dimension)
        }
    }

    func label(of constraint: SketchConstraint) -> String {
        let names = constraint.entities.map { label(of: $0) }
        let title = switch constraint {
        case .coincident: "Coincident"
        case .pointOn: "Point on"
        case .horizontal, .horizontalPoints: "Horizontal"
        case .vertical, .verticalPoints: "Vertical"
        case .parallel: "Parallel"
        case .perpendicular: "Perpendicular"
        case .tangent: "Tangent"
        case .equal: "Equal"
        case .midpoint: "Midpoint"
        case .concentric: "Concentric"
        case .symmetric: "Symmetric"
        case .fix: "Fix"
        }
        if case .symmetric = constraint, names.count == 3 {
            return "\(title) on \(names[0]) and \(names[1]) about \(names[2])"
        }
        return "\(title) on \(Self.joined(names))"
    }

    /// "Angle d4 (30°)".
    func label(of dimension: SketchDimension) -> String {
        let unit = if case .angle = dimension.kind { "°" } else { " mm" }
        return "\(title(of: dimension)) (\(dimension.value.sketchDisplay)\(unit))"
    }

    /// "Angle d4": the kind and the name, without the value.
    func title(of dimension: SketchDimension) -> String {
        let kind = switch dimension.kind {
        case .distance: "Distance"
        case .length: "Length"
        case .radius: "Radius"
        case .diameter: "Diameter"
        case .angle: "Angle"
        }
        return "\(kind) \(dimension.name)"
    }

    /// "A conflicts with B." / "A conflicts with B and C." for a minimal conflict set.
    public func conflictMessage(_ refs: [SketchConstraintRef]) -> String {
        let names = refs.map { label(of: $0) }
        guard let first = names.first else { return "" }
        guard names.count > 1 else { return "\(first) can't be met." }
        return "\(first) conflicts with \(Self.joined(Array(names.dropFirst())))."
    }

    static func kindName(_ kind: SketchEntityKind) -> String {
        switch kind {
        case .point: "Point"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .projected: "Projected edge"
        }
    }

    /// "A", "A and B", "A, B and C".
    static func joined(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
```
`Sources/CreatorSketch/Model/Double+SketchDisplay.swift`:
```swift
import Foundation

extension Double {
    /// Up to three decimals, the same on every machine ("30", "12.5"), for plain-language messages.
    var sketchDisplay: String {
        formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.ModelTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 8 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md Package.swift Sources/CreatorSketch/Model/DimensionID.swift Sources/CreatorSketch/Model/DimensionKind.swift Sources/CreatorSketch/Model/Double+SketchDisplay.swift Sources/CreatorSketch/Model/IDKey.swift Sources/CreatorSketch/Model/ProjectedCurve.swift Sources/CreatorSketch/Model/ProjectionSource.swift Sources/CreatorSketch/Model/Sketch+Editing.swift Sources/CreatorSketch/Model/Sketch+Labels.swift Sources/CreatorSketch/Model/Sketch.swift Sources/CreatorSketch/Model/SketchConstraint.swift Sources/CreatorSketch/Model/SketchConstraintID.swift Sources/CreatorSketch/Model/SketchConstraintRef.swift Sources/CreatorSketch/Model/SketchDimension.swift Sources/CreatorSketch/Model/SketchEntity.swift Sources/CreatorSketch/Model/SketchEntityID.swift Sources/CreatorSketch/Model/SketchEntityKind+Points.swift Sources/CreatorSketch/Model/SketchEntityKind.swift Sources/CreatorSketch/Model/SketchPlaneSource.swift Sources/CreatorSketch/Model/SolvedState.swift Tests/CreatorSketchTests/ModelTests.swift Tests/CreatorSketchTests/Support/SketchTestSupport.swift
git commit -m "feat(sketch): add CreatorSketch and the sketch model"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 2: Dense linear algebra: least squares and rank-revealing QR
**Files:**
- Create: `Sources/CreatorSketch/Solver/DenseMatrix.swift`, `Sources/CreatorSketch/Solver/HouseholderQR.swift`, `Sources/CreatorSketch/Solver/RankRevealingQR.swift`, `Tests/CreatorSketchTests/LinearAlgebraTests.swift`
- Test: `Tests/CreatorSketchTests/LinearAlgebraTests.swift`

**Interfaces:**
- Produces (internal):
  - `struct DenseMatrix { rows, columns, storage; init(rows:columns:); init(_ rowValues: [[Double]], columns:); subscript(row, column); transposed; selectingRows(_:) }`
  - `enum HouseholderQR { static func leastSquares(_ a: DenseMatrix, _ b: [Double]) -> [Double]? }`, which returns nil on a zero pivot
  - `struct RankRevealingQR { static let relativeTolerance = 1e-8; rank: Int; rangeBasis: DenseMatrix (rows × rank, orthonormal); init(_:); outsideSquaredNorm(ofUnitVector:) -> Double }`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/LinearAlgebraTests.swift`:
```swift
import Testing
@testable import CreatorSketch

struct LinearAlgebraTests {
    @Test func leastSquaresSolvesASquareSystemExactly() throws {
        let a = DenseMatrix([[2, 1], [1, 3]], columns: 2)
        let x = try #require(HouseholderQR.leastSquares(a, [3, 5]))
        #expect(isClose(x[0], 0.8, tolerance: 1e-12))
        #expect(isClose(x[1], 1.4, tolerance: 1e-12))
    }

    @Test func leastSquaresFitsAnOverdeterminedSystem() throws {
        // Fit y = c to 1, 2, 3, 6: the mean, 3.
        let a = DenseMatrix([[1], [1], [1], [1]], columns: 1)
        let x = try #require(HouseholderQR.leastSquares(a, [1, 2, 3, 6]))
        #expect(isClose(x[0], 3, tolerance: 1e-12))
    }

    @Test func leastSquaresRejectsARankDeficientMatrix() {
        #expect(HouseholderQR.leastSquares(DenseMatrix([[1, 2], [2, 4]], columns: 2), [1, 2]) == nil)
    }

    @Test func rankCountsIndependentRows() {
        #expect(RankRevealingQR(DenseMatrix([[1, 0, 0], [0, 1, 0], [1, 1, 0]], columns: 3)).rank == 2)
        #expect(RankRevealingQR(DenseMatrix([[1, 2], [3, 4]], columns: 2)).rank == 2)
        #expect(RankRevealingQR(DenseMatrix([[0, 0], [0, 0]], columns: 2)).rank == 0)
        #expect(RankRevealingQR(DenseMatrix(rows: 3, columns: 0)).rank == 0)
    }

    @Test func rangeBasisIsOrthonormalAndSpansTheColumns() {
        // Columns (1,1,0) and (2,2,0) span the line through (1,1,0).
        let qr = RankRevealingQR(DenseMatrix([[1, 2], [1, 2], [0, 0]], columns: 2))
        #expect(qr.rank == 1)
        #expect(isClose(qr.outsideSquaredNorm(ofUnitVector: 0), 0.5, tolerance: 1e-12))
        #expect(isClose(qr.outsideSquaredNorm(ofUnitVector: 1), 0.5, tolerance: 1e-12))
        #expect(isClose(qr.outsideSquaredNorm(ofUnitVector: 2), 1, tolerance: 1e-12))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.LinearAlgebraTests`
Expected: compile errors, starting with `cannot find 'DenseMatrix' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Solver/DenseMatrix.swift`:
```swift
/// A row-major dense matrix. Sketch components have tens to a few hundred unknowns, so dense
/// storage is simpler and fast enough (spec §4: dense QR).
struct DenseMatrix: Hashable, Sendable {
    let rows: Int
    let columns: Int
    var storage: [Double]

    init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
        storage = Array(repeating: 0, count: rows * columns)
    }

    /// A matrix from row arrays, which must all have `columns` entries.
    init(_ rowValues: [[Double]], columns: Int) {
        self.init(rows: rowValues.count, columns: columns)
        for (i, row) in rowValues.enumerated() {
            for (j, value) in row.enumerated() { self[i, j] = value }
        }
    }

    subscript(row: Int, column: Int) -> Double {
        get { storage[row * columns + column] }
        set { storage[row * columns + column] = newValue }
    }

    var transposed: DenseMatrix {
        var result = DenseMatrix(rows: columns, columns: rows)
        for i in 0..<rows {
            for j in 0..<columns { result[j, i] = self[i, j] }
        }
        return result
    }

    /// The rows at `indices`, in that order.
    func selectingRows(_ indices: [Int]) -> DenseMatrix {
        var result = DenseMatrix(rows: indices.count, columns: columns)
        for (target, source) in indices.enumerated() {
            for j in 0..<columns { result[target, j] = self[source, j] }
        }
        return result
    }
}
```
`Sources/CreatorSketch/Solver/HouseholderQR.swift`:
```swift
/// Least squares by Householder QR, used for every Levenberg–Marquardt step.
enum HouseholderQR {
    /// Solves min ‖A x − b‖ for `a` with at least as many rows as columns. Returns `nil` when
    /// `a` is rank deficient (a zero pivot), which the damped LM system never is.
    static func leastSquares(_ a: DenseMatrix, _ b: [Double]) -> [Double]? {
        var r = a
        var y = b
        let (m, n) = (a.rows, a.columns)
        guard m >= n, b.count == m else { return nil }
        for k in 0..<n {
            var norm = 0.0
            for i in k..<m { norm += r[i, k] * r[i, k] }
            norm = norm.squareRoot()
            guard norm > 0 else { return nil }
            let alpha = r[k, k] > 0 ? -norm : norm
            var v = Array(repeating: 0.0, count: m - k)
            for i in k..<m { v[i - k] = r[i, k] }
            v[0] -= alpha
            var vNorm = 0.0
            for value in v { vNorm += value * value }
            if vNorm > 0 {
                for j in k..<n {
                    var s = 0.0
                    for i in k..<m { s += v[i - k] * r[i, j] }
                    let f = 2 * s / vNorm
                    for i in k..<m { r[i, j] -= f * v[i - k] }
                }
                var s = 0.0
                for i in k..<m { s += v[i - k] * y[i] }
                let f = 2 * s / vNorm
                for i in k..<m { y[i] -= f * v[i - k] }
            }
        }
        var x = Array(repeating: 0.0, count: n)
        for k in stride(from: n - 1, through: 0, by: -1) {
            var s = y[k]
            for j in (k + 1)..<n { s -= r[k, j] * x[j] }
            guard r[k, k] != 0 else { return nil }
            x[k] = s / r[k, k]
        }
        return x
    }
}
```
`Sources/CreatorSketch/Solver/RankRevealingQR.swift`:
```swift
/// Householder QR with column pivoting (spec §4: rank-revealing QR). Gives the numerical rank and
/// an orthonormal basis of the column space.
struct RankRevealingQR {
    /// Pivots whose remaining column norm is at or below this fraction of max(1, the first
    /// pivot's norm) count as zero.
    static let relativeTolerance = 1e-8

    let rank: Int
    /// `rows × rank`: orthonormal columns spanning the matrix's column space.
    let rangeBasis: DenseMatrix

    init(_ a: DenseMatrix) {
        let (m, n) = (a.rows, a.columns)
        var r = a
        var reflectors: [(start: Int, v: [Double], vNorm: Double)] = []
        var threshold = 0.0
        var rank = 0
        for k in 0..<min(m, n) {
            // Pick the remaining column with the largest norm below row k (first wins on ties).
            var best = k
            var bestNorm = -1.0
            for j in k..<n {
                var s = 0.0
                for i in k..<m { s += r[i, j] * r[i, j] }
                if s > bestNorm {
                    bestNorm = s
                    best = j
                }
            }
            let norm = bestNorm.squareRoot()
            if k == 0 { threshold = Self.relativeTolerance * max(1, norm) }
            if norm <= threshold { break }
            if best != k {
                for i in 0..<m {
                    let t = r[i, k]
                    r[i, k] = r[i, best]
                    r[i, best] = t
                }
            }
            let alpha = r[k, k] > 0 ? -norm : norm
            var v = Array(repeating: 0.0, count: m - k)
            for i in k..<m { v[i - k] = r[i, k] }
            v[0] -= alpha
            var vNorm = 0.0
            for value in v { vNorm += value * value }
            if vNorm > 0 {
                for j in k..<n {
                    var s = 0.0
                    for i in k..<m { s += v[i - k] * r[i, j] }
                    let f = 2 * s / vNorm
                    for i in k..<m { r[i, j] -= f * v[i - k] }
                }
            }
            reflectors.append((k, v, vNorm))
            rank += 1
        }
        self.rank = rank
        // Q's first `rank` columns: apply the reflectors in reverse to the unit vectors.
        var basis = DenseMatrix(rows: m, columns: rank)
        for column in 0..<rank {
            var e = Array(repeating: 0.0, count: m)
            e[column] = 1
            for reflector in reflectors.reversed() where reflector.vNorm > 0 {
                var s = 0.0
                for i in reflector.start..<m { s += reflector.v[i - reflector.start] * e[i] }
                let f = 2 * s / reflector.vNorm
                for i in reflector.start..<m { e[i] -= f * reflector.v[i - reflector.start] }
            }
            for i in 0..<m { basis[i, column] = e[i] }
        }
        rangeBasis = basis
    }

    /// The squared length of unit vector `e_row`'s component outside the column space.
    func outsideSquaredNorm(ofUnitVector row: Int) -> Double {
        var inside = 0.0
        for k in 0..<rank { inside += rangeBasis[row, k] * rangeBasis[row, k] }
        return max(0, 1 - inside)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.LinearAlgebraTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 13 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Solver/DenseMatrix.swift Sources/CreatorSketch/Solver/HouseholderQR.swift Sources/CreatorSketch/Solver/RankRevealingQR.swift Tests/CreatorSketchTests/LinearAlgebraTests.swift
git commit -m "feat(sketch): add dense least squares and rank-revealing QR"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 3: Residuals with analytic Jacobians
**Files:**
- Create: `Sources/CreatorSketch/Geometry/SketchMath.swift`, `Sources/CreatorSketch/Solver/PointOperand.swift`, `Sources/CreatorSketch/Solver/RadiusOperand.swift`, `Sources/CreatorSketch/Solver/CircleOperand.swift`, `Sources/CreatorSketch/Solver/LineOperand.swift`, `Sources/CreatorSketch/Solver/RowBuilder.swift`, `Sources/CreatorSketch/Solver/Equation.swift`, `Sources/CreatorSketch/Solver/Equation+Rows.swift`, `Sources/CreatorSketch/Solver/Equation+Columns.swift`, `Tests/CreatorSketchTests/ResidualTests.swift`
- Test: `Tests/CreatorSketchTests/ResidualTests.swift`

**Interfaces:**
- Consumes: `RowBuilder` only from this task. `Vector2` from `CreatorGeometry`.
- Produces (internal):
  - `enum SketchMath`, static helpers: `dot`, `cross`, `perpendicular`, `normalized`, `angle`, `point(on:radius:at:)`, `wrapped`, `rotated(_:about:by:)`, `reflected(_:inLineThrough:_:)`
  - `PointOperand { .unknown(column:), .constant(Vector2); value(_ x:) }`. A point's y is at `column + 1`.
  - `RadiusOperand { .unknown(column:), .constant(Double), .through(PointOperand) }`
  - `CircleOperand { center; radius; endpoints; radiusValue(_:); addRadiusGradient(_:_:to:) }`, `LineOperand { start; end; direction(_:) }`
  - `RowBuilder { value; entries: [(column, value)]; add(column:_:); add(_ point:_ gradient:); scale(by:) }`
  - `Equation`: one case per residual kind (see the file), with `rowCount`, `rows(_ x: [Double]) -> [RowBuilder]` and `columns: [Int]`.
  - Shared rows: `static signedDistance`, `projection`, `distanceRow`, `difference`, `unitCross`, `unitDot`, `unitComponent`, `symmetricMidpointRow`, and `static let degenerateLine`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/ResidualTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Residual values at hand-checked configurations, and every analytic Jacobian against central
/// differences (the solver itself never uses finite differences).
struct ResidualTests {
    // Unknowns: p0 = (1, 2), p1 = (7, 3), p2 = (4, 8), p3 = (−2, 5), r = 2.5.
    static let x: [Double] = [1, 2, 7, 3, 4, 8, -2, 5, 2.5]
    static let p0 = PointOperand.unknown(column: 0)
    static let p1 = PointOperand.unknown(column: 2)
    static let p2 = PointOperand.unknown(column: 4)
    static let p3 = PointOperand.unknown(column: 6)
    static let lineA = LineOperand(start: p0, end: p1)
    static let lineB = LineOperand(start: p2, end: p3)
    static let circle = CircleOperand(center: p2, radius: .unknown(column: 8), endpoints: [])
    static let arc = CircleOperand(center: p0, radius: .through(p3), endpoints: [p3, p1])

    static let equations: [Equation] = [
        .coincident(p0, p1), .pointOnLine(p2, lineA), .pointOnCircle(p1, circle), .pointOnCircle(p1, arc),
        .horizontal(p0, p1), .vertical(p2, p3), .horizontalLine(lineA, scale: 3), .verticalLine(lineB, scale: 3), .parallel(lineA, lineB, scale: 7), .perpendicular(lineA, lineB, scale: 7),
        .angle(lineA, lineB, target: 0.6, scale: 7), .tangentAtPoint(p1, center: p0, lineB),
        .lineTangent(lineA, circle, side: -1), .circleTangent(circle, arc, isInternal: false, sign: 1),
        .circleTangent(circle, arc, isInternal: true, sign: -1), .equalLength(lineA, lineB), .equalRadius(circle, arc),
        .midpoint(p2, lineA), .symmetric(p2, p3, lineA), .fix(p1, Vector2(1, 1)), .distance(p0, p2, 3),
        .lineDistance(p3, lineA, 2, side: 1), .length(lineB, 4), .radius(arc, 1), .arcRadius(center: p0, start: p3, end: p1),
        .target(p2, Vector2(0, 0)), .pointOnLine(.constant(Vector2(3, 3)), LineOperand(start: p0, end: .constant(Vector2(9, 9)))),
    ]

    @Test(arguments: equations)
    func analyticJacobianMatchesCentralDifferences(_ equation: Equation) {
        let rows = equation.rows(Self.x)
        #expect(rows.count == equation.rowCount)
        let h = 1e-6
        for (index, row) in rows.enumerated() {
            var analytic = Array(repeating: 0.0, count: Self.x.count)
            for entry in row.entries { analytic[entry.column] += entry.value }
            for column in Self.x.indices {
                var plus = Self.x
                var minus = Self.x
                plus[column] += h
                minus[column] -= h
                let numeric = (equation.rows(plus)[index].value - equation.rows(minus)[index].value) / (2 * h)
                #expect(isClose(analytic[column], numeric, tolerance: 1e-6), "row \(index), column \(column)")
            }
        }
    }

    @Test func residualValuesMatchHandCalculations() {
        let x = Self.x
        // p2 = (4, 8) from the line (1,2)→(7,3): cross((6,1), (3,6)) / √37 = 33 / √37.
        #expect(isClose(Equation.pointOnLine(Self.p2, Self.lineA).rows(x)[0].value, 33 / 37.0.squareRoot(), tolerance: 1e-12))
        // |p1 − p2| − r = |(3, −5)| − 2.5.
        #expect(isClose(Equation.pointOnCircle(Self.p1, Self.circle).rows(x)[0].value, 34.0.squareRoot() - 2.5, tolerance: 1e-12))
        // Arc radius through p3 around p0: |(−3, 3)| = 3√2.
        #expect(isClose(Equation.radius(Self.arc, 1).rows(x)[0].value, 3 * 2.0.squareRoot() - 1, tolerance: 1e-12))
        #expect(Equation.horizontal(Self.p0, Self.p1).rows(x)[0].value == -1)
        #expect(Equation.vertical(Self.p2, Self.p3).rows(x)[0].value == 6)
        #expect(Equation.midpoint(Self.p2, Self.lineA).rows(x).map(\.value) == [0, 5.5])
        #expect(Equation.fix(Self.p1, Vector2(1, 1)).rows(x).map(\.value) == [6, 2])
    }

    @Test func parallelAndPerpendicularResidualsAreScaledSineAndCosine() {
        let x: [Double] = [0, 0, 10, 0, 0, 5, 10, 15]
        let first = LineOperand(start: .unknown(column: 0), end: .unknown(column: 2))
        let second = LineOperand(start: .unknown(column: 4), end: .unknown(column: 6))
        // The second line is at 45°.
        #expect(isClose(Equation.parallel(first, second, scale: 10).rows(x)[0].value, 10 * 0.5.squareRoot(), tolerance: 1e-12))
        #expect(isClose(Equation.perpendicular(first, second, scale: 10).rows(x)[0].value, 10 * 0.5.squareRoot(), tolerance: 1e-12))
        #expect(isClose(Equation.angle(first, second, target: .pi / 4, scale: 10).rows(x)[0].value, 0, tolerance: 1e-12))
        #expect(isClose(Equation.horizontalLine(second, scale: 10).rows(x)[0].value, 10 * 0.5.squareRoot(), tolerance: 1e-12))
        #expect(isClose(Equation.verticalLine(first, scale: 10).rows(x)[0].value, 10, tolerance: 1e-12))
    }

    @Test func zeroLengthLinesNeverLookSatisfied() {
        let x: [Double] = [3, 3, 3, 3, 0, 0, 10, 0]
        let collapsed = LineOperand(start: .unknown(column: 0), end: .unknown(column: 2))
        let other = LineOperand(start: .unknown(column: 4), end: .unknown(column: 6))
        #expect(Equation.horizontalLine(collapsed, scale: 5).rows(x)[0].value == 5)
        #expect(Equation.parallel(collapsed, other, scale: 5).rows(x)[0].value == 5)
        // A point's distance to a collapsed line is its distance to the point the line became.
        #expect(Equation.pointOnLine(.unknown(column: 4), collapsed).rows(x)[0].value == 18.0.squareRoot())
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.ResidualTests`
Expected: compile errors, starting with `cannot find type 'Equation' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Geometry/SketchMath.swift`:
```swift
import CreatorGeometry
import Foundation

/// Small 2D helpers. Kept as statics, not `Vector2` extensions, so they can never clash with
/// members CreatorGeometry adds later.
enum SketchMath {
    static func dot(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.x + a.y * b.y }

    /// The z component of the 3D cross product: positive when `b` is counter-clockwise of `a`.
    static func cross(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.y - a.y * b.x }

    /// `v` rotated a quarter turn counter-clockwise.
    static func perpendicular(_ v: Vector2) -> Vector2 { Vector2(-v.y, v.x) }

    static func normalized(_ v: Vector2) -> Vector2? {
        let length = v.length
        return length > 1e-12 ? v * (1 / length) : nil
    }

    /// The polar angle of `v` in (−π, π].
    static func angle(_ v: Vector2) -> Double { atan2(v.y, v.x) }

    /// The point at polar angle `angle` on the circle around `center`.
    static func point(on center: Vector2, radius: Double, at angle: Double) -> Vector2 {
        center + Vector2(cos(angle), sin(angle)) * radius
    }

    /// `angle` wrapped into [0, 2π).
    static func wrapped(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: turn)
        let positive = value < 0 ? value + turn : value
        return positive >= turn ? 0 : positive
    }

    /// `p` rotated by `angle` about `center`.
    static func rotated(_ p: Vector2, about center: Vector2, by angle: Double) -> Vector2 {
        let offset = p - center
        let (c, s) = (cos(angle), sin(angle))
        return center + Vector2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)
    }

    /// `p` reflected in the infinite line through `a` and `b`. Returns `p` for a degenerate line.
    static func reflected(_ p: Vector2, inLineThrough a: Vector2, _ b: Vector2) -> Vector2 {
        guard let direction = normalized(b - a) else { return p }
        let offset = p - a
        let along = direction * dot(offset, direction)
        return a + along * 2 - offset
    }
}
```
`Sources/CreatorSketch/Solver/PointOperand.swift`:
```swift
import CreatorGeometry

/// A point inside an equation: two unknown columns (x at `column`, y at `column + 1`) or a constant.
enum PointOperand: Hashable, Sendable {
    case unknown(column: Int)
    case constant(Vector2)

    func value(_ x: [Double]) -> Vector2 {
        switch self {
        case .unknown(let column): Vector2(x[column], x[column + 1])
        case .constant(let point): point
        }
    }
}
```
`Sources/CreatorSketch/Solver/RadiusOperand.swift`:
```swift
/// A radius inside an equation.
enum RadiusOperand: Hashable, Sendable {
    /// A circle's radius unknown.
    case unknown(column: Int)
    case constant(Double)
    /// An arc's radius: the distance from its centre to this point (its start point).
    case through(PointOperand)
}
```
`Sources/CreatorSketch/Solver/CircleOperand.swift`:
```swift
import CreatorGeometry

/// An arc or circle inside an equation (arcs count as their full circle).
struct CircleOperand: Hashable, Sendable {
    var center: PointOperand
    var radius: RadiusOperand
    /// The arc's start and end points, `nil` for circles and projected curves. Used to detect
    /// tangency at a shared endpoint.
    var endpoints: [PointOperand]

    func radiusValue(_ x: [Double]) -> Double {
        switch radius {
        case .unknown(let column): x[column]
        case .constant(let value): value
        case .through(let point): (point.value(x) - center.value(x)).length
        }
    }

    /// Adds `scale · ∂radius/∂x` to `row`.
    func addRadiusGradient(_ scale: Double, _ x: [Double], to row: inout RowBuilder) {
        switch radius {
        case .unknown(let column): row.add(column: column, scale)
        case .constant: break
        case .through(let point):
            let offset = point.value(x) - center.value(x)
            let length = offset.length
            guard length > 0 else { return }
            let unit = offset * (scale / length)
            row.add(point, unit)
            row.add(center, unit * -1)
        }
    }
}
```
`Sources/CreatorSketch/Solver/LineOperand.swift`:
```swift
import CreatorGeometry

/// A line inside an equation: its two endpoints (the line is taken as infinite).
struct LineOperand: Hashable, Sendable {
    var start: PointOperand
    var end: PointOperand

    func direction(_ x: [Double]) -> Vector2 { end.value(x) - start.value(x) }
}
```
`Sources/CreatorSketch/Solver/RowBuilder.swift`:
```swift
import CreatorGeometry

/// One residual row: its value and its sparse analytic gradient, in a fixed insertion order
/// (so assembling the dense Jacobian is deterministic).
struct RowBuilder: Sendable {
    var value: Double = 0
    var entries: [(column: Int, value: Double)] = []

    mutating func add(column: Int, _ derivative: Double) {
        entries.append((column, derivative))
    }

    /// Adds a gradient with respect to a point; constants contribute nothing.
    mutating func add(_ point: PointOperand, _ gradient: Vector2) {
        guard case .unknown(let column) = point else { return }
        entries.append((column, gradient.x))
        entries.append((column + 1, gradient.y))
    }

    /// Multiplies the value and every derivative by `factor`.
    mutating func scale(by factor: Double) {
        value *= factor
        for index in entries.indices { entries[index].value *= factor }
    }
}
```
`Sources/CreatorSketch/Solver/Equation.swift`:
```swift
import CreatorGeometry

/// One constraint, dimension, implicit condition or drag target, with its operands resolved to
/// unknown columns or constants. Every residual is in millimetres; angle-type residuals are
/// multiplied by the component's length scale so they weigh like millimetres (spec §4).
enum Equation: Hashable, Sendable {
    /// p − q (2 rows).
    case coincident(PointOperand, PointOperand)
    /// Signed distance from p to the infinite line.
    case pointOnLine(PointOperand, LineOperand)
    /// |p − c| − r.
    case pointOnCircle(PointOperand, CircleOperand)
    /// a.y − b.y, for two points.
    case horizontal(PointOperand, PointOperand)
    /// a.x − b.x, for two points.
    case vertical(PointOperand, PointOperand)
    /// scale · d.y / |d|: the sine of the line's angle to the x axis. Angle-based, not a.y − b.y,
    /// so a line can't meet it (and a conflicting angle) by shrinking to nothing.
    case horizontalLine(LineOperand, scale: Double)
    /// scale · d.x / |d|.
    case verticalLine(LineOperand, scale: Double)
    /// scale · sin of the angle between the lines.
    case parallel(LineOperand, LineOperand, scale: Double)
    /// scale · cos of the angle between the lines.
    case perpendicular(LineOperand, LineOperand, scale: Double)
    /// scale · sin(φ − target), φ the signed angle from the first line to the second.
    case angle(LineOperand, LineOperand, target: Double, scale: Double)
    /// Tangency at a shared endpoint p: (p − centre) · direction / |direction| (radius ⟂ line).
    case tangentAtPoint(PointOperand, center: PointOperand, LineOperand)
    /// side · distance(centre, line) − r, for a circle touching a line anywhere.
    case lineTangent(LineOperand, CircleOperand, side: Double)
    /// External: |c₁ − c₂| − (r₁ + r₂). Internal: |c₁ − c₂| − sign · (r₁ − r₂).
    case circleTangent(CircleOperand, CircleOperand, isInternal: Bool, sign: Double)
    /// |d₁| − |d₂|.
    case equalLength(LineOperand, LineOperand)
    /// r₁ − r₂.
    case equalRadius(CircleOperand, CircleOperand)
    /// p − (a + b) / 2 (2 rows).
    case midpoint(PointOperand, LineOperand)
    /// The midpoint of p, q on the line, and q − p along the line is zero (2 rows).
    case symmetric(PointOperand, PointOperand, LineOperand)
    /// p − target (2 rows).
    case fix(PointOperand, Vector2)
    /// |p − q| − d.
    case distance(PointOperand, PointOperand, Double)
    /// side · distance(p, line) − d.
    case lineDistance(PointOperand, LineOperand, Double, side: Double)
    /// |b − a| − L.
    case length(LineOperand, Double)
    /// r − value.
    case radius(CircleOperand, Double)
    /// The implicit arc condition |end − centre| − |start − centre|.
    case arcRadius(center: PointOperand, start: PointOperand, end: PointOperand)
    /// A drag target: p − target (2 rows), used only in drag mode's first phase.
    case target(PointOperand, Vector2)

    var rowCount: Int {
        switch self {
        case .coincident, .midpoint, .symmetric, .fix, .target: 2
        default: 1
        }
    }
}
```
`Sources/CreatorSketch/Solver/Equation+Rows.swift`:
```swift
import CreatorGeometry
import Foundation

extension Equation {
    /// The residual rows at `x`, each with its analytic gradient.
    func rows(_ x: [Double]) -> [RowBuilder] {
        switch self {
        case .coincident(let p, let q):
            return Self.difference(p, q, x)
        case .pointOnLine(let p, let line):
            return [Self.signedDistance(p, line, x)]
        case .pointOnCircle(let p, let circle):
            var row = Self.distanceRow(p, circle.center, x)
            row.value -= circle.radiusValue(x)
            circle.addRadiusGradient(-1, x, to: &row)
            return [row]
        case .horizontal(let a, let b):
            var row = RowBuilder(value: a.value(x).y - b.value(x).y)
            row.add(a, Vector2(0, 1))
            row.add(b, Vector2(0, -1))
            return [row]
        case .vertical(let a, let b):
            var row = RowBuilder(value: a.value(x).x - b.value(x).x)
            row.add(a, Vector2(1, 0))
            row.add(b, Vector2(-1, 0))
            return [row]
        case .horizontalLine(let line, let scale):
            var row = Self.unitComponent(line, vertical: false, x)
            row.scale(by: scale)
            return [row]
        case .verticalLine(let line, let scale):
            var row = Self.unitComponent(line, vertical: true, x)
            row.scale(by: scale)
            return [row]
        case .parallel(let first, let second, let scale):
            var row = Self.unitCross(first, second, x)
            row.scale(by: scale)
            return [row]
        case .perpendicular(let first, let second, let scale):
            var row = Self.unitDot(first, second, x)
            row.scale(by: scale)
            return [row]
        case .angle(let first, let second, let target, let scale):
            let crossRow = Self.unitCross(first, second, x)
            let dotRow = Self.unitDot(first, second, x)
            let (c, s) = (cos(target), sin(target))
            var row = RowBuilder(value: crossRow.value * c - dotRow.value * s)
            for entry in crossRow.entries { row.add(column: entry.column, entry.value * c) }
            for entry in dotRow.entries { row.add(column: entry.column, -entry.value * s) }
            row.scale(by: scale)
            return [row]
        case .tangentAtPoint(let p, let center, let line):
            return [Self.projection(from: center, to: p, along: line, x)]
        case .lineTangent(let line, let circle, let side):
            var row = Self.signedDistance(circle.center, line, x)
            row.scale(by: side)
            row.value -= circle.radiusValue(x)
            circle.addRadiusGradient(-1, x, to: &row)
            return [row]
        case .circleTangent(let first, let second, let isInternal, let sign):
            var row = Self.distanceRow(first.center, second.center, x)
            if isInternal {
                row.value -= sign * (first.radiusValue(x) - second.radiusValue(x))
                first.addRadiusGradient(-sign, x, to: &row)
                second.addRadiusGradient(sign, x, to: &row)
            } else {
                row.value -= first.radiusValue(x) + second.radiusValue(x)
                first.addRadiusGradient(-1, x, to: &row)
                second.addRadiusGradient(-1, x, to: &row)
            }
            return [row]
        case .equalLength(let first, let second):
            var row = Self.distanceRow(first.end, first.start, x)
            let other = Self.distanceRow(second.end, second.start, x)
            row.value -= other.value
            for entry in other.entries { row.add(column: entry.column, -entry.value) }
            return [row]
        case .equalRadius(let first, let second):
            var row = RowBuilder(value: first.radiusValue(x) - second.radiusValue(x))
            first.addRadiusGradient(1, x, to: &row)
            second.addRadiusGradient(-1, x, to: &row)
            return [row]
        case .midpoint(let p, let line):
            let (a, b, point) = (line.start.value(x), line.end.value(x), p.value(x))
            var rowX = RowBuilder(value: point.x - (a.x + b.x) / 2)
            rowX.add(p, Vector2(1, 0))
            rowX.add(line.start, Vector2(-0.5, 0))
            rowX.add(line.end, Vector2(-0.5, 0))
            var rowY = RowBuilder(value: point.y - (a.y + b.y) / 2)
            rowY.add(p, Vector2(0, 1))
            rowY.add(line.start, Vector2(0, -0.5))
            rowY.add(line.end, Vector2(0, -0.5))
            return [rowX, rowY]
        case .symmetric(let p, let q, let line):
            return [Self.symmetricMidpointRow(p, q, line, x), Self.projection(from: p, to: q, along: line, x)]
        case .fix(let p, let target), .target(let p, let target):
            return Self.difference(p, .constant(target), x)
        case .distance(let p, let q, let value):
            var row = Self.distanceRow(p, q, x)
            row.value -= value
            return [row]
        case .lineDistance(let p, let line, let value, let side):
            var row = Self.signedDistance(p, line, x)
            row.scale(by: side)
            row.value -= value
            return [row]
        case .length(let line, let value):
            var row = Self.distanceRow(line.end, line.start, x)
            row.value -= value
            return [row]
        case .radius(let circle, let value):
            var row = RowBuilder(value: circle.radiusValue(x) - value)
            circle.addRadiusGradient(1, x, to: &row)
            return [row]
        case .arcRadius(let center, let start, let end):
            var row = Self.distanceRow(end, center, x)
            let other = Self.distanceRow(start, center, x)
            row.value -= other.value
            for entry in other.entries { row.add(column: entry.column, -entry.value) }
            return [row]
        }
    }

    /// p − q as two rows.
    static func difference(_ p: PointOperand, _ q: PointOperand, _ x: [Double]) -> [RowBuilder] {
        let delta = p.value(x) - q.value(x)
        var rowX = RowBuilder(value: delta.x)
        rowX.add(p, Vector2(1, 0))
        rowX.add(q, Vector2(-1, 0))
        var rowY = RowBuilder(value: delta.y)
        rowY.add(p, Vector2(0, 1))
        rowY.add(q, Vector2(0, -1))
        return [rowX, rowY]
    }

    /// |p − q|. The gradient is zero where p = q (deterministic, and LM's damping moves on).
    static func distanceRow(_ p: PointOperand, _ q: PointOperand, _ x: [Double]) -> RowBuilder {
        let delta = p.value(x) - q.value(x)
        let length = delta.length
        var row = RowBuilder(value: length)
        guard length > 0 else { return row }
        let unit = delta * (1 / length)
        row.add(p, unit)
        row.add(q, unit * -1)
        return row
    }

    /// cross(d, p − a) / |d| with d = b − a: the signed distance from p to the line (positive on
    /// the left of a → b). A zero-length line counts as the point it shrank to, so collapsing a
    /// line can't satisfy a constraint.
    static func signedDistance(_ p: PointOperand, _ line: LineOperand, _ x: [Double]) -> RowBuilder {
        let (a, point) = (line.start.value(x), p.value(x))
        let d = line.direction(x)
        let w = point - a
        let n = d.length
        guard n > 0 else { return distanceRow(p, line.start, x) }
        let value = SketchMath.cross(d, w) / n
        var row = RowBuilder(value: value)
        let byD = Vector2(w.y, -w.x) * (1 / n) - d * (value / (n * n))
        let byW = Vector2(-d.y, d.x) * (1 / n)
        row.add(p, byW)
        row.add(line.end, byD)
        row.add(line.start, (byD + byW) * -1)
        return row
    }

    /// (q − p) · d / |d|: how far q lies from p along the line's direction.
    static func projection(from p: PointOperand, to q: PointOperand, along line: LineOperand, _ x: [Double]) -> RowBuilder {
        let d = line.direction(x)
        let e = q.value(x) - p.value(x)
        let n = d.length
        guard n > 0 else { return RowBuilder() }
        let value = SketchMath.dot(e, d) / n
        var row = RowBuilder(value: value)
        let byE = d * (1 / n)
        let byD = e * (1 / n) - d * (value / (n * n))
        row.add(q, byE)
        row.add(p, byE * -1)
        row.add(line.end, byD)
        row.add(line.start, byD * -1)
        return row
    }

    /// The signed distance from the midpoint of p and q to the line.
    static func symmetricMidpointRow(_ p: PointOperand, _ q: PointOperand, _ line: LineOperand, _ x: [Double]) -> RowBuilder {
        let a = line.start.value(x)
        let d = line.direction(x)
        let m = (p.value(x) + q.value(x)) * 0.5
        let w = m - a
        let n = d.length
        guard n > 0 else { return RowBuilder() }
        let value = SketchMath.cross(d, w) / n
        var row = RowBuilder(value: value)
        let byD = Vector2(w.y, -w.x) * (1 / n) - d * (value / (n * n))
        let byW = Vector2(-d.y, d.x) * (1 / n)
        row.add(p, byW * 0.5)
        row.add(q, byW * 0.5)
        row.add(line.end, byD)
        row.add(line.start, (byD + byW) * -1)
        return row
    }

    /// The value of an angle-type residual on a zero-length line: as far from satisfied as a
    /// unit sine or cosine can be, so a solve never "meets" an angle by collapsing a line.
    static let degenerateLine = RowBuilder(value: 1)

    /// d.y / |d| (or d.x / |d| when `vertical`): the sine (cosine) of the line's angle to the x axis.
    static func unitComponent(_ line: LineOperand, vertical: Bool, _ x: [Double]) -> RowBuilder {
        let d = line.direction(x)
        let n = d.length
        guard n > 0 else { return degenerateLine }
        let cube = n * n * n
        var row = RowBuilder(value: (vertical ? d.x : d.y) / n)
        let byD = vertical ? Vector2(d.y * d.y, -d.x * d.y) * (1 / cube) : Vector2(-d.x * d.y, d.x * d.x) * (1 / cube)
        row.add(line.end, byD)
        row.add(line.start, byD * -1)
        return row
    }

    /// cross(d₁, d₂) / (|d₁| |d₂|): the sine of the angle from the first line to the second.
    static func unitCross(_ first: LineOperand, _ second: LineOperand, _ x: [Double]) -> RowBuilder {
        let (d1, d2) = (first.direction(x), second.direction(x))
        let (n1, n2) = (d1.length, d2.length)
        guard n1 > 0, n2 > 0 else { return degenerateLine }
        let value = SketchMath.cross(d1, d2) / (n1 * n2)
        var row = RowBuilder(value: value)
        let byD1 = Vector2(d2.y, -d2.x) * (1 / (n1 * n2)) - d1 * (value / (n1 * n1))
        let byD2 = Vector2(-d1.y, d1.x) * (1 / (n1 * n2)) - d2 * (value / (n2 * n2))
        row.add(first.end, byD1)
        row.add(first.start, byD1 * -1)
        row.add(second.end, byD2)
        row.add(second.start, byD2 * -1)
        return row
    }

    /// d₁ · d₂ / (|d₁| |d₂|): the cosine of the angle between the lines.
    static func unitDot(_ first: LineOperand, _ second: LineOperand, _ x: [Double]) -> RowBuilder {
        let (d1, d2) = (first.direction(x), second.direction(x))
        let (n1, n2) = (d1.length, d2.length)
        guard n1 > 0, n2 > 0 else { return degenerateLine }
        let value = SketchMath.dot(d1, d2) / (n1 * n2)
        var row = RowBuilder(value: value)
        let byD1 = d2 * (1 / (n1 * n2)) - d1 * (value / (n1 * n1))
        let byD2 = d1 * (1 / (n1 * n2)) - d2 * (value / (n2 * n2))
        row.add(first.end, byD1)
        row.add(first.start, byD1 * -1)
        row.add(second.end, byD2)
        row.add(second.start, byD2 * -1)
        return row
    }
}
```
`Sources/CreatorSketch/Solver/Equation+Columns.swift`:
```swift
extension Equation {
    /// Every global unknown column the equation reads, in a fixed order (duplicates allowed).
    var columns: [Int] {
        switch self {
        case .coincident(let p, let q), .horizontal(let p, let q), .vertical(let p, let q), .distance(let p, let q, _):
            Self.columns(p) + Self.columns(q)
        case .pointOnLine(let p, let line), .midpoint(let p, let line), .lineDistance(let p, let line, _, _):
            Self.columns(p) + Self.columns(line)
        case .pointOnCircle(let p, let circle):
            Self.columns(p) + Self.columns(circle)
        case .horizontalLine(let line, _), .verticalLine(let line, _):
            Self.columns(line)
        case .parallel(let a, let b, _), .perpendicular(let a, let b, _), .angle(let a, let b, _, _), .equalLength(let a, let b):
            Self.columns(a) + Self.columns(b)
        case .tangentAtPoint(let p, let center, let line):
            Self.columns(p) + Self.columns(center) + Self.columns(line)
        case .lineTangent(let line, let circle, _):
            Self.columns(line) + Self.columns(circle)
        case .circleTangent(let a, let b, _, _), .equalRadius(let a, let b):
            Self.columns(a) + Self.columns(b)
        case .symmetric(let p, let q, let line):
            Self.columns(p) + Self.columns(q) + Self.columns(line)
        case .fix(let p, _), .target(let p, _):
            Self.columns(p)
        case .length(let line, _):
            Self.columns(line)
        case .radius(let circle, _):
            Self.columns(circle)
        case .arcRadius(let center, let start, let end):
            Self.columns(center) + Self.columns(start) + Self.columns(end)
        }
    }

    static func columns(_ point: PointOperand) -> [Int] {
        if case .unknown(let column) = point { return [column, column + 1] }
        return []
    }

    static func columns(_ line: LineOperand) -> [Int] { columns(line.start) + columns(line.end) }

    static func columns(_ circle: CircleOperand) -> [Int] {
        let radius: [Int] = switch circle.radius {
        case .unknown(let column): [column]
        case .constant: []
        case .through(let point): columns(point)
        }
        return columns(circle.center) + radius
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.ResidualTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 17 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Geometry/SketchMath.swift Sources/CreatorSketch/Solver/CircleOperand.swift Sources/CreatorSketch/Solver/Equation+Columns.swift Sources/CreatorSketch/Solver/Equation+Rows.swift Sources/CreatorSketch/Solver/Equation.swift Sources/CreatorSketch/Solver/LineOperand.swift Sources/CreatorSketch/Solver/PointOperand.swift Sources/CreatorSketch/Solver/RadiusOperand.swift Sources/CreatorSketch/Solver/RowBuilder.swift Tests/CreatorSketchTests/ResidualTests.swift
git commit -m "feat(sketch): add sketch residuals with analytic Jacobians"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 4: From sketch to equations: layout, warm start, branch choices, refusals
**Files:**
- Create: `Sources/CreatorSketch/Solver/SolveFailure.swift`, `Sources/CreatorSketch/Solver/SolverTerm.swift`, `Sources/CreatorSketch/Solver/UnknownLayout.swift`, `Sources/CreatorSketch/Solver/TermBuilder.swift`, `Tests/CreatorSketchTests/TermBuilderTests.swift`
- Test: `Tests/CreatorSketchTests/TermBuilderTests.swift`

**Interfaces:**
- Consumes: `Equation` and the operands (Task 3); `Sketch.label(of:)`, `title(of:)`, `Double.sketchDisplay` (Task 1).
- Produces (internal):
  - `struct SolveFailure: Error { reason: String }`
  - `struct SolverTerm { enum Role { .user(SketchConstraintRef), .implicit, .drag }; role; equation; userRef }`
  - `struct UnknownLayout { pointColumns; radiusColumns; owners; columnCount; init(_ sketch:); warmStart(_:) -> [Double] }`. Columns go in entity-ID order: 2 per point, 1 per circle.
  - `struct TermBuilder { sketch; layout; x0; struct Output { terms; suspended }; build() throws(SolveFailure) -> Output }`. Constraints come in ID order, then driving dimensions in ID order, then one implicit `arcRadius` per arc. Rows that hold whatever the geometry is are dropped (`isTriviallyMet(_:)`, `metTolerance = 1e-7`).

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/TermBuilderTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Turning a sketch into equations: layout, warm start, branch choices and refusals (spec §4).
struct TermBuilderTests {
    func build(_ sketch: Sketch) throws(SolveFailure) -> TermBuilder.Output {
        let layout = UnknownLayout(sketch)
        return try TermBuilder(sketch: sketch, layout: layout, x0: layout.warmStart(sketch)).build()
    }

    func refusal(_ sketch: Sketch) -> String? {
        do {
            _ = try build(sketch)
            return nil
        } catch {
            return error.reason
        }
    }

    @Test func columnsFollowEntityIDsAndWarmStartPrefersTheLastSolve() {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(1, 2))
        let circle = sketch.addCircle(center: a, radius: 3)
        let b = sketch.addPoint(Vector2(4, 5))
        sketch.solved[b] = .point(Vector2(6, 7))
        let layout = UnknownLayout(sketch)
        #expect(layout.pointColumns[a] == 0)
        #expect(layout.radiusColumns[circle] == 2)
        #expect(layout.pointColumns[b] == 3)
        #expect(layout.warmStart(sketch) == [1, 2, 3, 6, 7])
    }

    @Test func rowsThatHoldWhateverTheGeometryAreDropped() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let inner = sketch.addCircle(center: center, radius: 2)
        let outer = sketch.addCircle(center: center, radius: 3)
        let line = sketch.addLine(Vector2(5, 0), Vector2(9, 1))
        let flat = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        let tilted = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "f", curve: .line(.zero, Vector2(10, 3))))))
        sketch.add(.concentric(inner, outer))
        sketch.add(.coincident(center, center))
        sketch.add(.parallel(line, line))
        sketch.add(.equal(line, line))
        sketch.add(.horizontal(flat))
        sketch.addDimension(.angle(line, line), value: 0)
        // Constants that disagree are kept, so the solve can name them.
        let impossible = sketch.add(.horizontal(tilted))
        #expect(try build(sketch).terms.map(\.role) == [.user(.constraint(impossible))])
    }

    @Test func arcsAddTheImplicitRadiusTermAndReferenceDimensionsAddNothing() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let arc = sketch.addArc(center: center, start: sketch.addPoint(Vector2(5, 0)), end: sketch.addPoint(Vector2(0, 5)))
        sketch.addDimension(.radius(arc), value: 5, isDriving: false)
        let output = try build(sketch)
        #expect(output.terms.count == 1)
        #expect(output.terms.first?.role == .implicit)
    }

    @Test func lineOrientationsAreAngleBasedAndScaledByLength() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(8, 6))
        let horizontal = sketch.add(.horizontal(line))
        let term = try #require(try build(sketch).terms.first)
        #expect(term.role == .user(.constraint(horizontal)))
        // Length 10 at the warm start; the residual is 10 · sin(angle to x) = 6.
        #expect(term.equation == .horizontalLine(LineOperand(start: .unknown(column: 0), end: .unknown(column: 2)), scale: 10))
        #expect(isClose(term.equation.rows([0, 0, 8, 6])[0].value, 6, tolerance: 1e-12))
    }

    @Test func pointToLineDistanceKeepsTheDrawnSide() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let below = sketch.addPoint(Vector2(3, -2))
        sketch.addDimension(.distance(below, line), value: 5)
        let term = try #require(try build(sketch).terms.first)
        guard case .lineDistance(_, _, let value, let side) = term.equation else {
            Issue.record("not a line distance: \(term.equation)")
            return
        }
        #expect(value == 5)
        #expect(side == -1)
    }

    @Test func angleTargetTakesTheSignOfTheDrawnAngle() throws {
        var sketch = Sketch()
        let base = sketch.addLine(.zero, Vector2(10, 0))
        let down = sketch.addLine(.zero, Vector2(10, -6))
        sketch.addDimension(.angle(base, down), value: 30)
        let term = try #require(try build(sketch).terms.first)
        guard case .angle(_, _, let target, let scale) = term.equation else {
            Issue.record("not an angle: \(term.equation)")
            return
        }
        #expect(isClose(target, -.pi / 6, tolerance: 1e-12))
        #expect(isClose(scale, (10 + 136.0.squareRoot()) / 2, tolerance: 1e-12))
    }

    @Test func tangentAtASharedEndpointUsesThePerpendicularForm() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (_, joint) = sketch.ends(line)
        let center = sketch.addPoint(Vector2(10, 5))
        let arc = sketch.addArc(center: center, start: joint, end: sketch.addPoint(Vector2(15, 5)))
        sketch.add(.tangent(line, arc))
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 5)
        sketch.add(.tangent(circle, line))
        let terms = try build(sketch).terms.filter { $0.role != .implicit }
        try #require(terms.count == 2)
        #expect(terms[0].equation == .tangentAtPoint(.unknown(column: 2), center: .unknown(column: 4),
                                                    LineOperand(start: .unknown(column: 0), end: .unknown(column: 2))))
        guard case .lineTangent(_, _, let side) = terms[1].equation else {
            Issue.record("not a line tangent: \(terms[1].equation)")
            return
        }
        #expect(side == 1)
    }

    @Test func circleTangencyIsInternalWhenDrawnInside() throws {
        var sketch = Sketch()
        let outer = sketch.addCircle(center: .zero, radius: 10)
        let inner = sketch.addCircle(center: Vector2(3, 0), radius: 6)
        sketch.add(.tangent(inner, outer))
        let term = try #require(try build(sketch).terms.first)
        guard case .circleTangent(_, _, let isInternal, let sign) = term.equation else {
            Issue.record("not a circle tangent: \(term.equation)")
            return
        }
        #expect(isInternal)
        #expect(sign == -1)
    }

    @Test func suspendedProjectionsAreSkipped() throws {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0)),
                                                                     isSuspended: true))))
        let point = sketch.addPoint(.zero)
        let constraint = sketch.add(.pointOn(point: point, curve: edge))
        let dimension = sketch.addDimension(.distance(point, edge), value: 2)
        let output = try build(sketch)
        #expect(output.terms.isEmpty)
        #expect(output.suspended == [.constraint(constraint), .dimension(dimension)])
    }

    @Test func refusalsAreInPlainLanguage() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let circle = sketch.addCircle(center: Vector2(20, 0), radius: 2)
        var negative = sketch
        negative.addDimension(.radius(circle), value: 0)
        #expect(refusal(negative) == "Radius d1 must be greater than 0 mm, not 0 mm.")
        var wrongKind = sketch
        wrongKind.add(.parallel(line, circle))
        #expect(refusal(wrongKind) == "Parallel on Line 1 and Circle 1 needs two lines.")
        var badRadius = sketch
        let center = badRadius.centerOf(circle)
        badRadius.entities[circle]?.kind = .circle(center: center, radius: -1)
        #expect(refusal(badRadius) == "Circle 1 needs a radius greater than 0 mm.")
        var sharedPoints = sketch
        let (start, _) = sharedPoints.ends(line)
        sharedPoints.entities[line]?.kind = .line(start: start, end: start)
        #expect(refusal(sharedPoints) == "Line 1 starts and ends at the same point.")
        #expect(refusal(sketch) == nil)
    }

    @Test func aConstraintOnAMissingEntityIsRefusedNotSolvedAround() {
        // An edited or damaged file: the constraint outlived its point.
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        sketch.add(.coincident(point, SketchEntityID(99)))
        #expect(refusal(sketch) == "Coincident on Point 1 and a deleted entity refers to geometry that no longer exists.")
    }

    @Test func aWiredValueThatIsNotANumberIsRefused() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let length = sketch.addDimension(.length(line), value: 10)
        for bad in [Double.nan, .infinity, -.infinity] {
            sketch.dimensions[length]?.value = bad
            #expect(refusal(sketch) == "Length d1 is not a number.")
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.TermBuilderTests`
Expected: compile errors, starting with `cannot find 'UnknownLayout' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Solver/SolveFailure.swift`:
```swift
/// A sketch the solver refuses before solving, with a plain-language reason (spec §4).
struct SolveFailure: Error, Hashable, Sendable {
    var reason: String
}
```
`Sources/CreatorSketch/Solver/SolverTerm.swift`:
```swift
/// One equation plus where it came from.
struct SolverTerm: Hashable, Sendable {
    enum Role: Hashable, Sendable {
        /// A user constraint or driving dimension. Only these can be named in conflicts.
        case user(SketchConstraintRef)
        /// A condition implied by the model (an arc's equal radii). Never reported, never removed.
        case implicit
        /// A drag target (drag mode, first phase only).
        case drag
    }

    var role: Role
    var equation: Equation

    var userRef: SketchConstraintRef? {
        if case .user(let ref) = role { return ref }
        return nil
    }
}
```
`Sources/CreatorSketch/Solver/UnknownLayout.swift`:
```swift
import CreatorGeometry

/// Assigns global unknown columns in entity-ID order: two per point (x, y), one per circle (radius).
/// Projected geometry has no unknowns.
struct UnknownLayout: Sendable {
    private(set) var pointColumns: [SketchEntityID: Int] = [:]
    private(set) var radiusColumns: [SketchEntityID: Int] = [:]
    /// For each column, the entity that owns it.
    private(set) var owners: [SketchEntityID] = []

    init(_ sketch: Sketch) {
        for id in sketch.entityIDs {
            switch sketch.entities[id]?.kind {
            case .point:
                pointColumns[id] = owners.count
                owners += [id, id]
            case .circle:
                radiusColumns[id] = owners.count
                owners.append(id)
            default:
                break
            }
        }
    }

    var columnCount: Int { owners.count }

    /// The warm start: each unknown's `solved` value, falling back to the drawn value (spec §4).
    func warmStart(_ sketch: Sketch) -> [Double] {
        var x = Array(repeating: 0.0, count: columnCount)
        for (id, column) in pointColumns {
            let position = sketch.position(of: id) ?? .zero
            x[column] = position.x
            x[column + 1] = position.y
        }
        for (id, column) in radiusColumns {
            x[column] = sketch.radius(of: id) ?? 0
        }
        return x
    }
}
```
`Sources/CreatorSketch/Solver/TermBuilder.swift`:
```swift
import CreatorGeometry
import Foundation

/// Turns a sketch's constraints, driving dimensions and arcs into equations over the global
/// unknowns. Choices that pick a solution branch (which side of a line, which way an angle
/// opens, internal or external tangency) are read from the warm start `x0`, which is what keeps
/// solves branch-stable (spec §4).
struct TermBuilder {
    let sketch: Sketch
    let layout: UnknownLayout
    let x0: [Double]

    struct Output: Sendable {
        var terms: [SolverTerm]
        /// Constraints and dimensions skipped because they touch a suspended projected edge.
        var suspended: [SketchConstraintRef]
    }

    func build() throws(SolveFailure) -> Output {
        try validateEntities()
        var terms: [SolverTerm] = []
        var suspended: [SketchConstraintRef] = []
        for id in sketch.constraintIDs {
            guard let constraint = sketch.constraints[id] else { continue }
            let ref = SketchConstraintRef.constraint(id)
            try requireExisting(constraint.entities, ref)
            if touchesSuspended(constraint.entities) {
                suspended.append(ref)
                continue
            }
            for equation in try equations(for: constraint, ref) where !isTriviallyMet(equation) {
                terms.append(SolverTerm(role: .user(ref), equation: equation))
            }
        }
        for id in sketch.dimensionIDs {
            guard let dimension = sketch.dimensions[id], dimension.isDriving else { continue }
            let ref = SketchConstraintRef.dimension(id)
            try requireExisting(dimension.kind.entities, ref)
            if touchesSuspended(dimension.kind.entities) {
                suspended.append(ref)
                continue
            }
            try validate(dimension)
            let equation = try equation(for: dimension, ref)
            if !isTriviallyMet(equation) { terms.append(SolverTerm(role: .user(ref), equation: equation)) }
        }
        for id in sketch.entityIDs {
            guard case .arc(let center, let start, let end) = sketch.entities[id]?.kind else { continue }
            let equation = Equation.arcRadius(center: try point(center, ref: nil, needs: ""),
                                              start: try point(start, ref: nil, needs: ""),
                                              end: try point(end, ref: nil, needs: ""))
            terms.append(SolverTerm(role: .implicit, equation: equation))
        }
        return Output(terms: terms, suspended: suspended)
    }

    /// Constants agreeing to within this (mm) already hold. The same as the solver's satisfied
    /// tolerance (`ComponentSolver.satisfiedTolerance`, Task 5).
    static let metTolerance = 1e-7

    /// True for a row that holds whatever the unknowns are: the same point twice (coincident,
    /// horizontal or vertical points, or concentric curves that already share a centre), the
    /// same line or circle twice (parallel, equal, a 0° or 180° angle), or constants only that
    /// already agree (horizontal on a projected edge that is horizontal). Such a row's Jacobian
    /// is identically zero, so keeping it would always read as redundancy; it is dropped, and
    /// takes no part in DOF, redundancy or conflicts. Constants that disagree are kept, so the
    /// solve reports them as a conflict ("… can't be met.").
    func isTriviallyMet(_ equation: Equation) -> Bool {
        switch equation {
        case .coincident(let p, let q), .horizontal(let p, let q), .vertical(let p, let q):
            if p == q { return true }
        case .parallel(let a, let b, _), .equalLength(let a, let b):
            if a == b { return true }
        case .equalRadius(let a, let b):
            if a == b { return true }
        case .angle(let a, let b, let target, _):
            if a == b, abs(sin(target)) <= 1e-12 { return true }
        default:
            break
        }
        return equation.columns.isEmpty
            && equation.rows(x0).allSatisfy { abs($0.value) <= Self.metTolerance }
    }

    // MARK: Validation

    func validateEntities() throws(SolveFailure) {
        for id in sketch.entityIDs {
            guard let entity = sketch.entities[id] else { continue }
            switch entity.kind {
            case .point(let position):
                if !position.isFinite { throw SolveFailure(reason: "\(sketch.label(of: id)) has an invalid position.") }
            case .line(let start, let end):
                try requirePoints([start, end], of: id)
                if start == end { throw SolveFailure(reason: "\(sketch.label(of: id)) starts and ends at the same point.") }
            case .arc(let center, let start, let end):
                try requirePoints([center, start, end], of: id)
                if Set([center, start, end]).count < 3 {
                    throw SolveFailure(reason: "\(sketch.label(of: id)) needs three different points.")
                }
            case .circle(let center, let radius):
                try requirePoints([center], of: id)
                if !(radius > 0) || !radius.isFinite {
                    throw SolveFailure(reason: "\(sketch.label(of: id)) needs a radius greater than 0 mm.")
                }
            case .projected:
                break
            }
        }
    }

    func requirePoints(_ ids: [SketchEntityID], of owner: SketchEntityID) throws(SolveFailure) {
        for id in ids {
            guard let kind = sketch.entities[id]?.kind, kind.isPoint else {
                throw SolveFailure(reason: "\(sketch.label(of: owner)) is built on something that isn't a point.")
            }
        }
    }

    func validate(_ dimension: SketchDimension) throws(SolveFailure) {
        let value = dimension.value
        let title = sketch.title(of: dimension)
        guard value.isFinite else { throw SolveFailure(reason: "\(title) is not a number.") }
        if case .angle = dimension.kind {
            guard value >= 0, value <= 180 else {
                throw SolveFailure(reason: "\(title) must be between 0° and 180°, not \(value.sketchDisplay)°.")
            }
        } else if !(value > 0) {
            throw SolveFailure(reason: "\(title) must be greater than 0 mm, not \(value.sketchDisplay) mm.")
        }
    }

    /// Refuses a constraint or dimension that names an entity the sketch no longer has (an
    /// edited or damaged file), instead of solving around it.
    func requireExisting(_ ids: [SketchEntityID], _ ref: SketchConstraintRef) throws(SolveFailure) {
        guard ids.allSatisfy({ sketch.entities[$0] != nil }) else {
            throw SolveFailure(reason: "\(sketch.label(of: ref)) refers to geometry that no longer exists.")
        }
    }

    func touchesSuspended(_ ids: [SketchEntityID]) -> Bool {
        ids.contains { id in
            if case .projected(let source) = sketch.entities[id]?.kind { return source.isSuspended }
            return false
        }
    }

    // MARK: Operands

    func wrongKind(_ ref: SketchConstraintRef?, needs: String) -> SolveFailure {
        let name = ref.map { sketch.label(of: $0) } ?? "A constraint"
        return SolveFailure(reason: "\(name) needs \(needs).")
    }

    func point(_ id: SketchEntityID, ref: SketchConstraintRef?, needs: String) throws(SolveFailure) -> PointOperand {
        guard let column = layout.pointColumns[id] else { throw wrongKind(ref, needs: needs) }
        return .unknown(column: column)
    }

    func line(_ id: SketchEntityID, ref: SketchConstraintRef?, needs: String) throws(SolveFailure) -> LineOperand {
        switch sketch.entities[id]?.kind {
        case .line(let start, let end):
            return LineOperand(start: try point(start, ref: ref, needs: needs), end: try point(end, ref: ref, needs: needs))
        case .projected(let source):
            if case .line(let a, let b) = source.curve { return LineOperand(start: .constant(a), end: .constant(b)) }
            throw wrongKind(ref, needs: needs)
        default:
            throw wrongKind(ref, needs: needs)
        }
    }

    func circle(_ id: SketchEntityID, ref: SketchConstraintRef?, needs: String) throws(SolveFailure) -> CircleOperand {
        switch sketch.entities[id]?.kind {
        case .arc(let center, let start, let end):
            let startPoint = try point(start, ref: ref, needs: needs)
            return CircleOperand(center: try point(center, ref: ref, needs: needs), radius: .through(startPoint),
                                 endpoints: [startPoint, try point(end, ref: ref, needs: needs)])
        case .circle(let center, _):
            guard let column = layout.radiusColumns[id] else { throw wrongKind(ref, needs: needs) }
            return CircleOperand(center: try point(center, ref: ref, needs: needs), radius: .unknown(column: column), endpoints: [])
        case .projected(let source):
            switch source.curve {
            case .arc(let center, let radius, _, _), .circle(let center, let radius):
                return CircleOperand(center: .constant(center), radius: .constant(radius), endpoints: [])
            case .line:
                throw wrongKind(ref, needs: needs)
            }
        default:
            throw wrongKind(ref, needs: needs)
        }
    }

    func isLine(_ id: SketchEntityID) -> Bool {
        switch sketch.entities[id]?.kind {
        case .line: true
        case .projected(let source): if case .line = source.curve { true } else { false }
        default: false
        }
    }

    func isCircular(_ id: SketchEntityID) -> Bool {
        switch sketch.entities[id]?.kind {
        case .arc, .circle: true
        case .projected(let source): if case .line = source.curve { false } else { true }
        default: false
        }
    }

    func isPoint(_ id: SketchEntityID) -> Bool { layout.pointColumns[id] != nil }

    /// The point entity both curves end at, if they share one (lines: start/end; arcs: start/end).
    func sharedEndpoint(_ a: SketchEntityID, _ b: SketchEntityID) -> SketchEntityID? {
        let first = endpoints(of: a)
        return endpoints(of: b).first { first.contains($0) }
    }

    func endpoints(of id: SketchEntityID) -> [SketchEntityID] {
        switch sketch.entities[id]?.kind {
        case .line(let start, let end): [start, end]
        case .arc(_, let start, let end): [start, end]
        default: []
        }
    }

    func center(of id: SketchEntityID) -> SketchEntityID? {
        switch sketch.entities[id]?.kind {
        case .arc(let center, _, _), .circle(let center, _): center
        default: nil
        }
    }

    // MARK: Equations

    /// The mean length of two lines at the warm start, the scale that turns an angle-type
    /// residual into millimetres. 1 mm for degenerate lines.
    func scale(_ a: LineOperand, _ b: LineOperand) -> Double {
        let mean = (a.direction(x0).length + b.direction(x0).length) / 2
        return mean > 1e-9 ? mean : 1
    }

    /// +1 when `p` starts on the left of the line (or on it), −1 on the right.
    func side(_ p: PointOperand, _ line: LineOperand) -> Double {
        Equation.signedDistance(p, line, x0).value < 0 ? -1 : 1
    }

    func equations(for constraint: SketchConstraint, _ ref: SketchConstraintRef) throws(SolveFailure) -> [Equation] {
        switch constraint {
        case .coincident(let a, let b):
            return [.coincident(try point(a, ref: ref, needs: "two points"), try point(b, ref: ref, needs: "two points"))]
        case .pointOn(let p, let curve):
            let needs = "a point and a curve"
            let operand = try point(p, ref: ref, needs: needs)
            if isLine(curve) { return [.pointOnLine(operand, try line(curve, ref: ref, needs: needs))] }
            return [.pointOnCircle(operand, try circle(curve, ref: ref, needs: needs))]
        case .horizontal(let id):
            let l = try line(id, ref: ref, needs: "a line")
            return [.horizontalLine(l, scale: scale(l, l))]
        case .vertical(let id):
            let l = try line(id, ref: ref, needs: "a line")
            return [.verticalLine(l, scale: scale(l, l))]
        case .horizontalPoints(let a, let b):
            return [.horizontal(try point(a, ref: ref, needs: "two points"), try point(b, ref: ref, needs: "two points"))]
        case .verticalPoints(let a, let b):
            return [.vertical(try point(a, ref: ref, needs: "two points"), try point(b, ref: ref, needs: "two points"))]
        case .parallel(let a, let b):
            let (first, second) = (try line(a, ref: ref, needs: "two lines"), try line(b, ref: ref, needs: "two lines"))
            return [.parallel(first, second, scale: scale(first, second))]
        case .perpendicular(let a, let b):
            let (first, second) = (try line(a, ref: ref, needs: "two lines"), try line(b, ref: ref, needs: "two lines"))
            return [.perpendicular(first, second, scale: scale(first, second))]
        case .tangent(let a, let b):
            return [try tangent(a, b, ref)]
        case .equal(let a, let b):
            let needs = "two lines or two arcs or circles"
            if isLine(a), isLine(b) {
                return [.equalLength(try line(a, ref: ref, needs: needs), try line(b, ref: ref, needs: needs))]
            }
            guard isCircular(a), isCircular(b) else { throw wrongKind(ref, needs: needs) }
            return [.equalRadius(try circle(a, ref: ref, needs: needs), try circle(b, ref: ref, needs: needs))]
        case .midpoint(let p, let l):
            let needs = "a point and a line"
            return [.midpoint(try point(p, ref: ref, needs: needs), try line(l, ref: ref, needs: needs))]
        case .concentric(let a, let b):
            let needs = "two arcs or circles"
            return [.coincident(try circle(a, ref: ref, needs: needs).center, try circle(b, ref: ref, needs: needs).center)]
        case .symmetric(let a, let b, let l):
            let needs = "two points and a line"
            return [.symmetric(try point(a, ref: ref, needs: needs), try point(b, ref: ref, needs: needs),
                               try line(l, ref: ref, needs: needs))]
        case .fix(let p, let target):
            return [.fix(try point(p, ref: ref, needs: "a point"), target)]
        }
    }

    func tangent(_ a: SketchEntityID, _ b: SketchEntityID, _ ref: SketchConstraintRef) throws(SolveFailure) -> Equation {
        let needs = "a line and an arc or circle, or two arcs or circles"
        if isLine(a) || isLine(b) {
            let (lineID, circleID) = isLine(a) ? (a, b) : (b, a)
            guard !isLine(circleID) else { throw wrongKind(ref, needs: needs) }
            let l = try line(lineID, ref: ref, needs: needs)
            let c = try circle(circleID, ref: ref, needs: needs)
            if let shared = sharedEndpoint(lineID, circleID) {
                return .tangentAtPoint(try point(shared, ref: ref, needs: needs), center: c.center, l)
            }
            return .lineTangent(l, c, side: side(c.center, l))
        }
        let (first, second) = (try circle(a, ref: ref, needs: needs), try circle(b, ref: ref, needs: needs))
        if let shared = sharedEndpoint(a, b) {
            // The shared point lies on the line through both centres.
            return .pointOnLine(try point(shared, ref: ref, needs: needs), LineOperand(start: first.center, end: second.center))
        }
        let distance = (first.center.value(x0) - second.center.value(x0)).length
        let (r1, r2) = (first.radiusValue(x0), second.radiusValue(x0))
        let isInternal = abs(distance - abs(r1 - r2)) < abs(distance - (r1 + r2))
        return .circleTangent(first, second, isInternal: isInternal, sign: r1 >= r2 ? 1 : -1)
    }

    func equation(for dimension: SketchDimension, _ ref: SketchConstraintRef) throws(SolveFailure) -> Equation {
        switch dimension.kind {
        case .distance(let a, let b):
            let needs = "two points, or a point and a line"
            if isPoint(a), isPoint(b) {
                return .distance(try point(a, ref: ref, needs: needs), try point(b, ref: ref, needs: needs), dimension.value)
            }
            let (pointID, lineID) = isPoint(a) ? (a, b) : (b, a)
            let p = try point(pointID, ref: ref, needs: needs)
            let l = try line(lineID, ref: ref, needs: needs)
            return .lineDistance(p, l, dimension.value, side: side(p, l))
        case .length(let id):
            return .length(try line(id, ref: ref, needs: "a line"), dimension.value)
        case .radius(let id):
            return .radius(try circle(id, ref: ref, needs: "an arc or circle"), dimension.value)
        case .diameter(let id):
            return .radius(try circle(id, ref: ref, needs: "an arc or circle"), dimension.value / 2)
        case .angle(let a, let b):
            let (first, second) = (try line(a, ref: ref, needs: "two lines"), try line(b, ref: ref, needs: "two lines"))
            return .angle(first, second, target: angleTarget(first, second, degrees: dimension.value), scale: scale(first, second))
        }
    }

    /// ±θ, whichever has a zero of sin(φ − target) nearest the warm-start angle φ₀ (lines are
    /// undirected, so θ + π also satisfies the residual). Ties go to +θ.
    func angleTarget(_ first: LineOperand, _ second: LineOperand, degrees: Double) -> Double {
        let (d1, d2) = (first.direction(x0), second.direction(x0))
        let phi = atan2(SketchMath.cross(d1, d2), SketchMath.dot(d1, d2))
        let theta = degrees * .pi / 180
        func gap(_ target: Double) -> Double {
            let a = SketchMath.wrapped(phi - target)
            let b = SketchMath.wrapped(phi - target - .pi)
            return min(min(a, 2 * .pi - a), min(b, 2 * .pi - b))
        }
        return gap(theta) <= gap(-theta) ? theta : -theta
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.TermBuilderTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 29 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Solver/SolveFailure.swift Sources/CreatorSketch/Solver/SolverTerm.swift Sources/CreatorSketch/Solver/TermBuilder.swift Sources/CreatorSketch/Solver/UnknownLayout.swift Tests/CreatorSketchTests/TermBuilderTests.swift
git commit -m "feat(sketch): build solver equations from a sketch"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 5: Components, Levenberg–Marquardt, analysis and the solver entry
**Files:**
- Create: `Sources/CreatorSketch/Solver/ComponentSystem.swift`, `Sources/CreatorSketch/Solver/ComponentPartition.swift`, `Sources/CreatorSketch/Solver/LevenbergMarquardt.swift`, `Sources/CreatorSketch/Solver/ComponentSolver.swift`, `Sources/CreatorSketch/Solver/SketchSolveStatus.swift`, `Sources/CreatorSketch/Solver/EntityFreedom.swift`, `Sources/CreatorSketch/Solver/SketchSolution.swift`, `Sources/CreatorSketch/Solver/SketchMeasure.swift`, `Sources/CreatorSketch/Solver/SketchSolver.swift`, `Sources/CreatorSketch/Solver/Sketch+Solution.swift`, `Tests/CreatorSketchTests/Support/SketchFixtures.swift`, `Tests/CreatorSketchTests/PartitionTests.swift`, `Tests/CreatorSketchTests/ConstraintFixtureTests.swift`, `Tests/CreatorSketchTests/ClassicSketchTests.swift`, `Tests/CreatorSketchTests/FreedomTests.swift`, `Tests/CreatorSketchTests/ConvergenceTests.swift`
- Test: `Tests/CreatorSketchTests/PartitionTests.swift`, `Tests/CreatorSketchTests/ConstraintFixtureTests.swift`, `Tests/CreatorSketchTests/ClassicSketchTests.swift`, `Tests/CreatorSketchTests/FreedomTests.swift`, `Tests/CreatorSketchTests/ConvergenceTests.swift`

**Interfaces:**
- Consumes: `TermBuilder`, `UnknownLayout`, `SolverTerm`, `SolveFailure` (Task 4); `DenseMatrix`, `HouseholderQR`, `RankRevealingQR` (Task 2); `Equation.rows`, `Equation.columns` (Task 3).
- Produces:
  - internal `ComponentSystem { terms; columns; base; init(terms:columns:base:); columnCount; local(_:); global(_:); residuals(_:); evaluate(_:); rowRanges; filtered(_:); adding(_:) }`
  - internal `ComponentPartition { struct Component { columns; terms }; components; init(terms:layout:) }`
  - internal `LevenbergMarquardt { residualTolerance = 1e-9; stepTolerance = 1e-12; iterationLimit = 200; polishSteps = 2; polishedTolerance = 1e-12; struct Outcome { x; maxResidual; iterations }; minimize(_:from:) }`
  - internal `ComponentSolver { satisfiedTolerance = 1e-7; freeTolerance = 1e-10; struct Outcome; solve(_:base:); analyse(_:at:); rows(of:where:); refs(of:) }`. `Outcome.conflictSets: [[SketchConstraintRef]]`. In this task it is one set holding every ref of a component that can't be met or is redundant; Task 6 makes it minimal sets, one per conflict.
  - `public enum SketchSolveStatus { .solved, .underConstrained(dof:), .overConstrained(conflicts: [SketchConstraintRef]), .failed(reason:); isUsable }`
  - `public enum EntityFreedom { .free, .fixed, .conflicting }`
  - `public struct SketchSolution { status; points; radii; freedom; conflictMessages; suspended; measurements; degreesOfFreedom }`
  - `public enum SketchSolver { static func solve(_ sketch: Sketch) -> SketchSolution }` (Task 7 adds `dragging:`)
  - `Sketch.remember(_ solution:)` and internal `SketchMeasure.referenceValues(_:points:radii:)` and `measure(_:_:points:radii:near:)` (angles fold to whichever of α and 180° − α is nearer the stored value)
  - Test fixtures: `ConstrainedRectangle` (`Support/SketchFixtures.swift`) and `ClassicSketchTests.Slot`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/Support/SketchFixtures.swift`:
```swift
// Test fixture file: sketches shared by solver, region and command tests (several helpers by design).
import CreatorGeometry
@testable import CreatorSketch

/// The spec §10 rectangle: corners (0,0) (60,0) (60,40) (0,40), fixed at the origin, horizontal
/// bottom/top, vertical left/right, width 60 on the bottom line and height 40 on the left line.
/// Drawn slightly off so the solver has work to do. Lines: bottom, right, top, left.
struct ConstrainedRectangle {
    var sketch = Sketch()
    let lines: [SketchEntityID]
    let width: DimensionID
    let height: DimensionID

    init(drawnOffset: Double = 0.7) {
        let o = drawnOffset
        lines = addPolygon(&sketch, [Vector2(o, -o), Vector2(60 + o, o), Vector2(60 - o, 40 + o), Vector2(-o, 40 - o)])
        let (origin, _) = sketch.ends(lines[0])
        sketch.add(.fix(origin, at: .zero))
        sketch.add(.horizontal(lines[0]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[3]))
        width = sketch.addDimension(.length(lines[0]), value: 60)
        height = sketch.addDimension(.length(lines[3]), value: 40)
    }

    /// Corner i is the start of line i.
    func corner(_ i: Int, in solution: SketchSolution) -> Vector2? {
        solution.points[sketch.ends(lines[i]).0]
    }
}
```
`Tests/CreatorSketchTests/PartitionTests.swift`:
```swift
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Decomposition into connected components (spec §4 step 1).
struct PartitionTests {
    @Test func separateClustersSolveAsSeparateComponentsInIDOrder() throws {
        var sketch = Sketch()
        let first = sketch.addLine(.zero, Vector2(10, 1))
        let lonePoint = sketch.addPoint(Vector2(50, 50))
        let second = sketch.addLine(Vector2(20, 0), Vector2(30, 2))
        sketch.add(.horizontal(second))
        sketch.add(.horizontal(first))
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0))))))
        sketch.add(.vertical(edge))
        let layout = UnknownLayout(sketch)
        let terms = try TermBuilder(sketch: sketch, layout: layout, x0: layout.warmStart(sketch)).build().terms
        let components = ComponentPartition(terms: terms, layout: layout).components
        // First line (columns 0–3), the lone point (4–5), second line (6–9), then the
        // projected-only term with no unknowns.
        #expect(components.map(\.columns) == [[0, 1, 2, 3], [4, 5], [6, 7, 8, 9], []])
        #expect(components.map(\.terms.count) == [1, 0, 1, 1])
        _ = lonePoint
    }

    @Test func aSharedConstraintJoinsComponents() throws {
        var sketch = Sketch()
        let a = sketch.addLine(.zero, Vector2(10, 0))
        let b = sketch.addLine(Vector2(20, 0), Vector2(30, 0))
        sketch.add(.equal(a, b))
        let layout = UnknownLayout(sketch)
        let terms = try TermBuilder(sketch: sketch, layout: layout, x0: layout.warmStart(sketch)).build().terms
        #expect(ComponentPartition(terms: terms, layout: layout).components.map(\.columns) == [Array(0..<8)])
    }
}
```
`Tests/CreatorSketchTests/ConstraintFixtureTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// One analytic fixture per constraint and dimension kind (spec §10). Each starts off the answer,
/// solves, and checks the defining property and, where the solver's minimal step makes it exact,
/// the resulting position.
struct ConstraintFixtureTests {
    /// Solves and requires the constraints to be met.
    func solved(_ sketch: Sketch) throws -> SketchSolution {
        let solution = SketchSolver.solve(sketch)
        try #require(solution.status.isUsable, "status \(solution.status)")
        return solution
    }

    /// A point fixed where drawn.
    func fixedPoint(_ sketch: inout Sketch, _ position: Vector2) -> SketchEntityID {
        let point = sketch.addPoint(position)
        sketch.add(.fix(point, at: position))
        return point
    }

    /// A line whose two endpoints are fixed where drawn.
    func fixedLine(_ sketch: inout Sketch, _ a: Vector2, _ b: Vector2) -> SketchEntityID {
        let line = sketch.addLine(from: fixedPoint(&sketch, a), to: fixedPoint(&sketch, b))
        return line
    }

    @Test func coincidentMovesTheFreePointOntoTheFixedOne() throws {
        var sketch = Sketch()
        let anchor = fixedPoint(&sketch, Vector2(2, 3))
        let free = sketch.addPoint(Vector2(5, -1))
        sketch.add(.coincident(free, anchor))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[free]), Vector2(2, 3)))
    }

    @Test func pointOnLineDropsPerpendicularlyOntoIt() throws {
        var sketch = Sketch()
        let line = fixedLine(&sketch, .zero, Vector2(10, 0))
        let point = sketch.addPoint(Vector2(4, 3))
        sketch.add(.pointOn(point: point, curve: line))
        let solved = try #require(try solved(sketch).points[point])
        #expect(isClose(solved.y, 0))
        #expect(isNear(solved, Vector2(4, 0)))
    }

    @Test func pointOnCircleMovesRadially() throws {
        var sketch = Sketch()
        let center = fixedPoint(&sketch, .zero)
        let circle = sketch.addCircle(center: center, radius: 5)
        sketch.addDimension(.radius(circle), value: 5)
        let point = sketch.addPoint(Vector2(6, 8))
        sketch.add(.pointOn(point: point, curve: circle))
        #expect(isClose(try #require(try solved(sketch).points[point]), Vector2(3, 4)))
    }

    @Test func pointOnArcUsesItsCircle() throws {
        var sketch = Sketch()
        let center = fixedPoint(&sketch, .zero)
        let arc = sketch.addArc(center: center, start: fixedPoint(&sketch, Vector2(5, 0)), end: fixedPoint(&sketch, Vector2(0, 5)))
        // (−8, −6) is outside the arc's span: the constraint is on its full circle.
        let point = sketch.addPoint(Vector2(-8, -6))
        sketch.add(.pointOn(point: point, curve: arc))
        let solved = try #require(try solved(sketch).points[point])
        #expect(isClose(solved.length, 5))
        #expect(isNear(solved, Vector2(-4, -3)))
    }

    @Test func horizontalAndVerticalLines() throws {
        var sketch = Sketch()
        let start = fixedPoint(&sketch, .zero)
        let flat = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, 2)))
        let upright = sketch.addLine(from: start, to: sketch.addPoint(Vector2(-1, 7)))
        sketch.add(.horizontal(flat))
        sketch.add(.vertical(upright))
        let solution = try solved(sketch)
        // The line constraints are angle-based, so each end swings about the fixed start.
        let flatEnd = try #require(solution.points[sketch.ends(flat).1])
        let uprightEnd = try #require(solution.points[sketch.ends(upright).1])
        #expect(isClose(flatEnd.y, 0))
        #expect(flatEnd.x > 9)
        #expect(isClose(uprightEnd.x, 0))
        #expect(uprightEnd.y > 6)
    }

    @Test func horizontalAndVerticalPoints() throws {
        var sketch = Sketch()
        let anchor = fixedPoint(&sketch, Vector2(1, 1))
        let level = sketch.addPoint(Vector2(9, 4))
        let plumb = sketch.addPoint(Vector2(3, -6))
        sketch.add(.horizontalPoints(anchor, level))
        sketch.add(.verticalPoints(plumb, anchor))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[level]), Vector2(9, 1)))
        #expect(isClose(try #require(solution.points[plumb]), Vector2(1, -6)))
    }

    @Test func parallelAndPerpendicular() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(10, 0))
        let start = fixedPoint(&sketch, Vector2(0, 5))
        let parallel = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, 7)))
        let perpendicular = sketch.addLine(from: start, to: sketch.addPoint(Vector2(1, 12)))
        sketch.add(.parallel(reference, parallel))
        sketch.add(.perpendicular(perpendicular, reference))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[sketch.ends(parallel).1]).y, 5))
        #expect(isClose(try #require(solution.points[sketch.ends(perpendicular).1]).x, 0))
    }

    @Test func tangentCircleMovesToTouchTheLine() throws {
        var sketch = Sketch()
        let line = fixedLine(&sketch, .zero, Vector2(20, 0))
        let circle = sketch.addCircle(center: fixedPoint(&sketch, Vector2(8, 3)), radius: 5)
        sketch.add(.tangent(line, circle))
        let solution = try solved(sketch)
        // The centre is fixed, so the radius shrinks to the distance to the line.
        #expect(isClose(try #require(solution.radii[circle]), 3))
    }

    @Test func tangentArcAtASharedEndpointHasItsRadiusPerpendicularToTheLine() throws {
        var sketch = Sketch()
        let corner = fixedPoint(&sketch, Vector2(10, 0))
        let line = sketch.addLine(from: fixedPoint(&sketch, .zero), to: corner)
        let center = sketch.addPoint(Vector2(11, 4))
        let arc = sketch.addArc(center: center, start: corner, end: sketch.addPoint(Vector2(15, 4)))
        sketch.add(.tangent(line, arc))
        let solution = try solved(sketch)
        let c = try #require(solution.points[center])
        #expect(isClose(c.x, 10))
    }

    @Test func externallyTangentCircles() throws {
        var sketch = Sketch()
        let first = sketch.addCircle(center: fixedPoint(&sketch, .zero), radius: 3)
        sketch.addDimension(.radius(first), value: 3)
        let second = sketch.addCircle(center: fixedPoint(&sketch, Vector2(10, 0)), radius: 4)
        sketch.add(.tangent(first, second))
        #expect(isClose(try #require(try solved(sketch).radii[second]), 7))
    }

    @Test func internallyTangentCircles() throws {
        var sketch = Sketch()
        let outer = sketch.addCircle(center: fixedPoint(&sketch, .zero), radius: 10)
        sketch.addDimension(.radius(outer), value: 10)
        let inner = sketch.addCircle(center: fixedPoint(&sketch, Vector2(4, 0)), radius: 5)
        sketch.add(.tangent(inner, outer))
        #expect(isClose(try #require(try solved(sketch).radii[inner]), 6))
    }

    @Test func equalLengthsAndRadii() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(6, 8))
        let start = fixedPoint(&sketch, Vector2(0, 20))
        let copy = sketch.addLine(from: start, to: sketch.addPoint(Vector2(3, 20)))
        sketch.add(.equal(reference, copy))
        let big = sketch.addCircle(center: fixedPoint(&sketch, Vector2(30, 0)), radius: 4)
        sketch.addDimension(.radius(big), value: 4)
        let small = sketch.addCircle(center: fixedPoint(&sketch, Vector2(40, 0)), radius: 1)
        sketch.add(.equal(small, big))
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[sketch.ends(copy).1]), Vector2(10, 20)))
        #expect(isClose(try #require(solution.radii[small]), 4))
    }

    @Test func midpoint() throws {
        var sketch = Sketch()
        let line = fixedLine(&sketch, Vector2(2, 2), Vector2(8, 6))
        let point = sketch.addPoint(.zero)
        sketch.add(.midpoint(point: point, line: line))
        #expect(isClose(try #require(try solved(sketch).points[point]), Vector2(5, 4)))
    }

    @Test func concentricMovesTheFreeCentre() throws {
        var sketch = Sketch()
        let first = sketch.addCircle(center: fixedPoint(&sketch, Vector2(3, 3)), radius: 2)
        let freeCenter = sketch.addPoint(Vector2(5, 0))
        let second = sketch.addCircle(center: freeCenter, radius: 4)
        sketch.add(.concentric(second, first))
        #expect(isClose(try #require(try solved(sketch).points[freeCenter]), Vector2(3, 3)))
    }

    @Test func symmetricAboutAVerticalLine() throws {
        var sketch = Sketch()
        let axis = fixedLine(&sketch, Vector2(5, 0), Vector2(5, 10))
        let left = fixedPoint(&sketch, Vector2(2, 3))
        let right = sketch.addPoint(Vector2(9, 5))
        sketch.add(.symmetric(left, right, about: axis))
        #expect(isClose(try #require(try solved(sketch).points[right]), Vector2(8, 3)))
    }

    @Test func fixHoldsThePointWhereItSays() throws {
        var sketch = Sketch()
        let point = sketch.addPoint(Vector2(1, 1))
        sketch.add(.fix(point, at: Vector2(-4, 2.5)))
        #expect(isClose(try #require(try solved(sketch).points[point]), Vector2(-4, 2.5)))
    }

    @Test func pointToPointAndPointToLineDistances() throws {
        var sketch = Sketch()
        let origin = fixedPoint(&sketch, .zero)
        let far = sketch.addPoint(Vector2(3, 4))
        sketch.addDimension(.distance(origin, far), value: 10)
        let line = fixedLine(&sketch, Vector2(0, -10), Vector2(10, -10))
        let above = sketch.addPoint(Vector2(4, -7))
        sketch.addDimension(.distance(line, above), value: 5)
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[far]), Vector2(6, 8)))
        // It stays on the side of the line it was drawn on.
        let solvedAbove = try #require(solution.points[above])
        #expect(isClose(solvedAbove.y, -5))
        #expect(isNear(solvedAbove, Vector2(4, -5)))
    }

    @Test func lengthRadiusAndDiameter() throws {
        var sketch = Sketch()
        let line = sketch.addLine(from: fixedPoint(&sketch, .zero), to: sketch.addPoint(Vector2(3, 4)))
        sketch.addDimension(.length(line), value: 15)
        let circle = sketch.addCircle(center: fixedPoint(&sketch, Vector2(30, 0)), radius: 2)
        sketch.addDimension(.diameter(circle), value: 9)
        let center = fixedPoint(&sketch, Vector2(50, 0))
        let start = sketch.addPoint(Vector2(53, 0))
        let arc = sketch.addArc(center: center, start: start, end: sketch.addPoint(Vector2(50, 3)))
        sketch.addDimension(.radius(arc), value: 6)
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.points[sketch.ends(line).1]), Vector2(9, 12)))
        #expect(isClose(try #require(solution.radii[circle]), 4.5))
        let (_, arcStart, arcEnd) = sketch.arcPoints(arc)
        let solvedStart = try #require(solution.points[arcStart])
        #expect(isClose((solvedStart - Vector2(50, 0)).length, 6))
        #expect(isNear(solvedStart, Vector2(56, 0)))
        // The implicit equal-radius condition carries the end point too.
        #expect(isClose((try #require(solution.points[arcEnd]) - Vector2(50, 0)).length, 6))
    }

    @Test func angleBetweenLinesKeepsItsDrawnSense() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(10, 0))
        let start = fixedPoint(&sketch, .zero)
        let up = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, 4)))
        let down = sketch.addLine(from: start, to: sketch.addPoint(Vector2(10, -4)))
        sketch.addDimension(.angle(reference, up), value: 30)
        sketch.addDimension(.angle(reference, down), value: 30)
        let solution = try solved(sketch)
        let upEnd = try #require(solution.points[sketch.ends(up).1])
        let downEnd = try #require(solution.points[sketch.ends(down).1])
        #expect(isClose(atan2(upEnd.y, upEnd.x) * 180 / .pi, 30))
        #expect(isClose(atan2(downEnd.y, downEnd.x) * 180 / .pi, -30))
    }

    @Test func referenceDimensionsMeasureWithoutDriving() throws {
        var sketch = Sketch()
        let line = sketch.addLine(from: fixedPoint(&sketch, .zero), to: fixedPoint(&sketch, Vector2(3, 4)))
        let measured = sketch.addDimension(.length(line), value: 99, isDriving: false)
        let solution = try solved(sketch)
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.measurements[measured]), 5))
    }

    /// A driving angle is met by θ or 180° − θ, depending on which way each line runs. A
    /// reference angle on the same lines reads in that same sense, nearest its stored value.
    @Test func referenceAnglesAgreeWithDrivingAnglesOnLinesDrawnBackwards() throws {
        var sketch = Sketch()
        let reference = fixedLine(&sketch, .zero, Vector2(10, 0))
        let start = fixedPoint(&sketch, Vector2(20, 0))
        let backwards = Vector2(20 + 10 * cos(212 * Double.pi / 180), 10 * sin(212 * Double.pi / 180))
        let line = sketch.addLine(from: start, to: sketch.addPoint(backwards))
        sketch.addDimension(.angle(reference, line), value: 30)
        let measured = sketch.addDimension(.angle(reference, line), value: 30, isDriving: false)
        let supplementary = sketch.addDimension(.angle(reference, line), value: 140, isDriving: false)
        let solution = try solved(sketch)
        #expect(isClose(try #require(solution.measurements[measured]), 30))
        #expect(isClose(try #require(solution.measurements[supplementary]), 150))
    }
}
```
`Tests/CreatorSketchTests/ClassicSketchTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// The spec §10 classic sketches, each fully constrained.
struct ClassicSketchTests {
    @Test func rectangleSolvesToZeroDegreesOfFreedom() throws {
        let rectangle = ConstrainedRectangle()
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .solved)
        let expected = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)]
        for (i, corner) in expected.enumerated() {
            #expect(isClose(try #require(rectangle.corner(i, in: solution)), corner))
        }
        #expect(solution.freedom.values.allSatisfy { $0 == .fixed })
    }

    /// A slot: two lines joined by two tangent semicircles of equal radius.
    struct Slot {
        var sketch = Sketch()
        let top: SketchEntityID
        let left: SketchEntityID
        let right: SketchEntityID
        let leftCenter: SketchEntityID
        let rightCenter: SketchEntityID
        let length: DimensionID

        init(length value: Double = 40, radius: Double = 5) {
            leftCenter = sketch.addPoint(Vector2(0.3, 0.2))
            rightCenter = sketch.addPoint(Vector2(value - 0.4, -0.3))
            let topLeft = sketch.addPoint(Vector2(0.2, radius + 0.3))
            let topRight = sketch.addPoint(Vector2(value + 0.3, radius - 0.2))
            let bottomRight = sketch.addPoint(Vector2(value - 0.2, -radius + 0.4))
            let bottomLeft = sketch.addPoint(Vector2(-0.3, -radius - 0.1))
            top = sketch.addLine(from: topRight, to: topLeft)
            let bottom = sketch.addLine(from: bottomLeft, to: bottomRight)
            left = sketch.addArc(center: leftCenter, start: topLeft, end: bottomLeft)
            right = sketch.addArc(center: rightCenter, start: bottomRight, end: topRight)
            for (line, arc) in [(top, left), (top, right), (bottom, left), (bottom, right)] {
                sketch.add(.tangent(line, arc))
            }
            sketch.add(.equal(left, right))
            sketch.add(.fix(leftCenter, at: .zero))
            sketch.add(.horizontal(top))
            length = sketch.addDimension(.distance(leftCenter, rightCenter), value: value)
            sketch.addDimension(.radius(left), value: radius)
        }
    }

    @Test func slotSolvesToZeroDegreesOfFreedom() throws {
        let slot = Slot()
        let solution = SketchSolver.solve(slot.sketch)
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.points[slot.rightCenter]), Vector2(40, 0)))
        let (_, topRight, topLeft) = (0, slot.sketch.ends(slot.top).0, slot.sketch.ends(slot.top).1)
        #expect(isClose(try #require(solution.points[topLeft]), Vector2(0, 5)))
        #expect(isClose(try #require(solution.points[topRight]), Vector2(40, 5)))
    }

    @Test func triangleByDimensionsIsThreeFourFive() throws {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [Vector2(0.4, 0.3), Vector2(4.5, -0.2), Vector2(3.6, 3.4)])
        let (a, b) = sketch.ends(lines[0])
        let c = sketch.ends(lines[1]).1
        sketch.add(.fix(a, at: .zero))
        sketch.add(.horizontal(lines[0]))
        sketch.addDimension(.length(lines[0]), value: 4)
        sketch.addDimension(.length(lines[1]), value: 3)
        sketch.addDimension(.length(lines[2]), value: 5)
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.points[b]), Vector2(4, 0)))
        // The right angle is at B and C stays above the base, where it was drawn.
        #expect(isClose(try #require(solution.points[c]), Vector2(4, 3)))
    }
}
```
`Tests/CreatorSketchTests/FreedomTests.swift`:
```swift
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Degrees of freedom and per-entity freedom from the rank-revealing QR (spec §4, §10).
struct FreedomTests {
    @Test func unconstrainedGeometryCountsEveryUnknown() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let line = sketch.addLine(Vector2(1, 1), Vector2(5, 1))
        let circle = sketch.addCircle(center: Vector2(9, 9), radius: 2)
        let solution = SketchSolver.solve(sketch)
        // 2 (point) + 4 (line) + 2 + 1 (circle centre and radius).
        #expect(solution.status == .underConstrained(dof: 9))
        #expect(solution.freedom[point] == .free)
        #expect(solution.freedom[line] == .free)
        #expect(solution.freedom[circle] == .free)
    }

    @Test func anchoredHorizontalLineHasOneFreedomAtItsEnd() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 1))
        let (start, end) = sketch.ends(line)
        sketch.add(.fix(start, at: .zero))
        sketch.add(.horizontal(line))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        #expect(solution.degreesOfFreedom == 1)
        #expect(solution.freedom[start] == .fixed)
        #expect(solution.freedom[end] == .free)
        #expect(solution.freedom[line] == .free)
    }

    @Test func rectangleWithoutItsHeightLeavesOnlyTheTopFree() {
        var rectangle = ConstrainedRectangle()
        rectangle.sketch.dimensions[rectangle.height] = nil
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        let (bottom, right, top, left) = (rectangle.lines[0], rectangle.lines[1], rectangle.lines[2], rectangle.lines[3])
        #expect(solution.freedom[bottom] == .fixed)
        #expect(solution.freedom[rectangle.sketch.ends(bottom).0] == .fixed)
        #expect(solution.freedom[rectangle.sketch.ends(bottom).1] == .fixed)
        #expect(solution.freedom[top] == .free)
        #expect(solution.freedom[right] == .free)
        #expect(solution.freedom[left] == .free)
    }

    @Test func pinnedLineWithALengthCanStillRotate() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(3, 4))
        let (start, end) = sketch.ends(line)
        sketch.add(.fix(start, at: .zero))
        sketch.addDimension(.length(line), value: 5)
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        #expect(solution.freedom[start] == .fixed)
        #expect(solution.freedom[end] == .free)
    }

    @Test func fixedCentreAndRadiusFixTheCircle() {
        var sketch = Sketch()
        let center = sketch.addPoint(Vector2(1, 1))
        let circle = sketch.addCircle(center: center, radius: 3)
        sketch.add(.fix(center, at: Vector2(1, 1)))
        sketch.addDimension(.diameter(circle), value: 8)
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .solved)
        #expect(solution.freedom[circle] == .fixed)
    }

    @Test func projectedGeometryIsAlwaysFixed() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        let point = sketch.addPoint(Vector2(3, 2))
        sketch.add(.pointOn(point: point, curve: edge))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .underConstrained(dof: 1))
        #expect(solution.freedom[edge] == .fixed)
        #expect(solution.freedom[point] == .free)
        #expect(isClose(solution.points[point]?.y ?? 1, 0))
    }

    @Test func mirroredArcIsNotRedundantThoughItsRadiiAreImplied() {
        // All three arc points fixed: the implicit equal-radius row is implied, not redundant.
        var sketch = Sketch()
        let points = [Vector2(0, 0), Vector2(5, 0), Vector2(0, 5)].map { position in
            let point = sketch.addPoint(position)
            sketch.add(.fix(point, at: position))
            return point
        }
        sketch.addArc(center: points[0], start: points[1], end: points[2])
        #expect(SketchSolver.solve(sketch).status == .solved)
    }

    /// Rows that hold whatever the geometry is (concentric circles that already share a centre,
    /// horizontal on a projected edge that is horizontal) are neither redundancy nor conflict.
    @Test func constraintsThatAlwaysHoldAreNotRedundant() {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        sketch.add(.fix(center, at: .zero))
        let inner = sketch.addCircle(center: center, radius: 2)
        let outer = sketch.addCircle(center: center, radius: 3)
        sketch.addDimension(.radius(inner), value: 2)
        sketch.addDimension(.radius(outer), value: 3)
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        sketch.add(.concentric(inner, outer))
        sketch.add(.horizontal(edge))
        #expect(SketchSolver.solve(sketch).status == .solved)
    }
}
```
`Tests/CreatorSketchTests/ConvergenceTests.swift`:
```swift
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// What converging means in practice: precise coincidences and idempotent re-solves.
struct ConvergenceTests {
    @Test func reSolvingASolvedSketchMovesNothing() {
        // The editor re-solves every frame; a solved sketch must not creep.
        var slot = ClassicSketchTests.Slot(length: 27, radius: 3)
        slot.sketch.dimensions = slot.sketch.dimensions.filter { $0.key != slot.length }
        let first = SketchSolver.solve(slot.sketch)
        slot.sketch.remember(first)
        var current = first
        for _ in 0..<5 {
            current = SketchSolver.solve(slot.sketch)
            slot.sketch.remember(current)
        }
        #expect(current.points == first.points)
        #expect(current.status == .underConstrained(dof: 1))
    }

    @Test func solvedCoincidentPointsAgreeToRoundOff() throws {
        // Separate corner points held by coincident constraints, with nonlinear lengths: the
        // converged solve is polished far inside the regions' 1e-9 mm merge tolerance.
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(30, 0), Vector2(18, 20)]
        let lines = (0..<3).map { i in
            let gap = Vector2(0.3 * Double(i + 1), -0.4 * Double(i))
            return sketch.addLine(corners[i] + gap, corners[(i + 1) % 3] - gap)
        }
        for i in 0..<3 { sketch.add(.coincident(sketch.ends(lines[i]).1, sketch.ends(lines[(i + 1) % 3]).0)) }
        sketch.add(.fix(sketch.ends(lines[0]).0, at: .zero))
        for (line, value) in zip(lines, [31.7, 24.3, 25]) { sketch.addDimension(.length(line), value: value) }
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status.isUsable)
        for i in 0..<3 {
            let a = try #require(solution.points[sketch.ends(lines[i]).1])
            let b = try #require(solution.points[sketch.ends(lines[(i + 1) % 3]).0])
            #expect((a - b).length < 1e-12)
        }
    }

    @Test func anEmptySketchIsSolved() {
        let solution = SketchSolver.solve(Sketch())
        #expect(solution.status == .solved)
        #expect(solution.points.isEmpty)
        #expect(solution.conflictMessages.isEmpty)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter 'CreatorSketchTests\.(PartitionTests|ConstraintFixtureTests|ClassicSketchTests|FreedomTests|ConvergenceTests)'`
Expected: compile errors, starting with `cannot find 'SketchSolver' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Solver/ComponentSystem.swift`:
```swift
/// The residual system of one connected component. Equations use global unknown columns; the
/// component varies only `columns` (sorted), and every other unknown stays at `base`.
struct ComponentSystem: Sendable {
    var terms: [SolverTerm]
    /// The global columns this component solves for, ascending.
    var columns: [Int]
    /// The full global unknown vector the component's values are written into.
    var base: [Double]
    /// Global column → local index, −1 for columns outside the component.
    private var localIndex: [Int]

    init(terms: [SolverTerm], columns: [Int], base: [Double]) {
        self.terms = terms
        self.columns = columns
        self.base = base
        var localIndex = Array(repeating: -1, count: base.count)
        for (local, global) in columns.enumerated() { localIndex[global] = local }
        self.localIndex = localIndex
    }

    var columnCount: Int { columns.count }

    /// The component's unknowns read from a global vector.
    func local(_ global: [Double]) -> [Double] { columns.map { global[$0] } }

    /// `base` with the component's unknowns replaced by `local`.
    func global(_ local: [Double]) -> [Double] {
        var x = base
        for (index, column) in columns.enumerated() { x[column] = local[index] }
        return x
    }

    func residuals(_ local: [Double]) -> [Double] {
        let x = global(local)
        return terms.flatMap { $0.equation.rows(x).map(\.value) }
    }

    /// Residuals and the dense analytic Jacobian over local columns (rows in term order).
    func evaluate(_ local: [Double]) -> (residuals: [Double], jacobian: DenseMatrix) {
        let x = global(local)
        let rows = terms.flatMap { $0.equation.rows(x) }
        var jacobian = DenseMatrix(rows: rows.count, columns: columnCount)
        for (i, row) in rows.enumerated() {
            for entry in row.entries where localIndex[entry.column] >= 0 {
                jacobian[i, localIndex[entry.column]] += entry.value
            }
        }
        return (rows.map(\.value), jacobian)
    }

    /// The row indices of each term, in term order.
    var rowRanges: [Range<Int>] {
        var start = 0
        return terms.map { term in
            defer { start += term.equation.rowCount }
            return start..<(start + term.equation.rowCount)
        }
    }

    /// The same component with only the terms that pass `isIncluded`.
    func filtered(_ isIncluded: (SolverTerm) -> Bool) -> ComponentSystem {
        ComponentSystem(terms: terms.filter(isIncluded), columns: columns, base: base)
    }

    /// The same component with extra terms appended.
    func adding(_ extra: [SolverTerm]) -> ComponentSystem {
        ComponentSystem(terms: terms + extra, columns: columns, base: base)
    }
}
```
`Sources/CreatorSketch/Solver/ComponentPartition.swift`:
```swift
/// Splits the terms into connected components over the unknowns (spec §4 step 1). Components are
/// ordered by their smallest column, which is the order of their smallest entity ID because
/// columns are assigned in ID order. Terms with no unknowns (constraints between projected edges
/// only) each form a component with no columns, after all others.
struct ComponentPartition: Sendable {
    struct Component: Sendable {
        var columns: [Int]
        var terms: [SolverTerm]
    }

    let components: [Component]

    init(terms: [SolverTerm], layout: UnknownLayout) {
        var parent = Array(0..<layout.columnCount)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let (ra, rb) = (find(a), find(b))
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        for column in layout.pointColumns.values { union(column, column + 1) }
        for term in terms {
            let columns = term.equation.columns
            for column in columns.dropFirst() { union(columns[0], column) }
        }
        var byRoot: [Int: Component] = [:]
        for column in 0..<layout.columnCount {
            byRoot[find(column), default: Component(columns: [], terms: [])].columns.append(column)
        }
        var constantOnly: [Component] = []
        for term in terms {
            if let first = term.equation.columns.first {
                byRoot[find(first)]?.terms.append(term)
            } else {
                constantOnly.append(Component(columns: [], terms: [term]))
            }
        }
        components = byRoot.keys.sorted().compactMap { byRoot[$0] } + constantOnly
    }
}
```
`Sources/CreatorSketch/Solver/LevenbergMarquardt.swift`:
```swift
/// Levenberg–Marquardt with a dense QR solve of the damped system (spec §4). Deterministic: no
/// randomness, fixed iteration order, and the same input gives bit-identical output.
enum LevenbergMarquardt {
    /// Stop when every residual is at most this (mm).
    static let residualTolerance = 1e-9
    /// Stop when a step is at most this long.
    static let stepTolerance = 1e-12
    static let iterationLimit = 200
    /// Extra steps after converging. Stopping at 1e-9 leaves coincident points up to ~1e-9 mm
    /// apart, the same as the regions' merge tolerance; one or two more (quadratically
    /// converging) steps bring them to ~1e-14, so solved loops always close.
    static let polishSteps = 2
    /// Polishing stops (or never starts) once every residual is at most this, so re-solving an
    /// already solved sketch returns its warm start bit for bit and never creeps.
    static let polishedTolerance = 1e-12

    struct Outcome: Sendable {
        var x: [Double]
        var maxResidual: Double
        var iterations: Int
    }

    static func minimize(_ system: ComponentSystem, from start: [Double]) -> Outcome {
        var x = start
        var (r, jacobian) = system.evaluate(x)
        var iterations = 0
        guard system.columnCount > 0, !r.isEmpty else {
            return Outcome(x: x, maxResidual: maxAbs(r), iterations: 0)
        }
        let n = system.columnCount
        var mu = 1e-3 * max(1e-12, maxDiagonalOfNormalMatrix(jacobian))
        var nu = 2.0
        while iterations < iterationLimit, maxAbs(r) > residualTolerance {
            iterations += 1
            // Solve [J; √μ I] δ = [−r; 0].
            let m = jacobian.rows
            var augmented = DenseMatrix(rows: m + n, columns: n)
            for i in 0..<m {
                for j in 0..<n { augmented[i, j] = jacobian[i, j] }
            }
            let damping = mu.squareRoot()
            for j in 0..<n { augmented[m + j, j] = damping }
            let rhs = r.map { -$0 } + Array(repeating: 0, count: n)
            guard let step = HouseholderQR.leastSquares(augmented, rhs) else { break }
            let stepLength = step.reduce(0) { $0 + $1 * $1 }.squareRoot()
            if stepLength <= stepTolerance { break }
            let candidate = zip(x, step).map(+)
            let candidateResiduals = system.residuals(candidate)
            let gradient = transposeTimes(jacobian, r)
            let currentCost = 0.5 * sumOfSquares(r)
            let candidateCost = 0.5 * sumOfSquares(candidateResiduals)
            var predicted = 0.0
            for j in 0..<n { predicted += step[j] * (mu * step[j] - gradient[j]) }
            predicted *= 0.5
            let rho = predicted > 0 ? (currentCost - candidateCost) / predicted : -1
            if rho > 0, candidateCost.isFinite {
                x = candidate
                (r, jacobian) = system.evaluate(x)
                let factor = 2 * rho - 1
                mu *= max(1.0 / 3.0, 1 - factor * factor * factor)
                nu = 2
            } else {
                mu *= nu
                nu *= 2
            }
        }
        if maxAbs(r) <= residualTolerance {
            polish(system, &x, &r, &jacobian)
        }
        return Outcome(x: x, maxResidual: maxAbs(r), iterations: iterations)
    }

    /// Lightly damped steps from a converged solution, each kept only if it lowers the residual.
    static func polish(_ system: ComponentSystem, _ x: inout [Double], _ r: inout [Double], _ jacobian: inout DenseMatrix) {
        let n = system.columnCount
        for _ in 0..<polishSteps where maxAbs(r) > polishedTolerance {
            let m = jacobian.rows
            var augmented = DenseMatrix(rows: m + n, columns: n)
            for i in 0..<m {
                for j in 0..<n { augmented[i, j] = jacobian[i, j] }
            }
            for j in 0..<n { augmented[m + j, j] = 1e-9 }
            let rhs = r.map { -$0 } + Array(repeating: 0, count: n)
            guard let step = HouseholderQR.leastSquares(augmented, rhs) else { return }
            let candidate = zip(x, step).map(+)
            let candidateResiduals = system.residuals(candidate)
            guard sumOfSquares(candidateResiduals) < sumOfSquares(r) else { return }
            x = candidate
            (r, jacobian) = system.evaluate(x)
        }
    }

    static func maxAbs(_ values: [Double]) -> Double {
        values.reduce(0) { max($0, abs($1)) }
    }

    static func sumOfSquares(_ values: [Double]) -> Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    static func transposeTimes(_ a: DenseMatrix, _ v: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: a.columns)
        for i in 0..<a.rows {
            for j in 0..<a.columns { result[j] += a[i, j] * v[i] }
        }
        return result
    }

    static func maxDiagonalOfNormalMatrix(_ a: DenseMatrix) -> Double {
        var best = 0.0
        for j in 0..<a.columns {
            var s = 0.0
            for i in 0..<a.rows { s += a[i, j] * a[i, j] }
            best = max(best, s)
        }
        return best
    }
}
```
`Sources/CreatorSketch/Solver/ComponentSolver.swift`:
```swift
/// Solves one component, then analyses it: degrees of freedom and free unknowns from a
/// rank-revealing QR of the Jacobian, and a minimal conflict set when it can't be satisfied or
/// its constraints are redundant (spec §4).
enum ComponentSolver {
    /// A solve whose largest residual ends at or below this (mm) satisfies its constraints. LM
    /// stops at 1e-9 when it converges; a stalled solve at a least-squares minimum of an
    /// impossible sketch leaves residuals far larger than this.
    static let satisfiedTolerance = 1e-7
    /// An unknown whose unit vector has at least this squared length outside the Jacobian's row
    /// space can still move.
    static let freeTolerance = 1e-10

    struct Outcome: Sendable {
        /// Local unknown values: the solution, or the warm start when unsatisfied.
        var x: [Double]
        var isSatisfied: Bool
        /// Conflicting sets, empty when the component is consistent and independent. Here one
        /// set holding every ref; Task 6 narrows it to minimal sets, one per conflict.
        var conflictSets: [[SketchConstraintRef]]
        var degreesOfFreedom: Int
        /// Global columns that can still move.
        var freeColumns: [Int]
    }

    static func solve(_ component: ComponentPartition.Component, base: [Double]) -> Outcome {
        let system = ComponentSystem(terms: component.terms, columns: component.columns, base: base)
        let start = system.local(base)
        let solved = LevenbergMarquardt.minimize(system, from: start)
        let isSatisfied = solved.maxResidual <= satisfiedTolerance
        let x = isSatisfied ? solved.x : start
        let analysis = analyse(system, at: x)
        // Every constraint in a component that can't be met or is redundant (Task 6 narrows
        // this to minimal sets).
        let conflictSets = !isSatisfied || analysis.isRedundant ? [refs(of: system)] : []
        return Outcome(x: x, isSatisfied: isSatisfied, conflictSets: conflictSets,
                       degreesOfFreedom: analysis.degreesOfFreedom, freeColumns: analysis.freeColumns)
    }

    struct Analysis {
        var degreesOfFreedom: Int
        var freeColumns: [Int]
        var isRedundant: Bool
    }

    /// DOF = unknowns − rank(J). An unknown is free when its unit vector leaves the row space of J
    /// (the range of Jᵀ), that is, when it touches the null space. The constraints are redundant
    /// when the user rows alone are linearly dependent; implicit rows (an arc's equal radii) may
    /// be implied by user rows without counting as redundancy.
    static func analyse(_ system: ComponentSystem, at x: [Double]) -> Analysis {
        let n = system.columnCount
        let (_, jacobian) = system.evaluate(x)
        let qr = RankRevealingQR(jacobian.transposed)
        let free = (0..<n).filter { qr.outsideSquaredNorm(ofUnitVector: $0) > freeTolerance }.map { system.columns[$0] }
        let userRows = rows(of: system) { $0.userRef != nil }
        let userRank = RankRevealingQR(jacobian.selectingRows(userRows)).rank
        return Analysis(degreesOfFreedom: n - qr.rank, freeColumns: free, isRedundant: userRank < userRows.count)
    }

    /// Indices of the Jacobian rows whose terms pass `isIncluded`.
    static func rows(of system: ComponentSystem, where isIncluded: (SolverTerm) -> Bool) -> [Int] {
        zip(system.terms, system.rowRanges).flatMap { term, range in isIncluded(term) ? Array(range) : [] }
    }

    /// The user refs of a system, each once, in term order.
    static func refs(of system: ComponentSystem) -> [SketchConstraintRef] {
        var seen = Set<SketchConstraintRef>()
        return system.terms.compactMap(\.userRef).filter { seen.insert($0).inserted }
    }
}
```
`Sources/CreatorSketch/Solver/SketchSolveStatus.swift`:
```swift
/// The outcome of a solve (spec §4).
public enum SketchSolveStatus: Hashable, Sendable {
    /// Every constraint met and no degrees of freedom left.
    case solved
    /// Every constraint met with `dof` degrees of freedom left. Still a usable output.
    case underConstrained(dof: Int)
    /// Some constraints can't all be met, or some are redundant. `conflicts` holds every
    /// minimal conflicting set found (one per independent conflict, `ConflictSearch.setLimit`
    /// at most per component), flattened, components in order.
    case overConstrained(conflicts: [SketchConstraintRef])
    /// The sketch was refused before solving (bad value or reference).
    case failed(reason: String)

    /// True for `.solved` and `.underConstrained`, whose geometry is good to output.
    public var isUsable: Bool {
        switch self {
        case .solved, .underConstrained: true
        case .overConstrained, .failed: false
        }
    }
}
```
`Sources/CreatorSketch/Solver/EntityFreedom.swift`:
```swift
/// How much an entity can still move after a solve (spec §4).
public enum EntityFreedom: Hashable, Sendable {
    /// Some of its unknowns lie in the Jacobian's null space: it can still move.
    case free
    /// Fully determined (or projected, which never moves).
    case fixed
    /// Named by a conflict.
    case conflicting
}
```
`Sources/CreatorSketch/Solver/SketchSolution.swift`:
```swift
import CreatorGeometry

/// Everything one solve produces.
public struct SketchSolution: Hashable, Sendable {
    public var status: SketchSolveStatus
    /// The position of every point entity. Components that could not be satisfied keep their
    /// warm-start positions, so callers can ghost the last good geometry.
    public var points: [SketchEntityID: Vector2]
    /// The radius of every circle entity.
    public var radii: [SketchEntityID: Double]
    /// Freedom of every entity.
    public var freedom: [SketchEntityID: EntityFreedom]
    /// One plain-language sentence per conflict set, for example
    /// "Horizontal on Line 3 conflicts with Angle d4 (30°)."
    public var conflictMessages: [String]
    /// Constraints and dimensions skipped because they touch a suspended projected edge.
    public var suspended: [SketchConstraintRef]
    /// The measured value of every reference (non-driving) dimension, in mm or degrees.
    public var measurements: [DimensionID: Double]

    /// The total degrees of freedom left (0 unless `.underConstrained`).
    public var degreesOfFreedom: Int {
        if case .underConstrained(let dof) = status { return dof }
        return 0
    }
}
```
`Sources/CreatorSketch/Solver/SketchMeasure.swift`:
```swift
import CreatorGeometry
import Foundation

/// Measures dimensions on solved geometry, for reference (non-driving) dimensions (spec §3).
///
/// Angles are between undirected lines, the same sense a driving angle uses: its residual is met
/// by θ or 180° − θ depending on which way each line was drawn (see `TermBuilder.angleTarget`).
/// So a measured angle α and 180° − α describe the same pair of lines, and the measurement reports
/// whichever is nearer the dimension's own stored value. A driving angle switched to reference
/// therefore reads back the value the user typed, however the lines run.
enum SketchMeasure {
    static func referenceValues(_ sketch: Sketch, points: [SketchEntityID: Vector2],
                                radii: [SketchEntityID: Double]) -> [DimensionID: Double] {
        var values: [DimensionID: Double] = [:]
        for (id, dimension) in sketch.dimensions where !dimension.isDriving {
            values[id] = measure(dimension.kind, sketch, points: points, radii: radii, near: dimension.value)
        }
        return values
    }

    static func measure(_ kind: DimensionKind, _ sketch: Sketch, points: [SketchEntityID: Vector2],
                        radii: [SketchEntityID: Double], near stored: Double) -> Double? {
        func line(_ id: SketchEntityID) -> (Vector2, Vector2)? {
            switch sketch.entities[id]?.kind {
            case .line(let start, let end):
                guard let a = points[start], let b = points[end] else { return nil }
                return (a, b)
            case .projected(let source):
                if case .line(let a, let b) = source.curve { return (a, b) }
                return nil
            default:
                return nil
            }
        }
        func radius(_ id: SketchEntityID) -> Double? {
            switch sketch.entities[id]?.kind {
            case .arc(let center, let start, _):
                guard let c = points[center], let s = points[start] else { return nil }
                return (s - c).length
            case .circle: return radii[id]
            case .projected(let source):
                switch source.curve {
                case .arc(_, let r, _, _), .circle(_, let r): return r
                case .line: return nil
                }
            default: return nil
            }
        }
        switch kind {
        case .distance(let a, let b):
            if let p = points[a], let q = points[b] { return (p - q).length }
            let (pointID, lineID) = points[a] != nil ? (a, b) : (b, a)
            guard let p = points[pointID], let (s, e) = line(lineID), let unit = SketchMath.normalized(e - s) else { return nil }
            return abs(SketchMath.cross(unit, p - s))
        case .length(let id):
            return line(id).map { ($0.1 - $0.0).length }
        case .radius(let id):
            return radius(id)
        case .diameter(let id):
            return radius(id).map { $0 * 2 }
        case .angle(let a, let b):
            guard let (s1, e1) = line(a), let (s2, e2) = line(b) else { return nil }
            let (d1, d2) = (e1 - s1, e2 - s2)
            let directed = abs(atan2(SketchMath.cross(d1, d2), SketchMath.dot(d1, d2))) * 180 / .pi
            let supplement = 180 - directed
            return abs(supplement - stored) < abs(directed - stored) ? supplement : directed
        }
    }
}
```
`Sources/CreatorSketch/Solver/SketchSolver.swift`:
```swift
import CreatorGeometry

/// The numeric constraint solver (spec §4): decomposition into connected components, warm start
/// from `Sketch.solved`, Levenberg–Marquardt with dense QR, rank-revealing DOF and
/// freedom analysis, and minimal conflict sets. Pure and deterministic.
public enum SketchSolver {
    /// Solves `sketch`.
    public static func solve(_ sketch: Sketch) -> SketchSolution {
        let layout = UnknownLayout(sketch)
        let x0 = layout.warmStart(sketch)
        let built: TermBuilder.Output
        do {
            built = try TermBuilder(sketch: sketch, layout: layout, x0: x0).build()
        } catch {
            return failed(sketch, layout: layout, x: x0, reason: error.reason)
        }
        let partition = ComponentPartition(terms: built.terms, layout: layout)
        var x = x0
        var conflictSets: [[SketchConstraintRef]] = []
        var freeColumns = Set<Int>()
        var dof = 0
        for component in partition.components {
            let outcome = ComponentSolver.solve(component, base: x0)
            for (local, column) in component.columns.enumerated() { x[column] = outcome.x[local] }
            conflictSets += outcome.conflictSets
            freeColumns.formUnion(outcome.freeColumns)
            dof += outcome.degreesOfFreedom
        }
        let conflicts = conflictSets.flatMap { $0 }
        let status: SketchSolveStatus = if !conflicts.isEmpty {
            .overConstrained(conflicts: conflicts)
        } else if dof > 0 {
            .underConstrained(dof: dof)
        } else {
            .solved
        }
        var solution = assemble(sketch, layout: layout, x: x, status: status, freeColumns: freeColumns, conflicts: conflicts)
        solution.conflictMessages = conflictSets.map { sketch.conflictMessage($0) }
        solution.suspended = built.suspended
        return solution
    }

    static func failed(_ sketch: Sketch, layout: UnknownLayout, x: [Double], reason: String) -> SketchSolution {
        assemble(sketch, layout: layout, x: x, status: .failed(reason: reason), freeColumns: [], conflicts: [])
    }

    static func assemble(_ sketch: Sketch, layout: UnknownLayout, x: [Double], status: SketchSolveStatus,
                         freeColumns: Set<Int>, conflicts: [SketchConstraintRef]) -> SketchSolution {
        var points: [SketchEntityID: Vector2] = [:]
        for (id, column) in layout.pointColumns { points[id] = Vector2(x[column], x[column + 1]) }
        var radii: [SketchEntityID: Double] = [:]
        for (id, column) in layout.radiusColumns { radii[id] = x[column] }
        var conflicting = Set<SketchEntityID>()
        for ref in conflicts {
            switch ref {
            case .constraint(let id): conflicting.formUnion(sketch.constraints[id]?.entities ?? [])
            case .dimension(let id): conflicting.formUnion(sketch.dimensions[id]?.kind.entities ?? [])
            }
        }
        func isFree(_ id: SketchEntityID) -> Bool {
            if let column = layout.pointColumns[id] { return freeColumns.contains(column) || freeColumns.contains(column + 1) }
            return false
        }
        var freedom: [SketchEntityID: EntityFreedom] = [:]
        for (id, entity) in sketch.entities {
            let moves: Bool = switch entity.kind {
            case .point: isFree(id)
            case .line(let start, let end): isFree(start) || isFree(end)
            case .arc(let center, let start, let end): isFree(center) || isFree(start) || isFree(end)
            case .circle(let center, _): isFree(center) || layout.radiusColumns[id].map(freeColumns.contains) == true
            case .projected: false
            }
            freedom[id] = conflicting.contains(id) ? .conflicting : moves ? .free : .fixed
        }
        let measurements = SketchMeasure.referenceValues(sketch, points: points, radii: radii)
        return SketchSolution(status: status, points: points, radii: radii, freedom: freedom, conflictMessages: [],
                              suspended: [], measurements: measurements)
    }
}
```
`Sources/CreatorSketch/Solver/Sketch+Solution.swift`:
```swift
extension Sketch {
    /// Stores a solution's positions and radii as the warm start for the next solve.
    public mutating func remember(_ solution: SketchSolution) {
        for (id, point) in solution.points where entities[id] != nil { solved[id] = .point(point) }
        for (id, radius) in solution.radii where entities[id] != nil { solved[id] = .radius(radius) }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter 'CreatorSketchTests\.(PartitionTests|ConstraintFixtureTests|ClassicSketchTests|FreedomTests|ConvergenceTests)'`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 66 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Solver/ComponentPartition.swift Sources/CreatorSketch/Solver/ComponentSolver.swift Sources/CreatorSketch/Solver/ComponentSystem.swift Sources/CreatorSketch/Solver/EntityFreedom.swift Sources/CreatorSketch/Solver/LevenbergMarquardt.swift Sources/CreatorSketch/Solver/Sketch+Solution.swift Sources/CreatorSketch/Solver/SketchMeasure.swift Sources/CreatorSketch/Solver/SketchSolution.swift Sources/CreatorSketch/Solver/SketchSolveStatus.swift Sources/CreatorSketch/Solver/SketchSolver.swift Tests/CreatorSketchTests/ClassicSketchTests.swift Tests/CreatorSketchTests/ConstraintFixtureTests.swift Tests/CreatorSketchTests/ConvergenceTests.swift Tests/CreatorSketchTests/FreedomTests.swift Tests/CreatorSketchTests/PartitionTests.swift Tests/CreatorSketchTests/Support/SketchFixtures.swift
git commit -m "feat(sketch): solve sketches with LM, components and DOF analysis"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 6: Minimal conflict sets in plain language
**Files:**
- Create: `Sources/CreatorSketch/Solver/ConflictSearch.swift`, `Tests/CreatorSketchTests/ConflictTests.swift`
- Modify: `Sources/CreatorSketch/Solver/ComponentSolver.swift`
- Test: `Tests/CreatorSketchTests/ConflictTests.swift`

**Interfaces:**
- Consumes: `ComponentSolver` (Task 5); `Sketch.conflictMessage(_:)` (Task 1).
- Consumes also: `LevenbergMarquardt.minimize`/`maxAbs`, `ComponentSystem` (Task 5).
- Produces (internal): `enum ConflictSearch { setLimit = 8; involvedFraction = 1e-3; struct Result { sets; trialSolves }; unsatisfiableSets(_:from:stalled:) -> Result; dependentSets(_:at:limit:) -> [[SketchConstraintRef]]; involved(_:refs:at:); solveRestricted(_:to:from:); ordered(_:) }`. `ComponentSolver.Outcome.conflictSets` now holds minimal sets, one per independent conflict, in member order. `SketchSolver` and `SketchSolution` are unchanged (each set already gets its own `conflictMessages` entry).

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/ConflictTests.swift`:
```swift
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Over-constrained and refused sketches: minimal conflict sets in plain language (spec §4, §10).
struct ConflictTests {
    @Test func horizontalLineAgainstAnAngleToAProjectedEdge() throws {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0))))))
        // Two unrelated lines and three dimensions first, so the names match the spec's example.
        for y in [20.0, 30.0] {
            let line = sketch.addLine(Vector2(0, y), Vector2(10, y))
            sketch.addDimension(.length(line), value: 10)
        }
        sketch.addDimension(.length(sketch.ids(ofKind: "Line")[0]), value: 10, isDriving: false)
        let line = sketch.addLine(Vector2(0, 5), Vector2(10, 6))
        let horizontal = sketch.add(.horizontal(line))
        let angle = sketch.addDimension(.angle(edge, line), value: 30)
        let drawn = sketch.position(of: sketch.ends(line).1)

        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .overConstrained(conflicts: [.constraint(horizontal), .dimension(angle)]))
        #expect(solution.conflictMessages == ["Horizontal on Line 3 conflicts with Angle d4 (30°)."])
        #expect(solution.freedom[line] == .conflicting)
        #expect(solution.freedom[edge] == .conflicting)
        // The unsatisfiable component keeps its warm start, for the ghosted last good geometry.
        #expect(solution.points[sketch.ends(line).1] == drawn)
        #expect(solution.status.isUsable == false)
    }

    @Test func redundantParallelOnARectangleIsNamedWithTheConstraintsItRepeats() {
        var rectangle = ConstrainedRectangle()
        let horizontals = rectangle.sketch.constraintIDs.filter {
            if case .horizontal = rectangle.sketch.constraints[$0] { return true }
            return false
        }
        let parallel = rectangle.sketch.add(.parallel(rectangle.lines[0], rectangle.lines[2]))
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .overConstrained(conflicts: horizontals.map(SketchConstraintRef.constraint) + [.constraint(parallel)]))
        #expect(solution.conflictMessages
            == ["Horizontal on Line 1 conflicts with Horizontal on Line 3 and Parallel on Line 1 and Line 3."])
    }

    @Test func impossibleTriangleNamesItsThreeSides() {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [.zero, Vector2(4, 0), Vector2(2, 3)])
        sketch.add(.fix(sketch.ends(lines[0]).0, at: .zero))
        sketch.add(.horizontal(lines[0]))
        let sides = [3.0, 4, 10].enumerated().map { sketch.addDimension(.length(lines[$0.offset]), value: $0.element) }
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .overConstrained(conflicts: sides.map(SketchConstraintRef.dimension)))
        #expect(solution.conflictMessages == ["Length d1 (3 mm) conflicts with Length d2 (4 mm) and Length d3 (10 mm)."])
    }

    /// A component with two independent conflicts reports one minimal set for each, so fixing
    /// the first never just uncovers the second.
    @Test func independentConflictsInOneComponentAreEachReported() {
        var rectangle = ConstrainedRectangle()
        let wide = rectangle.sketch.addDimension(.length(rectangle.lines[0]), value: 50)
        let tall = rectangle.sketch.addDimension(.length(rectangle.lines[3]), value: 30)
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.status == .overConstrained(conflicts: [.dimension(rectangle.width), .dimension(wide),
                                                               .dimension(rectangle.height), .dimension(tall)]))
        #expect(solution.conflictMessages == ["Length d1 (60 mm) conflicts with Length d3 (50 mm).",
                                              "Length d2 (40 mm) conflicts with Length d4 (30 mm)."])
    }

    @Test func independentRedundanciesInOneComponentAreEachReported() {
        var rectangle = ConstrainedRectangle()
        let parallel = rectangle.sketch.add(.parallel(rectangle.lines[0], rectangle.lines[2]))
        let sideways = rectangle.sketch.add(.parallel(rectangle.lines[1], rectangle.lines[3]))
        let solution = SketchSolver.solve(rectangle.sketch)
        #expect(solution.conflictMessages == [
            "Horizontal on Line 1 conflicts with Horizontal on Line 3 and Parallel on Line 1 and Line 3.",
            "Vertical on Line 2 conflicts with Vertical on Line 4 and Parallel on Line 2 and Line 4.",
        ])
        guard case .overConstrained(let conflicts) = solution.status else {
            Issue.record("status \(solution.status)")
            return
        }
        #expect(conflicts.contains(.constraint(parallel)))
        #expect(conflicts.contains(.constraint(sideways)))
    }

    /// A strip of squares in a row, each fully held: the leftmost edge fixed and vertical, every
    /// square's bottom, top and right edges horizontal, horizontal and vertical, every bottom 10 mm.
    static func squareStrip(_ count: Int) -> Sketch {
        var sketch = Sketch()
        var bottom = sketch.addPoint(.zero)
        var top = sketch.addPoint(Vector2(0, 10))
        sketch.add(.fix(bottom, at: .zero))
        let left = sketch.addLine(from: bottom, to: top)
        sketch.add(.vertical(left))
        sketch.addDimension(.length(left), value: 10)
        for i in 1...count {
            let nextBottom = sketch.addPoint(Vector2(Double(i) * 10 + 0.3, 0.2))
            let nextTop = sketch.addPoint(Vector2(Double(i) * 10 - 0.2, 10.1))
            let lower = sketch.addLine(from: bottom, to: nextBottom)
            let upper = sketch.addLine(from: top, to: nextTop)
            sketch.add(.horizontal(lower))
            sketch.add(.horizontal(upper))
            sketch.add(.vertical(sketch.addLine(from: nextBottom, to: nextTop)))
            sketch.addDimension(.length(lower), value: 10)
            (bottom, top) = (nextBottom, nextTop)
        }
        return sketch
    }

    /// Spec §8 re-solves every frame, so a conflict in a mid-sized sketch must not cost one trial
    /// solve per constraint. The search narrows to the refs carrying the misfit first.
    @Test func aConflictInALargeComponentIsNarrowedBeforeFiltering() throws {
        var sketch = Self.squareStrip(12)
        let firstBottom = sketch.ids(ofKind: "Line")[1]
        let conflicting = sketch.addDimension(.length(firstBottom), value: 12)
        let layout = UnknownLayout(sketch)
        let x0 = layout.warmStart(sketch)
        let terms = try TermBuilder(sketch: sketch, layout: layout, x0: x0).build().terms
        let component = try #require(ComponentPartition(terms: terms, layout: layout).components.first)
        let system = ComponentSystem(terms: component.terms, columns: component.columns, base: x0)
        let start = system.local(x0)
        let stalled = LevenbergMarquardt.minimize(system, from: start)
        let search = ConflictSearch.unsatisfiableSets(system, from: start, stalled: stalled.x)
        let original = try #require(sketch.dimensionIDs.first { $0 != conflicting && sketch.dimensions[$0]?.kind == .length(firstBottom) })
        #expect(search.sets == [[.dimension(original), .dimension(conflicting)]])
        #expect(ComponentSolver.refs(of: system).count > 40)
        #expect(search.trialSolves <= 5)
    }

    @Test func constraintOnFixedGeometryOnlyCantBeMet() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 3))))))
        let horizontal = sketch.add(.horizontal(edge))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.status == .overConstrained(conflicts: [.constraint(horizontal)]))
        #expect(solution.conflictMessages == ["Horizontal on Projected edge 1 can't be met."])
    }

    @Test func negativeLengthIsRefusedInPlainLanguage() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        sketch.addDimension(.length(line), value: -5)
        #expect(SketchSolver.solve(sketch).status == .failed(reason: "Length d1 must be greater than 0 mm, not -5 mm."))
    }

    @Test func outOfRangeAngleIsRefused() {
        var sketch = Sketch()
        let a = sketch.addLine(.zero, Vector2(10, 0))
        let b = sketch.addLine(.zero, Vector2(0, 10))
        sketch.addDimension(.angle(a, b), value: 200)
        #expect(SketchSolver.solve(sketch).status == .failed(reason: "Angle d1 must be between 0° and 180°, not 200°."))
    }

    @Test func wrongKindOfGeometryIsRefused() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let line = sketch.addLine(Vector2(1, 0), Vector2(5, 0))
        sketch.add(.tangent(point, line))
        #expect(SketchSolver.solve(sketch).status
            == .failed(reason: "Tangent on Point 1 and Line 1 needs a line and an arc or circle, or two arcs or circles."))
    }

    @Test func constraintsOnASuspendedProjectionAreSkippedNotDeleted() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(10, 0)),
                                                                     isSuspended: true))))
        let point = sketch.addPoint(Vector2(3, 2))
        let onEdge = sketch.add(.pointOn(point: point, curve: edge))
        let solution = SketchSolver.solve(sketch)
        #expect(solution.suspended == [.constraint(onEdge)])
        #expect(solution.status == .underConstrained(dof: 2))
        #expect(solution.points[point] == Vector2(3, 2))
        #expect(sketch.constraints[onEdge] != nil)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.ConflictTests`
Expected: compile errors: `cannot find 'ConflictSearch' in scope` (from `aConflictInALargeComponentIsNarrowedBeforeFiltering`). To watch the behaviour tests fail first, comment that one test out: the build then succeeds and 4 tests fail, `redundantParallelOnARectangleIsNamedWithTheConstraintsItRepeats`, `impossibleTriangleNamesItsThreeSides`, `independentConflictsInOneComponentAreEachReported` and `independentRedundanciesInOneComponentAreEachReported`, because Task 5 lists every constraint in the component, including the fix, the verticals and the dimensions, as one set. Restore the test.

- [ ] **Step 3: Implement**

Replace the whole of `Sources/CreatorSketch/Solver/ComponentSolver.swift` with the version below. It differs from Task 5's file in one place: `solve` now asks `ConflictSearch` for minimal sets (the `Outcome` doc changes to match). Then create `ConflictSearch.swift`.

`Sources/CreatorSketch/Solver/ComponentSolver.swift`:
```swift
/// Solves one component, then analyses it: degrees of freedom and free unknowns from a
/// rank-revealing QR of the Jacobian, and minimal conflict sets when it can't be satisfied or
/// its constraints are redundant (spec §4).
enum ComponentSolver {
    /// A solve whose largest residual ends at or below this (mm) satisfies its constraints. LM
    /// stops at 1e-9 when it converges; a stalled solve at a least-squares minimum of an
    /// impossible sketch leaves residuals far larger than this.
    static let satisfiedTolerance = 1e-7
    /// An unknown whose unit vector has at least this squared length outside the Jacobian's row
    /// space can still move.
    static let freeTolerance = 1e-10

    struct Outcome: Sendable {
        /// Local unknown values: the solution, or the warm start when unsatisfied.
        var x: [Double]
        var isSatisfied: Bool
        /// Minimal conflicting sets, one per independent conflict; empty when the component is
        /// consistent and independent.
        var conflictSets: [[SketchConstraintRef]]
        var degreesOfFreedom: Int
        /// Global columns that can still move.
        var freeColumns: [Int]
    }

    static func solve(_ component: ComponentPartition.Component, base: [Double]) -> Outcome {
        let system = ComponentSystem(terms: component.terms, columns: component.columns, base: base)
        let start = system.local(base)
        let solved = LevenbergMarquardt.minimize(system, from: start)
        let isSatisfied = solved.maxResidual <= satisfiedTolerance
        let x = isSatisfied ? solved.x : start
        let analysis = analyse(system, at: x)
        var conflictSets: [[SketchConstraintRef]] = []
        if !isSatisfied {
            conflictSets = ConflictSearch.unsatisfiableSets(system, from: start, stalled: solved.x).sets
        } else if analysis.isRedundant {
            conflictSets = ConflictSearch.dependentSets(system, at: x)
        }
        return Outcome(x: x, isSatisfied: isSatisfied, conflictSets: conflictSets,
                       degreesOfFreedom: analysis.degreesOfFreedom, freeColumns: analysis.freeColumns)
    }

    struct Analysis {
        var degreesOfFreedom: Int
        var freeColumns: [Int]
        var isRedundant: Bool
    }

    /// DOF = unknowns − rank(J). An unknown is free when its unit vector leaves the row space of J
    /// (the range of Jᵀ), that is, when it touches the null space. The constraints are redundant
    /// when the user rows alone are linearly dependent; implicit rows (an arc's equal radii) may
    /// be implied by user rows without counting as redundancy.
    static func analyse(_ system: ComponentSystem, at x: [Double]) -> Analysis {
        let n = system.columnCount
        let (_, jacobian) = system.evaluate(x)
        let qr = RankRevealingQR(jacobian.transposed)
        let free = (0..<n).filter { qr.outsideSquaredNorm(ofUnitVector: $0) > freeTolerance }.map { system.columns[$0] }
        let userRows = rows(of: system) { $0.userRef != nil }
        let userRank = RankRevealingQR(jacobian.selectingRows(userRows)).rank
        return Analysis(degreesOfFreedom: n - qr.rank, freeColumns: free, isRedundant: userRank < userRows.count)
    }

    /// Indices of the Jacobian rows whose terms pass `isIncluded`.
    static func rows(of system: ComponentSystem, where isIncluded: (SolverTerm) -> Bool) -> [Int] {
        zip(system.terms, system.rowRanges).flatMap { term, range in isIncluded(term) ? Array(range) : [] }
    }

    /// The user refs of a system, each once, in term order.
    static func refs(of system: ComponentSystem) -> [SketchConstraintRef] {
        var seen = Set<SketchConstraintRef>()
        return system.terms.compactMap(\.userRef).filter { seen.insert($0).inserted }
    }
}
```
`Sources/CreatorSketch/Solver/ConflictSearch.swift`:
```swift
/// Minimal conflict sets for one component (spec §4): sets of user constraints and dimensions
/// that can't all hold, or whose rows are linearly dependent. Each set is minimal (every member
/// is needed), and a component with several independent conflicts reports one set per conflict,
/// so removing every reported set leaves the component consistent and independent.
enum ConflictSearch {
    /// The most conflict sets reported for one component. Past this, the sets found are reported
    /// and the rest show up once those are fixed.
    static let setLimit = 8
    /// A row takes part in a stalled least-squares fit when its residual is at least this
    /// fraction of the largest one there.
    static let involvedFraction = 1e-3

    struct Result: Sendable {
        /// Minimal sets, each in term order (constraints by ID, then dimensions by ID), and the
        /// sets in that same order by their members.
        var sets: [[SketchConstraintRef]]
        /// How many trial solves the search ran. Tests use it to pin the narrowing.
        var trialSolves: Int
    }

    /// Conflicts of a component that can't be satisfied. `stalled` is where its solve stopped.
    ///
    /// Each round narrows before filtering: the refs whose rows still carry residual at the
    /// stalled least-squares point are where the misfit sits. If those alone can't be met
    /// (one trial solve), the deletion filter runs on them only; otherwise on everything left.
    /// Either way the filter's result is a minimal unsatisfiable set, because the filter only
    /// ever drops a member while what remains still can't be met.
    static func unsatisfiableSets(_ system: ComponentSystem, from start: [Double], stalled: [Double]) -> Result {
        var trials = 0
        func trial(_ refs: Set<SketchConstraintRef>) -> LevenbergMarquardt.Outcome {
            trials += 1
            return solveRestricted(system, to: refs, from: start)
        }
        var sets: [[SketchConstraintRef]] = []
        var remaining = ComponentSolver.refs(of: system)
        var stalledAt = stalled
        while sets.count < setLimit {
            let candidates = involved(system, refs: Set(remaining), at: stalledAt)
            var pool = remaining
            if candidates.count < remaining.count,
               trial(Set(candidates)).maxResidual > ComponentSolver.satisfiedTolerance {
                pool = candidates
            }
            var kept = pool
            for ref in pool {
                let without = Set(kept.filter { $0 != ref })
                if trial(without).maxResidual > ComponentSolver.satisfiedTolerance {
                    kept.removeAll { $0 == ref }
                }
            }
            guard !kept.isEmpty else { break }
            sets.append(kept)
            remaining.removeAll { kept.contains($0) }
            let rest = trial(Set(remaining))
            if rest.maxResidual <= ComponentSolver.satisfiedTolerance {
                // What is left can be met; it may still repeat itself.
                let dependent = dependentSets(system.filtered { term in term.userRef.map(remaining.contains) ?? true },
                                              at: rest.x, limit: setLimit - sets.count)
                sets += dependent
                break
            }
            stalledAt = rest.x
        }
        return Result(sets: ordered(sets), trialSolves: trials)
    }

    /// Conflicts of a satisfied component whose user rows are linearly dependent at `x`: a
    /// deletion filter on rank finds one minimal dependent set, which is set aside before
    /// looking for the next while the rest is still dependent.
    static func dependentSets(_ system: ComponentSystem, at x: [Double], limit: Int = setLimit) -> [[SketchConstraintRef]] {
        let (_, jacobian) = system.evaluate(x)
        func isDependent(_ refs: Set<SketchConstraintRef>) -> Bool {
            let rowIndices = ComponentSolver.rows(of: system) { term in term.userRef.map(refs.contains) ?? false }
            return RankRevealingQR(jacobian.selectingRows(rowIndices)).rank < rowIndices.count
        }
        var sets: [[SketchConstraintRef]] = []
        var remaining = ComponentSolver.refs(of: system)
        while sets.count < limit, isDependent(Set(remaining)) {
            var kept = remaining
            for ref in remaining {
                let without = Set(kept.filter { $0 != ref })
                if isDependent(without) { kept.removeAll { $0 == ref } }
            }
            guard !kept.isEmpty else { break }
            sets.append(kept)
            remaining.removeAll { kept.contains($0) }
        }
        return ordered(sets)
    }

    /// Sets in reading order: by their members, constraints before dimensions, each in ID order.
    static func ordered(_ sets: [[SketchConstraintRef]]) -> [[SketchConstraintRef]] {
        sets.sorted { $0.lexicographicallyPrecedes($1) }
    }

    /// The refs (in term order) with a row whose residual at `x` is a real part of the misfit.
    static func involved(_ system: ComponentSystem, refs: Set<SketchConstraintRef>, at x: [Double]) -> [SketchConstraintRef] {
        let residuals = system.residuals(x)
        let largest = LevenbergMarquardt.maxAbs(residuals)
        var seen = Set<SketchConstraintRef>()
        var result: [SketchConstraintRef] = []
        for (term, range) in zip(system.terms, system.rowRanges) {
            guard let ref = term.userRef, refs.contains(ref), !seen.contains(ref) else { continue }
            if range.contains(where: { abs(residuals[$0]) >= involvedFraction * largest }) {
                seen.insert(ref)
                result.append(ref)
            }
        }
        return result
    }

    /// Solves only `refs` (plus the implicit rows they reach) from `start`, varying only the
    /// columns those terms touch, so a small trial set is a small solve. The returned `x` is
    /// local to `system`, with every other column left at `start`.
    static func solveRestricted(_ system: ComponentSystem, to refs: Set<SketchConstraintRef>,
                                from start: [Double]) -> LevenbergMarquardt.Outcome {
        var terms = system.terms.filter { term in term.userRef.map(refs.contains) ?? false }
        var columns = Set(terms.flatMap(\.equation.columns))
        var implicit = system.terms.filter { $0.userRef == nil }
        while true {
            let reached = implicit.filter { $0.equation.columns.contains(where: columns.contains) }
            guard !reached.isEmpty else { break }
            terms += reached
            columns.formUnion(reached.flatMap(\.equation.columns))
            implicit.removeAll { reached.contains($0) }
        }
        let globalStart = system.global(start)
        let restricted = ComponentSystem(terms: terms, columns: columns.sorted(), base: globalStart)
        let outcome = LevenbergMarquardt.minimize(restricted, from: restricted.local(globalStart))
        return LevenbergMarquardt.Outcome(x: system.local(restricted.global(outcome.x)),
                                          maxResidual: outcome.maxResidual, iterations: outcome.iterations)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.ConflictTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 77 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Solver/ComponentSolver.swift Sources/CreatorSketch/Solver/ConflictSearch.swift Tests/CreatorSketchTests/ConflictTests.swift
git commit -m "feat(sketch): report minimal conflict sets"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 7: Drag mode, and pinning determinism and branch stability
**Files:**
- Create: `Tests/CreatorSketchTests/SolverBehaviourTests.swift`
- Modify: `Sources/CreatorSketch/Solver/ComponentSolver.swift`, `Sources/CreatorSketch/Solver/SketchSolver.swift`
- Test: `Tests/CreatorSketchTests/SolverBehaviourTests.swift`

**Interfaces:**
- Consumes: `Equation.target`, `SolverTerm.Role.drag` (Tasks 3–4); `ComponentSystem.adding(_:)` (Task 5).
- Produces: `public static func SketchSolver.solve(_ sketch: Sketch, dragging: [SketchEntityID: Vector2] = [:]) -> SketchSolution`. Existing callers compile unchanged.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/SolverBehaviourTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Warm start, determinism, branch stability and drag mode (spec §4 guarantees, §10).
struct SolverBehaviourTests {
    /// An isosceles triangle on a horizontal base fixed at the origin: base `d1`, sides 60.
    struct Triangle {
        var sketch = Sketch()
        let base: DimensionID
        let a: SketchEntityID
        let b: SketchEntityID
        let c: SketchEntityID

        init(base value: Double, apexAbove: Bool = true) {
            let lines = addPolygon(&sketch, [.zero, Vector2(value, 0), Vector2(value / 2, apexAbove ? 50 : -50)])
            (a, b) = sketch.ends(lines[0])
            c = sketch.ends(lines[1]).1
            sketch.add(.fix(a, at: .zero))
            sketch.add(.horizontal(lines[0]))
            base = sketch.addDimension(.length(lines[0]), value: value)
            sketch.addDimension(.length(lines[1]), value: 60)
            sketch.addDimension(.length(lines[2]), value: 60)
        }

        /// Positive when C is counter-clockwise of A → B (above the base).
        func orientation(_ solution: SketchSolution) -> Double {
            guard let pa = solution.points[a], let pb = solution.points[b], let pc = solution.points[c] else { return 0 }
            return SketchMath.cross(pb - pa, pc - pa)
        }
    }

    @Test func warmStartChoosesTheBranchOverTheDrawing() {
        var triangle = Triangle(base: 40)
        #expect(triangle.orientation(SketchSolver.solve(triangle.sketch)) > 0)
        // The last good solve had the apex below; the warm start wins over the drawn position.
        triangle.sketch.solved[triangle.c] = .point(Vector2(20, -50))
        #expect(triangle.orientation(SketchSolver.solve(triangle.sketch)) < 0)
    }

    @Test func twoSolvesAreBitIdentical() throws {
        let slot = ClassicSketchTests.Slot(length: 33, radius: 4)
        let first = SketchSolver.solve(slot.sketch)
        let second = SketchSolver.solve(slot.sketch)
        #expect(first == second)
        // Decoding rebuilds every dictionary; the result still doesn't change by a bit.
        let copy = try JSONDecoder().decode(Sketch.self, from: try JSONEncoder().encode(slot.sketch))
        #expect(SketchSolver.solve(copy) == first)
    }

    @Test func sweepingTheBaseNeverReflectsTheTriangle() {
        var triangle = Triangle(base: 10)
        for value in stride(from: 10.0, through: 100, by: 1) {
            triangle.sketch.dimensions[triangle.base]?.value = value
            let solution = SketchSolver.solve(triangle.sketch)
            #expect(solution.status == .solved, "base \(value)")
            #expect(triangle.orientation(solution) > 0, "base \(value)")
            triangle.sketch.remember(solution)
        }
    }

    @Test func sweepingTheSlotLengthNeverInvertsAnArc() throws {
        var slot = ClassicSketchTests.Slot(length: 10)
        let (rightCenter, rightStart, _) = slot.sketch.arcPoints(slot.right)
        for value in stride(from: 10.0, through: 100, by: 1) {
            slot.sketch.dimensions[slot.length]?.value = value
            let solution = SketchSolver.solve(slot.sketch)
            #expect(solution.status == .solved, "length \(value)")
            // The right cap runs counter-clockwise from its bottom (start) point, so its start
            // stays below its centre and the cap bulges to the right.
            let center = try #require(solution.points[rightCenter])
            let start = try #require(solution.points[rightStart])
            #expect(isClose(center.x, value), "length \(value)")
            #expect(start.y < center.y, "length \(value)")
            slot.sketch.remember(solution)
        }
    }

    @Test func draggingAFreeEndSwingsItAroundItsLength() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        sketch.add(.fix(start, at: .zero))
        sketch.addDimension(.length(line), value: 10)
        let solution = SketchSolver.solve(sketch, dragging: [end: Vector2(0, 20)])
        #expect(solution.status.isUsable)
        let moved = try #require(solution.points[end])
        #expect(isClose(moved.length, 10))
        #expect(isNear(moved, Vector2(0, 10)))
    }

    @Test func draggingAFixedPointLeavesItWhereItIs() throws {
        var sketch = Sketch()
        let point = sketch.addPoint(Vector2(2, 2))
        sketch.add(.fix(point, at: Vector2(2, 2)))
        let solution = SketchSolver.solve(sketch, dragging: [point: Vector2(50, 50)])
        #expect(solution.status == .solved)
        #expect(isClose(try #require(solution.points[point]), Vector2(2, 2)))
    }

    @Test func draggingARectangleCornerKeepsItsConstraints() throws {
        var rectangle = ConstrainedRectangle()
        rectangle.sketch.dimensions = [:]
        let corner = rectangle.sketch.ends(rectangle.lines[2]).0
        let solution = SketchSolver.solve(rectangle.sketch, dragging: [corner: Vector2(80, 55)])
        #expect(solution.status.isUsable)
        #expect(isNear(try #require(solution.points[corner]), Vector2(80, 55)))
        let corners = (0..<4).compactMap { rectangle.corner($0, in: solution) }
        #expect(corners.count == 4)
        #expect(isClose(corners[0].y, corners[1].y))
        #expect(isClose(corners[1].x, corners[2].x))
        #expect(isClose(corners[2].y, corners[3].y))
        #expect(isClose(corners[3].x, corners[0].x))
        #expect(isClose(corners[0], .zero))
    }

    @Test func draggingAnUnconstrainedPointPutsItOnTheTarget() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let solution = SketchSolver.solve(sketch, dragging: [point: Vector2(7, -3)])
        #expect(isClose(solution.points[point] ?? .zero, Vector2(7, -3)))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.SolverBehaviourTests`
Expected: compile errors: `extra argument 'dragging' in call`. Once drag mode is in, the determinism, warm-start and sweep tests pin guarantees of Task 5's code and pass straight away. To check that they can fail, temporarily make `UnknownLayout.warmStart` read only drawn positions: `warmStartChoosesTheBranchOverTheDrawing` fails. Revert before moving on.

- [ ] **Step 3: Implement**

Replace the whole of `Sources/CreatorSketch/Solver/ComponentSolver.swift`. Only the start of `solve` changes: drag terms are split out and solved in two phases.

`Sources/CreatorSketch/Solver/ComponentSolver.swift`:
```swift
/// Solves one component, then analyses it: degrees of freedom and free unknowns from a
/// rank-revealing QR of the Jacobian, and minimal conflict sets when it can't be satisfied or
/// its constraints are redundant (spec §4).
enum ComponentSolver {
    /// A solve whose largest residual ends at or below this (mm) satisfies its constraints. LM
    /// stops at 1e-9 when it converges; a stalled solve at a least-squares minimum of an
    /// impossible sketch leaves residuals far larger than this.
    static let satisfiedTolerance = 1e-7
    /// An unknown whose unit vector has at least this squared length outside the Jacobian's row
    /// space can still move.
    static let freeTolerance = 1e-10

    struct Outcome: Sendable {
        /// Local unknown values: the solution, or the warm start when unsatisfied.
        var x: [Double]
        var isSatisfied: Bool
        /// Minimal conflicting sets, one per independent conflict; empty when the component is
        /// consistent and independent.
        var conflictSets: [[SketchConstraintRef]]
        var degreesOfFreedom: Int
        /// Global columns that can still move.
        var freeColumns: [Int]
    }

    static func solve(_ component: ComponentPartition.Component, base: [Double]) -> Outcome {
        let full = ComponentSystem(terms: component.terms, columns: component.columns, base: base)
        let system = full.filtered { $0.role != .drag }
        let drags = full.terms.filter { $0.role == .drag }
        let start = system.local(base)
        var result: LevenbergMarquardt.Outcome?
        if !drags.isEmpty {
            // Drag mode (spec §4 step 4): pull towards the targets as soft rows, then restore every
            // hard constraint exactly from there, so geometry slides along its remaining freedom.
            let pulled = LevenbergMarquardt.minimize(system.adding(drags), from: start)
            let projected = LevenbergMarquardt.minimize(system, from: pulled.x)
            if projected.maxResidual <= satisfiedTolerance { result = projected }
        }
        let solved = result ?? LevenbergMarquardt.minimize(system, from: start)
        let isSatisfied = solved.maxResidual <= satisfiedTolerance
        let x = isSatisfied ? solved.x : start
        let analysis = analyse(system, at: x)
        var conflictSets: [[SketchConstraintRef]] = []
        if !isSatisfied {
            conflictSets = ConflictSearch.unsatisfiableSets(system, from: start, stalled: solved.x).sets
        } else if analysis.isRedundant {
            conflictSets = ConflictSearch.dependentSets(system, at: x)
        }
        return Outcome(x: x, isSatisfied: isSatisfied, conflictSets: conflictSets,
                       degreesOfFreedom: analysis.degreesOfFreedom, freeColumns: analysis.freeColumns)
    }

    struct Analysis {
        var degreesOfFreedom: Int
        var freeColumns: [Int]
        var isRedundant: Bool
    }

    /// DOF = unknowns − rank(J). An unknown is free when its unit vector leaves the row space of J
    /// (the range of Jᵀ), that is, when it touches the null space. The constraints are redundant
    /// when the user rows alone are linearly dependent; implicit rows (an arc's equal radii) may
    /// be implied by user rows without counting as redundancy.
    static func analyse(_ system: ComponentSystem, at x: [Double]) -> Analysis {
        let n = system.columnCount
        let (_, jacobian) = system.evaluate(x)
        let qr = RankRevealingQR(jacobian.transposed)
        let free = (0..<n).filter { qr.outsideSquaredNorm(ofUnitVector: $0) > freeTolerance }.map { system.columns[$0] }
        let userRows = rows(of: system) { $0.userRef != nil }
        let userRank = RankRevealingQR(jacobian.selectingRows(userRows)).rank
        return Analysis(degreesOfFreedom: n - qr.rank, freeColumns: free, isRedundant: userRank < userRows.count)
    }

    /// Indices of the Jacobian rows whose terms pass `isIncluded`.
    static func rows(of system: ComponentSystem, where isIncluded: (SolverTerm) -> Bool) -> [Int] {
        zip(system.terms, system.rowRanges).flatMap { term, range in isIncluded(term) ? Array(range) : [] }
    }

    /// The user refs of a system, each once, in term order.
    static func refs(of system: ComponentSystem) -> [SketchConstraintRef] {
        var seen = Set<SketchConstraintRef>()
        return system.terms.compactMap(\.userRef).filter { seen.insert($0).inserted }
    }
}
```

Replace the whole of `Sources/CreatorSketch/Solver/SketchSolver.swift`. `solve` gains `dragging:`, which adds one `.target` term per dragged point.

`Sources/CreatorSketch/Solver/SketchSolver.swift`:
```swift
import CreatorGeometry

/// The numeric constraint solver (spec §4): decomposition into connected components, warm start
/// from `Sketch.solved`, Levenberg–Marquardt with dense QR, drag mode, rank-revealing DOF and
/// freedom analysis, and minimal conflict sets. Pure and deterministic.
public enum SketchSolver {
    /// Solves `sketch`. `dragging` maps point entities to where the pointer wants them; those
    /// points become soft targets and everything else slides along its remaining freedom.
    public static func solve(_ sketch: Sketch, dragging: [SketchEntityID: Vector2] = [:]) -> SketchSolution {
        let layout = UnknownLayout(sketch)
        let x0 = layout.warmStart(sketch)
        let built: TermBuilder.Output
        do {
            built = try TermBuilder(sketch: sketch, layout: layout, x0: x0).build()
        } catch {
            return failed(sketch, layout: layout, x: x0, reason: error.reason)
        }
        let drags = dragging.keys.sorted().compactMap { id -> SolverTerm? in
            guard let column = layout.pointColumns[id], let target = dragging[id], target.isFinite else { return nil }
            return SolverTerm(role: .drag, equation: .target(.unknown(column: column), target))
        }
        let partition = ComponentPartition(terms: built.terms + drags, layout: layout)
        var x = x0
        var conflictSets: [[SketchConstraintRef]] = []
        var freeColumns = Set<Int>()
        var dof = 0
        for component in partition.components {
            let outcome = ComponentSolver.solve(component, base: x0)
            for (local, column) in component.columns.enumerated() { x[column] = outcome.x[local] }
            conflictSets += outcome.conflictSets
            freeColumns.formUnion(outcome.freeColumns)
            dof += outcome.degreesOfFreedom
        }
        let conflicts = conflictSets.flatMap { $0 }
        let status: SketchSolveStatus = if !conflicts.isEmpty {
            .overConstrained(conflicts: conflicts)
        } else if dof > 0 {
            .underConstrained(dof: dof)
        } else {
            .solved
        }
        var solution = assemble(sketch, layout: layout, x: x, status: status, freeColumns: freeColumns, conflicts: conflicts)
        solution.conflictMessages = conflictSets.map { sketch.conflictMessage($0) }
        solution.suspended = built.suspended
        return solution
    }

    static func failed(_ sketch: Sketch, layout: UnknownLayout, x: [Double], reason: String) -> SketchSolution {
        assemble(sketch, layout: layout, x: x, status: .failed(reason: reason), freeColumns: [], conflicts: [])
    }

    static func assemble(_ sketch: Sketch, layout: UnknownLayout, x: [Double], status: SketchSolveStatus,
                         freeColumns: Set<Int>, conflicts: [SketchConstraintRef]) -> SketchSolution {
        var points: [SketchEntityID: Vector2] = [:]
        for (id, column) in layout.pointColumns { points[id] = Vector2(x[column], x[column + 1]) }
        var radii: [SketchEntityID: Double] = [:]
        for (id, column) in layout.radiusColumns { radii[id] = x[column] }
        var conflicting = Set<SketchEntityID>()
        for ref in conflicts {
            switch ref {
            case .constraint(let id): conflicting.formUnion(sketch.constraints[id]?.entities ?? [])
            case .dimension(let id): conflicting.formUnion(sketch.dimensions[id]?.kind.entities ?? [])
            }
        }
        func isFree(_ id: SketchEntityID) -> Bool {
            if let column = layout.pointColumns[id] { return freeColumns.contains(column) || freeColumns.contains(column + 1) }
            return false
        }
        var freedom: [SketchEntityID: EntityFreedom] = [:]
        for (id, entity) in sketch.entities {
            let moves: Bool = switch entity.kind {
            case .point: isFree(id)
            case .line(let start, let end): isFree(start) || isFree(end)
            case .arc(let center, let start, let end): isFree(center) || isFree(start) || isFree(end)
            case .circle(let center, _): isFree(center) || layout.radiusColumns[id].map(freeColumns.contains) == true
            case .projected: false
            }
            freedom[id] = conflicting.contains(id) ? .conflicting : moves ? .free : .fixed
        }
        let measurements = SketchMeasure.referenceValues(sketch, points: points, radii: radii)
        return SketchSolution(status: status, points: points, radii: radii, freedom: freedom, conflictMessages: [],
                              suspended: [], measurements: measurements)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.SolverBehaviourTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 85 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Solver/ComponentSolver.swift Sources/CreatorSketch/Solver/SketchSolver.swift Tests/CreatorSketchTests/SolverBehaviourTests.swift
git commit -m "feat(sketch): add drag mode; pin determinism and branch stability"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 8: Curve shapes and exact intersections
**Files:**
- Create: `Sources/CreatorSketch/Geometry/CurveShape.swift`, `Sources/CreatorSketch/Geometry/CurveIntersection.swift`, `Sources/CreatorSketch/Geometry/SketchCurve.swift`, `Sources/CreatorSketch/Geometry/Sketch+Curves.swift`, `Tests/CreatorSketchTests/IntersectionTests.swift`
- Test: `Tests/CreatorSketchTests/IntersectionTests.swift`

**Interfaces:**
- Consumes: `SketchMath` (Task 3); `Sketch.position(of:)`, `radius(of:)` (Task 1).
- Produces (internal):
  - `enum CurveShape { .line(Vector2, Vector2), .arc(center:radius:start:sweep:) }` (counter-clockwise, sweep in (0, 2π], 2π a full circle) with `fullTurn`, `isFullCircle`, `parameterEnd`, `point(at:)`, `startPoint`, `endPoint`, `parameter(of:)`, `nearestParameter(to:)`, `length(from:to:)`, `contains(_:tolerance:)`, `tangent(at:)`, `curvature`, `piece(from:to:)`
  - `enum CurveIntersection { static let tolerance = 1e-9; points(_:_:) -> [Vector2]; lineLine; lineCircle; circleCircle }`
  - `struct SketchCurve { source: SketchEntityID; shape: CurveShape }`
  - `Sketch.shape(of:) -> CurveShape?` (nil for points, suspended projections and degenerate curves) and `Sketch.curves(includingConstruction:) -> [SketchCurve]` (in ID order)

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/IntersectionTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Exact curve intersections and curve-shape helpers (spec §5 step 2).
struct IntersectionTests {
    func circle(_ center: Vector2, _ radius: Double) -> CurveShape {
        .arc(center: center, radius: radius, start: 0, sweep: 2 * .pi)
    }

    func sorted(_ points: [Vector2]) -> [Vector2] {
        points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    @Test func crossingLinesMeetOnce() {
        let points = CurveIntersection.points(.line(.zero, Vector2(10, 10)), .line(Vector2(0, 10), Vector2(10, 0)))
        #expect(points.count == 1)
        #expect(isClose(points[0], Vector2(5, 5), tolerance: 1e-12))
    }

    @Test func linesThatWouldCrossBeyondTheirEndsDoNot() {
        #expect(CurveIntersection.points(.line(.zero, Vector2(4, 0)), .line(Vector2(5, -1), Vector2(5, 1))).isEmpty)
    }

    @Test func parallelLinesNeverMeet() {
        #expect(CurveIntersection.points(.line(.zero, Vector2(10, 0)), .line(Vector2(0, 1), Vector2(10, 1))).isEmpty)
    }

    @Test func overlappingCollinearLinesMeetAtTheOverlapEnds() {
        let points = CurveIntersection.points(.line(.zero, Vector2(10, 0)), .line(Vector2(4, 0), Vector2(15, 0)))
        #expect(sorted(points) == [Vector2(4, 0), Vector2(10, 0)])
    }

    @Test func aTJunctionMeetsAtTheStemsEnd() {
        let points = CurveIntersection.points(.line(.zero, Vector2(10, 0)), .line(Vector2(3, 0), Vector2(3, 7)))
        #expect(points == [Vector2(3, 0)])
    }

    @Test func lineThroughACircleMeetsItTwice() {
        let points = sorted(CurveIntersection.points(.line(Vector2(-10, 3), Vector2(10, 3)), circle(.zero, 5)))
        #expect(points.count == 2)
        #expect(isClose(points[0], Vector2(-4, 3), tolerance: 1e-12))
        #expect(isClose(points[1], Vector2(4, 3), tolerance: 1e-12))
    }

    @Test func tangentLineTouchesOnce() {
        let points = CurveIntersection.points(.line(Vector2(-10, 5), Vector2(10, 5)), circle(.zero, 5))
        #expect(points.count == 1)
        #expect(isClose(points[0], Vector2(0, 5), tolerance: 1e-12))
    }

    @Test func anArcOnlyMeetsWithinItsSpan() {
        // The upper half only: the line y = −3 misses it; y = 3 meets it twice.
        let upper = CurveShape.arc(center: .zero, radius: 5, start: 0, sweep: .pi)
        #expect(CurveIntersection.points(.line(Vector2(-10, -3), Vector2(10, -3)), upper).isEmpty)
        #expect(CurveIntersection.points(.line(Vector2(-10, 3), Vector2(10, 3)), upper).count == 2)
    }

    @Test func circlesMeetTwiceOnceOrNever() {
        let two = sorted(CurveIntersection.points(circle(.zero, 5), circle(Vector2(8, 0), 5)))
        #expect(two.count == 2)
        #expect(isClose(two[0], Vector2(4, -3), tolerance: 1e-12))
        #expect(isClose(two[1], Vector2(4, 3), tolerance: 1e-12))
        let touching = CurveIntersection.points(circle(.zero, 3), circle(Vector2(5, 0), 2))
        #expect(touching.count == 1)
        #expect(isClose(touching[0], Vector2(3, 0), tolerance: 1e-12))
        #expect(CurveIntersection.points(circle(.zero, 5), circle(Vector2(1, 0), 1)).isEmpty)
        #expect(CurveIntersection.points(circle(.zero, 5), circle(.zero, 3)).isEmpty)
    }

    @Test func coCircularArcsMeetAtTheirOverlapEnds() {
        let first = CurveShape.arc(center: .zero, radius: 5, start: 0, sweep: .pi)
        let second = CurveShape.arc(center: .zero, radius: 5, start: .pi / 2, sweep: .pi)
        let points = sorted(CurveIntersection.points(first, second))
        #expect(points.count == 2)
        #expect(isClose(points[0], Vector2(-5, 0), tolerance: 1e-9))
        #expect(isClose(points[1], Vector2(0, 5), tolerance: 1e-9))
    }

    @Test func shapeParametersAndPieces() {
        let arc = CurveShape.arc(center: Vector2(1, 1), radius: 2, start: .pi / 2, sweep: .pi)
        #expect(isClose(arc.startPoint, Vector2(1, 3), tolerance: 1e-12))
        #expect(isClose(arc.endPoint, Vector2(1, -1), tolerance: 1e-12))
        #expect(isClose(arc.parameter(of: Vector2(-1, 1)), .pi / 2, tolerance: 1e-12))
        // A point outside the span clamps to the nearer end.
        #expect(arc.nearestParameter(to: Vector2(3, 1.5)) == 0)
        #expect(arc.contains(Vector2(-1, 1), tolerance: 1e-9))
        #expect(!arc.contains(Vector2(3, 1), tolerance: 1e-9))
        let piece = CurveShape.line(.zero, Vector2(10, 0)).piece(from: 0.2, to: 0.5)
        #expect(piece == .line(Vector2(2, 0), Vector2(5, 0)))
        #expect(isClose(arc.tangent(at: 0), Vector2(-1, 0), tolerance: 1e-12))
    }

    @Test func sketchShapesComeFromCurrentPositions() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(0, 5))
        // From 90° counter-clockwise round to 0°: a three-quarter arc.
        let arc = sketch.addArc(center: center, start: start, end: sketch.addPoint(Vector2(5, 0)))
        guard case .arc(_, let radius, let from, let sweep)? = sketch.shape(of: arc) else {
            Issue.record("no arc shape")
            return
        }
        #expect(radius == 5)
        #expect(isClose(from, .pi / 2, tolerance: 1e-12))
        #expect(isClose(sweep, 3 * .pi / 2, tolerance: 1e-12))
        sketch.solved[start] = .point(Vector2(-5, 0))
        guard case .arc(_, _, _, let moved)? = sketch.shape(of: arc) else {
            Issue.record("no arc shape")
            return
        }
        #expect(isClose(moved, .pi, tolerance: 1e-12))
        let suspended = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0)),
                                                                          isSuspended: true))))
        #expect(sketch.shape(of: suspended) == nil)
        #expect(sketch.shape(of: center) == nil)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.IntersectionTests`
Expected: compile errors, starting with `cannot find 'CurveIntersection' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Geometry/CurveShape.swift`:
```swift
import CreatorGeometry
import Foundation

/// A curve in plane coordinates, as regions and commands see it.
enum CurveShape: Hashable, Sendable {
    case line(Vector2, Vector2)
    /// A counter-clockwise arc from polar angle `start` (radians) through `sweep` in (0, 2π].
    /// A sweep of exactly 2π is a full circle.
    case arc(center: Vector2, radius: Double, start: Double, sweep: Double)

    static let fullTurn = 2 * Double.pi

    var isFullCircle: Bool {
        if case .arc(_, _, _, let sweep) = self { return sweep >= Self.fullTurn }
        return false
    }

    /// Parameters run over [0, 1] on a line and over [0, sweep] (radians from `start`) on an arc.
    var parameterEnd: Double {
        switch self {
        case .line: 1
        case .arc(_, _, _, let sweep): sweep
        }
    }

    func point(at parameter: Double) -> Vector2 {
        switch self {
        case .line(let a, let b): a + (b - a) * parameter
        case .arc(let center, let radius, let start, _): SketchMath.point(on: center, radius: radius, at: start + parameter)
        }
    }

    var startPoint: Vector2 { point(at: 0) }
    var endPoint: Vector2 { point(at: parameterEnd) }

    /// The parameter of the point on the curve's line or circle nearest `p`: unclamped along a
    /// line, in [0, 2π) around an arc.
    func parameter(of p: Vector2) -> Double {
        switch self {
        case .line(let a, let b):
            let d = b - a
            let squared = SketchMath.dot(d, d)
            return squared > 0 ? SketchMath.dot(p - a, d) / squared : 0
        case .arc(let center, _, let start, _):
            return SketchMath.wrapped(SketchMath.angle(p - center) - start)
        }
    }

    /// The parameter, clamped to the curve, of the curve point nearest `p`.
    func nearestParameter(to p: Vector2) -> Double {
        let t = parameter(of: p)
        switch self {
        case .line:
            return min(max(t, 0), 1)
        case .arc(_, _, _, let sweep):
            if t <= sweep { return t }
            // Outside the span: the nearer end, measured around the circle.
            return (t - sweep) <= (Self.fullTurn - t) ? sweep : 0
        }
    }

    /// The length of a parameter interval, in mm.
    func length(from t0: Double, to t1: Double) -> Double {
        switch self {
        case .line(let a, let b): (b - a).length * abs(t1 - t0)
        case .arc(_, let radius, _, _): radius * abs(t1 - t0)
        }
    }

    /// True when `p` lies on the curve within `tolerance` mm.
    func contains(_ p: Vector2, tolerance: Double) -> Bool {
        switch self {
        case .line(let a, let b):
            let t = nearestParameter(to: p)
            return (point(at: t) - p).length <= tolerance && (b - a).length > 0
        case .arc(let center, let radius, _, let sweep):
            guard abs((p - center).length - radius) <= tolerance else { return false }
            if isFullCircle { return true }
            let t = parameter(of: p)
            let slack = radius > 0 ? tolerance / radius : 0
            return t <= sweep + slack || t >= Self.fullTurn - slack
        }
    }

    /// The unit tangent in the direction of increasing parameter at `parameter`.
    func tangent(at parameter: Double) -> Vector2 {
        switch self {
        case .line(let a, let b):
            return SketchMath.normalized(b - a) ?? Vector2(1, 0)
        case .arc(_, _, let start, _):
            let angle = start + parameter
            return Vector2(-sin(angle), cos(angle))
        }
    }

    /// The signed curvature in the direction of increasing parameter (left turns positive).
    var curvature: Double {
        switch self {
        case .line: 0
        case .arc(_, let radius, _, _): radius > 0 ? 1 / radius : 0
        }
    }

    /// The piece between two parameters, `t0 < t1`.
    func piece(from t0: Double, to t1: Double) -> CurveShape {
        switch self {
        case .line: .line(point(at: t0), point(at: t1))
        case .arc(let center, let radius, let start, _): .arc(center: center, radius: radius, start: start + t0, sweep: t1 - t0)
        }
    }
}
```
`Sources/CreatorSketch/Geometry/CurveIntersection.swift`:
```swift
import CreatorGeometry
import Foundation

/// Exact line/line, line/arc and arc/arc intersections (spec §5 step 2). Overlapping collinear or
/// co-circular spans report the endpoints of each that lie on the other, which is where the
/// spans must be split for their pieces to merge.
enum CurveIntersection {
    /// Points closer than this are the same point (mm).
    static let tolerance = 1e-9

    /// The points where `a` and `b` meet, without duplicates, in a fixed order.
    static func points(_ a: CurveShape, _ b: CurveShape) -> [Vector2] {
        var found: [Vector2] = []
        switch (a, b) {
        case (.line(let p, let q), .line(let r, let s)):
            found = lineLine(p, q, r, s)
        case (.line(let p, let q), .arc(let center, let radius, _, _)), (.arc(let center, let radius, _, _), .line(let p, let q)):
            found = lineCircle(p, q, center, radius)
        case (.arc(let c1, let r1, _, _), .arc(let c2, let r2, _, _)):
            found = circleCircle(c1, r1, c2, r2)
        }
        // Endpoints touching the other curve: T-junctions, overlaps and tangent touches whose
        // computed point drifted by rounding.
        found += [a.startPoint, a.endPoint].filter { b.contains($0, tolerance: tolerance) }
        found += [b.startPoint, b.endPoint].filter { a.contains($0, tolerance: tolerance) }
        var unique: [Vector2] = []
        for point in found where a.contains(point, tolerance: tolerance * 10) && b.contains(point, tolerance: tolerance * 10) {
            if !unique.contains(where: { ($0 - point).length <= tolerance }) { unique.append(point) }
        }
        return unique
    }

    /// The crossing of two segments' lines, when they are not parallel.
    static func lineLine(_ p: Vector2, _ q: Vector2, _ r: Vector2, _ s: Vector2) -> [Vector2] {
        let (d1, d2) = (q - p, s - r)
        let denominator = SketchMath.cross(d1, d2)
        guard abs(denominator) > 1e-15 * max(1, d1.length * d2.length) else { return [] }
        let t = SketchMath.cross(r - p, d2) / denominator
        return [p + d1 * t]
    }

    /// Where the infinite line through p, q meets the circle: two points, or one when tangent.
    static func lineCircle(_ p: Vector2, _ q: Vector2, _ center: Vector2, _ radius: Double) -> [Vector2] {
        guard let unit = SketchMath.normalized(q - p) else { return [] }
        let foot = p + unit * SketchMath.dot(center - p, unit)
        let h = (center - foot).length
        if h > radius + tolerance { return [] }
        if abs(h - radius) <= tolerance { return [foot] }
        let half = (radius * radius - h * h).squareRoot()
        return [foot - unit * half, foot + unit * half]
    }

    /// Where two circles meet: two points, one when tangent, none when apart, nested or concentric.
    static func circleCircle(_ c1: Vector2, _ r1: Double, _ c2: Vector2, _ r2: Double) -> [Vector2] {
        let d = (c2 - c1).length
        guard d > tolerance else { return [] }
        if d > r1 + r2 + tolerance || d < abs(r1 - r2) - tolerance { return [] }
        let unit = (c2 - c1) * (1 / d)
        let a = (d * d + r1 * r1 - r2 * r2) / (2 * d)
        let base = c1 + unit * a
        let hSquared = r1 * r1 - a * a
        if hSquared <= tolerance * tolerance { return [base] }
        let h = hSquared.squareRoot()
        let normal = SketchMath.perpendicular(unit)
        return [base + normal * h, base - normal * h]
    }
}
```
`Sources/CreatorSketch/Geometry/SketchCurve.swift`:
```swift
/// A curve of the solved sketch plus the entity it came from.
struct SketchCurve: Hashable, Sendable {
    var source: SketchEntityID
    var shape: CurveShape
}
```
`Sources/CreatorSketch/Geometry/Sketch+Curves.swift`:
```swift
import CreatorGeometry

extension Sketch {
    /// The current shape of a line, arc, circle or projected edge (from `solved`, else drawn),
    /// or `nil` for points, suspended projections and degenerate curves.
    func shape(of id: SketchEntityID) -> CurveShape? {
        switch entities[id]?.kind {
        case .line(let start, let end):
            guard let a = position(of: start), let b = position(of: end), (b - a).length > CurveIntersection.tolerance else { return nil }
            return .line(a, b)
        case .arc(let center, let start, let end):
            guard let c = position(of: center), let s = position(of: start), let e = position(of: end) else { return nil }
            let radius = (s - c).length
            let from = SketchMath.angle(s - c)
            let sweep = SketchMath.wrapped(SketchMath.angle(e - c) - from)
            guard radius > CurveIntersection.tolerance, sweep * radius > CurveIntersection.tolerance else { return nil }
            return .arc(center: c, radius: radius, start: from, sweep: sweep)
        case .circle(let center, _):
            guard let c = position(of: center), let radius = radius(of: id), radius > CurveIntersection.tolerance else { return nil }
            return .arc(center: c, radius: radius, start: 0, sweep: CurveShape.fullTurn)
        case .projected(let source):
            guard !source.isSuspended else { return nil }
            switch source.curve {
            case .line(let a, let b):
                return (b - a).length > CurveIntersection.tolerance ? .line(a, b) : nil
            case .arc(let center, let radius, let start, let end):
                let sweep = end.radians - start.radians
                guard radius > 0, sweep > 0 else { return nil }
                return .arc(center: center, radius: radius, start: start.radians, sweep: min(sweep, CurveShape.fullTurn))
            case .circle(let center, let radius):
                return radius > 0 ? .arc(center: center, radius: radius, start: 0, sweep: CurveShape.fullTurn) : nil
            }
        default:
            return nil
        }
    }

    /// Every curve in ID order, optionally leaving out construction geometry.
    func curves(includingConstruction: Bool) -> [SketchCurve] {
        entityIDs.compactMap { id in
            guard let entity = entities[id], includingConstruction || !entity.isConstruction,
                  let shape = shape(of: id) else { return nil }
            return SketchCurve(source: id, shape: shape)
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.IntersectionTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 97 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Geometry/CurveIntersection.swift Sources/CreatorSketch/Geometry/CurveShape.swift Sources/CreatorSketch/Geometry/Sketch+Curves.swift Sources/CreatorSketch/Geometry/SketchCurve.swift Tests/CreatorSketchTests/IntersectionTests.swift
git commit -m "feat(sketch): add curve shapes and exact intersections"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 9: Regions: split, walk faces, nest, order
**Files:**
- Create: `Sources/CreatorSketch/Regions/LoopSegment.swift`, `Sources/CreatorSketch/Regions/LoopMeasure.swift`, `Sources/CreatorSketch/Regions/RegionGraph.swift`, `Sources/CreatorSketch/Regions/HalfEdge.swift`, `Sources/CreatorSketch/Regions/RegionGraph+Faces.swift`, `Sources/CreatorSketch/Regions/SketchRegion.swift`, `Sources/CreatorSketch/Regions/SketchRegionResult.swift`, `Sources/CreatorSketch/Regions/SketchRegions.swift`, `Tests/CreatorSketchTests/LoopMeasureTests.swift`, `Tests/CreatorSketchTests/RegionTests.swift`
- Test: `Tests/CreatorSketchTests/LoopMeasureTests.swift`, `Tests/CreatorSketchTests/RegionTests.swift`

**Interfaces:**
- Consumes: `CurveShape`, `CurveIntersection`, `Sketch.curves(includingConstruction:)` (Task 8); `SketchSolver`, `Sketch.remember` (Task 5), used in tests.
- Produces:
  - `public struct SketchRegion { outer: [Segment2D]; holes: [[Segment2D]]; area; centroid; profile(on: Plane) -> Profile2D }`. The profile is the outer loop only until S3.
  - `public struct SketchRegionResult { regions; openCurves: [SketchEntityID]; warning: String? }`
  - `public enum SketchRegions { static func find(in sketch: Sketch) -> SketchRegionResult }`
  - internal `LoopSegment` (traversal-ordered, exact `start`/`end` vertices, `merged(with:)`), `LoopMeasure.area/moments/contains`, `RegionGraph`, `HalfEdge`, `RegionGraph.faceCycles()/componentLabels()/loop(_:)`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/LoopMeasureTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Exact loop area, moments and containment (Green's theorem), the basis of nesting and order.
struct LoopMeasureTests {
    func line(_ a: Vector2, _ b: Vector2) -> LoopSegment { LoopSegment(geometry: .line(a, b), source: 0) }
    func arc(_ c: Vector2, _ r: Double, _ from: Double, _ to: Double) -> LoopSegment {
        LoopSegment(geometry: .arc(center: c, radius: r, from: from, to: to), source: 0)
    }

    /// The upper half disk of radius 3, with the arc's ends at the exact vertices (±3, 0).
    var halfDisk: [LoopSegment] {
        [LoopSegment(geometry: .arc(center: .zero, radius: 3, from: 0, to: .pi), source: 0, start: Vector2(3, 0), end: Vector2(-3, 0)),
         line(Vector2(-3, 0), Vector2(3, 0))]
    }

    var square: [LoopSegment] {
        [line(.zero, Vector2(4, 0)), line(Vector2(4, 0), Vector2(4, 4)), line(Vector2(4, 4), Vector2(0, 4)), line(Vector2(0, 4), .zero)]
    }

    @Test func squareAreaAndCentroid() {
        #expect(LoopMeasure.area(square) == 16)
        #expect(LoopMeasure.moments(square) == Vector2(32, 32))
        #expect(LoopMeasure.area(square.reversed().map { segment in
            guard case .line(let a, let b) = segment.geometry else { return segment }
            return line(b, a)
        }) == -16)
    }

    @Test func offCentreCircleAreaAndCentroid() {
        let disk = [arc(Vector2(3, -2), 2, 0, 2 * .pi)]
        #expect(isClose(LoopMeasure.area(disk), 4 * .pi, tolerance: 1e-12))
        let moments = LoopMeasure.moments(disk)
        #expect(isClose(moments * (1 / LoopMeasure.area(disk)), Vector2(3, -2), tolerance: 1e-12))
        // Clockwise, the same circle has negative area.
        #expect(isClose(LoopMeasure.area([arc(Vector2(3, -2), 2, 2 * .pi, 0)]), -4 * .pi, tolerance: 1e-12))
    }

    @Test func halfDiskCentroidIsFourROverThreePi() {
        let half = halfDisk
        let area = LoopMeasure.area(half)
        #expect(isClose(area, 4.5 * .pi, tolerance: 1e-12))
        let centroid = LoopMeasure.moments(half) * (1 / area)
        #expect(isClose(centroid, Vector2(0, 4 * 3 / (3 * .pi)), tolerance: 1e-12))
    }

    @Test func containmentFollowsArcsExactly() {
        let half = halfDisk
        #expect(LoopMeasure.contains(half, Vector2(0, 2.9)))
        #expect(!LoopMeasure.contains(half, Vector2(0, 3.1)))
        #expect(!LoopMeasure.contains(half, Vector2(0, -0.1)))
        // Level with the arc's start: the half-open rule counts the vertex once.
        #expect(!LoopMeasure.contains(half, Vector2(-4, 0)))
        #expect(LoopMeasure.contains(square, Vector2(2, 2)))
        #expect(!LoopMeasure.contains(square, Vector2(5, 2)))
    }
}
```
`Tests/CreatorSketchTests/RegionTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

/// Region finding (spec §5, §10). Areas and centroids are analytic.
struct RegionTests {
    func square(_ sketch: inout Sketch, x: Double = 0, y: Double = 0, side: Double, isConstruction: Bool = false) {
        addPolygon(&sketch, [Vector2(x, y), Vector2(x + side, y), Vector2(x + side, y + side), Vector2(x, y + side)],
                   isConstruction: isConstruction)
    }

    @Test func squareWithACircularHoleIsOneRegionWithOneHole() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        sketch.addCircle(center: Vector2(5, 5), radius: 2)
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.count == 1)
        let region = try #require(result.regions.first)
        #expect(region.outer.count == 4)
        #expect(region.holes.count == 1)
        #expect(isClose(region.area, 100 - 4 * .pi))
        #expect(isClose(region.centroid, Vector2(5, 5)))
        // The hole is the whole circle in one clockwise arc.
        let hole = try #require(region.holes.first)
        #expect(hole.count == 1)
        guard case .arc(let center, let radius, let start, let end) = hole[0] else { Issue.record("hole is not an arc"); return }
        #expect(isClose(center, Vector2(5, 5)))
        #expect(radius == 2)
        #expect(isClose(end.radians - start.radians, -2 * .pi))
        #expect(result.warning == nil)
    }

    @Test func anIslandInsideAHoleIsASecondRegion() throws {
        var sketch = Sketch()
        square(&sketch, side: 20)
        sketch.addCircle(center: Vector2(10, 10), radius: 6)
        square(&sketch, x: 8, y: 8, side: 4)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 400 - 36 * .pi))
        #expect(regions[0].holes.count == 1)
        #expect(isClose(regions[1].area, 16))
        #expect(regions[1].holes.isEmpty)
    }

    @Test func overlappingSquaresSplitIntoThreeRegions() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        square(&sketch, x: 5, y: 5, side: 10)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.map(\.area).map { ($0 * 1e6).rounded() / 1e6 } == [75, 75, 25])
        // Equal areas order by centroid x: the lower-left L first.
        #expect(isClose(regions[0].centroid, Vector2(312.5 / 75, 312.5 / 75)))
        #expect(isClose(regions[1].centroid, Vector2(812.5 / 75, 812.5 / 75)))
        #expect(isClose(regions[2].centroid, Vector2(7.5, 7.5)))
    }

    @Test func squaresSharingPartOfAnEdgeGiveTwoRegions() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        addPolygon(&sketch, [Vector2(10, 0), Vector2(20, 0), Vector2(20, 5), Vector2(10, 5)])
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 100))
        #expect(isClose(regions[1].area, 50))
    }

    @Test func aLineAcrossASquareSplitsItInTwo() {
        var sketch = Sketch()
        square(&sketch, side: 10)
        sketch.addLine(Vector2(-5, 4), Vector2(15, 4))
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.map(\.area).map { ($0 * 1e6).rounded() / 1e6 } == [60, 40])
        // The overhanging ends are dangling, but the line still bounds regions.
        #expect(result.openCurves.isEmpty)
    }

    @Test func externallyTangentCirclesAreTwoRegions() throws {
        var sketch = Sketch()
        sketch.addCircle(center: .zero, radius: 3)
        sketch.addCircle(center: Vector2(5, 0), radius: 2)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 9 * .pi))
        #expect(isClose(regions[1].area, 4 * .pi))
    }

    @Test func internallyTangentCirclesAreACrescentAndADisk() throws {
        var sketch = Sketch()
        sketch.addCircle(center: .zero, radius: 4)
        sketch.addCircle(center: Vector2(2, 0), radius: 2)
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        #expect(isClose(regions[0].area, 12 * .pi))
        #expect(isClose(regions[1].area, 4 * .pi))
        #expect(regions.allSatisfy { $0.holes.isEmpty })
    }

    @Test func constructionGeometryIsIgnored() throws {
        var sketch = Sketch()
        square(&sketch, side: 50, isConstruction: true)
        sketch.addCircle(center: Vector2(25, 25), radius: 5)
        let result = SketchRegions.find(in: sketch)
        try #require(result.regions.count == 1)
        #expect(isClose(result.regions[0].area, 25 * .pi))
        #expect(result.openCurves.isEmpty)
    }

    @Test func openCurvesProduceAWarning() {
        var sketch = Sketch()
        square(&sketch, side: 10)
        let spur = sketch.addLine(Vector2(10, 5), Vector2(20, 5))
        let loose = sketch.addLine(Vector2(30, 0), Vector2(40, 3))
        let result = SketchRegions.find(in: sketch)
        #expect(result.regions.count == 1)
        #expect(result.openCurves == [spur, loose])
        #expect(result.warning == "2 curves don't form a closed region.")
    }

    @Test func projectedEdgesBoundRegions() throws {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .circle(center: .zero, radius: 10)))))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "f", curve: .circle(center: .zero, radius: 1),
                                                            isSuspended: true))))
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 1)
        #expect(isClose(regions[0].area, 100 * .pi))
    }

    @Test func slotAreaIncludesItsCaps() throws {
        let slot = ClassicSketchTests.Slot(length: 40, radius: 5)
        var sketch = slot.sketch
        sketch.remember(SketchSolver.solve(sketch))
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        #expect(region.outer.count == 4)
        #expect(isClose(region.area, 2 * 5 * 40 + 25 * .pi, tolerance: 1e-6))
    }

    @Test func notchedPlateKeepsAContinuousLoopThroughItsClockwiseArc() throws {
        // A plate with a semicircular notch in its top edge.
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(14, 10), Vector2(6, 10), Vector2(0, 10)]
        let points = corners.map { sketch.addPoint($0) }
        for (a, b) in [(0, 1), (1, 2), (2, 3), (4, 5), (5, 0)] { sketch.addLine(from: points[a], to: points[b]) }
        let center = sketch.addPoint(Vector2(10, 10))
        sketch.addArc(center: center, start: points[4], end: points[3])
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        #expect(isClose(region.area, 200 - 8 * .pi))
        let profile = region.profile(on: .xy)
        #expect(profile.isClosed)
        let arcs = profile.segments.compactMap { segment -> Double? in
            if case .arc(_, _, let start, let end) = segment { return end.radians - start.radians }
            return nil
        }
        #expect(arcs.count == 1)
        #expect(isClose(arcs[0], -.pi))
    }

    @Test func regionOrderDoesNotDependOnDrawingOrder() throws {
        func circles(_ order: [Double]) -> [Vector2] {
            var sketch = Sketch()
            for x in order { sketch.addCircle(center: Vector2(x, 0), radius: 1) }
            return SketchRegions.find(in: sketch).regions.map(\.centroid)
        }
        let expected = [Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)]
        for order in [[0.0, 10, -10], [10.0, -10, 0], [-10.0, 0, 10]] {
            let centroids = circles(order)
            try #require(centroids.count == 3)
            #expect(zip(centroids, expected).allSatisfy { isClose($0, $1) })
        }
    }

    @Test func profileConversionUsesTheOuterLoop() throws {
        var sketch = Sketch()
        square(&sketch, side: 10)
        sketch.addCircle(center: Vector2(5, 5), radius: 2)
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        let profile = region.profile(on: .xz)
        #expect(profile.plane == .xz)
        #expect(profile.segments == region.outer)
        #expect(profile.isClosed)
    }

    @Test func cornersJoinedByCoincidentConstraintsCloseARegionOnceSolved() throws {
        // Lines drawn with gaps and joined only by coincident constraints, as an editor that
        // doesn't share points would leave them.
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(30, 0), Vector2(18, 20)]
        let lines = (0..<3).map { i in
            let gap = Vector2(0.3 * Double(i + 1), -0.4 * Double(i))
            return sketch.addLine(corners[i] + gap, corners[(i + 1) % 3] - gap)
        }
        for i in 0..<3 { sketch.add(.coincident(sketch.ends(lines[i]).1, sketch.ends(lines[(i + 1) % 3]).0)) }
        sketch.add(.fix(sketch.ends(lines[0]).0, at: .zero))
        for (line, value) in zip(lines, [31.7, 24.3, 25]) { sketch.addDimension(.length(line), value: value) }
        #expect(SketchRegions.find(in: sketch).regions.isEmpty)
        sketch.remember(SketchSolver.solve(sketch))
        let result = SketchRegions.find(in: sketch)
        try #require(result.regions.count == 1)
        #expect(result.warning == nil)
        // Heron's formula for sides 31.7, 24.3, 25.
        let s = (31.7 + 24.3 + 25) / 2
        #expect(isClose(result.regions[0].area, (s * (s - 31.7) * (s - 24.3) * (s - 25)).squareRoot(), tolerance: 1e-6))
    }

    @Test func anEmptySketchHasNoRegionsAndNoWarning() {
        let result = SketchRegions.find(in: Sketch())
        #expect(result.regions.isEmpty)
        #expect(result.warning == nil)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter 'CreatorSketchTests\.(LoopMeasureTests|RegionTests)'`
Expected: compile errors, starting with `cannot find 'LoopSegment' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Regions/LoopSegment.swift`:
```swift
import CreatorGeometry
import Foundation

/// One step along a loop, in traversal order. Arcs keep their traversal sense: `to < from`
/// when the loop runs clockwise along them.
struct LoopSegment: Hashable, Sendable {
    enum Geometry: Hashable, Sendable {
        case line(Vector2, Vector2)
        case arc(center: Vector2, radius: Double, from: Double, to: Double)
    }

    var geometry: Geometry
    /// The curve (index into the region graph's curves) this came from.
    var source: Int
    /// The exact graph vertices it runs between. Arc ends recomputed from angles are off by
    /// rounding (sin π ≠ 0), which would break the containment test's half-open rule.
    var start: Vector2
    var end: Vector2

    init(geometry: Geometry, source: Int, start: Vector2, end: Vector2) {
        self.geometry = geometry
        self.source = source
        self.start = start
        self.end = end
    }

    /// A segment whose ends are computed from its geometry.
    init(geometry: Geometry, source: Int) {
        let (start, end) = switch geometry {
        case .line(let a, let b): (a, b)
        case .arc(let c, let r, let from, let to): (SketchMath.point(on: c, radius: r, at: from), SketchMath.point(on: c, radius: r, at: to))
        }
        self.init(geometry: geometry, source: source, start: start, end: end)
    }

    var segment: Segment2D {
        switch geometry {
        case .line(let a, let b): .line(a, b)
        case .arc(let c, let r, let from, let to): .arc(center: c, radius: r, start: Angle(radians: from), end: Angle(radians: to))
        }
    }

    /// The point halfway along, used as a component's test point for nesting.
    var midpoint: Vector2 {
        switch geometry {
        case .line(let a, let b): (a + b) * 0.5
        case .arc(let c, let r, let from, let to): SketchMath.point(on: c, radius: r, at: (from + to) / 2)
        }
    }

    /// `next` continued into this segment, when both come from the same curve in the same sense.
    func merged(with next: LoopSegment) -> LoopSegment? {
        guard source == next.source else { return nil }
        switch (geometry, next.geometry) {
        case (.line(let a, _), .line(_, let b)):
            return LoopSegment(geometry: .line(a, b), source: source, start: start, end: next.end)
        case (.arc(let c, let r, let from, let to), .arc(_, _, let nextFrom, let nextTo)):
            guard (to - from) * (nextTo - nextFrom) > 0 else { return nil }
            return LoopSegment(geometry: .arc(center: c, radius: r, from: from, to: to + (nextTo - nextFrom)), source: source,
                               start: start, end: next.end)
        default:
            return nil
        }
    }
}
```
`Sources/CreatorSketch/Regions/LoopMeasure.swift`:
```swift
import CreatorGeometry
import Foundation

/// Exact area, first moments and point containment for loops of lines and arcs (Green's theorem).
enum LoopMeasure {
    /// Signed area: positive for counter-clockwise loops.
    static func area(_ loop: [LoopSegment]) -> Double {
        loop.reduce(0) { total, segment in
            switch segment.geometry {
            case .line(let p, let q):
                return total + 0.5 * (p.x * q.y - q.x * p.y)
            case .arc(let c, let r, let a, let b):
                return total + 0.5 * (r * r * (b - a) + r * (c.x * (sin(b) - sin(a)) - c.y * (cos(b) - cos(a))))
            }
        }
    }

    /// (∬x dA, ∬y dA) over the loop's interior, signed like `area`.
    static func moments(_ loop: [LoopSegment]) -> Vector2 {
        var mx = 0.0
        var my = 0.0
        for segment in loop {
            switch segment.geometry {
            case .line(let p, let q):
                let e = q - p
                mx += e.y / 2 * (p.x * p.x + p.x * e.x + e.x * e.x / 3)
                my -= e.x / 2 * (p.y * p.y + p.y * e.y + e.y * e.y / 3)
            case .arc(let c, let r, let a, let b):
                func fx(_ t: Double) -> Double {
                    c.x * c.x * sin(t) + 2 * c.x * r * (t / 2 + sin(2 * t) / 4) + r * r * (sin(t) - pow(sin(t), 3) / 3)
                }
                func fy(_ t: Double) -> Double {
                    -c.y * c.y * cos(t) + 2 * c.y * r * (t / 2 - sin(2 * t) / 4) + r * r * (-cos(t) + pow(cos(t), 3) / 3)
                }
                mx += r / 2 * (fx(b) - fx(a))
                my += r / 2 * (fy(b) - fy(a))
            }
        }
        return Vector2(mx, my)
    }

    /// Even–odd containment by a ray towards +x. Arcs are split at their top and bottom so each
    /// piece crosses a horizontal line at most once; the half-open rule (`y > p.y`) counts a
    /// vertex on the ray once.
    static func contains(_ loop: [LoopSegment], _ p: Vector2) -> Bool {
        var crossings = 0
        func count(_ a: Vector2, _ b: Vector2, x: () -> Double) {
            if (a.y > p.y) != (b.y > p.y), x() > p.x { crossings += 1 }
        }
        for segment in loop {
            switch segment.geometry {
            case .line(let a, let b):
                count(a, b) { a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y) }
            case .arc(let c, let r, let from, let to):
                let (lo, hi) = (min(from, to), max(from, to))
                var cuts = [lo]
                var k = ((lo - .pi / 2) / .pi).rounded(.down) + 1
                while .pi / 2 + k * .pi < hi {
                    cuts.append(.pi / 2 + k * .pi)
                    k += 1
                }
                cuts.append(hi)
                // The outermost ends are the exact vertices, so neighbours agree on their y.
                let (lowEnd, highEnd) = from < to ? (segment.start, segment.end) : (segment.end, segment.start)
                func point(_ t: Double) -> Vector2 {
                    t == lo ? lowEnd : t == hi ? highEnd : SketchMath.point(on: c, radius: r, at: t)
                }
                for (t0, t1) in zip(cuts, cuts.dropFirst()) {
                    let a = point(t0)
                    let b = point(t1)
                    count(a, b) {
                        let dy = p.y - c.y
                        let dx = max(0, r * r - dy * dy).squareRoot()
                        return cos((t0 + t1) / 2) >= 0 ? c.x + dx : c.x - dx
                    }
                }
            }
        }
        return crossings % 2 == 1
    }
}
```
`Sources/CreatorSketch/Regions/RegionGraph.swift`:
```swift
import CreatorGeometry
import Foundation

/// The planar graph of a sketch's curves, split at every intersection (spec §5 steps 2–3), with
/// duplicate (overlapping) pieces merged and every edge that can't bound a face removed.
struct RegionGraph: Sendable {
    struct Edge: Hashable, Sendable {
        var from: Int
        var to: Int
        /// The piece, parameterised from `from` to `to` (arcs counter-clockwise).
        var shape: CurveShape
        /// Index into `curves`.
        var source: Int
    }

    let curves: [SketchCurve]
    private(set) var vertices: [Vector2] = []
    private(set) var edges: [Edge] = []

    init(curves: [SketchCurve]) {
        self.curves = curves
        for (index, curve) in curves.enumerated() {
            addPieces(of: curve.shape, source: index)
        }
        removeEdgesThatBoundNoFace()
    }

    /// Curve indices with at least one edge left.
    var usedSources: Set<Int> { Set(edges.map(\.source)) }

    /// The vertex at `point`, merging points closer than the intersection tolerance.
    mutating func vertex(_ point: Vector2) -> Int {
        if let existing = vertices.firstIndex(where: { ($0 - point).length <= CurveIntersection.tolerance }) {
            return existing
        }
        vertices.append(point)
        return vertices.count - 1
    }

    /// Splits one curve at its intersections with every other curve and adds the pieces.
    mutating func addPieces(of shape: CurveShape, source: Int) {
        var parameters: [Double] = []
        for (other, curve) in curves.enumerated() where other != source {
            for point in CurveIntersection.points(shape, curve.shape) {
                parameters.append(shape.nearestParameter(to: point))
            }
        }
        if shape.isFullCircle {
            parameters = parameters.map { SketchMath.wrapped($0) }
        } else {
            parameters += [0, shape.parameterEnd]
        }
        parameters.sort()
        var distinct: [Double] = []
        for t in parameters where distinct.last.map({ shape.length(from: $0, to: t) > CurveIntersection.tolerance }) ?? true {
            distinct.append(t)
        }
        if shape.isFullCircle {
            // A closed curve needs two vertices so each piece has distinct ends.
            if let last = distinct.last, let first = distinct.first,
               shape.length(from: last, to: first + CurveShape.fullTurn) <= CurveIntersection.tolerance {
                distinct.removeLast()
            }
            if distinct.isEmpty { distinct = [0] }
            if distinct.count == 1 { distinct.append(distinct[0] + .pi) }
            distinct.append(distinct[0] + CurveShape.fullTurn)
        }
        for (t0, t1) in zip(distinct, distinct.dropFirst()) where shape.length(from: t0, to: t1) > CurveIntersection.tolerance {
            let piece = shape.piece(from: t0, to: t1)
            let from = vertex(piece.startPoint)
            let to = vertex(piece.endPoint)
            guard from != to else { continue }
            let edge = Edge(from: from, to: to, shape: piece, source: source)
            if !edges.contains(where: { Self.isSameGeometry($0, edge) }) { edges.append(edge) }
        }
    }

    /// Two pieces joining the same vertices along the same line or circle (an overlap).
    static func isSameGeometry(_ a: Edge, _ b: Edge) -> Bool {
        guard Set([a.from, a.to]) == Set([b.from, b.to]) else { return false }
        switch (a.shape, b.shape) {
        case (.line, .line):
            return true
        case (.arc(let c1, let r1, _, let s1), .arc(let c2, let r2, _, let s2)):
            let tolerance = CurveIntersection.tolerance
            return (c1 - c2).length <= tolerance && abs(r1 - r2) <= tolerance
                && (a.shape.point(at: s1 / 2) - b.shape.point(at: s2 / 2)).length <= tolerance * 10
        default:
            return false
        }
    }

    /// Repeatedly drops dangling edges (an end of degree 1) and bridges (edges whose removal
    /// disconnects their ends): neither can border a bounded face on one side only.
    mutating func removeEdgesThatBoundNoFace() {
        var changed = true
        while changed {
            changed = false
            var degree = Array(repeating: 0, count: vertices.count)
            for edge in edges {
                degree[edge.from] += 1
                degree[edge.to] += 1
            }
            let kept = edges.filter { degree[$0.from] > 1 && degree[$0.to] > 1 }
            if kept.count != edges.count {
                edges = kept
                changed = true
                continue
            }
            let bridges = Set(edges.indices.filter(isBridge))
            if !bridges.isEmpty {
                edges = edges.enumerated().filter { !bridges.contains($0.offset) }.map(\.element)
                changed = true
            }
        }
    }

    func isBridge(_ index: Int) -> Bool {
        let target = edges[index].to
        var seen: Set<Int> = [edges[index].from]
        var stack = [edges[index].from]
        while let vertex = stack.popLast() {
            if vertex == target { return false }
            for (other, edge) in edges.enumerated() where other != index {
                for (a, b) in [(edge.from, edge.to), (edge.to, edge.from)] where a == vertex && seen.insert(b).inserted {
                    stack.append(b)
                }
            }
        }
        return true
    }

    /// The number of edges at each vertex.
    var degrees: [Int] {
        var degree = Array(repeating: 0, count: vertices.count)
        for edge in edges {
            degree[edge.from] += 1
            degree[edge.to] += 1
        }
        return degree
    }
}
```
`Sources/CreatorSketch/Regions/HalfEdge.swift`:
```swift
import CreatorGeometry

/// One direction of a region-graph edge.
struct HalfEdge: Hashable, Sendable {
    var edge: Int
    /// True when it runs from the edge's `from` to its `to`.
    var isForward: Bool

    var twin: HalfEdge { HalfEdge(edge: edge, isForward: !isForward) }

    func origin(_ graph: RegionGraph) -> Int { isForward ? graph.edges[edge].from : graph.edges[edge].to }
    func target(_ graph: RegionGraph) -> Int { isForward ? graph.edges[edge].to : graph.edges[edge].from }

    /// The direction it leaves its origin in, as a polar angle in [0, 2π).
    func outgoingAngle(_ graph: RegionGraph) -> Double {
        let shape = graph.edges[edge].shape
        let tangent = isForward ? shape.tangent(at: 0) : shape.tangent(at: shape.parameterEnd) * -1
        let angle = SketchMath.wrapped(SketchMath.angle(tangent))
        // Snap a hair below a full turn to 0 so tangent ties sort together.
        return angle > CurveShape.fullTurn - 1e-9 ? 0 : angle
    }

    /// Signed curvature as it leaves its origin (left turns positive).
    func curvature(_ graph: RegionGraph) -> Double {
        isForward ? graph.edges[edge].shape.curvature : -graph.edges[edge].shape.curvature
    }

    /// The step this half-edge makes along a loop.
    func loopSegment(_ graph: RegionGraph) -> LoopSegment {
        let edge = graph.edges[edge]
        let geometry: LoopSegment.Geometry = switch edge.shape {
        case .line:
            isForward ? .line(graph.vertices[edge.from], graph.vertices[edge.to])
                : .line(graph.vertices[edge.to], graph.vertices[edge.from])
        case .arc(let center, let radius, let start, let sweep):
            isForward ? .arc(center: center, radius: radius, from: start, to: start + sweep)
                : .arc(center: center, radius: radius, from: start + sweep, to: start)
        }
        let (from, to) = isForward ? (edge.from, edge.to) : (edge.to, edge.from)
        return LoopSegment(geometry: geometry, source: edge.source, start: graph.vertices[from], end: graph.vertices[to])
    }
}
```
`Sources/CreatorSketch/Regions/RegionGraph+Faces.swift`:
```swift
extension RegionGraph {
    /// Every face boundary: at each vertex, leave by the half-edge just clockwise of the one
    /// you arrived along (spec §5 step 3), which keeps the face on the left. Bounded faces come
    /// out counter-clockwise; each connected component's outside comes out clockwise.
    func faceCycles() -> [[HalfEdge]] {
        var outgoing = Array(repeating: [HalfEdge](), count: vertices.count)
        for index in edges.indices {
            for half in [HalfEdge(edge: index, isForward: true), HalfEdge(edge: index, isForward: false)] {
                outgoing[half.origin(self)].append(half)
            }
        }
        for vertex in outgoing.indices {
            outgoing[vertex].sort { a, b in
                let (angleA, angleB) = (a.outgoingAngle(self), b.outgoingAngle(self))
                if abs(angleA - angleB) > 1e-9 { return angleA < angleB }
                let (curvatureA, curvatureB) = (a.curvature(self), b.curvature(self))
                if curvatureA != curvatureB { return curvatureA < curvatureB }
                return (a.edge, a.isForward ? 0 : 1) < (b.edge, b.isForward ? 0 : 1)
            }
        }
        func next(_ half: HalfEdge) -> HalfEdge {
            let around = outgoing[half.target(self)]
            let index = around.firstIndex(of: half.twin) ?? 0
            return around[(index - 1 + around.count) % around.count]
        }
        var visited = Set<HalfEdge>()
        var cycles: [[HalfEdge]] = []
        for index in edges.indices {
            for start in [HalfEdge(edge: index, isForward: true), HalfEdge(edge: index, isForward: false)]
            where !visited.contains(start) {
                var cycle: [HalfEdge] = []
                var half = start
                while visited.insert(half).inserted {
                    cycle.append(half)
                    half = next(half)
                }
                cycles.append(cycle)
            }
        }
        return cycles
    }

    /// The connected component (smallest vertex index as its label) of each vertex.
    func componentLabels() -> [Int] {
        var label = Array(vertices.indices)
        var changed = true
        while changed {
            changed = false
            for edge in edges {
                let low = min(label[edge.from], label[edge.to])
                if label[edge.from] != low || label[edge.to] != low {
                    label[edge.from] = low
                    label[edge.to] = low
                    changed = true
                }
            }
        }
        return label
    }

    /// A cycle as loop segments, joining consecutive pieces of one curve across vertices that
    /// only they meet at (so a circle split for the walk comes back whole).
    func loop(_ cycle: [HalfEdge]) -> [LoopSegment] {
        let degree = degrees
        let segments = cycle.map { $0.loopSegment(self) }
        let joints = cycle.map { $0.origin(self) }
        func joins(_ i: Int) -> Bool {
            let previous = (i - 1 + segments.count) % segments.count
            return degree[joints[i]] == 2 && segments[previous].merged(with: segments[i]) != nil
        }
        guard let breakIndex = segments.indices.first(where: { !joins($0) }) else {
            // Every joint merges: one curve closing on itself (a circle).
            return [segments.dropFirst().reduce(segments[0]) { $0.merged(with: $1) ?? $0 }]
        }
        var result: [LoopSegment] = []
        for offset in 0..<segments.count {
            let i = (breakIndex + offset) % segments.count
            if offset > 0, joins(i), let last = result.last, let merged = last.merged(with: segments[i]) {
                result[result.count - 1] = merged
            } else {
                result.append(segments[i])
            }
        }
        return result
    }
}
```
`Sources/CreatorSketch/Regions/SketchRegion.swift`:
```swift
import CreatorGeometry

/// One closed region of a sketch: an outer loop and its holes (spec §5). The outer loop runs
/// counter-clockwise and each hole clockwise. Segments follow the loop: an arc traversed
/// clockwise is stored with `end < start`, so every loop stays continuous (`Profile2D.isClosed`
/// holds) even though `Segment2D` documents its arcs as counter-clockwise.
public struct SketchRegion: Hashable, Sendable {
    public var outer: [Segment2D]
    public var holes: [[Segment2D]]
    /// The outer area minus the holes' areas, mm².
    public var area: Double
    public var centroid: Vector2

    public init(outer: [Segment2D], holes: [[Segment2D]], area: Double, centroid: Vector2) {
        self.outer = outer
        self.holes = holes
        self.area = area
        self.centroid = centroid
    }

    /// Today's single-loop profile: the outer loop only. S3 gives `Profile2D` holes and switches
    /// this to `Profile2D(plane:outer:holes:)`; until then holes are not cut.
    public func profile(on plane: Plane) -> Profile2D {
        Profile2D(plane: plane, segments: outer)
    }
}
```
`Sources/CreatorSketch/Regions/SketchRegionResult.swift`:
```swift
/// The regions found in a sketch, plus what didn't form one.
public struct SketchRegionResult: Hashable, Sendable {
    /// Sorted by area (largest first), then centroid x, then centroid y.
    public var regions: [SketchRegion]
    /// Non-construction curves that bound no region (open or dangling).
    public var openCurves: [SketchEntityID]

    /// "2 curves don't form a closed region." when any curve is open, for the node's warning.
    public var warning: String? {
        switch openCurves.count {
        case 0: nil
        case 1: "1 curve doesn't form a closed region."
        default: "\(openCurves.count) curves don't form a closed region."
        }
    }
}
```
`Sources/CreatorSketch/Regions/SketchRegions.swift`:
```swift
import CreatorGeometry

/// Finds the closed regions of a solved sketch (spec §5).
public enum SketchRegions {
    /// The regions bounded by the sketch's non-construction curves (projected edges included),
    /// at their current positions. Faces nest even–odd: a face inside another is its hole, and
    /// a face inside a hole is a region again.
    public static func find(in sketch: Sketch) -> SketchRegionResult {
        let curves = sketch.curves(includingConstruction: false)
        let graph = RegionGraph(curves: curves)
        let labels = graph.componentLabels()
        var faces: [Face] = []
        var outlines: [Int: [LoopSegment]] = [:]
        var outlineAreas: [Int: Double] = [:]
        for cycle in graph.faceCycles() {
            let loop = graph.loop(cycle)
            let area = LoopMeasure.area(loop)
            let component = labels[cycle[0].origin(graph)]
            if area > 0 {
                faces.append(Face(loop: loop, area: area, component: component))
            } else if area < outlineAreas[component, default: .infinity] {
                outlines[component] = loop
                outlineAreas[component] = area
            }
        }
        // Each component's depth is the number of other components' faces around it; its parent
        // is the smallest of those faces.
        var depth: [Int: Int] = [:]
        var parent: [Int: Int] = [:]
        for (component, outline) in outlines {
            let probe = outline[0].midpoint
            let around = faces.indices.filter { faces[$0].component != component && LoopMeasure.contains(faces[$0].loop, probe) }
            depth[component] = around.count
            parent[component] = around.min { faces[$0].area < faces[$1].area }
        }
        var regions: [SketchRegion] = []
        for (index, face) in faces.enumerated() where depth[face.component, default: 0] % 2 == 0 {
            let holes = outlines.keys.sorted().filter { parent[$0] == index }.compactMap { outlines[$0] }
            let loops = [face.loop] + holes
            let area = loops.reduce(0) { $0 + LoopMeasure.area($1) }
            let moments = loops.reduce(Vector2.zero) { $0 + LoopMeasure.moments($1) }
            regions.append(SketchRegion(outer: face.loop.map(\.segment), holes: holes.map { $0.map(\.segment) },
                                        area: area, centroid: moments * (1 / area)))
        }
        regions.sort(by: isOrderedBefore)
        let used = graph.usedSources
        let open = curves.indices.filter { !used.contains($0) }.map { curves[$0].source }
        return SketchRegionResult(regions: regions, openCurves: open)
    }

    struct Face {
        var loop: [LoopSegment]
        var area: Double
        var component: Int
    }

    /// Area descending, then centroid x, then y, each compared with a tolerance so rounding
    /// noise can't reorder equal regions.
    static func isOrderedBefore(_ a: SketchRegion, _ b: SketchRegion) -> Bool {
        let areaTolerance = 1e-9 * max(1, abs(a.area), abs(b.area))
        if abs(a.area - b.area) > areaTolerance { return a.area > b.area }
        if abs(a.centroid.x - b.centroid.x) > 1e-9 { return a.centroid.x < b.centroid.x }
        return a.centroid.y < b.centroid.y
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter 'CreatorSketchTests\.(LoopMeasureTests|RegionTests)'`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 117 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Regions/HalfEdge.swift Sources/CreatorSketch/Regions/LoopMeasure.swift Sources/CreatorSketch/Regions/LoopSegment.swift Sources/CreatorSketch/Regions/RegionGraph+Faces.swift Sources/CreatorSketch/Regions/RegionGraph.swift Sources/CreatorSketch/Regions/SketchRegion.swift Sources/CreatorSketch/Regions/SketchRegionResult.swift Sources/CreatorSketch/Regions/SketchRegions.swift Tests/CreatorSketchTests/LoopMeasureTests.swift Tests/CreatorSketchTests/RegionTests.swift
git commit -m "feat(sketch): find nested regions in a solved sketch"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 10: Command support, trim and extend
**Files:**
- Create: `Sources/CreatorSketch/Commands/SketchEdit.swift`, `Sources/CreatorSketch/Commands/SketchCommandError.swift`, `Sources/CreatorSketch/Commands/SketchCommands.swift`, `Sources/CreatorSketch/Commands/SketchEntityKind+Replacing.swift`, `Sources/CreatorSketch/Commands/SketchCommands+Trim.swift`, `Sources/CreatorSketch/Commands/SketchCommands+Extend.swift`, `Tests/CreatorSketchTests/Support/SketchTestSupport+Commands.swift`, `Tests/CreatorSketchTests/TrimExtendTests.swift`
- Test: `Tests/CreatorSketchTests/TrimExtendTests.swift`

**Interfaces:**
- Consumes: `CurveIntersection`, `Sketch.shape(of:)`, `Sketch.curves(includingConstruction:)` (Task 8); `Sketch.removeEntity`, `removeOrphanPoints`, `move(_:to:)` and labels (Task 1); `SketchSolver` (tests).
- Produces:
  - `public struct SketchEdit { sketch; description; init(sketch:description:) }`, `public struct SketchCommandError: Error { message; init(_:) }`
  - `public enum SketchCommands`, with `trim(_:curve:near:) throws(SketchCommandError) -> SketchEdit` and `extend(_:curve:near:) throws(SketchCommandError) -> SketchEdit`
  - internal helpers in `SketchCommands`: `editableShape`, `point(at:on:in:)`, `sharedEndpoint(of:at:in:)`, `newPoint(at:in:)`, `removeExtentDependent(on:in:)`, `removeTangents`, `moveTangents`, `users(of:besides:in:)`, `cuts(of:curve:in:)` and `Cut`, `endpoints(of:)`, `extensionProbe`, `reach(of:)`, `isArc`
  - internal `SketchEntityKind.replacingPoint(_:with:)`
  - Test helpers: `requireSolvesInPlace(_:)` and `Sketch.constraintList`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/Support/SketchTestSupport+Commands.swift`:
```swift
// Test fixture file: helpers for command tests (several helpers by design).
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// Solves an edited sketch and requires a usable result that left every point where the command
/// put it (commands create geometry that already satisfies what they add).
@discardableResult
func requireSolvesInPlace(_ sketch: Sketch, sourceLocation: SourceLocation = #_sourceLocation) throws -> SketchSolution {
    let solution = SketchSolver.solve(sketch)
    try #require(solution.status.isUsable, "status \(solution.status)", sourceLocation: sourceLocation)
    for id in sketch.entityIDs {
        guard let before = sketch.position(of: id), let after = solution.points[id] else { continue }
        #expect(isClose(before, after, tolerance: 1e-6), "\(sketch.label(of: id)) moved", sourceLocation: sourceLocation)
    }
    return solution
}

extension Sketch {
    /// The constraints of the sketch, as a list, for membership checks.
    var constraintList: [SketchConstraint] { constraintIDs.compactMap { constraints[$0] } }
}
```
`Tests/CreatorSketchTests/TrimExtendTests.swift`:
```swift
import CreatorGeometry
import Testing
@testable import CreatorSketch

struct TrimExtendTests {
    @Test func trimmingAnOverhangEndsTheLineAtTheCutter() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, oldEnd) = sketch.ends(line)
        let cutter = sketch.addLine(Vector2(6, -5), Vector2(6, 5))
        sketch.add(.horizontal(line))
        sketch.addDimension(.length(line), value: 10)
        let edit = try SketchCommands.trim(sketch, curve: line, near: Vector2(8, 0.1))
        let trimmed = edit.sketch
        #expect(edit.description == "Trim Line 1")
        let (newStart, newEnd) = trimmed.ends(line)
        #expect(newStart == start)
        #expect(isClose(try #require(trimmed.position(of: newEnd)), Vector2(6, 0)))
        #expect(trimmed.entities[oldEnd] == nil)
        #expect(trimmed.constraintList.contains(.pointOn(point: newEnd, curve: cutter)))
        #expect(trimmed.constraintList.contains(.horizontal(line)))
        #expect(trimmed.dimensions.isEmpty)
        try requireSolvesInPlace(trimmed)
    }

    @Test func trimmingTheMiddleSplitsTheLineAndKeepsItStraight() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        let (start, end) = sketch.ends(line)
        let left = sketch.addLine(Vector2(3, -5), Vector2(3, 5))
        let right = sketch.addLine(Vector2(7, -5), Vector2(7, 5))
        let trimmed = try SketchCommands.trim(sketch, curve: line, near: Vector2(5, 0)).sketch
        let lines = trimmed.ids(ofKind: "Line")
        try #require(lines.count == 4)
        let piece = try #require(lines.last)
        #expect(trimmed.ends(line).0 == start)
        #expect(trimmed.ends(piece).1 == end)
        let (pieceStart, lineEnd) = (trimmed.ends(piece).0, trimmed.ends(line).1)
        #expect(isClose(try #require(trimmed.position(of: lineEnd)), Vector2(3, 0)))
        #expect(isClose(try #require(trimmed.position(of: pieceStart)), Vector2(7, 0)))
        let constraints = trimmed.constraintList
        #expect(constraints.contains(.pointOn(point: lineEnd, curve: left)))
        #expect(constraints.contains(.pointOn(point: pieceStart, curve: right)))
        #expect(constraints.contains(.pointOn(point: pieceStart, curve: line)))
        #expect(constraints.contains(.pointOn(point: end, curve: line)))
        try requireSolvesInPlace(trimmed)
    }

    @Test func trimmingACurveWithNoCrossingsDeletesIt() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(10, 0))
        sketch.addCircle(center: Vector2(50, 50), radius: 2)
        let trimmed = try SketchCommands.trim(sketch, curve: line, near: Vector2(5, 0)).sketch
        #expect(trimmed.entities[line] == nil)
        #expect(trimmed.ids(ofKind: "Point").count == 1)
    }

    @Test func trimmingACircleLeavesTheArcAwayFromThePick() throws {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 5)
        let center = sketch.centerOf(circle)
        let radius = sketch.addDimension(.radius(circle), value: 5)
        sketch.addLine(Vector2(-10, 0), Vector2(10, 0))
        let trimmed = try SketchCommands.trim(sketch, curve: circle, near: Vector2(0.5, 6)).sketch
        let (arcCenter, start, end) = trimmed.arcPoints(circle)
        #expect(arcCenter == center)
        // The bottom half remains: counter-clockwise from (−5, 0) to (5, 0).
        #expect(isClose(try #require(trimmed.position(of: start)), Vector2(-5, 0)))
        #expect(isClose(try #require(trimmed.position(of: end)), Vector2(5, 0)))
        #expect(trimmed.dimensions[radius] != nil)
        try requireSolvesInPlace(trimmed)
    }

    @Test func trimmingAtATJunctionSharesTheStemsEndpoint() throws {
        var sketch = Sketch()
        let bar = sketch.addLine(.zero, Vector2(10, 0))
        let stem = sketch.addLine(Vector2(5, 0), Vector2(5, 5))
        let trimmed = try SketchCommands.trim(sketch, curve: bar, near: Vector2(9, 0)).sketch
        #expect(trimmed.ends(bar).1 == trimmed.ends(stem).0)
        #expect(trimmed.constraints.isEmpty)
    }

    @Test func projectedEdgesCantBeTrimmed() {
        var sketch = Sketch()
        let edge = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(.zero, Vector2(1, 0))))))
        #expect(throws: SketchCommandError("Projected edges can't be trimmed.")) {
            try SketchCommands.trim(sketch, curve: edge, near: .zero)
        }
    }

    @Test func extendingALineStopsAtTheFirstCurveItMeets() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(4, 0))
        let (_, end) = sketch.ends(line)
        let near = sketch.addLine(Vector2(10, -5), Vector2(10, 5))
        sketch.addLine(Vector2(20, -5), Vector2(20, 5))
        sketch.addDimension(.length(line), value: 4)
        let edit = try SketchCommands.extend(sketch, curve: line, near: Vector2(3.5, 0))
        #expect(edit.description == "Extend Line 1")
        #expect(isClose(try #require(edit.sketch.position(of: end)), Vector2(10, 0)))
        #expect(edit.sketch.constraintList.contains(.pointOn(point: end, curve: near)))
        #expect(edit.sketch.dimensions.isEmpty)
        try requireSolvesInPlace(edit.sketch)
    }

    @Test func extendingOntoAnEndpointSharesIt() throws {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(4, 0))
        let wall = sketch.addLine(Vector2(10, 0), Vector2(10, 10))
        let extended = try SketchCommands.extend(sketch, curve: line, near: Vector2(4, 0)).sketch
        #expect(extended.ends(line).1 == extended.ends(wall).0)
        #expect(extended.ids(ofKind: "Point").count == 3)
    }

    @Test func extendingAnArcStartRunsClockwiseToTheLine() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let arc = sketch.addArc(center: center, start: sketch.addPoint(Vector2(5, 0)), end: sketch.addPoint(Vector2(0, 5)))
        sketch.addLine(Vector2(-10, -3), Vector2(10, -3))
        let extended = try SketchCommands.extend(sketch, curve: arc, near: Vector2(5, 0.5)).sketch
        let (_, start, _) = extended.arcPoints(arc)
        #expect(isClose(try #require(extended.position(of: start)), Vector2(4, -3)))
        try requireSolvesInPlace(extended)
    }

    @Test func aConnectedEndCantBeExtended() {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [.zero, Vector2(10, 0), Vector2(10, 10)])
        #expect(throws: SketchCommandError("That end of Line 1 is connected to other geometry.")) {
            try SketchCommands.extend(sketch, curve: lines[0], near: Vector2(9, 0))
        }
    }

    @Test func extendingTowardsNothingIsAPlainError() {
        var sketch = Sketch()
        let line = sketch.addLine(.zero, Vector2(4, 0))
        sketch.addLine(Vector2(0, 5), Vector2(4, 5))
        #expect(throws: SketchCommandError("There is nothing to extend Line 1 to.")) {
            try SketchCommands.extend(sketch, curve: line, near: Vector2(4, 0))
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.TrimExtendTests`
Expected: compile errors, starting with `cannot find 'SketchCommands' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Commands/SketchEdit.swift`:
```swift
/// The result of a sketch command (spec §3): the new sketch plus a description for undo.
public struct SketchEdit: Hashable, Sendable {
    public var sketch: Sketch
    /// For the undo menu, for example "Trim Line 2".
    public var description: String

    public init(sketch: Sketch, description: String) {
        self.sketch = sketch
        self.description = description
    }
}
```
`Sources/CreatorSketch/Commands/SketchCommandError.swift`:
```swift
/// A command that can't be applied, with a plain-language reason.
public struct SketchCommandError: Error, Hashable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}
```
`Sources/CreatorSketch/Commands/SketchCommands.swift`:
```swift
import CreatorGeometry

/// Pure sketch editing commands (spec §3): each takes a sketch and arguments and returns a
/// `SketchEdit`, never touching its input. Geometry is read at the current positions (the last
/// solve, else drawn), and new points get drawn and warm-start positions where they are created,
/// so the result solves without moving anything that was already in place.
public enum SketchCommands {}

extension SketchCommands {
    /// A curve's current shape, refusing points and projected edges.
    static func editableShape(_ sketch: Sketch, _ id: SketchEntityID, verb: String) throws(SketchCommandError) -> CurveShape {
        guard let entity = sketch.entities[id] else { throw SketchCommandError("That curve no longer exists.") }
        if case .projected = entity.kind { throw SketchCommandError("Projected edges can't be \(verb).") }
        guard !entity.kind.isPoint, let shape = sketch.shape(of: id) else {
            throw SketchCommandError("Pick a line, arc or circle.")
        }
        return shape
    }

    /// The point entity to end a curve at `position` on `cutter`: the cutter's own endpoint when
    /// one is there (shared, as lines and arcs share endpoints), else a new point held on the
    /// cutter by a point-on constraint.
    static func point(at position: Vector2, on cutter: SketchEntityID, in sketch: inout Sketch) -> SketchEntityID {
        if let shared = sharedEndpoint(of: cutter, at: position, in: sketch) { return shared }
        let point = newPoint(at: position, in: &sketch)
        sketch.add(.pointOn(point: point, curve: cutter))
        return point
    }

    /// The cutter's start or end point when it lies at `position`.
    static func sharedEndpoint(of cutter: SketchEntityID, at position: Vector2, in sketch: Sketch) -> SketchEntityID? {
        let ends: [SketchEntityID] = switch sketch.entities[cutter]?.kind {
        case .line(let start, let end), .arc(_, let start, let end): [start, end]
        default: []
        }
        return ends.first { sketch.position(of: $0).map { ($0 - position).length <= CurveIntersection.tolerance } ?? false }
    }

    /// A new point with matching drawn and warm-start positions.
    static func newPoint(at position: Vector2, in sketch: inout Sketch) -> SketchEntityID {
        let point = sketch.addPoint(position)
        sketch.solved[point] = .point(position)
        return point
    }

    /// Removes the constraints and dimensions on `curve` that depend on its extent and would
    /// fight a trim, extend or fillet: lengths, equal lengths and midpoints. Everything else on a
    /// curve treats lines as infinite and arcs as full circles, so it stays valid.
    static func removeExtentDependent(on curve: SketchEntityID, in sketch: inout Sketch) {
        let isLine = if case .line = sketch.entities[curve]?.kind { true } else { false }
        sketch.constraints = sketch.constraints.filter { _, constraint in
            switch constraint {
            case .equal(let a, let b): !(isLine && (a == curve || b == curve))
            case .midpoint(_, let line): line != curve
            default: true
            }
        }
        sketch.dimensions = sketch.dimensions.filter { _, dimension in
            if case .length(let line) = dimension.kind { return line != curve }
            return true
        }
    }

    /// Removes tangent constraints on `curve` that relied on it sharing `point` with the other curve.
    static func removeTangents(on curve: SketchEntityID, sharing point: SketchEntityID, in sketch: inout Sketch) {
        sketch.constraints = sketch.constraints.filter { _, constraint in
            guard case .tangent(let a, let b) = constraint, a == curve || b == curve else { return true }
            let other = a == curve ? b : a
            return !(sketch.entities[other]?.kind.referencedPoints.contains(point) ?? false)
        }
    }

    /// Moves tangent constraints between `curve` and curves sharing `point` onto `replacement`.
    static func moveTangents(on curve: SketchEntityID, sharing point: SketchEntityID, to replacement: SketchEntityID,
                             in sketch: inout Sketch) {
        for id in sketch.constraintIDs {
            guard case .tangent(let a, let b) = sketch.constraints[id], a == curve || b == curve else { continue }
            let other = a == curve ? b : a
            if sketch.entities[other]?.kind.referencedPoints.contains(point) ?? false {
                sketch.constraints[id] = .tangent(replacement, other)
            }
        }
    }

    /// The other non-point entities that use `point`.
    static func users(of point: SketchEntityID, besides curve: SketchEntityID? = nil, in sketch: Sketch) -> [SketchEntityID] {
        sketch.entityIDs.filter { $0 != curve && (sketch.entities[$0]?.kind.referencedPoints.contains(point) ?? false) }
    }
}
```
`Sources/CreatorSketch/Commands/SketchEntityKind+Replacing.swift`:
```swift
extension SketchEntityKind {
    /// The same entity with every reference to point `old` changed to `new`.
    func replacingPoint(_ old: SketchEntityID, with new: SketchEntityID) -> SketchEntityKind {
        func swap(_ id: SketchEntityID) -> SketchEntityID { id == old ? new : id }
        return switch self {
        case .point, .projected: self
        case .line(let start, let end): .line(start: swap(start), end: swap(end))
        case .arc(let center, let start, let end): .arc(center: swap(center), start: swap(start), end: swap(end))
        case .circle(let center, let radius): .circle(center: swap(center), radius: radius)
        }
    }
}
```
`Sources/CreatorSketch/Commands/SketchCommands+Trim.swift`:
```swift
import CreatorGeometry

extension SketchCommands {
    /// Removes the span of `curve` around `pick` between its nearest intersections with any other
    /// curve (spec §3). A span reaching a free end shortens the curve, a span in the middle splits
    /// it in two (the new piece is held collinear or co-circular with the first), a curve with no
    /// intersections is deleted, and a circle becomes an arc. New endpoints are shared with the
    /// cutting curve's endpoint when one is there, else held on the cutter by point-on.
    public static func trim(_ sketch: Sketch, curve: SketchEntityID, near pick: Vector2) throws(SketchCommandError) -> SketchEdit {
        let shape = try editableShape(sketch, curve, verb: "trimmed")
        let description = "Trim \(sketch.label(of: curve))"
        let cuts = cuts(of: shape, curve: curve, in: sketch)
        var edited = sketch
        let pickT = shape.nearestParameter(to: pick)
        guard case let kind? = sketch.entities[curve]?.kind else { throw SketchCommandError("That curve no longer exists.") }

        if shape.isFullCircle {
            guard cuts.count >= 2, case .circle(let center, _) = kind else {
                edited.removeEntity(curve)
                edited.removeOrphanPoints(kind.referencedPoints)
                return SketchEdit(sketch: edited, description: description)
            }
            // The removed span runs counter-clockwise from the last cut at or before the pick to the next.
            let index = cuts.lastIndex { $0.t <= pickT } ?? cuts.count - 1
            let (removedFrom, removedTo) = (cuts[index], cuts[(index + 1) % cuts.count])
            let start = point(at: removedTo.position, on: removedTo.cutter, in: &edited)
            let end = point(at: removedFrom.position, on: removedFrom.cutter, in: &edited)
            edited.entities[curve]?.kind = .arc(center: center, start: start, end: end)
            edited.solved[curve] = nil
            return SketchEdit(sketch: edited, description: description)
        }

        let lower = cuts.last { $0.t < pickT }
        let upper = cuts.first { $0.t > pickT }
        let (oldStart, oldEnd) = endpoints(of: kind)
        switch (lower, upper) {
        case (nil, nil):
            edited.removeEntity(curve)
            edited.removeOrphanPoints(kind.referencedPoints)
        case (nil, let upper?):
            let start = point(at: upper.position, on: upper.cutter, in: &edited)
            edited.entities[curve]?.kind = kind.replacingPoint(oldStart, with: start)
            removeTangents(on: curve, sharing: oldStart, in: &edited)
            removeExtentDependent(on: curve, in: &edited)
            edited.removeOrphanPoints([oldStart])
        case (let lower?, nil):
            let end = point(at: lower.position, on: lower.cutter, in: &edited)
            edited.entities[curve]?.kind = kind.replacingPoint(oldEnd, with: end)
            removeTangents(on: curve, sharing: oldEnd, in: &edited)
            removeExtentDependent(on: curve, in: &edited)
            edited.removeOrphanPoints([oldEnd])
        case (let lower?, let upper?):
            let end = point(at: lower.position, on: lower.cutter, in: &edited)
            let start = point(at: upper.position, on: upper.cutter, in: &edited)
            let isConstruction = sketch.entities[curve]?.isConstruction ?? false
            edited.entities[curve]?.kind = kind.replacingPoint(oldEnd, with: end)
            let piece = edited.add(SketchEntity(kind.replacingPoint(oldStart, with: start), isConstruction: isConstruction))
            moveTangents(on: curve, sharing: oldEnd, to: piece, in: &edited)
            removeExtentDependent(on: curve, in: &edited)
            if case .line = kind {
                edited.add(.pointOn(point: start, curve: curve))
                edited.add(.pointOn(point: oldEnd, curve: curve))
            } else {
                // Arc pieces already share the centre.
                edited.add(.equal(curve, piece))
            }
        }
        return SketchEdit(sketch: edited, description: description)
    }

    struct Cut {
        var t: Double
        var position: Vector2
        var cutter: SketchEntityID
    }

    /// Where every other curve (construction and projected included) crosses `shape`, strictly
    /// inside it, sorted by parameter, one cut per place (the lowest-ID cutter wins).
    static func cuts(of shape: CurveShape, curve: SketchEntityID, in sketch: Sketch) -> [Cut] {
        var cuts: [Cut] = []
        for other in sketch.curves(includingConstruction: true) where other.source != curve {
            for position in CurveIntersection.points(shape, other.shape) {
                let t = shape.isFullCircle ? SketchMath.wrapped(shape.parameter(of: position)) : shape.nearestParameter(to: position)
                let interior = shape.isFullCircle
                    || (shape.length(from: 0, to: t) > CurveIntersection.tolerance
                        && shape.length(from: t, to: shape.parameterEnd) > CurveIntersection.tolerance)
                if interior { cuts.append(Cut(t: t, position: position, cutter: other.source)) }
            }
        }
        cuts.sort { ($0.t, $0.cutter) < ($1.t, $1.cutter) }
        var distinct: [Cut] = []
        for cut in cuts where distinct.last.map({ shape.length(from: $0.t, to: cut.t) > CurveIntersection.tolerance }) ?? true {
            distinct.append(cut)
        }
        if shape.isFullCircle, distinct.count > 1, let first = distinct.first, let last = distinct.last,
           shape.length(from: last.t, to: first.t + CurveShape.fullTurn) <= CurveIntersection.tolerance {
            distinct.removeLast()
        }
        return distinct
    }

    /// The (start, end) points of a line or arc.
    static func endpoints(of kind: SketchEntityKind) -> (SketchEntityID, SketchEntityID) {
        switch kind {
        case .line(let start, let end), .arc(_, let start, let end): (start, end)
        default: (SketchEntityID(0), SketchEntityID(0))
        }
    }
}
```
`Sources/CreatorSketch/Commands/SketchCommands+Extend.swift`:
```swift
import CreatorGeometry

extension SketchCommands {
    /// Extends the end of a line or arc nearest `pick` to the first curve it meets (spec §3). The
    /// end must be free: used by no other curve and not coincident with or fixed to anything.
    /// The moved end is shared with, or held on, the curve it reaches.
    public static func extend(_ sketch: Sketch, curve: SketchEntityID, near pick: Vector2) throws(SketchCommandError) -> SketchEdit {
        let shape = try editableShape(sketch, curve, verb: "extended")
        guard case let kind? = sketch.entities[curve]?.kind, !shape.isFullCircle,
              case let (start, end) = endpoints(of: kind), start != end else {
            throw SketchCommandError("Only lines and arcs can be extended.")
        }
        let atEnd = (shape.endPoint - pick).length < (shape.startPoint - pick).length
        let moving = atEnd ? end : start
        let isHeld = sketch.constraints.values.contains { constraint in
            switch constraint {
            case .coincident(let a, let b): a == moving || b == moving
            case .fix(let point, _): point == moving
            default: false
            }
        }
        guard users(of: moving, besides: curve, in: sketch).isEmpty, !isHeld else {
            throw SketchCommandError("That end of \(sketch.label(of: curve)) is connected to other geometry.")
        }
        let probe = extensionProbe(of: shape, atEnd: atEnd, reach: reach(of: sketch))
        var best: (distance: Double, position: Vector2, cutter: SketchEntityID)?
        for other in sketch.curves(includingConstruction: true) where other.source != curve {
            for position in CurveIntersection.points(probe, other.shape) {
                // Arc probes that extend the start run backwards from it.
                let t = probe.nearestParameter(to: position)
                let distance = probe.length(from: 0, to: (atEnd || !isArc(shape)) ? t : probe.parameterEnd - t)
                guard distance > CurveIntersection.tolerance else { continue }
                if best.map({ distance < $0.distance - CurveIntersection.tolerance }) ?? true {
                    best = (distance, position, other.source)
                }
            }
        }
        guard let hit = best else {
            throw SketchCommandError("There is nothing to extend \(sketch.label(of: curve)) to.")
        }
        var edited = sketch
        // Anything that pins the moving end elsewhere would pull it back.
        edited.constraints = edited.constraints.filter { !$0.value.entities.contains(moving) }
        edited.dimensions = edited.dimensions.filter { !$0.value.kind.entities.contains(moving) }
        removeExtentDependent(on: curve, in: &edited)
        if let shared = sharedEndpoint(of: hit.cutter, at: hit.position, in: edited) {
            edited.entities[curve]?.kind = kind.replacingPoint(moving, with: shared)
            edited.removeEntity(moving)
        } else {
            edited.move(moving, to: hit.position)
            edited.add(.pointOn(point: moving, curve: hit.cutter))
        }
        return SketchEdit(sketch: edited, description: "Extend \(sketch.label(of: curve))")
    }

    static func isArc(_ shape: CurveShape) -> Bool {
        if case .arc = shape { return true }
        return false
    }

    /// The curve the end would sweep along: a long ray beyond a line's end, or the rest of an
    /// arc's circle beyond (or before) its span.
    static func extensionProbe(of shape: CurveShape, atEnd: Bool, reach: Double) -> CurveShape {
        switch shape {
        case .line(let a, let b):
            let (from, away) = atEnd ? (b, b - a) : (a, a - b)
            let unit = SketchMath.normalized(away) ?? Vector2(1, 0)
            return .line(from, from + unit * reach)
        case .arc(let center, let radius, let start, let sweep):
            let rest = CurveShape.fullTurn - sweep - 1e-9
            return atEnd ? .arc(center: center, radius: radius, start: start + sweep, sweep: rest)
                : .arc(center: center, radius: radius, start: start - rest, sweep: rest)
        }
    }

    /// Far enough to cross the whole sketch: four times its bounding diagonal, at least 1 m.
    static func reach(of sketch: Sketch) -> Double {
        let points = sketch.curves(includingConstruction: true).flatMap { curve -> [Vector2] in
            switch curve.shape {
            case .line(let a, let b): [a, b]
            case .arc(let c, let r, _, _): [c + Vector2(-r, -r), c + Vector2(r, r)]
            }
        }
        guard let first = points.first else { return 1000 }
        var (low, high) = (first, first)
        for p in points {
            low = Vector2(min(low.x, p.x), min(low.y, p.y))
            high = Vector2(max(high.x, p.x), max(high.y, p.y))
        }
        return max(1000, 4 * (high - low).length)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.TrimExtendTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 128 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Commands/SketchCommandError.swift Sources/CreatorSketch/Commands/SketchCommands+Extend.swift Sources/CreatorSketch/Commands/SketchCommands+Trim.swift Sources/CreatorSketch/Commands/SketchCommands.swift Sources/CreatorSketch/Commands/SketchEdit.swift Sources/CreatorSketch/Commands/SketchEntityKind+Replacing.swift Tests/CreatorSketchTests/Support/SketchTestSupport+Commands.swift Tests/CreatorSketchTests/TrimExtendTests.swift
git commit -m "feat(sketch): add trim and extend commands"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 11: Fillet
**Files:**
- Create: `Sources/CreatorSketch/Commands/SketchCommands+Fillet.swift`, `Tests/CreatorSketchTests/FilletTests.swift`
- Test: `Tests/CreatorSketchTests/FilletTests.swift`

**Interfaces:**
- Consumes: `SketchCommands.users`, `newPoint`, `removeExtentDependent`, `SketchEntityKind.replacingPoint` (Task 10); `ConstrainedRectangle` (Task 5); `SketchRegions` (Task 9), used in a test.
- Produces: `public static func SketchCommands.fillet(_ sketch: Sketch, corner: SketchEntityID, radius: Double) throws(SketchCommandError) -> SketchEdit`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/FilletTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

struct FilletTests {
    @Test func filletingARectangleCornerStaysFullyConstrained() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        let (right, top) = (rectangle.lines[1], rectangle.lines[2])
        let corner = rectangle.sketch.ends(right).1
        let edit = try SketchCommands.fillet(rectangle.sketch, corner: corner, radius: 5)
        let filleted = edit.sketch
        #expect(edit.description == "Fillet Point 3 (5 mm)")
        #expect(filleted.entities[corner] == nil)
        let arc = try #require(filleted.ids(ofKind: "Arc").first)
        let (center, start, end) = filleted.arcPoints(arc)
        #expect(isClose(try #require(filleted.position(of: center)), Vector2(55, 35)))
        #expect(isClose(try #require(filleted.position(of: start)), Vector2(60, 35)))
        #expect(isClose(try #require(filleted.position(of: end)), Vector2(55, 40)))
        #expect(filleted.ends(right).1 == start)
        #expect(filleted.ends(top).0 == end)
        let constraints = filleted.constraintList
        #expect(constraints.contains(.tangent(right, arc)))
        #expect(constraints.contains(.tangent(top, arc)))
        #expect(filleted.dimensions.values.contains { $0.kind == .radius(arc) && $0.value == 5 && $0.name == "d3" })
        let solution = try requireSolvesInPlace(filleted)
        #expect(solution.status == .solved)
    }

    @Test func filletRegionHasTheRoundedArea() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        let corner = rectangle.sketch.ends(rectangle.lines[1]).1
        let filleted = try SketchCommands.fillet(rectangle.sketch, corner: corner, radius: 5).sketch
        let region = try #require(SketchRegions.find(in: filleted).regions.first)
        #expect(isClose(region.area, 2400 - (25 - 25 * .pi / 4), tolerance: 1e-6))
    }

    @Test func tooLargeARadiusNamesTheLargestThatFits() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(0, 20)))
        #expect(throws: SketchCommandError("Radius 15 mm is too large for this corner (max ≈ 10 mm).")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 15)
        }
    }

    @Test func aFilletNeedsExactlyTwoLines() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        for end in [Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0)] {
            sketch.addLine(from: corner, to: sketch.addPoint(end))
        }
        #expect(throws: SketchCommandError("A fillet needs a corner where exactly two lines meet.")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 1)
        }
    }

    @Test func straightThroughLinesCantBeFilleted() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        sketch.addLine(from: sketch.addPoint(Vector2(-10, 0)), to: corner)
        sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        #expect(throws: SketchCommandError("The lines at that corner are parallel.")) {
            try SketchCommands.fillet(sketch, corner: corner, radius: 1)
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.FilletTests`
Expected: compile errors: `type 'SketchCommands' has no member 'fillet'`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Commands/SketchCommands+Fillet.swift`:
```swift
import CreatorGeometry
import Foundation

extension SketchCommands {
    /// Rounds the corner where exactly two lines meet at `corner` (spec §3): the lines are trimmed
    /// back to the tangent points and joined by a tangent arc with a radius dimension. The corner
    /// point and everything on it are removed, as are the lines' lengths, equal-length and
    /// midpoint constraints, which no longer describe the trimmed lines.
    public static func fillet(_ sketch: Sketch, corner: SketchEntityID, radius: Double) throws(SketchCommandError) -> SketchEdit {
        guard radius > 0, radius.isFinite else { throw SketchCommandError("The fillet radius must be greater than 0 mm.") }
        let lines = users(of: corner, in: sketch)
        guard lines.count == 2, let p = sketch.position(of: corner),
              case .line(let s1, let e1)? = sketch.entities[lines[0]]?.kind,
              case .line(let s2, let e2)? = sketch.entities[lines[1]]?.kind,
              let a = sketch.position(of: s1 == corner ? e1 : s1), let b = sketch.position(of: s2 == corner ? e2 : s2),
              let u1 = SketchMath.normalized(a - p), let u2 = SketchMath.normalized(b - p) else {
            throw SketchCommandError("A fillet needs a corner where exactly two lines meet.")
        }
        let between = acos(min(1, max(-1, SketchMath.dot(u1, u2))))
        guard sin(between) > 1e-9 else { throw SketchCommandError("The lines at that corner are parallel.") }
        let half = between / 2
        let setback = radius / tan(half)
        let shorter = min((a - p).length, (b - p).length)
        guard setback < shorter - CurveIntersection.tolerance else {
            let largest = (shorter * tan(half) * 10).rounded() / 10
            throw SketchCommandError("Radius \(radius.sketchDisplay) mm is too large for this corner (max ≈ \(largest.sketchDisplay) mm).")
        }
        guard let bisector = SketchMath.normalized(u1 + u2) else {
            throw SketchCommandError("The lines at that corner are parallel.")
        }
        let (firstPosition, secondPosition) = (p + u1 * setback, p + u2 * setback)
        let centerPosition = p + bisector * (radius / sin(half))
        var edited = sketch
        let first = newPoint(at: firstPosition, in: &edited)
        let second = newPoint(at: secondPosition, in: &edited)
        let center = newPoint(at: centerPosition, in: &edited)
        for (line, tangentPoint) in [(lines[0], first), (lines[1], second)] {
            if let kind = edited.entities[line]?.kind {
                edited.entities[line]?.kind = kind.replacingPoint(corner, with: tangentPoint)
            }
            removeExtentDependent(on: line, in: &edited)
        }
        edited.removeEntity(corner)
        // Counter-clockwise from whichever tangent point makes the short arc.
        let isCounterClockwise = SketchMath.cross(firstPosition - centerPosition, secondPosition - centerPosition) > 0
        let isConstruction = lines.allSatisfy { sketch.entities[$0]?.isConstruction ?? false }
        let arc = edited.addArc(center: center, start: isCounterClockwise ? first : second, end: isCounterClockwise ? second : first,
                                isConstruction: isConstruction)
        edited.add(.tangent(lines[0], arc))
        edited.add(.tangent(lines[1], arc))
        edited.addDimension(.radius(arc), value: radius)
        return SketchEdit(sketch: edited, description: "Fillet \(sketch.label(of: corner)) (\(radius.sketchDisplay) mm)")
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.FilletTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 133 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketch/Commands/SketchCommands+Fillet.swift Tests/CreatorSketchTests/FilletTests.swift
git commit -m "feat(sketch): add the fillet command"
```
(End the message with the blank line and attribution lines from Global Constraints.)

### Task 12: Mirror and patterns, and the S3–S5 handoff notes
**Files:**
- Create: `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`, `Sources/CreatorSketch/Commands/SketchCommands+Copy.swift`, `Sources/CreatorSketch/Commands/SketchCommands+Mirror.swift`, `Sources/CreatorSketch/Commands/SketchCommands+Pattern.swift`, `Tests/CreatorSketchTests/MirrorPatternTests.swift`
- Modify: `docs/superpowers/roadmap.md`
- Test: `Tests/CreatorSketchTests/MirrorPatternTests.swift`

**Interfaces:**
- Consumes: `SketchCommands.newPoint` and `SketchMath.reflected`/`rotated` (Tasks 3, 10); `SketchRegions` (Task 9), used in tests.
- Produces:
  - `public static func SketchCommands.mirror(_:entities:about:) throws(SketchCommandError) -> SketchEdit`
  - `public static func SketchCommands.linearPattern(_:entities:direction:spacing:count:) throws(SketchCommandError) -> SketchEdit`
  - `public static func SketchCommands.circularPattern(_:entities:center:count:) throws(SketchCommandError) -> SketchEdit`
  - internal `SketchCommands.Copy`, `selection(_:in:verb:)`, `points(of:in:)`, `copy(_:in:reversesArcs:stays:transform:)`, `count(_:)`, `patternLimit`, `checkCount(_:)`, `holdRadii(_:in:)`, `holdDirection(of:along:selection:in:)`
  - `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorSketchTests/MirrorPatternTests.swift`:
```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorSketch

struct MirrorPatternTests {
    @Test func mirroringATriangleAddsSymmetricPoints() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10), isConstruction: true)
        let lines = addPolygon(&sketch, [Vector2(2, 0), Vector2(6, 0), Vector2(4, 3)])
        let edit = try SketchCommands.mirror(sketch, entities: lines, about: axis)
        let mirrored = edit.sketch
        #expect(edit.description == "Mirror 3 entities")
        #expect(mirrored.ids(ofKind: "Line").count == 7)
        let symmetric = mirrored.constraintList.filter { if case .symmetric = $0 { true } else { false } }
        #expect(symmetric.count == 3)
        let copies = mirrored.ids(ofKind: "Point").suffix(3).compactMap { mirrored.position(of: $0) }
        #expect(zip(copies, [Vector2(-2, 0), Vector2(-6, 0), Vector2(-4, 3)]).allSatisfy { isClose($0, $1) })
        try requireSolvesInPlace(mirrored)
    }

    @Test func pointsOnTheAxisAreShared() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10))
        let line = sketch.addLine(.zero, Vector2(5, 5))
        let mirrored = try SketchCommands.mirror(sketch, entities: [line, axis], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Line").last)
        #expect(mirrored.ends(copy).0 == sketch.ends(line).0)
        #expect(mirrored.constraints.count == 1)
    }

    @Test func aMirroredArcRunsCounterClockwiseAndStaysFullyConstrained() throws {
        var sketch = Sketch()
        let axis = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(Vector2(0, -10), Vector2(0, 10))))))
        let points = [Vector2(5, 0), Vector2(8, 0), Vector2(5, 3)].map { position in
            let point = sketch.addPoint(position)
            sketch.add(.fix(point, at: position))
            return point
        }
        let arc = sketch.addArc(center: points[0], start: points[1], end: points[2])
        let mirrored = try SketchCommands.mirror(sketch, entities: [arc], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Arc").last)
        let (center, start, end) = mirrored.arcPoints(copy)
        #expect(isClose(try #require(mirrored.position(of: center)), Vector2(-5, 0)))
        #expect(isClose(try #require(mirrored.position(of: start)), Vector2(-5, 3)))
        #expect(isClose(try #require(mirrored.position(of: end)), Vector2(-8, 0)))
        #expect(try requireSolvesInPlace(mirrored).status == .solved)
    }

    @Test func mirroredCirclesKeepEqualRadii() throws {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 10))
        let circle = sketch.addCircle(center: Vector2(4, 4), radius: 2)
        let mirrored = try SketchCommands.mirror(sketch, entities: [circle], about: axis).sketch
        let copy = try #require(mirrored.ids(ofKind: "Circle").last)
        #expect(mirrored.constraintList.contains(.equal(circle, copy)))
        #expect(mirrored.radius(of: copy) == 2)
        try requireSolvesInPlace(mirrored)
    }

    @Test func linearPatternSpacesCopiesWithDistanceDimensions() throws {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 2)
        let edit = try SketchCommands.linearPattern(sketch, entities: [circle], direction: Vector2(3, 0), spacing: 10, count: 3)
        let patterned = edit.sketch
        #expect(edit.description == "Linear pattern of 1 entity (×3)")
        let circles = patterned.ids(ofKind: "Circle")
        try #require(circles.count == 3)
        let centers = circles.compactMap { patterned.position(of: patterned.centerOf($0)) }
        #expect(zip(centers, [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)]).allSatisfy { isClose($0, $1) })
        // Two equal radii, plus the second connector held parallel and equal to the first.
        #expect(patterned.constraintList.filter { if case .equal = $0 { true } else { false } }.count == 3)
        #expect(patterned.constraintList.filter { if case .parallel = $0 { true } else { false } }.count == 1)
        #expect(patterned.constraintList.filter { if case .horizontal = $0 { true } else { false } }.count == 1)
        let distances = patterned.dimensions.values.filter { if case .distance = $0.kind { true } else { false } }
        #expect(distances.map(\.value) == [10])
        try requireSolvesInPlace(patterned)
        #expect(SketchRegions.find(in: patterned).regions.count == 3)
    }

    @Test func circularPatternUsesEqualSpokesAndAngles() throws {
        var sketch = Sketch()
        let pivot = sketch.addPoint(.zero)
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 1)
        let patterned = try SketchCommands.circularPattern(sketch, entities: [circle], center: pivot, count: 4).sketch
        let circles = patterned.ids(ofKind: "Circle")
        try #require(circles.count == 4)
        let centers = circles.compactMap { patterned.position(of: patterned.centerOf($0)) }
        let expected = [Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0), Vector2(0, -10)]
        #expect(zip(centers, expected).allSatisfy { isClose($0, $1, tolerance: 1e-9) })
        let spokes = patterned.ids(ofKind: "Line")
        #expect(spokes.count == 4)
        #expect(spokes.allSatisfy { patterned.entities[$0]?.isConstruction == true })
        let angles = patterned.dimensions.values.filter { if case .angle = $0.kind { true } else { false } }
        #expect(angles.map(\.value) == [90, 90, 90])
        try requireSolvesInPlace(patterned)
        // Spokes are construction: only the four circles are regions.
        #expect(SketchRegions.find(in: patterned).regions.count == 4)
    }

    /// A pattern holds each copy rigidly, without redundancy or new freedom, so a closed loop
    /// patterned keeps the status it had (spec §10: the result solves).
    @Test(arguments: [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
    func linearPatternsOfClosedLoopsKeepTheirStatus(direction: Vector2) throws {
        let rectangle = ConstrainedRectangle()
        var triangle = Sketch()
        let sides = addPolygon(&triangle, [.zero, Vector2(4, 0), Vector2(2, 3)])
        for (sketch, lines) in [(rectangle.sketch, rectangle.lines), (triangle, sides)] {
            let before = SketchSolver.solve(sketch).status
            let patterned = try SketchCommands.linearPattern(sketch, entities: lines, direction: direction, spacing: 80, count: 3).sketch
            #expect(SketchSolver.solve(patterned).status == before)
        }
        let solved = try SketchCommands.linearPattern(rectangle.sketch, entities: rectangle.lines, direction: direction,
                                                      spacing: 80, count: 3).sketch
        #expect(SketchSolver.solve(solved).status == .solved)
    }

    @Test func circularPatternsOfClosedLoopsKeepTheirStatus() throws {
        var rectangle = ConstrainedRectangle(drawnOffset: 0)
        let rectanglePivot = rectangle.sketch.addPoint(Vector2(-30, -30))
        rectangle.sketch.add(.fix(rectanglePivot, at: Vector2(-30, -30)))
        var triangle = Sketch()
        let sides = addPolygon(&triangle, [.zero, Vector2(4, 0), Vector2(2, 3)])
        let trianglePivot = triangle.addPoint(Vector2(-10, 0))
        triangle.add(.fix(trianglePivot, at: Vector2(-10, 0)))
        let cases = [(rectangle.sketch, rectangle.lines, rectanglePivot), (triangle, sides, trianglePivot)]
        for (sketch, lines, pivot) in cases {
            let before = SketchSolver.solve(sketch).status
            let patterned = try SketchCommands.circularPattern(sketch, entities: lines, center: pivot, count: 3).sketch
            #expect(SketchSolver.solve(patterned).status == before)
            try requireSolvesInPlace(patterned)
        }
        #expect(SketchSolver.solve(cases[0].0).status == .solved)
    }

    @Test func linearCopiesFollowTheOriginalRigidly() throws {
        let rectangle = ConstrainedRectangle(drawnOffset: 0)
        var patterned = try SketchCommands.linearPattern(rectangle.sketch, entities: rectangle.lines,
                                                         direction: Vector2(1, 0), spacing: 80, count: 2).sketch
        patterned.dimensions[rectangle.width]?.value = 70
        let solution = SketchSolver.solve(patterned)
        #expect(solution.status == .solved)
        // The copy's corners are the original's, 80 mm along: still a 70 × 40 rectangle.
        let copied = patterned.ids(ofKind: "Point").filter { !rectangle.sketch.ids(ofKind: "Point").contains($0) }
        let originals = rectangle.lines.map { rectangle.sketch.ends($0).0 }
        for (original, copy) in zip(originals, copied) {
            let expected = try #require(solution.points[original]) + Vector2(80, 0)
            #expect(isClose(try #require(solution.points[copy]), expected))
        }
    }

    @Test func patternsNeedTwoOrMoreInstances() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 2)
        #expect(throws: SketchCommandError("A pattern needs at least 2 instances.")) {
            try SketchCommands.linearPattern(sketch, entities: [circle], direction: Vector2(1, 0), spacing: 5, count: 1)
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorSketchTests.MirrorPatternTests`
Expected: compile errors: `type 'SketchCommands' has no member 'mirror'`.

- [ ] **Step 3: Implement**

`Sources/CreatorSketch/Commands/SketchCommands+Copy.swift`:
```swift
import CreatorGeometry

extension SketchCommands {
    /// What one copy of a selection made: old point → new point (a point that stays put maps to
    /// itself) and each copied curve as (original, copy), in ID order.
    struct Copy {
        var points: [SketchEntityID: SketchEntityID] = [:]
        var curves: [(original: SketchEntityID, copy: SketchEntityID)] = []
    }

    /// The selection in ID order, refusing missing entities and projected edges.
    static func selection(_ ids: [SketchEntityID], in sketch: Sketch, verb: String) throws(SketchCommandError) -> [SketchEntityID] {
        let selected = Set(ids).sorted()
        guard !selected.isEmpty else { throw SketchCommandError("Select the geometry to \(verb) first.") }
        for id in selected {
            guard let entity = sketch.entities[id] else { throw SketchCommandError("Some of the selected geometry no longer exists.") }
            if case .projected = entity.kind { throw SketchCommandError("Projected edges can't be copied by \(verb).") }
        }
        return selected
    }

    /// Every point the selection uses (selected points and the curves' points), in ID order.
    static func points(of selection: [SketchEntityID], in sketch: Sketch) -> [SketchEntityID] {
        var points = Set<SketchEntityID>()
        for id in selection {
            guard let kind = sketch.entities[id]?.kind else { continue }
            if kind.isPoint { points.insert(id) } else { points.formUnion(kind.referencedPoints) }
        }
        return points.sorted()
    }

    /// Copies the selection, moving every point through `transform` except those `stays` keeps.
    /// `reversesArcs` swaps arc ends so a mirrored arc still runs counter-clockwise.
    static func copy(_ selection: [SketchEntityID], in sketch: inout Sketch, reversesArcs: Bool,
                     stays: (Vector2) -> Bool, transform: (Vector2) -> Vector2) -> Copy {
        var copy = Copy()
        for point in points(of: selection, in: sketch) {
            guard let position = sketch.position(of: point) else { continue }
            copy.points[point] = stays(position) ? point : newPoint(at: transform(position), in: &sketch)
        }
        for id in selection {
            guard let entity = sketch.entities[id], !entity.kind.isPoint else { continue }
            func mapped(_ point: SketchEntityID) -> SketchEntityID { copy.points[point] ?? point }
            let kind: SketchEntityKind = switch entity.kind {
            case .line(let start, let end): .line(start: mapped(start), end: mapped(end))
            case .arc(let center, let start, let end):
                reversesArcs ? .arc(center: mapped(center), start: mapped(end), end: mapped(start))
                    : .arc(center: mapped(center), start: mapped(start), end: mapped(end))
            case .circle(let center, _): .circle(center: mapped(center), radius: sketch.radius(of: id) ?? 1)
            case .point, .projected: entity.kind
            }
            let duplicate = sketch.add(SketchEntity(kind, isConstruction: entity.isConstruction))
            if case .circle = kind, let radius = sketch.radius(of: id) { sketch.solved[duplicate] = .radius(radius) }
            copy.curves.append((id, duplicate))
        }
        return copy
    }

    /// "1 entity", "3 entities".
    static func count(_ n: Int) -> String { n == 1 ? "1 entity" : "\(n) entities" }
}
```
`Sources/CreatorSketch/Commands/SketchCommands+Mirror.swift`:
```swift
import CreatorGeometry

extension SketchCommands {
    /// Copies the selection reflected in `axis` (spec §3), holding each copied point symmetric to
    /// its original about the axis. Points on the axis are shared, not copied. Mirrored circles
    /// also get an equal-radius constraint; arcs are fully held by their three symmetric points.
    public static func mirror(_ sketch: Sketch, entities ids: [SketchEntityID], about axis: SketchEntityID) throws(SketchCommandError) -> SketchEdit {
        guard case .line(let a, let b)? = sketch.shape(of: axis) else {
            throw SketchCommandError("Mirror needs a line to mirror about.")
        }
        let selection = try selection(ids.filter { $0 != axis }, in: sketch, verb: "mirror")
        var edited = sketch
        let copy = copy(selection, in: &edited, reversesArcs: true, stays: { position in
            guard let unit = SketchMath.normalized(b - a) else { return false }
            return abs(SketchMath.cross(unit, position - a)) <= CurveIntersection.tolerance
        }, transform: { SketchMath.reflected($0, inLineThrough: a, b) })
        for (original, mirrored) in copy.points.sorted(by: { $0.key < $1.key }) where original != mirrored {
            edited.add(.symmetric(original, mirrored, about: axis))
        }
        for pair in copy.curves {
            if case .circle = edited.entities[pair.copy]?.kind { edited.add(.equal(pair.original, pair.copy)) }
        }
        return SketchEdit(sketch: edited, description: "Mirror \(count(selection.count))")
    }
}
```
`Sources/CreatorSketch/Commands/SketchCommands+Pattern.swift`:
```swift
import CreatorGeometry
import Foundation

extension SketchCommands {
    /// The most instances one pattern command makes.
    static let patternLimit = 1000

    /// `count − 1` copies of the selection, each `spacing` further along `direction` (spec §3).
    ///
    /// Every instance is held as an exact translation, with exactly two rows per copied point, so
    /// patterning never adds redundancy or freedom. A construction connector joins each point to
    /// its copy in the next instance. The first connector from the selection's first point gets
    /// a distance dimension of `spacing`, and its direction is held: horizontal or vertical when
    /// `direction` is, otherwise parallel, perpendicular or at a measured angle to the
    /// selection's first line. With no line in the selection, an oblique direction stays free.
    /// Every other connector is held parallel and equal to that first one. Copied circles are
    /// held equal to their originals; lines and arcs need nothing more, since their points are held.
    public static func linearPattern(_ sketch: Sketch, entities ids: [SketchEntityID], direction: Vector2,
                                     spacing: Double, count: Int) throws(SketchCommandError) -> SketchEdit {
        let selection = try selection(ids, in: sketch, verb: "pattern")
        try checkCount(count)
        guard spacing > 0, spacing.isFinite else { throw SketchCommandError("The pattern spacing must be greater than 0 mm.") }
        guard let unit = SketchMath.normalized(direction) else { throw SketchCommandError("The pattern needs a direction.") }
        let points = points(of: selection, in: sketch)
        var edited = sketch
        var previous = Dictionary(uniqueKeysWithValues: points.map { ($0, $0) })
        var first: SketchEntityID?
        for instance in 1..<count {
            let offset = unit * (spacing * Double(instance))
            let copy = copy(selection, in: &edited, reversesArcs: false, stays: { _ in false }, transform: { $0 + offset })
            holdRadii(copy, in: &edited)
            for point in points {
                guard let from = previous[point], let to = copy.points[point] else { continue }
                let connector = edited.addLine(from: from, to: to, isConstruction: true)
                if let first {
                    edited.add(.parallel(first, connector))
                    edited.add(.equal(first, connector))
                } else {
                    first = connector
                    edited.addDimension(.distance(from, to), value: spacing)
                    holdDirection(of: connector, along: unit, selection: selection, in: &edited)
                }
                previous[point] = to
            }
        }
        return SketchEdit(sketch: edited, description: "Linear pattern of \(Self.count(selection.count)) (×\(count))")
    }

    /// `count − 1` copies of the selection rotated about `center` in equal steps round a full turn
    /// (spec §3).
    ///
    /// Every instance is held as an exact rotation, with exactly two rows per copied point. Each
    /// point away from the centre gets a construction spoke from the centre, and so does each of
    /// its copies; a copy's spoke is held equal to the original's spoke, with an angle dimension
    /// of one step from the previous instance's spoke. Points at the centre are shared, so arcs
    /// and circles centred on it stay concentric. Copied circles are held equal to their originals.
    public static func circularPattern(_ sketch: Sketch, entities ids: [SketchEntityID], center: SketchEntityID,
                                       count: Int) throws(SketchCommandError) -> SketchEdit {
        let selection = try selection(ids.filter { $0 != center }, in: sketch, verb: "pattern")
        try checkCount(count)
        guard let pivot = sketch.position(of: center) else { throw SketchCommandError("A circular pattern needs a centre point.") }
        let step = 360 / Double(count)
        let isAtCenter = { (position: Vector2) in (position - pivot).length <= CurveIntersection.tolerance }
        let moving = points(of: selection, in: sketch).filter { sketch.position(of: $0).map { !isAtCenter($0) } ?? false }
        guard !moving.isEmpty else { throw SketchCommandError("Select geometry away from the pattern centre.") }
        var edited = sketch
        var originals: [SketchEntityID: SketchEntityID] = [:]
        for point in moving { originals[point] = edited.addLine(from: center, to: point, isConstruction: true) }
        var previous = originals
        for instance in 1..<count {
            let angle = Double(instance) * step * .pi / 180
            let copy = copy(selection, in: &edited, reversesArcs: false, stays: isAtCenter,
                            transform: { SketchMath.rotated($0, about: pivot, by: angle) })
            holdRadii(copy, in: &edited)
            for point in moving {
                guard let next = copy.points[point], let original = originals[point], let last = previous[point] else { continue }
                let spoke = edited.addLine(from: center, to: next, isConstruction: true)
                edited.add(.equal(original, spoke))
                edited.addDimension(.angle(last, spoke), value: step)
                previous[point] = spoke
            }
        }
        return SketchEdit(sketch: edited, description: "Circular pattern of \(Self.count(selection.count)) (×\(count))")
    }

    static func checkCount(_ count: Int) throws(SketchCommandError) {
        guard count >= 2 else { throw SketchCommandError("A pattern needs at least 2 instances.") }
        guard count <= patternLimit else { throw SketchCommandError("A pattern can have at most \(patternLimit) instances.") }
    }

    /// Equal radii between each copied circle and its original. A circle's radius is its own
    /// unknown; every other curve is fully held by its points.
    static func holdRadii(_ copy: Copy, in sketch: inout Sketch) {
        for pair in copy.curves {
            if case .circle = sketch.entities[pair.copy]?.kind { sketch.add(.equal(pair.original, pair.copy)) }
        }
    }

    /// Holds the first connector of a linear pattern along the pattern direction with one row.
    static func holdDirection(of connector: SketchEntityID, along unit: Vector2, selection: [SketchEntityID],
                              in sketch: inout Sketch) {
        let exact = 1e-12
        if abs(unit.y) <= exact {
            sketch.add(.horizontal(connector))
            return
        }
        if abs(unit.x) <= exact {
            sketch.add(.vertical(connector))
            return
        }
        for line in selection {
            guard case .line(let a, let b)? = sketch.shape(of: line) else { continue }
            let d = b - a
            let degrees = abs(atan2(SketchMath.cross(d, unit), SketchMath.dot(d, unit))) * 180 / .pi
            let angleTolerance = 1e-9
            if degrees <= angleTolerance || degrees >= 180 - angleTolerance {
                sketch.add(.parallel(line, connector))
            } else if abs(degrees - 90) <= angleTolerance {
                sketch.add(.perpendicular(line, connector))
            } else {
                sketch.addDimension(.angle(line, connector), value: degrees)
            }
            return
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorSketchTests.MirrorPatternTests`
Expected: PASS.
Run: `swift test --filter CreatorSketchTests`
Expected: PASS, 143 tests, no warnings from `CreatorSketch` (OCCT's "built for newer macOS" linker warnings are expected noise).

- [ ] **Step 5: Record the handoff**

Create `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`:
```markdown
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
```

In `docs/superpowers/roadmap.md`, replace the status cell of the `| 6 | Constraint sketcher …` row. The cell is `💬`; make it
`🔄 S1+S2 (CreatorSketch: solver, regions, commands) done on spec/sketcher; S3 after M3 merges`, and change no other row.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketch/Commands/SketchCommands+Copy.swift Sources/CreatorSketch/Commands/SketchCommands+Mirror.swift Sources/CreatorSketch/Commands/SketchCommands+Pattern.swift Tests/CreatorSketchTests/MirrorPatternTests.swift docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md docs/superpowers/roadmap.md
git commit -m "feat(sketch): add mirror and pattern commands; record the S3-S5 handoff"
```
(End the message with the blank line and attribution lines from Global Constraints.)
