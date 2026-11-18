# NS-1: Curves, sheets and Import Model — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 3D curves on wires, open surface bodies ("sheets") on the `solid` socket, the first surface nodes, a Sketch
`curves` output and a general STEP/IGES Import Model node.

**Architecture:** A new `Curve` value (an OCCT wire behind `SolidStorage`) travels on a new `curve` socket. Sheets are
ordinary `Solid`s whose topology reports boundary edges (one face) and faces on open shells. Boundary edges carry
their own tags (`TopoRole.boundary`) so picks name them. Each surface builder is a shim function that also returns
the boundary roles. The viewport draws a sheet's back faces in a new theme colour and draws curves as lines.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, OpenCascade 7.9 through `Sources/COCCT`, Metal and
HLSL shaders.

**Spec:** `docs/superpowers/specs/2026-11-17-nurbs-surfaces-design.md` (§Values, §Naming, §Drawing, §Export,
§Rules, §NS-1).

## Global Constraints

- **Worktree and branch.** Worktree `/Users/maxburger/Developer/MetalCreator-nurbs`; rename the branch
  `nurbs-spec` to `ns-1` before Task 1. Never touch MetalUI.
- **OCCT only through the kernel.** OCCT is reached only through `Kernel`, under `OCCTKernel.serialized`. Every C
  allocation has a `*_free`, and no C++ exception crosses into Swift (`guarded`).
- **Shim portability.** No `M_PI` (use `cocct::kPi`), no POSIX headers, no `__attribute__` (`ShimPortabilityTests`).
- **Valid results only.** Every surface builder checks its result with `BRepCheck_Analyzer`. An invalid shape is
  never returned; the builder refuses in a sentence.
- **Messages.** Full sentences in the app's voice. Numbers through `Locale.messages`.
- **Limits:**
  - Curve through Points: 10,000 points.
  - Loft Surface: 1,000 sections.
  - Sweep: 100 profiles.
  - Import Model: a 256 MB file.
- **File format 14** (`GraphFile.currentFormatVersion`). Formats 1 to 13 open unchanged.
- **Tests and checks.**
  - Swift Testing only.
  - `swiftlint lint --strict` passes with zero violations.
  - macOS, Linux and Windows each print 14 "Test run with" lines.
  - OCCT tests are gated `#if canImport(CreatorOCCT)`.
- **Never block a pool thread in tests.** No `DispatchSemaphore.wait` in async code or test hooks.
- **Commit trailer:**
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec)

- **R1.** `Curve` carries no per-piece tags. A surface built from a curve names its faces by piece index
  (`.side(loop: 0, segment: k)` of its own node tag), as Extrude names its sides. (The spec leaves `Curve`'s shape
  to the builder.)
- **R2.** Sweep's `twist` and the guide-surface orientation move to NS-2. NS-1 ships Frenet and fixed-binormal
  orientation and an end scale.
- **R3.** Curves are drawn and framed, but neither hovered nor picked.
- **R4.** An item whose solid has any open shell gets no section cap; it is cut and drawn as its outline.
- **R5.** A `Solid` is `isClosed` when no edge borders exactly one face. A face on an open shell is flagged by the
  shim per face.
- **R6.** Degree 5 for Curve through Points is an approximation through the points
  (`GeomAPI_PointsToBSpline`, degree 5 to 5, C4). It is refused when any point is more than 1e-6 mm off.
- **R7.** New `NodeCategory.surface` ("Surfaces", subgroups "Curves" and "Make"), placed after `.solid`. Import
  Model is `.solid`, beside Import KiCad Board.

## Review Focus

1. **A sheet through Transform and Place keeps its boundary picks** (edge tags are copied and qualified as face
   tags are). Task 3's test.
2. **A sketch with a T-junction, a lone construction line or only closed shapes:**
   - `curves` chains at branches;
   - the profiles are unchanged;
   - a curve failure never fails the node.
   Task 7's tests.
3. **A sweep along a polyline path with a sharp corner, and a profile larger than the path's bend:** a valid
   solid or a sentence, never an invalid shape. Task 5's test.
4. **A STEP holding only wires, one holding only a sheet, a mixed one, and an IGES:** each lands on the right
   output. Task 8's test.
5. **The default suite on `FakeKernel` stays green.** The Sketch node's new output must not break any existing
   sketch test (FakeKernel makes curves of every piece kind). Task 1 and Task 7.

---

### Task 1: Curve values, the `curve` socket and format 14

**Files:**
- Create:
  - `Sources/CreatorGeometry/Curves/CurvePiece.swift`
  - `Sources/CreatorGeometry/Curves/BSplineCurve3D.swift`
  - `Sources/CreatorKernel/Curve.swift`
  - `Sources/CreatorKernel/FakeKernel+Curves.swift`
  - `Sources/CreatorNodes/Surfaces/CurveInput.swift`
- Modify:
  - `Sources/CreatorGraph/SocketType.swift`, `Scalar.swift`, `SocketType+IndefiniteName.swift`, `NodeInputs.swift`,
    `GraphFile.swift` (14)
  - `Sources/CreatorEditor/Palette.swift` (curve socket colour = the `.edgeSet` colour)
  - `Sources/CreatorMCP/Session/DocumentModelSession.swift` (`ValueSummary`: "curve" / "curves")
  - `Sources/CreatorKernel/Kernel.swift`
  - `Tests/CreatorNodesTests/Support/NodeTestSupport.swift` (`.curves` reader)
- Test:
  - `Tests/CreatorGeometryTests/CurvePieceTests.swift`
  - `Tests/CreatorKernelTests/FakeCurveTests.swift`
  - `Tests/CreatorGraphTests/CurveSocketTests.swift`
  - `Tests/CreatorNodesTests/CurveInputTests.swift`

**Interfaces (produces):**
```swift
// CreatorGeometry
public struct BSplineCurve3D: Hashable, Sendable, Codable { public var degree: Int; public var poles: [Vector3]
    public var weights: [Double]?; public var knots: [Double]; public var multiplicities: [Int] }
public enum CurvePiece: Hashable, Sendable {
    case line(Vector3, Vector3)
    case arc(center: Vector3, normal: Vector3, radius: Double, start: Vector3, sweep: Double)   // sweep in radians, signed about normal
    case spline(BSplineCurve3D)
    public var start: Vector3 { get }; public var end: Vector3 { get }
    public static func pieces(of segments: [Segment2D], on plane: Plane) -> [CurvePiece]  // sketch/profile → 3D
}
// CreatorKernel
public final class Curve: Sendable {
    public let pieceCount: Int; public let isClosed: Bool; public let plane: Plane?; public let length: Double
    public let bounds: BoundingBox; public let polyline: [Vector3]   // display, 0.01 mm / 0.5 rad
    public let storage: any SolidStorage
    public init(pieceCount:isClosed:plane:length:bounds:polyline:storage:)
    public var estimatedBytes: Int { get }
}
public enum SweepOrientation: Int, Sendable { case frenet = 0, fixedBinormal = 1 }
public struct SweepOptions: Hashable, Sendable { public var orientation: SweepOrientation; public var binormal: Vector3
    public var endScale: Double; public var makesSolid: Bool }
public struct ImportedShapes: Sendable { public var solids: [Solid]; public var sheets: [Solid]; public var curves: [Curve]
    public var fileUnitMillimetres: Double }
// Kernel additions, each defaulted to `throw KernelError.unsupported("<name>")` in the protocol extension:
func makeCurve(_ pieces: [CurvePiece], tag: NodeTag) throws -> Curve          // pieces must join end to end within 1e-6 mm
func interpolate(_ points: [Vector3], degree: Int, closed: Bool, startTangent: Vector3?, endTangent: Vector3?, tag: NodeTag) throws -> Curve
func curves(from edges: [EdgeID], of solid: Solid, tag: NodeTag) throws -> [Curve]
func extrude(_ curve: Curve, direction: Vector3, distance: Double, symmetric: Bool, tag: NodeTag) throws -> Solid
func revolve(_ curve: Curve, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid
func loftSurface(_ sections: [Curve], ruled: Bool, closed: Bool, tag: NodeTag) throws -> Solid
func sweep(_ profiles: [Curve], along path: Curve, options: SweepOptions, tag: NodeTag) throws -> Solid
func planarSurface(_ loops: [Curve], tag: NodeTag) throws -> Solid
func readShapes(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> ImportedShapes
func export(_ solids: [Solid], curves: [Curve], format: ExportFormat, to url: URL) throws  // default: curves empty → old export, else unsupported
// CreatorGraph
SocketType.curve           // accepts .curve and .profile (no conversion in Value: a profile stays a profile)
Scalar.curve(Curve)
NodeInputs.curves(_ name: SocketName) throws -> [CurveSource]   // CurveSource: .curve(Curve) | .profile(Profile2D)
// CreatorNodes
enum CurveInput { enum Holes { case refuse(String), all }
    static func loops(_ sources: [CurveSource], holes: Holes, kernel: any Kernel, tag: NodeTag) throws -> [Curve] }
```

- [ ] **Step 1: Write the failing tests.**
  - `CurvePieceTests`:
    - `pieces(of:on:)` maps a 2D line, arc and spline onto `Plane(origin: (0,0,5), normal: z)` with every
      endpoint at z = 5;
    - an arc with `end < start` gives a negative `sweep`.
  - `CurveSocketTests`:
    - `SocketType.curve.accepts(.profile)` and `.accepts(.curve)` are true;
    - `.solid.accepts(.curve)` is false;
    - a group interface with a `curve` socket round-trips in a format-14 file;
    - `GraphFile.currentFormatVersion == 14`;
    - a format-13 fixture opens unchanged.
  - `FakeCurveTests`:
    - `FakeKernel().makeCurve` of three lines making a closed triangle gives `isClosed`, length = perimeter and
      `pieceCount == 3`;
    - pieces that don't join refuse with "The curve's pieces don't join end to end.";
    - a spline piece is accepted (its polyline is the control polygon).
  - `CurveInputTests`:
    - a profile with one hole gives 2 loops with `.all`, and with `.refuse("x")` throws `NodeError.invalidValue("x")`;
    - a wired `Curve` passes through unchanged.
- [ ] **Step 2: Run them.** `swift test --filter 'CurvePieceTests|CurveSocketTests|FakeCurveTests|CurveInputTests'`
  fails to compile.
- [ ] **Step 3: Implement the interfaces above.**
  - The exhaustive switches over `Scalar` and `SocketType` gain their cases (`Scalar.type`, `estimatedBytes`,
    `IndefiniteName` "a curve", `Palette.socket`).
  - `Scalar.converted(to: .curve)` leaves a `.profile` as it is (as implicit → mesh does).
  - `FakeKernel` implements only `makeCurve` (all piece kinds, Swift only, `FakeStorage`).
- [ ] **Step 4: Run them, then `swift test --filter 'CreatorGraphTests|CreatorKernelTests|CreatorGeometryTests'`.**
  All pass.
- [ ] **Step 5: Commit.** "NURBS: curve values and the curve socket".

### Task 2: Curves in OpenCascade

**Files:**
- Create:
  - `Sources/COCCT/cocct_curve.cpp`, declared in `Sources/COCCT/include/cocct.h`
  - `Sources/CreatorOCCT/OCCTKernel+Curves.swift`
- Test: `Tests/CreatorOCCTTests/CurveKernelTests.swift`

**Interfaces:**
- **Consumes:** Task 1's `CurvePiece`, `Curve`, the three curve methods.
- **Produces:** `OCCTKernel.makeCurve`, `interpolate` and `curves(from:of:tag:)`. A `Curve`'s storage is an
  `OCCTSolidStorage` holding a `TopoDS_Wire`.

- [ ] **Step 1: Write the failing tests** (`#if canImport(CreatorOCCT)`):
  - `aClosedRectangleIsOnePlanarClosedCurve`: 4 lines on z = 0 give `isClosed`, `plane?.normal ≈ ±z`, length 40.
  - `aFullCircleArcIsClosed`: one arc piece, sweep 2π, radius 5, length ≈ 10π (1e-6).
  - `interpolateDegree3PassesThroughEveryPoint`: 6 points on a helix. Sample the curve's polyline; each input
    point is within 1e-6 mm of the curve (use `Kernel.distances` to an edge set made from the curve, or a test
    helper on the shim).
  - `interpolateDegree5RefusesWhenItMisses`: 3 points give "The curve can't pass through these points at degree 5;
    try degree 3." (R6), or it passes. Pin whichever OCCT gives, and prove the 1e-6 check with a case that fails.
  - `twoCoincidentPointsAreRefused`: "Points 2 and 3 are in the same place."
  - `curvesFromTheTopEdgesOfABox`: the 4 top edges of a box give one closed curve of length 2(w+d). Two
    disjoint edge loops give two curves, in the order of their lowest edge ID.
  - `aSplinePieceRoundTrips`: the degree-5 `BSplineCurve3D` from a sketch spline is kept (poles count, degree).
- [ ] **Step 2: Run them.** `swift test --filter CurveKernelTests` fails.
- [ ] **Step 3: Implement.**
  - Wires come from `BRepBuilderAPI_MakeWire` over `BRepBuilderAPI_MakeEdge` (`GC_MakeSegment`,
    `GC_MakeArcOfCircle`, `Geom_BSplineCurve`).
  - `interpolate` uses `GeomAPI_Interpolate` for degree 3 and `GeomAPI_PointsToBSpline` for degree 5.
  - `curves(from:)` uses `ShapeAnalysis_FreeBounds::ConnectEdgesToWires` (tolerance 1e-6).
  - Length comes from `GCPnts_AbscissaPoint`. Planarity uses `BRepBuilderAPI_FindPlane` (tolerance 1e-7).
  - The polyline is `GCPnts_TangentialDeflection` (0.5 rad, 0.01 mm).
- [ ] **Step 4: Run `swift test --filter CreatorOCCTTests`.** It passes.
- [ ] **Step 5: Commit.** "NURBS: curves in OpenCascade".

### Task 3: Sheets: boundary edges, their names and the Planar Surface builder

**Files:**
- Modify:
  - `Sources/COCCT/cocct_inspect.cpp` (one distinct face and not `BRep_Tool::IsClosed(edge, face)` means a
    boundary edge, reported with `face_b = 0` and a new `boundary` flag; a per-face `on_open_shell` from the
    face's shell `BRep_Tool::IsClosed`)
  - `Sources/COCCT/cocct_mesh.cpp` (draw boundary edges' polylines)
  - `Sources/CreatorOCCT/OCCTRawTopology.swift` (a boundary edge has `faces == [f]`)
  - `Sources/CreatorKernel/EdgeInfo.swift` (`tags: Set<TopoTag>`, default empty; `isBoundary`)
  - `FaceInfo.swift` (`isOnOpenShell: Bool`, default false)
  - `TopoRole.swift`, `TopoRole+Codable.swift`, `TopoRole+Stability.swift`
  - `Topology.swift`, `Topology+EdgePicks.swift`, `Topology+EdgeRuns.swift`, `Topology` qualification (edge tags
    qualified like face tags)
  - `Solid.swift` (`isClosed`)
  - `Sources/CreatorOCCT/OCCTTagger.swift`
  - the selection nodes (`AllEdges`, `EdgesByDirection`, `EdgeTagMatch`)
- Create:
  - `Sources/COCCT/cocct_sheet.cpp` (planar surface, and the boundary-role table shared by Tasks 4 and 5)
  - `Sources/CreatorOCCT/OCCTKernel+Sheets.swift`
- Test:
  - `Tests/CreatorKernelTests/BoundaryKeyTests.swift`
  - `Tests/CreatorOCCTTests/SheetTopologyTests.swift`
  - `Tests/CreatorNodesTests/SheetPickTests.swift`

**Interfaces (produces):**
```swift
public enum BoundaryRole: Hashable, Sendable, Codable {
    case start, end                       // the first and last position of a sweep, extrusion, revolution or loft
    case rail(Int)                        // traced by an open curve's start (0) or end (1)
    case piece(loop: Int, segment: Int)   // a planar surface's edge from loop's piece
    case imported(edge: Int)              // an imported sheet's boundary edge, by its index in the file's edge map
}
extension TopoRole { case boundary(BoundaryRole) }    // a new case; Codable kind "boundary"
extension Solid { public var isClosed: Bool }          // no edge with exactly one face
extension EdgeInfo { public var isBoundary: Bool }    // faces.count == 1
// Topology.key(of:) for a boundary edge with tags: EdgeKey(face.tags, edge.tags); without tags: nil (never picked)
```
- **Shim contract** (used by Tasks 4, 5 and 8): each sheet builder returns its shape plus a role table. The table
  gives, per boundary edge in the shape's `TopExp::MapShapes(EDGE)` order, one `BoundaryRole` code (kind, a, b)
  or "none". It also gives, per face, the face role (the existing face-history route). `OCCTKernel` turns the
  table into `EdgeInfo.tags = [TopoTag(tag, .boundary(role))]`.
- **Planar Surface:**
  - `planarSurface(_ loops:)` classifies loops by containment: one outer loop that contains all others, every loop
    closed and in one plane within 1e-6 mm.
  - Refusals: "The curves must be one outer loop with holes inside it.", "The curve isn't flat, so it can't be
    filled with a plane." and "The curve isn't closed, so it can't be filled."
  - The face is `.startCap`. Loop i's pieces are `.boundary(.piece(loop: i, segment: k))`, with the outer loop as
    loop 0 and holes in input order.

- [ ] **Step 1: Write the failing tests.**
  - `BoundaryKeyTests`:
    - a `TopoRole.boundary(.rail(1))` round-trips through Codable;
    - `sortKey`s are distinct per role;
    - `Topology.key(of:)` of a one-face edge with tags is `EdgeKey(face.tags, edge.tags)`, and without tags is nil;
    - `Topology.picks(for:)` includes a tagged boundary edge;
    - `runCount` counts it;
    - a seam (`faces == [f, f]`) is still skipped.
  - `SheetTopologyTests` (OCCT):
    - a planar surface from a 10 × 20 rectangle curve has 1 face, `isOnOpenShell`, 4 boundary edges each tagged
      `.piece(loop: 0, segment: k)`, `isClosed == false`, area 200;
    - with a circular hole it has 5 boundary edges, the hole's tagged loop 1;
    - a box from `extrude` is `isClosed` with no boundary edges, and its cylinder seams are unchanged;
    - `tessellate` of the sheet has a polyline for every boundary edge;
    - non-planar and open loops give the sentences above.
  - `SheetPickTests` (nodes, OCCT):
    - a Planar Surface's boundary edge picked through Edges by Tag still matches after the rectangle's width
      changes;
    - after a Transform node, and after Place copies it (the tag is qualified per instance), the pick matches
      copy `{1}`'s edge;
    - All Edges includes the 4 boundary edges.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement as the interface and files say.**
  - `TopoRole.boundary` makes the file format 14 (already set by Task 1).
  - `TopoRole+Stability`: a boundary role is stable.
- [ ] **Step 4: Run `swift test --filter 'CreatorKernelTests|CreatorOCCTTests|CreatorNodesTests'`.** It passes,
  with no change in the existing naming suites.
- [ ] **Step 5: Commit.** "NURBS: sheets, boundary edges and their names".

### Task 4: Extrude, Revolve and Loft of curves

**Files:**
- Modify: `Sources/COCCT/cocct_sheet.cpp`, `Sources/CreatorOCCT/OCCTKernel+Sheets.swift`
- Test: `Tests/CreatorOCCTTests/SheetBuilderTests.swift`

**Interfaces:**
- **Consumes:** the Task 3 shim contract.
- **Produces:** `OCCTKernel.extrude(_:direction:distance:symmetric:tag:)`, `revolve(_:axis:angle:tag:)` and
  `loftSurface(_:ruled:closed:tag:)`.
- **Naming:**
  - The face from curve piece k is `.side(loop: 0, segment: k)`.
  - The first and last positions are `.boundary(.start)` and `.boundary(.end)`. A symmetric extrusion's start is
    the −distance side.
  - An open curve's traced ends are `.rail(0)` and `.rail(1)`.
  - A 360° revolution and a closed loft have no start or end. A rail on the axis is degenerate and untagged.
  - A loft's rails join the sections' first vertices (0) and last vertices (1).
- **Building:**
  - `BRepPrimAPI_MakePrism` and `BRepPrimAPI_MakeRevol` of the wire, with roles from `FirstShape`, `LastShape`
    and `Generated(vertex)`.
  - `BRepOffsetAPI_ThruSections(isSolid: false, ruled)`. `closed` appends the first section again.
- **Refusals:**
  - "A loft needs at least two sections."
  - "Section 2 is open and section 1 is closed; a loft's sections must all be open or all closed."
  - "The direction can't be zero."
  - "The angle must be more than 0° and at most 360°."

- [ ] **Step 1: Write the failing tests.**
  - An open 3-line curve extruded 10 mm has 3 faces, area = curve length × 10, and boundary edges tagged
    start ×3, end ×3, rail(0), rail(1).
  - Symmetric doubles the area.
  - A closed circle extruded is a tube: 1 face, 2 boundary edges (start, end), `isClosed == false`.
  - A quarter arc revolved 360° about an axis through its centre's plane gives the expected area within 1e-6
    relative. The rail on the axis is untagged and the other rail is tagged.
  - A loft of two open arcs gives one B-spline face, with the start, end and two rail edges tagged.
  - A closed loft of three circles has no start or end edges.
  - Each refusal sentence above.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test --filter SheetBuilderTests`.** It passes.
- [ ] **Step 5: Commit.** "NURBS: extrude, revolve and loft curves into sheets".

### Task 5: Sweep

**Files:**
- Modify: `Sources/COCCT/cocct_sheet.cpp` (or create `cocct_sweep.cpp`), `Sources/CreatorOCCT/OCCTKernel+Sheets.swift`
- Test: `Tests/CreatorOCCTTests/SweepTests.swift`

**Interfaces:**
- **Consumes:** Task 1's `SweepOptions` and the Task 3 contract.
- **Produces:** `OCCTKernel.sweep(_:along:options:tag:)`.
- **Building:** `BRepOffsetAPI_MakePipeShell`.
  - Orientation: `SetMode(true)` (Frenet) or `SetMode(gp_Dir binormal)`.
  - Each profile is `Add(profile, WithContact: false, WithCorrection: true)`.
  - `endScale ≠ 1` uses `SetLaw` with a linear `Law_Linear` from 1 to `endScale`. That allows exactly one
    profile; with more it refuses: "An end scale needs exactly one profile."
  - `makesSolid` and every profile closed: `MakeSolid()`. Faces `.startCap`/`.endCap`, a closed result.
  - Otherwise a sheet. Faces are `.side(loop: 0, segment: k)` from profile piece k; edges are `.start`, `.end`,
    `.rail(0)`, `.rail(1)`.
- **Checks:**
  - Self-interference is checked with `BRepAlgoAPI_Check`. A hit gives "The sweep runs into itself; shorten the
    path or shrink the profile."
  - An invalid shape gives "The sweep couldn't be made along this path."

- [ ] **Step 1: Write the failing tests.**
  - A circle of r = 2 swept along a 50 mm straight line with makesSolid gives a closed solid of volume π·4·50
    (1e-6 relative).
  - Along a quarter arc of radius 30, the volume is π·4·(π/2·30) (Pappus, 1e-4 relative).
  - An open arc profile gives a sheet with start, end and rails tagged.
  - endScale 2 on a straight path gives the frustum volume (1e-4 relative).
  - Frenet on a helix path and fixed binormal (0,0,1) on a planar S-curve are each valid.
  - **Review Focus 3:** a profile of r = 10 along an arc of radius 5 gives the self-intersection sentence. An
    L-shaped polyline path gives a valid solid or "The sweep couldn't be made…"; pin which, and assert
    `BRepCheck` validity whenever a solid is returned.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test --filter SweepTests`.** It passes.
- [ ] **Step 5: Commit.** "NURBS: sweep".

### Task 6: The curve and surface nodes

**Files:**
- Create in `Sources/CreatorNodes/Surfaces/`: `CurveThroughPointsNode.swift`, `CurveFromEdgesNode.swift`,
  `ProfileToCurvesNode.swift`, `ExtrudeCurveNode.swift`, `RevolveCurveNode.swift`, `LoftSurfaceNode.swift`,
  `SweepNode.swift`, `PlanarSurfaceNode.swift`.
- Modify:
  - `Sources/CreatorGraph/NodeCategory.swift` (`.surface`, R7)
  - `Sources/CreatorEditor/Palette.swift` (`header(for: .surface)` = the `.solid` header colour)
  - `Sources/CreatorNodes/BuiltInNodes.swift`
  - `Tests/CreatorNodesTests/OutputNodeTests.swift` (97 nodes here; 98 with Import Model in Task 8;
    `.surface: 8`)
  - `CatalogTests` if it lists type IDs
- Test: `Tests/CreatorNodesTests/SurfaceNodeTests.swift` (OCCT), `SurfaceNodeRefusalTests.swift` (FakeKernel)

**Interfaces (sockets; all lengths in mm with `unit: .millimetres`):**

| typeID | inputs | outputs |
|---|---|---|
| `creator.curveThroughPoints` ("Curve through Points", "Curves") | `points` .vector list; `degree` .integer segmented ["3","5"] default 0; `closed` .bool false; `start tangent`, `end tangent` .vector optional | `curve` .curve |
| `creator.curveFromEdges` ("Curve from Edges", "Curves") | `edges` .edgeSet | `curves` .curve list |
| `creator.profileToCurves` ("Profile to Curves", "Curves") | `profile` .profile | `curves` .curve list (outer, then holes) |
| `creator.extrudeCurve` ("Extrude Curve", "Make") | `curve` .curve; `direction` .vector (0,0,1); `distance` .number 10, range 0.001…10,000; `symmetric` .bool | `surface` .solid; handle `linear("distance")` |
| `creator.revolveCurve` ("Revolve Curve", "Make") | `curve`; `axis origin` .vector (0,0,0); `axis direction` .vector (0,1,0); `angle` .number 360 (degrees) | `surface` |
| `creator.loftSurface` ("Loft Surface", "Make") | `sections` .curve list; `ruled` .bool; `closed` .bool | `surface` |
| `creator.sweep` ("Sweep", "Make") | `profiles` .curve list; `path` .curve; `orientation` .integer segmented ["Frenet","Fixed"]; `binormal` .vector (0,0,1), shown only for Fixed via `inspector(for:)`; `end scale` .number 1, range 0.01…100; `solid` .bool true | `surface` |
| `creator.planarSurface` ("Planar Surface", "Make") | `curves` .curve list | `surface` |

- **Profile on a curve socket (spec):**
  - Loft Surface refuses holes: "Section N has holes; a loft section is one loop."
  - Sweep, Planar Surface and Profile to Curves take every loop.
  - All go through `CurveInput.loops`.
- **Node refusals:**
  - "A curve needs at least two points."
  - "Curve through Points takes at most 10,000 points."
  - "A loft takes at most 1,000 sections."
  - "A sweep takes at most 100 profiles."
  - "Sweep needs exactly one path." (a list on `path`; `singleValuesRefusal`)
- [ ] **Step 1: Write the failing tests.**
  - OCCT: each node evaluated through `Harness` against the Task 2–5 numbers (one assertion of area or volume per
    node).
  - A Sketch's profile wired into Loft Surface `sections` is accepted, and one with a hole is refused with the
    sentence.
  - Category counts: `.surface: 8`, total 97.
  - FakeKernel: every surface node says the kernel's unsupported sentence, never a crash.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test --filter CreatorNodesTests` and `--filter CreatorEditorTests`.** Both pass (the
  library gains the Surfaces section).
- [ ] **Step 5: Commit.** "NURBS: curve and surface nodes".

### Task 7: The Sketch node's `curves` output

**Files:**
- Create: `Sources/CreatorSketch/Regions/SketchChains.swift`
- Modify: `Sources/CreatorNodes/Profiles/SketchNode.swift`, `Sources/CreatorNodes/Sketch/SketchSolve.swift`
- Test: `Tests/CreatorSketchTests/SketchChainsTests.swift`, `Tests/CreatorNodesTests/SketchCurvesOutputTests.swift`

**Interfaces:**
```swift
public struct SketchChain: Hashable, Sendable { public var segments: [Segment2D]; public var isClosed: Bool
    public var sources: [SketchEntityID] }
public enum SketchChains { public static func find(in solved: Sketch) -> [SketchChain] }
```
- **Chaining:**
  - Every non-construction curve, projected curves included.
  - Pieces are chained at shared solved points of degree 2. A point of degree 1 or 3+ ends a chain.
  - A circle is its own closed chain.
  - Chains are ordered by their first source's position in the sketch, so the order is stable as edits are
    made elsewhere.
  - Segments are oriented end to end.
- **The output:**
  - `curves` is a `.curve` list, one per chain, made by `kernel.makeCurve(CurvePiece.pieces(of:on:), tag:)`.
  - The tag item is the chain's index.
  - If the kernel throws, `curves` is empty and the node warns "The sketch's curves couldn't be made: <reason>".
    The profiles never fail because of curves.
  - `SketchTrace` and `profiles` are unchanged.
- [ ] **Step 1: Write the failing tests.**
  - `SketchChainsTests`:
    - a rectangle gives 1 closed chain of 4;
    - a T-junction (three lines meeting at one point) gives 3 open chains;
    - an open polyline of 3 lines with one arc gives 1 open chain of 4 in order;
    - a lone construction line gives nothing;
    - a circle and a separate spline give 2 chains, the circle closed.
  - `SketchCurvesOutputTests` (FakeKernel):
    - every existing sketch fixture still produces the same profiles;
    - `curves` counts match the chains;
    - with a kernel stub that throws on `makeCurve` the node warns and still outputs its profiles.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test --filter 'CreatorSketchTests|CreatorNodesTests|CreatorAppTests'`.** All pass.
- [ ] **Step 5: Commit.** "NURBS: the sketch's curves".

### Task 8: Import Model

**Files:**
- Create:
  - `Sources/CreatorNodes/Import/ImportModelNode.swift`
  - `Sources/CreatorApp/AppModel+ModelFiles.swift`
  - `readShapes` in `Sources/COCCT/cocct_import.cpp` and `Sources/CreatorOCCT/OCCTKernel+Models.swift`
- Modify, copying the `meshFile` plumbing at each site:
  - `ConstantValue` (`.modelFile(ImageReference)`)
  - `NodeSetting` (`modelFile`, excluded from `reservedForSockets`)
  - `Graph+Images.mapImages`
  - `Scalar.init?`
  - `GraphParameterNode`
  - the CreatorMCP `ReadTools` sites
  - `InspectorControl.modelFile`
  - `InspectorAction` (`chooseModelFile`, `relinkModelFile`, `embedModelFile`)
  - `InspectorBuilder+FileRows`
  - `AppModel+Picking`, `AppCommands` (File ▸ Import Model…)
  - `ContentType+MetalCreator` (`.step` [step, stp], `.iges` [igs, iges])
  - `UndoName.importModel` ("Import Model")
  - `ImageResolver` (`modelFileBytes(of:)`, 256 MB limit)
- Test:
  - `Tests/CreatorOCCTTests/ReadShapesTests.swift`
  - `Tests/CreatorNodesTests/ImportModelNodeTests.swift`
  - `Tests/CreatorAppTests/ImportModelCommandTests.swift`

**Interfaces:**
- **Node** `creator.importModel` ("Import Model", `.solid` category).
  - Input `units`: .integer segmented ["From file","mm","cm","m","in"], default 0.
  - Outputs `solids` (.solid list), `sheets` (.solid list) and `curves` (.curve list). `factsTitle` "Model".
  - Facts: Format (STEP/IGES), File units, Solids, Sheets, Curves.
  - The format is detected from the bytes (`ISO-10303-21` gives STEP; else IGES's fixed 80-column "S" record).
  - Cached in an actor `ImportedModelCache` keyed by `ImageStamp` (LRU, 512 MB, the `ComponentModelCache` pattern).
  - The explicit unit scales by `unitMillimetres / fileUnitMillimetres` with `kernel.scaled`.
- **`readShapes`:**
  - Reads with `xstep.cascade.unit` MM.
  - Splits the result: `TopAbs_SOLID` gives solids; free shells and faces give sheets; free wires and edges give
    curves.
  - Faces are tagged `.imported(face: i)`, boundary edges `.boundary(.imported(edge: i))`.
  - It returns the file's unit.
- **Refusals:**
  - An empty file: "The model contains no shapes."
  - Over 256 MB: "The model file is larger than 256 MB."
- **File ▸ Import Model…** inserts the node and, at the top level, an Output wired `solids → solid`, as one
  "Import Model" step. The file is linked; Embed is offered like Import Mesh's.

- [ ] **Step 1: Write the failing tests.**
  - `ReadShapesTests` uses fixtures written at test time by OCCT's own STEP and IGES export: a box; a planar
    sheet; a wire; one file with all three. **Review Focus 4:** each goes to the right list.
    - An IGES of the sheet reads a sheet.
    - A STEP written in inches reports `fileUnitMillimetres == 25.4`.
  - `ImportModelNodeTests`:
    - the outputs and the facts;
    - `units` = cm on an mm file scales by 10;
    - the file is edited on disk, then re-read at the next evaluation;
    - an embedded copy reads the same.
  - `ImportModelCommandTests`: one undo step, the node and Output wired, the name "Import Model".
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test --filter 'ReadShapesTests|ImportModel'`, then `CreatorAppTests`.** All pass.
- [ ] **Step 5: Commit.** "NURBS: Import Model".

### Task 9: Closed-solid refusals, facts and tooltips

**Files:**
- Modify:
  - `Sources/CreatorNodes/Features/FilletNode.swift`, `ChamferNode.swift`
  - `Sources/CreatorNodes/Solids/BooleanNode.swift`
  - `Sources/CreatorNodes/Patterns/PatternApply.swift`
  - `Sources/CreatorNodes/Implicit/ToImplicitNode.swift`
  - `Sources/CreatorNodes/Fields/Sources/DistanceFieldNode.swift`
  - `Sources/CreatorApp/Section/SectionCapModel.swift` (R4)
  - `Sources/CreatorMCP/Tools/SolidFacts.swift`
  - `Sources/CreatorEditor/EditorModel+TreeDisplay.swift` (`socketHelp`)
- Test: `Tests/CreatorNodesTests/SheetRefusalTests.swift`, `Tests/CreatorMCPTests/SheetFactsTests.swift`,
  `Tests/CreatorEditorTests/SheetTooltipTests.swift`, `Tests/CreatorAppTests/SheetSectionTests.swift`

**Messages:**
- "Fillet needs a closed solid; Thicken or Sew the sheet first." (Chamfer the same.)
- "“tools” is an open surface; use Split or Trim, or Thicken or Sew it first." Each input is named: Boolean's
  `target` and `tools`, and the shortcuts' `part` and tool.
- "To Implicit needs a closed solid; Thicken or Sew the sheet first."
- Distance Field with a sheet target and mode Signed: "A signed distance needs a closed solid; use Unsigned for
  a sheet."
- `SolidFacts`:
  - "sheet: N faces, M open edges, bounds …" when every face is on an open shell;
  - "solid and sheet: …" when mixed;
  - otherwise unchanged.
- `socketHelp` for a `.solid` socket, only when its value holds a sheet: "1 sheet", or "2 solids and 1 sheet".

- [ ] **Step 1: Write the failing tests:**
  - each refusal through `Harness` with a Planar Surface sheet (OCCT);
  - the facts strings;
  - the tooltip;
  - a sheet in the scene with Section on gives no cap entry and no failure message.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the four suites.** They pass.
- [ ] **Step 5: Commit.** "NURBS: sheets refused where a closed solid is needed".

### Task 10: Drawing sheets and curves

**Files:**
- Modify:
  - `Sources/CreatorStyle/ThemeColors.swift`, `ThemeRole+All.swift` and the three built-ins: a role `sheetBack`
    "Sheet back" in the shading group, right after the shade roles. Dracula `#6272A4`, Alucard `#635D97`, Nord
    `#5E81AC`. A `.mctheme` without it reads Dracula's.
  - `Sources/CreatorViewport/Render/ViewportPalette.swift`
  - `ShadeUniforms.swift` (`back` after `warning`, stride 96)
  - `ViewportShaders.swift` (MSL), `Shaders/common.hlsli` and `Shaders/mesh.frag.hlsl`. Face flag bit 8 means "on
    an open shell": a back face with bit 8 is shaded in `back`, lit with the flipped normal. The clip branch's
    darkening applies only without bit 8.
  - `GPUGeometry.faceFlags`, `GPUMesh` and `SDLViewportMesh`
  - `ViewportItem.swift` (`isCurve: Bool`, default false; a curve item draws its edges in every display mode in
    the reference colour Measure uses, writes nothing to the ID pass, opens no face menu, and counts in
    `sceneBounds`)
  - both renderers' edge paths
  - `Sources/CreatorApp/SceneBuilder.swift` (`case .curve`)
  - `Sources/CreatorNodes/Output/OutputNode.swift` (a `curve` input and output, list, optional)
- Test:
  - update `GPUDataTests` (96), `ShaderSourceTests`, `ThemeRoleTests` (49), `SectionRoleTests` (if the suffix
    moves) and `ThemeTests`
  - new `SheetBackRenderTests` (Metal) and the SDL twin in `SDLRenderTests`: a planar sheet seen from behind is
    `sheetBack` at its centre pixel, and from the front is the usual shade
  - `CurveItemRenderTests`: a curve item's pixels are the reference colour in Shaded mode; the ID pass reads
    empty there
  - `SceneBuilderCurveTests`: an Output with a curve wired gives one curve item

- [ ] **Step 1: Write and update the tests.**
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.** Edit the Swift struct, the MSL and the HLSL together (CLAUDE.md rule).
- [ ] **Step 4: Run `swift test --filter 'CreatorViewportTests|CreatorStyleTests|CreatorAppTests'`, then
  `scripts/linux-test.sh test --filter CreatorViewportTests`** (the HLSL recompiles). Both pass. Delete any Docker
  volume or image this created.
- [ ] **Step 5: Commit.** "NURBS: draw sheets and curves".

### Task 11: Export

**Files:**
- Modify: `Sources/CreatorApp/AppModel+Export.swift`, `Export/ExportPlan.swift` (`curves: [Curve]`,
  `sheetOutputs: [String]`), `Sources/CreatorOCCT/OCCTKernel.swift` (`export(_:curves:format:to:)`: wires in the
  STEP compound)
- Test: `Tests/CreatorAppTests/SheetExportTests.swift`, `Tests/CreatorOCCTTests/CurveExportTests.swift`

**Rules:**

| Format | Sheet | Curve |
|---|---|---|
| STEP | Written as a shell | Written as a wire |
| STL | Written as an open mesh; warns "<Output>: The surface is open, so the STL is open there." | Left out; warns "<Output>: Curves aren't written to STL." |
| 3MF | Refused before the save panel: `AppProblem("<Output> can't be exported", "<Output> is an open surface; 3MF needs closed parts. Thicken or Sew it first.")` | Left out; warns "<Output>: Curves aren't written to 3MF." |

- [ ] **Step 1: Write the failing tests.**
  - A STEP with a sheet and a curve read back with `readShapes` gives 1 sheet and 1 curve.
  - The STL warning.
  - The 3MF refusal comes before any file is written.
  - The curve warnings.
- [ ] **Step 2: Run them.** They fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** They pass.
- [ ] **Step 5: Commit.** "NURBS: exporting sheets and curves".

### Task 12: Docs and the full suites

- **CLAUDE.md:**
  - an "NURBS surfaces, NS-1" paragraph (values, sockets, boundary roles, the 8 nodes, Import Model, the theme
    role, export rules);
  - the module notes for `CreatorKernel` (`Curve`, `BoundaryRole`) and `COCCT` (`cocct_curve.cpp`,
    `cocct_sheet.cpp`);
  - node count 98;
  - file format 14 in the format history.
- **Human checks:** group NS-1 in `docs/verification/human-checks.md`:
  - draw an open sketch curve and extrude it;
  - a sweep along a 3D curve through points;
  - a sheet's back colour while orbiting;
  - pick a sheet edge, change a parameter, and see the pick stay;
  - import a supplier STEP with surfaces;
  - export STEP and reopen it in another CAD tool.
- **The spec's status line:** NS-1 done.
- **Full suites:**
  - `swift test` on macOS: 14 "Test run with" lines, none "recorded an issue".
  - `scripts/linux-test.sh test`: 14 lines. Clean up the Docker volume and images it made.
  - `swiftlint lint --strict`: 0 violations.
- **Commit:** "Docs: NS-1".
