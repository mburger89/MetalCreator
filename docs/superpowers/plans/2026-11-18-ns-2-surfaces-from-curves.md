# NS-2: Surfaces from curves — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Network Surface (a Gordon surface through u and v curves), Boundary Patch (an N-sided fill with G0, G1 or G2
to the faces around it), Sweep with a second rail, a guide surface and twist, and a kernel call that grades continuity
between an edge of one body and a face of another.

**Architecture:** Each surface is a sheet builder in the shim, following NS-1's contract: shape, face history and a
boundary-role table. The Gordon surface and the G2 patches are our own code in `Sources/COCCT`. G0 and G1 patches
use `BRepFill_Filling`. Every promised continuity is measured afterwards by the new two-body continuity call, and a
result that misses is refused in words.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 (`BRepFill_Filling`, `BRepOffsetAPI_MakePipeShell`,
`GeomAPI_PointsToBSpline`, `Geom_BSplineSurface`), our `cocct_g2_*` Bezier and triangle code.

**Spec:** `docs/superpowers/specs/2026-11-17-nurbs-surfaces-design.md`. Read §Joining a part, §Rules every surface
node follows and §NS-2. Read CLAUDE.md's NS-1 paragraph for the sheet contract.

## Global Constraints

- **Worktree and branch.** Worktree `/Users/maxburger/Developer/MetalCreator-ns2`, branch `ns-2`. Never touch MetalUI.
- **OCCT only through the kernel.** OCCT is reached only through `Kernel`/`OCCTKernel`, under `OCCTKernel.serialized`.
  Every C allocation has a `*_free`, and no C++ exception crosses into Swift (`guarded`).
- **Shim portability.** No `M_PI` (use `cocct::kPi`), no POSIX headers, no `__attribute__`.
- **Valid results only.** Every result is checked with `BRepCheck_Analyzer`, and an invalid shape is refused in a
  sentence.
- **Promised continuity is checked**, at the measure's thresholds: position 1e-4 mm, angle 0.01°, curvature within
  1 % of the larger value or 1e-4 /mm (`EdgeContinuity`). A miss is a refusal in words, never a weaker surface.
- **Limits:**
  - Network Surface: 2,000 curves in all, at least 2 in each direction, `tolerance` default 0.01 mm.
  - Boundary Patch: 2 to 16 bounding pieces, at most 1,000 interior points.
  - Sweep twist: −3,600° to 3,600°.
- **Cancellation** is checked between curves, sections and iterations.
- **Messages** are full sentences, with numbers through `Locale.messages`.
- **Sheets.** The output is a sheet on a `.solid` socket. Sheet tests use `hasOpenShell`, the NS-1 rule.
- **File format** stays at 14. New nodes and sockets need no bump; `SweepOrientation` gains raw values 2 and 3.
- **Tests and checks.**
  - Swift Testing only. OCCT tests are gated `#if canImport(CreatorOCCT)`.
  - `swiftlint lint --strict` passes over the whole tree.
  - macOS and Linux each print 14 "Test run with" lines.
- **Never block a pool thread in tests.**
- **Commit trailer:**
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec)

- **R1. Network Surface passes through its border curves (G0) only.** G1 or G2 to a part's faces along its borders
  is Match Surface's job in NS-4. Cost if wrong: one extra node in a chain.
- **R2. Boundary Patch has one `continuity` for all its bounding edges.**
  - It applies to every bounding piece that is a sheet's boundary edge, an edge with exactly one face.
  - Curves, and a solid's edges (two faces), are always held G0.
  - A G1/G2 request where no piece has a face warns "No bounding edge lies on a surface, so the patch is only G0."
  - Cost if wrong: you can't mix G1 and G2 around one patch.
- **R3. A G2 patch takes no interior points or curves.** It refuses: "A G2 patch can't pass through interior points
  or curves."
- **R4. Network curve order is found, not given.** The u curves are sorted by where they cross the first v curve,
  and the v curves by where they cross the first u curve. Each curve is turned to run the same way as its first
  neighbour. Cost if wrong: none, since the input order no longer matters.
- **R5. Twist works only with Frenet and Fixed orientation.** It is made with an auxiliary spine (the path offset by
  a direction that turns by `twist × t` about the tangent). With a rail or a guide surface it is refused: "Twist
  can't be combined with a rail or a guide surface."
- **R6. Naming:**
  - Network Surface: the face is `.side(loop: 0, segment: 0)`. The first and last u curve's edges are
    `.boundary(.start)` and `.boundary(.end)`; the first and last v curve's are `.boundary(.rail(0))` and
    `.boundary(.rail(1))`.
  - Boundary Patch: the face is `.startCap`. Bounding piece k, in loop order starting from the first input piece,
    is `.boundary(.piece(loop: 0, segment: k))`.
  - No new `BoundaryRole` case.

## Review Focus

1. **Curves that almost meet.**
   - A network whose curves miss by less than `tolerance` builds.
   - One that misses by more refuses, naming the pair and the gap.
   - Task 2's tests.
2. **Curves given in mixed directions and shuffled order** (R4) build the same surface as ordered ones. Task 2.
3. **A patch loop with a gap** between consecutive pieces refuses: "The bounding pieces don't form a closed loop; pieces
   2 and 3 are 0.5 mm apart." A loop of 2 pieces (a lens) builds. Task 4.
4. **A G1 patch on a sheet's hole** measures G1 on every bounding edge against the sheet, through the two-body call.
   A G2 three-sided and a G2 four-sided patch measure G2. Tasks 4 and 5.
5. **A twisted sweep of a square profile by 90°** has its end profile turned by 90° within 0.01°. A two-rail sweep
   stays on both rails within 1e-4 mm. Task 7.

---

### Task 1: Continuity between two bodies

**Files:**
- Modify: `Sources/COCCT/cocct_continuity.cpp`, `Sources/COCCT/include/cocct.h`,
  `Sources/CreatorOCCT/OCCTKernel+Continuity.swift`, `Sources/CreatorKernel/Kernel.swift`
- Test: `Tests/CreatorOCCTTests/TwoBodyContinuityTests.swift`

**Interfaces (produces):**
```swift
// Kernel, with a throwing default (unsupported) in the protocol extension:
func continuity(of edge: EdgeID, in first: Solid, against face: FaceID, of second: Solid) async throws -> EdgeContinuity
```
- **Shim.** `occt_edge_continuity_against(first, edge_index, second, face_index, out, status)` reuses
  `edge_continuity`'s sampling (32 samples, 1 % end margins).
  - Side A is the edge's own face in `first`. The edge must have exactly one face, or else: "The edge must be a
    surface's free edge."
  - Side B is `second`'s face. Each sample is projected onto it (`GeomAPI_ProjectPointOnSurf`) to get its uv, and
    then the same D2 and normal-curvature computation runs.
  - Orientation: the two normals are compared up to sign (B's normal is flipped when that makes the angle smaller),
    and the curvature sign follows the flip.
  - A sample whose projection is farther than 1 mm is skipped. With no usable sample it refuses: "The edge doesn't
    run along that face."

- [ ] **Step 1: Write the failing tests.**
  - `twoHalvesOfAPlaneAreG2`: two planar sheets sharing a straight border; edge of A against face of B gives grade
    `.g2`.
  - `aCylinderPatchAgainstItsTangentPlaneIsG1`:
    - A quarter-cylinder sheet against the plane tangent to it along its straight edge is `.g1`.
    - The `absoluteCurvatureGap` is 1/r within 1e-6.
  - `aRightAngleIsG0`: two sheets at 90° give `angleGap ≈ π/2`.
  - `aFaceElsewhereIsRefused`: the face is 10 mm away, and the sentence above is asserted.
  - `aSolidsEdgeIsRefused`: a box edge (two faces) gives the free-edge sentence.
- [ ] **Step 2: Run them.** `swift test --filter TwoBodyContinuityTests` fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** They pass. Then run `swift test --filter CreatorOCCTTests`.
- [ ] **Step 5: Commit.** "NURBS: continuity between two bodies".

### Task 2: Gordon network surface (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_network.cpp` (declared in `cocct.h`), `Sources/CreatorOCCT/OCCTKernel+Network.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift`
- Test: `Tests/CreatorOCCTTests/NetworkSurfaceTests.swift`

**Interfaces (produces):**
```swift
func networkSurface(u: [Curve], v: [Curve], tolerance: Double, tag: NodeTag) throws -> Solid   // throwing default
```

**Algorithm.** The implementer writes it; these are the decisions.

1. **Intersections.**
   - For every pair (u_i, v_j), find the closest points with `GeomAPI_ExtremaCurveCurve` on the curves' single
     B-spline (convert each wire with `GeomConvert_CompCurveToBSplineCurve`).
   - If the gap is more than `tolerance`: "u curve 2 and v curve 3 miss each other by 0.4 mm." Numbers are 1-based and
     in the sorted order of step 2.
   - With several extrema, take the one nearest the pair's neighbours' ordering, and refuse when two are within
     `tolerance` of each other: "u curve 2 crosses v curve 3 more than once."
2. **Order and direction (R4).**
   - Sort the u curves by the parameter of their intersection along v₀, and the v curves along u₀.
   - Reverse a curve whose intersection parameters decrease.
   - After sorting, every row and column of intersection parameters must increase strictly, or: "The curves don't
     form a grid."
3. **Common parameters.**
   - Normalise each curve to [0, 1].
   - The common v-parameters v̄_i are the mean, over the v curves, of u_i's crossing parameter on each v curve. The
     common ū_j are found the same way.
4. **Reparametrise.**
   - Sample each u curve at 20 points per span between crossings.
   - Map the samples' parameters piecewise-linearly so each crossing lands on its ū_j.
   - Refit with `GeomAPI_PointsToBSpline(points, parameters, 3, 5, GeomAbs_C2, 1e-7·scale)`.
   - The refit must stay within `tolerance/10` of the original curve, else: "u curve 2 can't be fitted to the
     network."
   - Do the same for the v curves.
5. **Compatibility.** Raise every u curve to the highest degree among them (`IncreaseDegree`), then insert every
   knot of every u curve into each (`InsertKnot`). Do the same for the v curves.
6. **Three surfaces.**
   - S_u: skin the compatible u curves through v̄. Interpolate each pole column across the curves with
     `GeomAPI_Interpolate` at v̄, degree 3, or degree 1 when there are only 2 curves (the cubic needs 4; use
     `PointsToBSpline` for 3).
   - S_v: likewise.
   - T: the tensor interpolation of the crossing points at (ū_j, v̄_i), by the same column-then-row interpolation.
7. **Combine.** Make S_u, S_v and T compatible in both directions (raise degrees, insert knots). The Gordon poles are
   `P = P_u + P_v − P_T` in one `Geom_BSplineSurface`.
8. **Check.**
   - Sample every input curve at 50 points and project each onto the surface (`GeomAPI_ProjectPointOnSurf`).
   - Any distance over `tolerance` gives: "The surface misses u curve 2 by 0.03 mm."
   - Then make the face, run `BRepCheck`, and apply the R6 naming.

- [ ] **Step 1: Write the failing tests.**
  - `aGridOfLinesIsTheirBilinearSurface`:
    - u: 3 lines y = 0, 5, 10 from x = 0 to 10 at z = 0. v: 3 lines x = 0, 5, 10.
    - The result is planar within 1e-9, with area 100.
  - `aSaddleNetworkPassesThroughEveryCurve`:
    - u curves z = 0.1x² at y = 0, 5, 10; v curves z = −0.1y² + 0.1x₀² at x = 0, 5, 10, made to intersect.
    - The check passes, and the max distance over all samples is ≤ 1e-4.
  - `curvesThatMissAreNamed`: one v curve is lifted 0.5 mm, giving the "miss each other by 0.5 mm" sentence with the
    right 1-based indices.
  - `nearlyMeetingCurvesBuild`: lifted 0.005 mm with tolerance 0.01 builds.
  - `shuffledAndReversedCurvesBuildTheSameSurface`: the saddle curves shuffled and half of them reversed give an area
    and a sampled point set equal to the ordered build within 1e-6 (Review Focus 2).
  - `aNetworkNeedsTwoCurvesEachWay`: "A network needs at least two curves in each direction."
  - `aCurveCrossingTwiceIsRefused`.
  - `namesTheBorders`: the face is side(0,0); border edges are tagged start, end, rail(0) and rail(1).
- [ ] **Step 2: Run them.** `swift test --filter NetworkSurfaceTests` fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** They pass. Then run `swift test --filter CreatorOCCTTests`.
- [ ] **Step 5: Commit.** "NURBS: Gordon network surface".

### Task 3: The Network Surface node

**Files:**
- Create: `Sources/CreatorNodes/Surfaces/NetworkSurfaceNode.swift`
- Modify: `BuiltInNodes.swift`, `Tests/CreatorNodesTests/OutputNodeTests.swift` (99 nodes, `.surface: 9`)
- Test: `Tests/CreatorNodesTests/NetworkSurfaceNodeTests.swift`

**Interfaces:**
- `creator.networkSurface`, "Network Surface", subgroup "Make".
- Inputs:
  - `u curves`: `.curve` list.
  - `v curves`: `.curve` list.
  - `tolerance`: `.number`, mm, default 0.01, range 0.0001…1.
- Output `surface` (`.solid`).
- Profiles on either input go through `CurveInput.loops(holes: .refuse("Curve N has holes; a network curve is one loop."))`.
- Over 2,000 curves in all gives: "A network takes at most 2,000 curves."

- [ ] **Step 1: Write the failing tests** (OCCT): the line grid through Harness gives area 100; the limit sentence;
  FakeKernel gives the unsupported sentence.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test --filter CreatorNodesTests` and `--filter CreatorEditorTests`.** Both pass.
- [ ] **Step 5: Commit.** "NURBS: Network Surface node".

### Task 4: Boundary Patch, G0 and G1 (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_patch.cpp`, `Sources/CreatorOCCT/OCCTKernel+Patch.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift`, `Sources/CreatorKernel/Curve.swift` (`PatchContinuity`)
- Test: `Tests/CreatorOCCTTests/BoundaryPatchTests.swift`

**Interfaces (produces):**
```swift
public enum PatchContinuity: Int, Sendable { case g0 = 0, g1 = 1, g2 = 2 }
public struct PatchBoundary: Sendable { public var curves: [Curve]; public var edges: [EdgeID]; public var part: Solid?
    public init(curves:edges:part:) }
func boundaryPatch(_ boundary: PatchBoundary, interior points: [Vector3], interior curves: [Curve],
                   continuity: PatchContinuity, tag: NodeTag) async throws -> PatchResult     // throwing default
public struct PatchResult: Sendable { public var sheet: Solid; public var warnings: [String] }
```
- **Loop.**
  - The pieces are each curve's edges followed by each picked edge.
  - Chain them with `ShapeAnalysis_FreeBounds::ConnectEdgesToWires` (shared vertices false, tolerance 1e-4).
  - There must be exactly one closed wire of 2 to 16 edges.
  - A gap gives: "The bounding pieces don't form a closed loop; pieces 2 and 3 are 0.5 mm apart." Pieces are counted
    in input order, 1-based.
  - Other refusals: "A patch needs 2 to 16 bounding pieces." and "The bounding pieces form more than one loop."
- **Build (G0/G1).**
  - `BRepFill_Filling(3, 15, 2, false, 1e-5, 1e-4, 1e-2, 0.1, 8, 9)`.
  - Each piece is added with `Add(edge, order, true)`.
  - A sheet-boundary edge (one face on `part`) at G1 uses `Add(edge, supportFace, GeomAbs_G1, true)` (R2).
  - Points go through `Add(gp_Pnt)`, and interior curves through `Add(edge, GeomAbs_C0, false)`.
- **Check.**
  - Each bounding piece: position within 1e-4 mm.
  - A G1 piece: graded through Task 1's call (patch edge against the support face). It must be ≥ G1, else "The patch
    isn't tangent to the surface along piece 2; the hole may be too sharp for G1."
  - Interior points within 1e-3 mm, else: "The patch can't pass through point 3."
- **Naming** follows R6.
- **G2** is Task 5. Here a `.g2` request throws `.unsupported` until Task 5.

- [ ] **Step 1: Write the failing tests.**
  - `fourLinesMakeAFlatSquare`: area 100, planar.
  - `aLensOfTwoArcs`: two arcs sharing ends build; area within 1e-3 of the analytic lens (Review Focus 3).
  - `aGapIsRefusedNamingThePieces` (Review Focus 3).
  - `seventeenPiecesAreRefused`.
  - `twoLoopsAreRefused`.
  - `throughAPointBulges`: a square plus the point (5, 5, 2); the patch passes within 1e-3.
  - `aG1PatchClosesASheetsHole`:
    - A sheet made by Planar Surface with a square hole, then the hole's four boundary edges lifted (use a sheet
      from Loft Surface of two offset squares instead, so the faces around the hole are not coplanar with the
      patch).
    - Patch at G1. Every bounding edge grades ≥ G1 against the sheet face through Task 1 (Review Focus 4).
  - `g1WithOnlyCurvesWarns`: R2's warning.
  - `namesThePieces`: R6.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them, then `swift test --filter CreatorOCCTTests`.** All pass.
- [ ] **Step 5: Commit.** "NURBS: boundary patch G0 and G1".

### Task 5: Boundary Patch at G2 (3 and 4 sides)

**Files:**
- Create: `Sources/COCCT/cocct_patch_g2.cpp`, `Sources/COCCT/cocct_patch_quad.hpp` (the four-sided patch)
- Modify: `cocct_patch.cpp` (dispatch), the `cocct_g2_triangle.hpp` consumer side only (no behaviour change to the
  fillet)
- Test: `Tests/CreatorOCCTTests/BoundaryPatchG2Tests.swift`

**Decisions:**
- **Side data from a face.** For each bounding edge on a sheet:
  - **Boundary curve.** Fit the boundary to a quintic Bezier (6 points, `bezier_through`). The fit must be within
    1e-7 mm, else refuse: "Piece 2 is too complex for a G2 patch; split it."
  - **cross1.** At each of the 6 parameters, cross1 = λ·(n × t) pointing into the hole, where n is the face normal
    and t the edge tangent. λ is chosen per side by `across_scales` (triangle) or by the side's chord length (quad).
  - **cross2.** Its normal component is κₙ·|cross1|², with κₙ the face's normal curvature across the edge
    (`SurfacePoint.normal_curvature`). Its tangential component is 0.
  - Both are fitted as quintics with `bezier_through`.
- **Three sides.** Use `TriangleSide`, `across_scales`, `build_triangle` and `to_tensor` unchanged.
  - Keep the existing checks: direction cosine, block mismatch and regularity.
  - The fillet's `4/radius` interior curvature cap is replaced by 10/(the loop's bounding-box diagonal).
- **Four sides.** A degree-(5,5)… biquintic Coons patch with quintic Hermite blending in each direction, using
  boundary curves, cross1 and cross2 on all four sides.
  - The corner twist and second-order corner terms must be compatible between the two meeting sides. Measure the
    mismatch at each corner; over 1e-6 relative, refuse: "The surfaces meet at corner 2 in a way a G2 patch can't
    follow."
  - Write the Boolean-sum formula in `cocct_patch_quad.hpp` with a comment deriving it.
- **Five or more sides at G2:** "A G2 patch needs 3 or 4 sides; this loop has 6."
- **Check.** Every bounding edge must grade `.g2` through Task 1 against its sheet face, else: "The patch can't be made
  curvature continuous along piece 2." Then `BRepCheck`.
- **Pieces from curves** (no face) are held at G0 in G2 mode too. Their cross data comes from the Coons interpolation
  of the other sides (the tangential and normal parts are zero).

- [ ] **Step 1: Write the failing tests.**
  - `aThreeSidedG2PatchOnAQuarterSphere`:
    - The three boundary edges of an octant opening, using a sheet that is a sphere with an octant cut out (make it
      by Revolve Curve and a trim with Planar Surface boundaries, or by three cylinder-quarter sheets around a
      corner like the fillet's corner).
    - Every edge grades G2.
  - `aFourSidedG2PatchClosesALoftedTube`:
    - A Loft Surface of two circles is open at one end, with the end loop split into 4 arcs.
    - Patch the end at G2. All four edges grade G2, and the patch is valid.
  - `sixSidesAtG2IsRefused`.
  - `g2WithInteriorPointsIsRefused` (R3).
  - `anIncompatibleCornerIsRefused`: a quad loop where one corner meets at a crease. Assert the corner sentence.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.** If a test fixture can't be made to pass the G2 check because of the fixture itself (not the
  patch), say so in the report with the measured gaps rather than loosening a threshold.
- [ ] **Step 4: Run them, then `swift test --filter CreatorOCCTTests`** (the G2 fillet suites must be unchanged).
- [ ] **Step 5: Commit.** "NURBS: G2 boundary patches".

### Task 6: The Boundary Patch node

**Files:**
- Create: `Sources/CreatorNodes/Surfaces/BoundaryPatchNode.swift`
- Modify: `BuiltInNodes.swift`, `OutputNodeTests` (100 nodes, `.surface: 10`)
- Test: `Tests/CreatorNodesTests/BoundaryPatchNodeTests.swift`

**Interfaces:**
- `creator.boundaryPatch`, "Boundary Patch", subgroup "Make".
- Inputs:
  - `curves`: `.curve` list, optional. A profile gives its outer loop; holes are refused with "Profile N has holes;
    a patch boundary is one loop."
  - `edges`: `.edgeSet`, optional. Its solid is `part`.
  - `points`: `.vector` list, optional.
  - `interior curves`: `.curve` list, optional.
  - `continuity`: `.integer` segmented ["G0","G1","G2"], default 1.
- Output `surface`.
- Kernel warnings become node warnings. At least one of curves or edges must be wired, else: "Wire the curves or
  edges that bound the patch."
- Over 1,000 points: "A patch takes at most 1,000 points."

- [ ] **Step 1: Write the failing tests:**
  - the square of four lines gives area 100;
  - edges picked on a lofted sheet's hole at G1, through Harness with Edges by Tag, build;
  - the "Wire the curves…" sentence;
  - the point limit;
  - FakeKernel gives the unsupported sentence.
- [ ] **Step 2–4: Fail, implement, pass.** Run `CreatorNodesTests` and `CreatorEditorTests`.
- [ ] **Step 5: Commit.** "NURBS: Boundary Patch node".

### Task 7: Sweep with a rail, a guide surface and twist

**Files:**
- Modify:
  - `Sources/COCCT/cocct_sheet.cpp` (`occt_sweep_curves` gains a guide argument)
  - `cocct.h`
  - `Sources/CreatorOCCT/OCCTShape+Sheets.swift`, `OCCTKernel+Sheets.swift`
  - `Sources/CreatorKernel/Curve.swift` (`SweepOrientation` gains `secondRail = 2`, `guideSurface = 3`;
    `SweepOptions.twist: Double` in degrees, default 0)
  - `Kernel.swift`
  - `Sources/CreatorNodes/Surfaces/SweepNode.swift`
- Test: `Tests/CreatorOCCTTests/SweepGuideTests.swift`, additions to `Tests/CreatorNodesTests/SurfaceNodeTests.swift`

**Interfaces:**
```swift
public enum SweepGuide: Sendable { case rail(Curve), surface(Solid) }
func sweep(_ profiles: [Curve], along path: Curve, options: SweepOptions, guide: SweepGuide?, tag: NodeTag) throws -> Solid
// the existing sweep(_:along:options:tag:) forwards with guide nil
```
- **Second rail:** `SetMode(railWire, CurvilinearEquivalence: true, BRepFill_ContactOnBorder)`.
- **Guide surface:** `SetMode(guideShape)`.
- **Twist (R5):** build the auxiliary spine in the shim.
  - Sample the path at 64·max(1, |twist|/90) points.
  - Offset each sample by a unit direction d(t): the profile frame's x axis at the start, turned by twist·t about
    the tangent, with t the normalised arc length.
  - Interpolate the points with `GeomAPI_PointsToBSpline` (degree 3).
  - Use `SetMode(auxSpine, false, BRepFill_NoContact)`.
- **Refusals:**
  - Twist out of range: "The twist must be between −3,600° and 3,600°."
  - R5's sentence.
  - A rail that doesn't touch each profile within 1e-4 mm: "The rail must touch every profile."
- **Node.**
  - `orientation` gains "Rail" and "Guide".
  - New inputs: `rail` (`.curve`, optional, shown for Rail), `guide` (`.solid`, optional, shown for Guide) and
    `twist` (`.number`, degrees, default 0, shown for Frenet and Fixed).
  - Rail or Guide with nothing wired: "Wire a rail curve." / "Wire a guide surface."

- [ ] **Step 1: Write the failing tests.**
  - `aNinetyDegreeTwistTurnsTheEndProfile`:
    - A 10 × 4 rectangle profile swept 50 mm straight with twist 90.
    - The end cap's longest edge direction is turned 90° from the start's, within 0.01° (Review Focus 5).
  - `aTwoRailSweepStaysOnBothRails`:
    - The path is one rail. The second rail is a curve that diverges.
    - The open profile's two ends lie on the two rails at the start.
    - Sample the rail(1) boundary edge: within 1e-4 mm of the second rail (Review Focus 5).
  - `aGuideSurfaceKeepsTheProfileNormal`: a sweep along a curve lying on a cylinder sheet, with guide = the sheet, is
    valid.
  - `twistWithARailIsRefused`.
  - `aRailThatMissesIsRefused`.
  - Node tests: the inspector shows `rail`, `guide` and `twist` per orientation (`inspector(for:)`), and the two "Wire
    a …" sentences.
- [ ] **Step 2–4: Fail, implement, pass.** Run `CreatorOCCTTests` and `CreatorNodesTests` (NS-1's SweepTests
  unchanged).
- [ ] **Step 5: Commit.** "NURBS: sweep with a rail, a guide and twist".

### Task 8: Docs and the suites

- **CLAUDE.md:**
  - an NS-2 paragraph after NS-1's (the three nodes and the two-body continuity call, the rulings R1–R6, the shim
    files `cocct_network.cpp`, `cocct_patch.cpp`, `cocct_patch_g2.cpp` and `cocct_patch_quad.hpp`);
  - node count 100;
  - the `Kernel` module note gains `continuity(of:in:against:of:)`, `networkSurface` and `boundaryPatch`.
- **Human checks**, group NS-2:
  - a network of four sketched splines each way;
  - patch a hole in a lofted sheet at G1 and G2, then check with zebra stripes that they flow across;
  - a twisted sweep;
  - a two-rail sweep.
- **The spec's status line:** NS-2 done, noting R1 and R3.
- **Full suites:**
  - `swift test` on macOS: 14 lines.
  - `scripts/linux-test.sh test`: 14 lines. Remove only the Docker objects your run created.
  - `swiftlint lint --strict`: 0.
- **Commit:** "Docs: NS-2".
