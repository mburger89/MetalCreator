# NS-3: Control points — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edit Surface and Edit Curve (control-point moves stored in the graph), a viewport mode that drags control points,
Rebuild Surface and Rebuild Curve (a chosen degree and span count), and Surface facts.

**Architecture:** The kernel reads a one-face sheet's or a one-piece curve's B-spline net (`BRepBuilderAPI_NurbsConvert` /
`GeomConvert` for anything else), moves poles in a copy and rebuilds the boundary edges from their pcurves, so the
topology, and therefore every tag and pick, is the input's. The moves are a node setting (`ConstantValue.poleMoves`, file
format 15). The viewport mode is an app-level session like Measure's: a `ViewportTool` over the net read once from the
node's input, drawn as an overlay of base poles plus the stored moves, so a drag redraws at once and the graph catches up.
Rebuild is our own least-squares fit on uniform knots, put back under the face's own trims by the same surface-replacing
helper.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 (`BRepBuilderAPI_NurbsConvert`, `GeomConvert`,
`Geom_BSplineSurface`, `BRepLib::BuildCurves3d`, `BRepLib::SameParameter`, `BRepCheck_Analyzer`), MetalUI.

**Spec:** `docs/superpowers/specs/2026-11-17-nurbs-surfaces-design.md`. Read §Rules every surface node follows, §Drawing
(control nets) and §NS-3. Read CLAUDE.md's NS-1 and NS-2 paragraphs for the sheet contract, and its Measure paragraph for
the session pattern this plan copies.

## Global Constraints

- **Worktree and branch.** Worktree `/Users/maxburger/Developer/MetalCreator-ns3`, branch `ns-3`. Never touch MetalUI.
- **OCCT only through the kernel,** under `OCCTKernel.serialized`; every C allocation has a `*_free`; no C++ exception
  crosses into Swift (`guarded`). Shim portability: no `M_PI` (`cocct::kPi`), no POSIX headers, no `__attribute__`, never the
  token `near` (reword; never split it across literals).
- **Valid results only.** Every moved or rebuilt shape is checked with `BRepCheck_Analyzer`; an invalid one is refused in a
  sentence.
- **Limits** (spec): degree 1 to 11; at most 100,000 control points per surface; every limit is a sentence.
- **Cancellation** is asked between rows and fitting passes.
- **Messages** are full sentences, numbers through `Locale.messages`.
- **Hidden geometry is an anti-goal:** a control-point move is a node setting, never a change outside the graph.
- **Picks don't drift:** an Edit Surface, Edit Curve or Rebuild Surface result keeps the input's topology tables unchanged.
- **File format 15** (`GraphFile.currentFormatVersion`): `poleMoves` is a new `ConstantValue` kind. Files of format 1 to 14
  open unchanged and are written as 15.
- **Undo names** have no numbers and no typed text: "Move Control Points" (a drag, one step) and "Change Control Point"
  (typed in the inspector). Selecting points makes no step.
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; `swiftlint lint --strict` over the
  whole tree; macOS and Linux each print 14 "Test run with" lines; never block a pool thread in a test (use `HookGate`).
- **Commit trailer:** `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec)

- **R1. Rebuild is two nodes,** Rebuild Surface and Rebuild Curve, not one node with two inputs, so each has plain sockets
  and its own facts. 104 built-in nodes after NS-3 (Edit Surface, Edit Curve, Rebuild Surface, Rebuild Curve).
- **R2. Rebuild keeps the face's trims.** The new surface spans the old one's parameter range, so the face's pcurves stay
  valid and its edges are rebuilt from them; a trimmed face stays trimmed and its picks keep naming the same edges.
  Rebuild Curve makes one B-spline piece of the whole curve (several pieces become one), clamped, its end points pinned.
- **R3. The fit is ours,** least squares over uniform knots on the source's own parameters (separable for a surface: rows,
  then columns), not `GeomAPI_PointsToBSplineSurface`, which chooses its own knots and so can't honour a span count.
- **R4. Edit Curve takes a one-piece curve,** refusing more: "Edit Curve takes a curve of one piece; this one has 3. Rebuild
  it first." A line or arc is converted exactly.
- **R5. Axis locks toggle.** X, Y, Z and N set a lock that holds for the next drags until pressed again, another lock is
  chosen, or the mode ends; the inspector shows it. N is the surface normal at the dragged point's Greville parameters;
  on Edit Curve N does nothing.
- **R6. The mode works on one surface at the top level.** Inside a group it is refused in the sketch's words ("Control
  points inside a group can't be edited yet. Edit them before grouping, or from the top level."); a node that gets a list
  is refused: "Edit Control Points works on one surface; this node gets 3." (curve: "one curve").
- **R7. Box select is a plain primary drag on empty space** (replaces), ⌘-drag toggles. A Shift-drag stays the viewport's
  pan, as `ViewportTool.dragBegan` already reserves it; ⇧ adds only on clicks.
- **R8. The net is drawn over the model** (no depth test against the surface) and points are pickable through it, within
  8 points on screen, the nearest to the camera winning a tie.
- **R9. Exclusivity** follows Measure: starting the mode ends Measure; while the mode is on, sketching, picks, the model
  dimension tool and Measure are refused, MCP edits are refused ("MetalCreator is editing control points. Click Done, then
  try again."), and New, Open, removing the node or undoing it away end the mode.

## Review Focus

1. **The net changes size upstream** (a degree or span change). Moves whose index no longer exists are dropped from the
   result, kept in the setting, and warned about; the mode clears its point selection. Task 5 and Task 7.
2. **A move that makes the face invalid** (a pole dragged through the opposite side) is refused in words, not returned.
   Task 3.
3. **A trimmed face** (Planar Surface on a circle, an imported trimmed face): moving poles and rebuilding keep the trim and
   the boundary edges' tags. Tasks 3 and 4.
4. **A rational input** (a cylinder converted exactly): moves change positions only; weights are kept as read. Task 3.
5. **A drag while the upstream node is still evaluating:** the overlay keeps the last net it read and never shows a mix of
   two nets. Task 7.

---

### Task 1: Pole moves in the file (format 15)

**Files:**
- Create: `Sources/CreatorKernel/ControlNet.swift`
- Modify: `Sources/CreatorGraph/ConstantValue.swift`, `Sources/CreatorGraph/NodeSetting.swift`,
  `Sources/CreatorGraph/GraphFile.swift`, every exhaustive `switch` over `ConstantValue` the compiler names (MCP encoding,
  clipboard, inspector).
- Test: `Tests/CreatorGraphTests/PoleMovesFileTests.swift`

**Interfaces:**
- Produces:
  - `public struct PoleIndex: Hashable, Comparable, Codable, Sendable { public var i: Int; public var j: Int }` (curves use
    `j == 0`; ordered by `i` then `j`).
  - `public struct PoleMove: Hashable, Codable, Sendable { public var index: PoleIndex; public var offset: Vector3 }`.
  - `ConstantValue.poleMoves([PoleMove])`, stored sorted by index, at most one move per index, finite offsets (`isFinite`).
  - `NodeSetting.poleMoves: SocketName = "poleMoves"`, in `all` and `reservedForSockets`.
  - `GraphFile.currentFormatVersion == 15`.

- [ ] **Step 1: Tests.** `poleMovesRoundTrip` (encode, decode, equal, sorted output for unsorted input);
  `aFormat14FileOpens` (an existing format-14 fixture decodes); `nonFiniteOffsetsAreRejected` (`isFinite` false for a NaN
  offset, so `.setInput` refuses it); `theSettingIsReserved` (a group socket named "poleMoves" is refused).
- [ ] **Step 2: Run** `swift test --filter PoleMovesFileTests`; expect compile failure.
- [ ] **Step 3: Implement.** The Codable kind is `poleMoves`; the value is an array of `{"i","j","offset"}`.
- [ ] **Step 4: Run** the filter, then `swift test --filter CreatorGraphTests`; pass.
- [ ] **Step 5: Commit** "NURBS: pole moves in the file (format 15)".

### Task 2: Reading control nets and surface facts (kernel)

**Files:**
- Create: `Sources/CreatorGeometry/Curves/BSplineSurface3D.swift`, `Sources/COCCT/cocct_control_net.cpp`,
  `Sources/CreatorOCCT/OCCTKernel+ControlNet.swift`
- Modify: `Sources/CreatorKernel/ControlNet.swift`, `Sources/CreatorKernel/Kernel.swift` (requirements and refusing
  defaults), `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/ControlNetTests.swift`

**Interfaces:**
- Produces:
  - `BSplineSurface3D` (CreatorGeometry; pure data like `BSplineCurve3D`): `degreeU`, `degreeV`, `uCount`, `vCount`,
    `poles` row-major (`poles[i * vCount + j]`, i along u), `weights: [Double]?`, `knotsU`, `multiplicitiesU`, `knotsV`,
    `multiplicitiesV`, `isPeriodicU`, `isPeriodicV`, `isWellFormed`.
  - `public enum SurfaceKind: String, Sendable { plane, cylinder, cone, sphere, torus, bezier, bspline, revolution,
    extrusion, offset, other }`.
  - `public struct SurfaceNet: Sendable { surface: BSplineSurface3D; normals: [Vector3] /* per pole, at its Greville
    point */; convertedFrom: SurfaceKind? /* nil when already a B-spline */ }`.
  - `public struct CurveNet: Sendable { curve: BSplineCurve3D; isPeriodic: Bool; convertedFrom: CurvePieceKind? }` with
    `CurvePieceKind` `line`, `arc`, `other`.
  - `public struct SurfaceInfo: Sendable { kind: SurfaceKind; net: BSplineSurface3D? /* for bezier and bspline */ }`.
  - `Kernel.controlNet(of surface: Solid) throws -> SurfaceNet`, `Kernel.controlNet(of curve: Curve) throws -> CurveNet`,
    `Kernel.surfaceInfo(of face: FaceID, in solid: Solid) throws -> SurfaceInfo`. Defaults and `FakeKernel` throw
    `.unsupported`.

- [ ] **Step 1: Tests.**
  - `aLoftedSheetGivesItsNet`: a Loft Surface of three curves; the net's corner poles are the corner points (1e-9), sizes
    and degrees as OCCT made them, `convertedFrom == nil`.
  - `aPlanarSheetConvertsExactly`: Planar Surface of a 10 mm square → degree 1 × 1, 2 × 2 poles at the square's corners,
    `convertedFrom == .plane`.
  - `aRevolvedSheetIsRational`: a line revolved 90° → `weights != nil`, `convertedFrom == .revolution` or `.cylinder`
    (whichever OCCT reports), every pole's normal unit length.
  - `aSheetOfTwoFacesIsRefused`: "Edit Surface takes a sheet with one face; this one has 2. Rebuild or Split it first."
  - `aClosedSolidIsRefused`: a box → "Edit Surface takes a sheet; this is a closed solid."
  - `aNetOverTheLimitIsRefused`: a 400 × 300 B-spline sheet (made by `networkSurface` or a test helper) →
    "This surface has 120,000 control points; Edit Surface works on at most 100,000."
  - `aCurvesNet`: a degree-5 Curve through Points → its poles; a line → degree 1, 2 poles, `convertedFrom == .line`;
    a three-piece curve → R4's sentence.
  - `surfaceInfoNamesTheKind`: a box face → `.plane`, `net == nil`; a lofted face → `.bspline` with its net.
- [ ] **Step 2: Run** `swift test --filter ControlNetTests`; fail.
- [ ] **Step 3: Implement** `occt_control_net_of_face`, `occt_control_net_of_curve`, `occt_surface_info` (C structs with
  counts and flat arrays, each with a `*_free`). A non-B-spline face goes through `BRepBuilderAPI_NurbsConvert` on a copy;
  a Bezier through `GeomConvert::SurfaceToBSplineSurface`. Normals at Greville parameters, oriented by the face's
  orientation.
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "NURBS: read control nets".

### Task 3: Moving poles (kernel)

**Files:**
- Modify: `Sources/COCCT/cocct_control_net.cpp` (add the move and the shared `replace_face_surface` helper),
  `Sources/CreatorOCCT/OCCTKernel+ControlNet.swift`, `Sources/CreatorKernel/Kernel.swift`
- Test: `Tests/CreatorOCCTTests/PoleMoveTests.swift`

**Interfaces:**
- Consumes: Task 2's nets and refusals.
- Produces:
  - `Kernel.movingPoles(of surface: Solid, by moves: [PoleMove]) throws -> Solid`: the face's surface converted as in Task
    2, the moved poles offset, weights unchanged; the result's `Topology` is the input's, unchanged.
  - `Kernel.movingPoles(of curve: Curve, by moves: [PoleMove]) throws -> Curve`: the same for a one-piece curve, keeping
    its piece tag.
  - Shim helper `replace_face_surface(face, new_surface) -> TopoDS_Face`, used again by Task 4: the face rebuilt on the new
    surface with its pcurves kept, every edge's 3D curve dropped and rebuilt from its pcurve (`BRepLib::BuildCurves3d`),
    `BRepLib::SameParameter`, the copy checked by `BRepCheck_Analyzer`.
- Every index in `moves` must exist (the node filters first); an index outside the net throws `.invalidInput`.

- [ ] **Step 1: Tests.**
  - `movingACornerMovesTheSurfaceAndItsEdges`: a 3 × 3 lofted sheet, pole (0, 0) moved by (0, 0, 2) → the face's corner and
    the two boundary edges through it end at the new corner (1e-6); the other corners don't move.
  - `topologyIsTheInputs`: `result.topology == input.topology` (faces, edges and boundary roles, in order).
  - `aTrimmedFaceStaysTrimmed`: Planar Surface of a 10 mm circle, an interior pole moved by (0, 0, 1) → still one face,
    one boundary edge, valid, its edge's tags unchanged, area changed.
  - `weightsAreKept`: a revolved (rational) sheet, a pole moved → the moved net's weights equal the input's.
  - `aFoldingMoveIsRefused`: a pole of a planar 3 × 3 net dragged far across the opposite edge so the face self-overlaps →
    "Moving these control points makes an invalid surface." (if OCCT's checker accepts the fold, pick the move that the
    checker rejects and assert the sentence; the point is that `BRepCheck_Analyzer` gates the result).
  - `aCurvesPoleMoves`: a Curve through Points with pole 2 moved → `controlNet(of:)` of the result shows the moved pole;
    its end points unchanged when an interior pole moved.
- [ ] **Step 2: Run** `swift test --filter PoleMoveTests`; fail.
- [ ] **Step 3: Implement** `occt_move_face_poles` and `occt_move_curve_poles` (copy the shape first; never mutate a
  surface another solid shares).
- [ ] **Step 4: Run** the filter and `ControlNetTests`; pass.
- [ ] **Step 5: Commit** "NURBS: move control points".

### Task 4: Rebuild (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_rebuild.cpp`, `Sources/CreatorOCCT/OCCTKernel+Rebuild.swift`
- Modify: `Sources/CreatorKernel/ControlNet.swift`, `Sources/CreatorKernel/Kernel.swift`, `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/RebuildTests.swift`

**Interfaces:**
- Consumes: `replace_face_surface` (Task 3).
- Produces:
  - `public struct RebuildSpec: Hashable, Sendable { degreeU, degreeV, spansU, spansV: Int }` (a curve uses `degreeU` and
    `spansU`); `validate(for poles limit)` throws the sentences below.
  - `public struct SurfaceRebuild: Sendable { sheet: Solid; deviation: Double }`,
    `public struct CurveRebuild: Sendable { curve: Curve; deviation: Double }`.
  - `Kernel.rebuilt(_ surface: Solid, as spec: RebuildSpec) async throws -> SurfaceRebuild` (topology unchanged, R2).
  - `Kernel.rebuilt(_ curve: Curve, as spec: RebuildSpec, tag: NodeTag) async throws -> CurveRebuild` (one `.spline` piece).
- The fit (R3): samples per direction `4 × (degree + spans) + 1`, evenly in the face's parameter range (a curve: by arc
  length over every piece); uniform interior knots; least squares (normal equations, Cholesky, our code) for each row, then
  each column; a curve's end poles pinned to its end points. `deviation` is the largest distance from the source at a grid
  twice as dense, inside the face's parameter box. Cancellation polled between rows.
- Sentences: "The degree must be from 1 to 11.", "There must be at least 1 span.", "That would make 120,000 control
  points; a surface may have at most 100,000."

- [ ] **Step 1: Tests.**
  - `aPlaneRebuildsExactly`: a planar square at degree 3 × 3, 2 × 2 spans → deviation < 1e-9, 5 × 5 poles.
  - `aRevolvedSheetRebuildsNonRational`: a quarter cylinder (radius 10) at degree 3, 8 spans around → `weights == nil`,
    deviation < 1e-3 mm, and the rebuilt face's boundary edges keep their tags.
  - `aTrimmedFaceKeepsItsTrim` (R2): Planar Surface of a circle at degree 2 × 2, 1 × 1 → still one boundary edge, same tag.
  - `deviationIsReportedHonestly`: a wavy loft at degree 1 × 1, 1 × 1 → deviation equals the measured largest gap within
    1 % (measure independently with `shortestDistance` at a few known points).
  - `aThreePieceCurveBecomesOne`: line + arc + line → one piece, ends pinned (1e-9), deviation < 0.01 at degree 3, 12 spans.
  - The three limit sentences.
- [ ] **Step 2: Run** `swift test --filter RebuildTests`; fail.
- [ ] **Step 3: Implement** `occt_rebuild_face` and `occt_rebuild_curve`.
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "NURBS: rebuild surfaces and curves".

### Task 5: Edit Surface and Edit Curve nodes

**Files:**
- Create: `Sources/CreatorNodes/Surfaces/EditSurfaceNode.swift`, `EditCurveNode.swift`, `ControlNetFacts.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`, `Sources/CreatorGraph/InspectorAction.swift`
- Test: `Tests/CreatorNodesTests/EditSurfaceNodeTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces:
  - `creator.editSurface`: input `surface` (`.solid`), output `surface`; setting `poleMoves` (seeded empty);
    `factsTitle` "Surface"; inspector button "Edit Control Points" (`InspectorAction.editControlPoints`, first, so a double
    click presses it).
  - `creator.editCurve`: input `curve` (`.curve`), output `curve`; the same setting, action and title "Curve".
  - `ControlNetFacts.surface(_ net: BSplineSurface3D, kind: SurfaceKind?) -> [PayloadFact]` and `.curve(…)`: "Degree:
    3 × 3", "Control points: 6 × 8", "Knots: 4 × 6", "Rational: no", plus "Converted exactly from a cylinder." when
    converted. Used by Task 6 too.
- Behaviour: the node reads the net, splits `poleMoves` into fitting and stale (index outside the net), moves the fitting
  ones, warns about the stale ones: "3 control point moves no longer fit the surface's 6 × 8 net." (singular "1 control
  point move no longer fits …"; curve: "… the curve's 12 control points."). With no moves it returns its input unchanged
  (no kernel copy). `readsScrubbing` is false.

- [ ] **Step 1: Tests** (OCCT-gated where geometry matters): `noMovesPassesTheSurfaceThrough` (same object);
  `aMoveMovesThePole`; `staleMovesWarnAndStayInTheSetting` (a 6 × 8 net, moves at (7, 0) and (0, 9) and (1, 1) → one move
  applied, the warning with "2 control point moves … 6 × 8 net.", the setting unchanged); `picksDownstreamSurvive` (Edges by
  Tag on the result's boundary edge picks the same edge before and after a move); `factsListTheNet`;
  `editCurveMovesAPole`; `theButtonIsFirst` (`doubleClickActions` presses `editControlPoints`).
- [ ] **Step 2: Run** `swift test --filter EditSurfaceNodeTests`; fail.
- [ ] **Step 3: Implement**, registering both nodes in the `.surface` category's Make section.
- [ ] **Step 4: Run** the filter and `OutputNodeTests` (node count 102 now, `.surface` 12); pass.
- [ ] **Step 5: Commit** "NURBS: Edit Surface and Edit Curve nodes".

### Task 6: Rebuild Surface and Rebuild Curve nodes

**Files:**
- Create: `Sources/CreatorNodes/Surfaces/RebuildSurfaceNode.swift`, `RebuildCurveNode.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorNodesTests/RebuildNodeTests.swift`

**Interfaces:**
- Consumes: Task 4, `ControlNetFacts`.
- Produces: `creator.rebuildSurface` (inputs `surface`, `degreeU` 3, `degreeV` 3, `spansU` 4, `spansV` 4, `tolerance`
  0.01 mm; output `surface`) and `creator.rebuildCurve` (`curve`, `degree` 3, `spans` 8, `tolerance`; output `curve`).
  Integers 1 to 11 for degrees, 1 to 1,000 for spans. Facts as Task 5 plus "Deviation: 0.003 mm". Above `tolerance` it
  warns: "The rebuilt surface is up to 0.12 mm from the original, more than the 0.01 mm tolerance." (curve: "The rebuilt
  curve …").

- [ ] **Step 1: Tests:** `aRebuildReportsItsDeviation`, `aDeviationAboveToleranceWarns`, `limitsAreSentences`,
  `rebuildCurveJoinsPieces`, and `aRebuildFeedsEditSurface` (Rebuild → Edit Surface, a move applies on the rebuilt net).
- [ ] **Step 2: Run**; fail. **Step 3: Implement.** **Step 4: Run** the filter and `OutputNodeTests` (104 nodes,
  `.surface` 14); pass.
- [ ] **Step 5: Commit** "NURBS: Rebuild Surface and Rebuild Curve nodes".

### Task 7: The control-net tool (model)

**Files:**
- Create: `Sources/CreatorApp/ControlNet/ControlNetSession.swift`, `ControlNetSession+Drag.swift`,
  `ControlNetSession+Overlay.swift`
- Test: `Tests/CreatorAppTests/ControlNetSessionTests.swift`

**Interfaces:**
- Consumes: `SurfaceNet`/`CurveNet` (Task 2), `PoleMove` (Task 1), `ViewportTool`, `ViewportProjector`
  (`screenPoint(of:)`, `planePoint(under:on:)`), `OverlayPoint`, `OverlayLine`.
- Produces: `@MainActor final class ControlNetSession: ViewportTool` with
  - `init(node: NodeID, kind: Kind /* .surface, .curve */, events: Events)` where `Events` carries
    `moved: ([PoleMove], DragPhase) -> Void` and `ended: () -> Void`;
  - `func showNet(_ net: ControlNetGrid, moves: [PoleMove])` (`ControlNetGrid`: base poles, `uCount`, `vCount`, normals) —
    replacing a net of another size clears `selection`;
  - `selection: Set<PoleIndex>`, `lock: AxisLock?` (`.x`, `.y`, `.z`, `.normal`), `boxRect: ScreenRect?` (for the app's box
    view), `overlay: ViewportOverlay`;
  - `func toggleLock(_ lock: AxisLock)`, `func setOffset(_ component: Int, to value: Double)` (one selected point; emits
    `moved` with phase `.typed`).
- Behaviour: R5, R7, R8. Net lines are `.construction` (dashed) between neighbours in u and in v; points `.underConstrained`,
  selected `.selected`, hovered `.hovered`, size 7. A drag on a selected point moves the whole selection by the pointer's
  movement in the plane through the grabbed point facing the camera; with an axis lock, by its component along the axis
  (`.normal`: the grabbed point's normal). Each drag step emits `moved` with every selected point's new total offset
  (`.changed`), and the release once (`.ended`). A drag on an unselected point selects it first. Esc (`cancel()`) and Done
  call `ended`.

- [ ] **Step 1: Tests** (a fake projector looking down −Z, orthographic, 1 mm per point):
  `aClickPicksThePointWithin8Points`, `shiftClickAdds`, `commandClickToggles`, `aClickOnEmptySpaceClears`,
  `aDragOnEmptySpaceBoxSelects`, `commandBoxToggles`, `dragMovesTheSelectionInTheViewPlane` (a 5 mm pointer move →
  offsets of 5 mm in x for both selected points), `zLockMovesAlongZOnly` (camera looking along −Y), `normalLockFollowsTheNormal`,
  `aNetOfAnotherSizeClearsTheSelection`, `typingSetsTheOffset`, `theOverlayHasNetLinesAndPoints` (a 3 × 4 net → 17 lines,
  12 points), `aDragEmitsOneEnded`.
- [ ] **Step 2: Run** `swift test --filter ControlNetSessionTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "NURBS: the control-net tool".

### Task 8: Control-point mode in the app

**Files:**
- Create: `Sources/CreatorApp/AppModel+ControlNet.swift`, `Sources/CreatorApp/ControlNet/ControlNetInspector.swift`,
  `ControlNetBoxView.swift`, `ControlNetKeys.swift`
- Modify: `AppModel.swift` (`controlNet: ControlNetSession?`), `AppModel+Picking.swift` (the action), `InspectorDock.swift`,
  `AppInput.swift`/`AppKeyContext.swift` as the keys need, `MCP/AppDocumentSession.swift`, `UndoName.swift`
  (`moveControlPoints`, `changeControlPoint`), the Measure, sketch, pick and model-dimension entry points (R9)
- Test: `Tests/CreatorAppTests/ControlNetModeTests.swift`

**Interfaces:**
- Consumes: Tasks 5 and 7.
- Produces: `AppModel.editControlPoints(of: NodeID)`, `AppModel.endControlPoints()`.
- Behaviour:
  - Entering (R6, R9) installs the session as `viewport.tool`; the base net is read off the main actor from the value on the
    node's input (`kernel.controlNet(of:)`) and re-read after each evaluation in which that value changed, never mixing two
    (Review Focus 5); "The surface isn't ready." shows in the inspector while there is none.
  - `moved` → `document.perform(.setInput(node, NodeSetting.poleMoves, .poleMoves(merged)), coalescingKey:
    "control-points-<node>-<drag serial>", name: UndoName.moveControlPoints)`; `.changed` sets `document.isScrubbing = true`,
    `.ended` sets it false; `.typed` is one step named `changeControlPoint`. A move back to a zero offset removes it.
  - The inspector shows `ControlNetInspector` in `SketchChrome(.inspector)`: the selected count, x, y and z offset fields for
    one selected point, the lock, Done. `ControlNetKeys` are invisible buttons (as `SketchToolbarKeys`): X, Y, Z, N, Esc.
  - `ControlNetBoxView` draws `boxRect` over the viewport, as `PointerReadoutView` is placed.
  - The mode ends on Done, Esc, New, Open, the node's removal, and an undo that removes the node.
  - Outside the mode, while exactly one Edit Surface or Edit Curve node is selected (spec §Drawing), its net is shown
    read-only: the same overlay, no tool, nothing picked. It goes when the node is deselected.

- [ ] **Step 1: Tests:** `enteringInstallsTheTool`, `insideAGroupIsRefused`, `aListIsRefused`, `aDragIsOneUndoStep` ("Undo
  Move Control Points"; the setting holds the moves), `scrubbingHoldsDuringADrag`, `typingIsOneStepNamedChangeControlPoint`,
  `enteringEndsMeasure`, `measureIsRefusedWhileEditing`, `mcpIsRefusedWhileEditing` (the sentence in R9),
  `deletingTheNodeEndsTheMode`, `aSelectedNodeShowsItsNetReadOnly`, `aStaleNetIsNeverMixed` (an evaluation held by `HookGate`; the overlay shows the old net until
  the new one lands).
- [ ] **Step 2: Run** `swift test --filter ControlNetModeTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorAppTests`; pass.
- [ ] **Step 5: Commit** "NURBS: control-point mode".

### Task 9: Benchmark, docs and the suites

**Files:**
- Create: `Tests/CreatorAppTests/Bench/SurfaceBench.swift` (row `surface-3`: dragging one control point of a 30 × 30 net,
  one drag step to the preview, with a G2 Fillet downstream building at G1; the spec's target is 60 fps)
- Modify: `CLAUDE.md` (an NS-3 paragraph: the nodes, the kernel calls, the mode, R1 to R9, format 15, 104 nodes),
  `docs/verification/human-checks.md` (group NS-3: drag a point and undo it; box select and an axis lock; a stale move's
  warning after Rebuild changes the net; Rebuild's deviation fact; Edit Curve on a sketch spline), the spec's status line,
  `docs/verification/performance.md` (the row, marked saturated if the Mac is loaded).
- [ ] **Step 1:** write the bench; run `scripts/bench.sh SurfaceBench` in release; record the number.
- [ ] **Step 2:** docs.
- [ ] **Step 3:** `swift test` on macOS (14 lines, no "recorded an issue" or "failed after"); `XP_TRACK=ns-3
  scripts/linux-test.sh test` (14 lines; remove only the Docker volume the run made); `swiftlint lint --strict` 0.
- [ ] **Step 4: Commit** "Docs: NS-3".
