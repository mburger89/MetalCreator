# Section analysis, part B: the cap, the hatch and the outlines — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Where the section plane passes through material, draw a hatched cap lying on the plane, with crisp outlines, computed from geometry (OpenCascade for solids, a mesh slice for meshes), on macOS, Linux and Windows.

**Architecture:** A new `Kernel.section(_:by:tolerance:)` (OCCT shim `cocct_section.cpp`) and a new `MeshSlicer` (CreatorImplicit) both return a `PlaneSection` (CreatorKernel): regions, each a triangulation plus its boundary pieces. `SectionCapModel` (CreatorApp) computes one per shown, non-ghost item off the main actor whenever the clip or the items change, keeps the last result until the new one lands, and hands the viewport a `ViewportSection`. Both renderers gain a cap pipeline (`section`) that fills the cap with a plane-space hatch, an ID-pass twin (`id_section`) that hides what lies behind the cap from picking, and draw the outlines through the existing line pipeline.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, OpenCascade 7.9 (C++17 shim), Metal (MSL compiled at run time), SDL GPU with HLSL compiled by `scripts/build-shaders.sh`, MetalUI.

**Spec:** `docs/superpowers/specs/2026-10-30-section-measure-design.md` (§3.3, §3.4, §3.5, §6 step 2, §8, §9). Part A's plan: `docs/superpowers/plans/2026-10-30-section-a-placement.md`.

## Global Constraints

- OCCT only behind `Kernel`, every shim call under `OCCTKernel.serialized`; every C allocation has a `*_free`; no C++ exception crosses into Swift (`guarded`); shim stays portable (`ShimPortabilityTests`: no `M_PI`, POSIX headers, `__attribute__`, `min`/`max` macros — use `std::min`).
- No Metal, CoreGraphics or CoreText outside `#if canImport(…)`. Metal render tests are `#if canImport(Metal)`; OCCT tests `#if canImport(CreatorOCCT)`.
- The Swift GPU structs, the MSL and the HLSL (`Shaders/viewport/common.hlsli`) change together; HLSL members are only `float4`, `uint4`, `float2`, `uint2`, `float`, `uint` (never `float3`); `GPUDataTests` and `ShaderSourceTests` pin the sizes.
- Swift Testing only. `swiftlint lint --strict` reports 0. `swift test` prints twelve "Test run with" lines on macOS and Linux and none of them "recorded an issue" or "failed after" (the known pre-existing failure `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine` on macOS is reproduced on `main` and is not this plan's).
- Spec §3.5: no command, no undo step, no edited dot, no effect on export, graph or evaluation. Sketch mode hides the section (part A already makes `SectionModel.shown` nil there).
- Spec §3.3: ghosted items are clipped but not capped; guide items, overlays, handles, the field slice and dimensions are not clipped or capped.
- Spec §3.4: sectioning runs off the main actor; a newer request cancels the older; the last cap stays drawn (clipped to the new plane) until the new one is ready.
- Theme roles `sectionFill`, `sectionHatch`, `sectionEdge`, group of their own, last in `ThemeRole.all`; a `.mctheme` without them reads Dracula's (already true of `ThemeFile`).
- Commands that need the toolchain: prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if `swift`/`swiftlint` fail to find it. Linux: `PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH" scripts/linux-test.sh test`.
- MetalUI gaps go in `docs/metalui-gaps.md` and to the `metalui-42` session; never worked around here.

## Decisions this plan makes (spec §8 "left to the builder")

- **Inset.** The app always sections at the clip plane moved `SectionCaps.inset = 1e-4` mm towards the kept side (`origin − clip.normal × inset`). This makes a section exactly on a boundary face (Section from Face, offset 0, or an origin plane on a box face) a proper cross-section instead of a coplanar degenerate case, and keeps the cap unclipped by its own plane.
- **Depth.** The cap is drawn right after the opaque solids with depth write, its vertices shifted towards the eye by half the edge depth bias (`edgeDepthBias × 0.5`), so it wins over a coplanar face and the part in front of the plane still hides it. Its clip test uses the unshifted world position, against the current clip (so an old cap still drawn after a plane move is clipped by the new plane).
- **Hatch.** Plane-space stripes: the fragment's position on the cap plane (axes `Plane.xAxis`, `yAxis` of `ViewportSection.plane`) is projected on the direction at the cap's hatch angle; a stripe every `hatchSpacingPoints = 8` points, `hatchLinePoints = 1.25` points wide, converted to millimetres each frame by `CameraMath.millimetresPerPoint(pose, size:)`. Stripes stay on the part while panning and orbiting.
- **Hatch angles** by the cap's order among capped items: 45°, 135°, 15°, 105°, 75°, 165°, then repeating (`ViewportSection.hatchAngle(forCap:)`, radians).
- **Picking.** The cap is drawn into the ID pass writing "nothing" (0) with depth, so a click on the cap never picks the inside face behind it. Section edges are not pickable in part B (Measure B decides).
- **Outlines** are `LineInstance`s through the existing `line` pipeline, `depthTest`, `ClipUniforms.off`, the B-rep edge's width, colour `sectionEdge`, cached by `ViewportSection.generation`.
- **The old darkened back faces stay** as what shows before the first cap lands, for an item whose section failed, and inside an open mesh.
- **Mesh pieces.** A mesh section's boundary is one `SectionPiece` per loop (a closed polyline, `curve` nil); Measure B may split them.
- **A failed section** of one item leaves that item uncapped and the Section panel shows `SectionCapModel.capProblem` = "The cut face couldn't be filled for every part." (no other wording).
- **Tolerance.** Solid sections are tessellated at the tolerance the viewport tessellates the part with (`ViewportModel`'s tessellation tolerance, the one passed to `TessellationCache.load` near `ViewportModel.swift:167`).

## Review Focus

1. **A section exactly on a face** (Section from Face at offset 0; an origin plane through a box's face): a person expects a filled cap, not speckle or nothing. Pinned by Task 3's inset kernel test, Task 5's coplanar render test and Task 7's offset-0 test.
2. **A plane beside the part** (offset past the part's end): no cap, no error, no problem line. Pinned in Tasks 2, 3, 4 and 7.
3. **Fast drags**: dozens of plane moves; only the newest section may be published, never an older one landing late. Pinned by Task 7's burst test.
4. **Open meshes and nested loops** (a mesh that does not close; a lattice skin with islands inside holes): open loops are outlines without a cap, and even-odd nesting gives the right regions. Pinned by Task 4.
5. **Clicking the cap**: a person expects nothing behind the cap to be picked or highlighted. Pinned by Task 5's (Metal) and Task 6's (SDL) ID-pass tests.

---

### Task 1: The section theme roles

**Files:**
- Modify: `Sources/CreatorStyle/ThemeColors.swift`, `ThemeRole+All.swift`, `ThemeRoleGroup.swift`, `ColorTheme+Dracula.swift`, `ColorTheme+Alucard.swift`, `ColorTheme+Nord.swift`
- Modify: `Sources/CreatorViewport/Render/ViewportPalette.swift` (where `ViewportPalette` is declared; both renderers read it)
- Test: `Tests/CreatorStyleTests/ThemeRoleTests.swift`, `ThemeTests.swift`, new `Tests/CreatorStyleTests/SectionRoleTests.swift`

**Interfaces:**
- Produces: `ThemeColors.sectionFill`, `.sectionHatch`, `.sectionEdge: HexColor` (stored, last, in that order); `ThemeRoleGroup.section` (title "Section", last case); `ViewportPalette.sectionFill`, `.sectionHatch`, `.sectionEdge: SIMD4<Float>` (gamma-space RGBA like the other fields).

Values (exact):

| Theme | sectionFill | sectionHatch | sectionEdge |
|---|---|---|---|
| Dracula | `0xbd93f9` | `0x282a36` | `0xf8f8f2` |
| Alucard | `0x644ac9` | `0xfffbeb` | `0x1f1f1f` |
| Nord | `0x81a1c1` | `0x2e3440` | `0xeceff4` |

Role titles: "Section fill", "Section hatch", "Section edge".

- [ ] **Step 1: Tests.** `ThemeRoleTests`: count 45 → 48. `ThemeTests`' Dracula table gains the three pairs. `SectionRoleTests`: `theSectionRolesAreLastInTheirOwnGroup` (the last three of `ThemeRole.all` have names `sectionFill`, `sectionHatch`, `sectionEdge` and group `.section`; `ThemeRoleGroup.allCases.last == .section`); `aThemeFileWithoutTheSectionRolesReadsDraculas` (decode a `.mctheme` JSON with only a name and one other role; its three section colours equal `ColorTheme.dracula.colors.quantized`'s); `eachBuiltInHasTheTabledColours` (the table above).
- [ ] **Step 2:** Run `swift test --filter CreatorStyleTests`; expect failures on the new names.
- [ ] **Step 3:** Add the properties, roles, group and built-in values; add the three `ViewportPalette` fields read from the theme.
- [ ] **Step 4:** `swift test --filter CreatorStyleTests` and `swift test --filter CreatorViewportTests` pass; `swiftlint lint --strict` 0.
- [ ] **Step 5:** Commit `feat(section): sectionFill, sectionHatch and sectionEdge theme roles`.

### Task 2: `PlaneSection` and the `Kernel.section` requirement

**Files:**
- Create: `Sources/CreatorKernel/Section/PlaneSection.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift` (requirement + default), `FakeKernel.swift` (or a new `FakeKernel+Section.swift`), `KernelUnavailable.swift`
- Test: `Tests/CreatorKernelTests/FakeKernelSectionTests.swift`

**Interfaces:**
- Produces:
```swift
public struct PlaneSection: Hashable, Sendable {
    public var regions: [SectionRegion]
    public var openOutlines: [[Vector3]]          // loops that did not close (meshes only)
    public init(regions: [SectionRegion] = [], openOutlines: [[Vector3]] = [])
    public var isEmpty: Bool                      // no regions and no open outlines
}
public struct SectionRegion: Hashable, Sendable {
    public var positions: [Vector3]               // on the plane
    public var triangles: [UInt32]                // 3 per triangle, indices into positions
    public var boundary: [SectionPiece]           // outer loop and holes, in any order
}
public struct SectionPiece: Hashable, Sendable {
    public var curve: EdgeCurve?                  // exact line or circle arc when known
    public var polyline: [Vector3]                // always present, for drawing
    public var sourceFace: FaceID?                // the solid's face this piece lies on
}
// Kernel:
func section(_ solid: Solid, by plane: Plane, tolerance: Double) throws -> PlaneSection
```
- Default in `extension Kernel`: `throw KernelError.unsupported("section")`; doc comment ending "The default refuses." `KernelUnavailable` refuses with `try refuse()`.
- `FakeKernel` (checks cancellation, logs `"section"` in `operationLog`): treats the solid as its `bounds` box. A plane whose normal is ±X, ±Y or ±Z (within 1e-9) gives one rectangular region (two triangles, four `.line` pieces, each `sourceFace` the topology face whose normal is that side's outward direction, nil when none matches); a plane that misses the box (or only touches it) gives `PlaneSection()`; any other normal throws `KernelError.unsupported("section on a tilted plane")`. Refuses a non-finite or non-positive tolerance with `KernelError.invalidInput`.

- [ ] **Step 1: Tests** in `FakeKernelSectionTests`: `aBoxCutAcrossGivesOneRectangle` (box 10×20×30 from the origin, plane z = 5 normal +Z: one region, area of its triangles 200, four pieces all `.line`, every piece's polyline has 2 points on z = 5); `aPlaneBesideTheBoxGivesNothing` (z = 40: `isEmpty`); `aTiltedPlaneIsRefused`; `aBadToleranceIsRefused` (0 and `.nan`); `theDefaultRefuses` (a minimal test kernel that does not implement it throws `.unsupported`).
- [ ] **Step 2:** Run `swift test --filter FakeKernelSectionTests`; expect a compile failure.
- [ ] **Step 3:** Implement the types, requirement, default and the two conformers.
- [ ] **Step 4:** Tests pass; `swift build` builds every target (any other `Kernel` conformer in tests compiles through the default).
- [ ] **Step 5:** Commit `feat(section): PlaneSection and Kernel.section, with FakeKernel's boxes`.

### Task 3: The OCCT section

**Files:**
- Create: `Sources/COCCT/cocct_section.cpp`, `Sources/CreatorOCCT/OCCTKernel+Section.swift`, a wrapper in `Sources/CreatorOCCT/OCCTShape+Section.swift`
- Modify: `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/OCCTSectionTests.swift`

**Interfaces:**
- Consumes: Task 2's types.
- Produces: `OCCTKernel.section(_:by:tolerance:)`.

C API (exact):
```c
typedef struct {
    double *positions; int vertex_count;                 // xyz per vertex, all regions
    unsigned int *indices; int triangle_count;           // into positions
    int *region_triangle_offsets; int region_count;      // region_count + 1 entries
    int piece_count;
    int *piece_region;                                   // region of each piece
    int *piece_kind;                                     // 0 polyline only, 1 line, 2 circle
    double *piece_curve;                                 // 11 per piece: line = start xyz, end xyz;
                                                         // circle = centre xyz, axis xyz, radius, start xyz, sweep
    int *piece_source_face;                              // 0-based face index, -1 when unknown
    double *piece_points; int *piece_point_offsets;      // piece_count + 1 entries
} occt_section_result;
int occt_section(const occt_shape *shape, const double origin[3], const double normal[3], const double x_axis[3],
                 double tolerance, occt_section_result *out, occt_status *status);
void occt_section_free(occt_section_result *result);
```

Approach (the spec leaves the OCCT construction to the builder; this is the decision): make a planar face on `gp_Pln(origin, normal, x_axis)` reaching `R = 2 × the shape's bounding-box diagonal + 1` each way (`BRepBuilderAPI_MakeFace(plane, -R, R, -R, R)`), take `BRepAlgoAPI_Common(solid, face)`; each face of the result is a region. Tessellate the result as `occt_tessellate` does (`IMeshTools_Parameters`, `Deflection = tolerance`, `Angle = 0.5`, `InParallel = false`), orient every triangle so its normal is along `normal`. Pieces: every edge of each region face; `piece_kind`/`piece_curve` from the same edge-curve description the topology tables use (reuse the helper behind `EdgeInfo.curve` in `cocct_inspect.cpp`; move it to `cocct_internal.hpp` if it is file-local); the polyline from `BRep_Tool::PolygonOnTriangulation`, else `GCPnts_TangentialDeflection` as `occt_tessellate` does. Source faces: for each face `f` of the solid (`map_of(shape, TopAbs_FACE)`), every edge in `common.Generated(f)` maps to `f`'s index; an edge found in none is -1. A plane missing the solid returns success with zero regions. Swift wrapper: as `OCCTKernel+FaceChart.swift` (check cancellation, validate the tolerance and a finite unit normal, `shape(of:)`, `try Self.serialized { () throws -> PlaneSection in … }` with untyped throws, map `OCCTError` to `KernelError.occt("section", error)`).

- [ ] **Step 1: Tests** (`#if canImport(CreatorOCCT)`, OCCT box/cylinder built through `OCCTKernel` as other `CreatorOCCTTests` do): `aBoxCutAcrossGivesOneRectangle` (20×10×6 box, plane z = 3: one region, triangle area 200 ± 1e-6, four `.line` pieces, each `sourceFace` non-nil and a side face whose normal is perpendicular to +Z); `aPlateWithAHoleGivesARegionWithAHole` (plate 40×40×6 minus a Ø10 through hole, plane z = 3: one region, triangle area `1600 − 25π` within 0.5 % (tessellated), one piece is `.circle` with radius 5 ± 1e-9); `aCylinderCutAlongItsAxisGivesARectangle` and `aCylinderCutAcrossGivesADisc` (the disc's one piece is a full `.circle`, radius exact); `aPlaneBesideTheSolidGivesNothing`; `aPlaneJustInsideATopFaceGivesTheWholeFace` (box top at z = 6, plane z = 6 − 1e-4: one region of area 200 ± 1e-3 — the inset case); `aBadToleranceIsRefused`; `everyCallFreesWhatItAllocates` is covered by `occt_section_free` being called in a `defer` (assert by code review, not a test).
- [ ] **Step 2:** Run `swift test --filter OCCTSectionTests`; expect failures.
- [ ] **Step 3:** Implement the shim, the header and the Swift wrapper.
- [ ] **Step 4:** `swift test --filter CreatorOCCTTests` passes (including `ShimPortabilityTests`, whose file count only grows); `swiftlint lint --strict` 0.
- [ ] **Step 5:** Linux: `PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH" scripts/linux-test.sh test --filter CreatorOCCTTests` passes.
- [ ] **Step 6:** Commit `feat(section): OCCTKernel.section through BRepAlgoAPI_Common with a planar face`.

### Task 4: `PolygonTriangulator` in CreatorGeometry and the `MeshSlicer`

**Files:**
- Create: `Sources/CreatorGeometry/PolygonTriangulator.swift` (the `outer:holes:` core of `RegionTriangulator`, moved unchanged, made `public`)
- Modify: `Sources/CreatorSketchEditor/RegionTriangulator.swift` (its `triangles(outer:holes:)` calls `PolygonTriangulator`; the `SketchRegion` overload and `polyline` stay)
- Create: `Sources/CreatorImplicit/Mesh/MeshSlicer.swift`
- Test: move the core cases of `Tests/CreatorSketchEditorTests/RegionTriangulatorTests.swift` that test `triangles(outer:holes:)` to `Tests/CreatorGeometryTests/PolygonTriangulatorTests.swift` (keep the region ones where they are); new `Tests/CreatorImplicitTests/MeshSlicerTests.swift`

**Interfaces:**
- Produces: `public enum PolygonTriangulator { public static func triangles(outer: [Vector2], holes: [[Vector2]]) -> [Vector2] }` (3 points per triangle, counter-clockwise, `[]` when it cannot finish exactly — unchanged behaviour).
- Produces: `public enum MeshSlicer { public static func slice(positions: [Vector3], triangles: [UInt32], plane: Plane) -> PlaneSection }`.

Algorithm (decided here):
1. Weld positions by exact bit equality (a dictionary keyed by the three `Double`s' bit patterns), so a display mesh with split vertices chains.
2. Signed distance `d = (p − plane.origin) · plane.normal` per vertex; a vertex with `d >= 0` is on the positive side (so no vertex lies on the plane and no segment is degenerate).
3. Each triangle with vertices on both sides gives one segment between the two crossing edges; a crossing point is keyed by its welded edge (the sorted index pair) and computed once.
4. Chain segments into loops through the edge keys; a chain that comes back to its start is a closed loop, any other is an open outline (`openOutlines`, as 3D points).
5. Project closed loops to 2D on (`plane.xAxis`, `plane.yAxis`); nesting depth of a loop = how many other loops contain one of its points (bounding-box prefilter, then even-odd point-in-polygon); depth even → an outer loop, odd → a hole of the containing loop of depth one less with the smallest area.
6. Each outer loop with its direct holes → `PolygonTriangulator.triangles`; the region's `positions` are the triangle points lifted back to 3D on the plane (no sharing; `triangles` is `0..<count`); `boundary` is one `SectionPiece` per loop (outer and its holes): `curve` nil, `polyline` the loop's 3D points with the first repeated at the end, `sourceFace` nil. A region whose triangulation comes back empty keeps its boundary and has no triangles.

- [ ] **Step 1: Tests** `MeshSlicerTests` (fixtures built in the test or `MeshFixtures`): `aClosedCubeCutAcrossGivesOneSquare` (unit-scale 10 mm cube mesh, 12 triangles, plane z = 5: one region, area 100 ± 1e-9, one piece with 5 polyline points, `openOutlines` empty); `aCubeWithSplitVerticesStillCloses` (same cube with each triangle's vertices duplicated: same result); `aTubeGivesARegionWithAHole` (square tube, outer 20, inner 10: one region of area 300); `anIslandInsideAHoleIsItsOwnRegion` (three nested closed square shells 30 / 20 / 10 (the 10 one solid inside the 20 one's cavity): two regions, areas 900 − 400 and 100); `anOpenMeshGivesAnOutlineWithoutACap` (the cube without its two +X side triangles, cut at z = 5: `regions` empty, one open outline of 4 points); `aPlaneBesideTheMeshGivesNothing`; `aPlaneThroughAVertexIsNotDegenerate` (plane through a cube corner level, z = 0 exactly on the bottom face's vertices: no NaN, every polyline point finite, result either empty or one region of area 100).
- [ ] **Step 2:** `PolygonTriangulatorTests` (the moved cases) and `RegionTriangulatorTests` (what stays) both pass after the move; run `swift test --filter MeshSlicerTests` and see it fail first.
- [ ] **Step 3:** Move the triangulator; implement `MeshSlicer`.
- [ ] **Step 4:** `swift test --filter CreatorGeometryTests`, `--filter CreatorSketchEditorTests`, `--filter CreatorImplicitTests` pass; `ImplicitPortabilityTests` passes; lint 0.
- [ ] **Step 5:** Commit `feat(section): MeshSlicer, with the polygon triangulator moved to CreatorGeometry`.

### Task 5: The cap in the viewport model and the Metal renderer

**Files:**
- Create: `Sources/CreatorViewport/Model/ViewportSection.swift`
- Modify: `ViewportModel.swift` (`showSection`), `ViewportModel+Frame.swift`, the render key (`ViewportRenderKey`), `Render/ViewportFrame.swift`
- Create: `Sources/CreatorViewport/Render/SectionShaders.swift` (MSL), `Render/ViewportRenderer+Section.swift`, `Render/SectionUniforms.swift` (Swift structs, portable like the other GPU structs)
- Modify: `Render/ViewportPipelines.swift` (`section`, `idSection`), `Render/ViewportRenderer.swift` (draw order, ID pass, shader source concatenation)
- Test: `Tests/CreatorViewportTests/ViewportSectionTests.swift` (model), `ViewportSectionRenderTests.swift` (Metal, `#if canImport(Metal)`), `GPUDataTests.swift`

**Interfaces:**
- Consumes: Task 1's palette fields.
- Produces:
```swift
public struct ViewportSection: Sendable, Equatable, Hashable {   // == and hash by generation only
    public struct Cap: Sendable { public var positions: [Vector3]; public var triangles: [UInt32]
                                  public var outlines: [[Vector3]]; public var hatchAngle: Double }
    public var caps: [Cap]
    public var plane: Plane                                         // hatch axes
    public var generation: Int
    public static let hatchSpacingPoints = 8.0
    public static let hatchLinePoints = 1.25
    public static func hatchAngle(forCap index: Int) -> Double    // 45°,135°,15°,105°,75°,165°, repeating; radians
}
ViewportModel.showSection(_ section: ViewportSection?)             // assigns when != (by generation); in renderKey and the frame
public private(set) var section: ViewportSection?
// GPU (Swift, MSL, later HLSL):
struct SectionVertex { var position: SIMD4<Float> }                              // stride 16
struct SectionUniforms { var fill, hatch, origin, axisU, axisV: SIMD4<Float>
                         var hatchParams: SIMD4<Float>   // spacing mm, line width mm, cos angle, sin angle
                         var depthParams: SIMD4<Float> } // x = bias towards the eye, mm   // stride 112
```
- MSL entry points: `section_vertex` (vertex buffer 0 `SectionVertex*`, 1 `FrameUniforms`, 2 `SectionUniforms`; outputs clip position shifted towards the eye by `depthParams.x` and the unshifted world position), `section_fragment` (fragment bytes 0 `SectionUniforms`, 1 `ClipUniforms`; discards when `clipped`; stripe = `fract(s / spacing) < width / spacing` with `s = u·cos + v·sin`, `u`,`v` on `axisU`,`axisV` from `origin`; returns `hatch` or `fill`, opaque), `id_section_fragment` (same discard, writes 0).
- Pipelines: `section` (not blended, 4× MSAA, `depthWrite`, no culling), `idSection` (`r32Uint`, 1 sample, `depthWrite`).
- Order in `encode`: caps right after `drawSolids(opaque, ghosts: false)`; outlines right after `drawEdges`. In `encodeIDs`: caps after the faces. One draw per cap (its own `SectionUniforms` with its angle); `fill`/`hatch` from `palette.sectionFill`/`sectionHatch`; bias `edgeDepthBias(frame) × 0.5`; `origin`, `axisU`, `axisV` from `section.plane`; spacing and width = points × `CameraMath.millimetresPerPoint(pose, size:)`.
- GPU buffers of caps and outline instances are kept between frames, keyed by `generation` (like `SliceTextures`), and dropped when the section is nil.

- [ ] **Step 1: Tests.** Model: `showSectionStoresAndClears`, `aNewGenerationChangesTheRenderKey`, `theHatchAnglesCycle` (indices 0…6 → 45, 135, 15, 105, 75, 165, 45 degrees). `GPUDataTests`: `SectionVertex` 16, `SectionUniforms` 112. Render (`RendererCacheTests.Rig`, `TestFrames`/`TestMeshes.box`, `OffscreenRenderTests.front`, as `ViewportClipRenderTests`): `aCapFillsTheCutWithTheSectionColours` (box clipped at its middle, cap = the box's cross-section on the clip plane; the centre region's pixels are each either `sectionFill` or `sectionHatch` within 3 per channel, and both occur in a 40×40 point window); `aCapCoplanarWithAFaceShowsNotTheFace` (cap at the front face's plane, inset 1e-4 inwards, no clip: the centre pixel is a section colour); `aCapBehindThePartIsHidden` (cap placed inside an unclipped box: centre pixel equals the frame without the cap); `anOldCapBeyondTheClipIsDiscarded` (cap on the cut-away side of the clip: equals the frame without it); `outlinesDrawInTheEdgeColour` (a pixel on the outline is `sectionEdge`); `aClickOnTheCapPicksNothing` (ID pass through `ViewportPicker` or the rig's pick: at the cap's centre, no pick; without the cap the same point picks a face).
- [ ] **Step 2:** Run `swift test --filter ViewportSection`; expect failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test --filter CreatorViewportTests` passes; `swift build` on macOS; lint 0. (`ShaderSourceTests` must still pass: the new Swift structs are not yet in `common.hlsli`; Task 6 adds both.)
- [ ] **Step 5:** Commit `feat(section): the hatched cap and outlines in the Metal viewport`.

### Task 6: The cap in the SDL GPU renderer

**Files:**
- Create: `Shaders/viewport/section.vert.hlsl`, `section.frag.hlsl`, `id_section.vert.hlsl`, `id_section.frag.hlsl`
- Modify: `Shaders/viewport/common.hlsli` (`SectionVertex`, `SectionUniforms`), `Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift` (`names` gains `"section"`, `"id_section"`), `SDLViewportPipelines.swift` (`section`: triangle list, no culling, `writes`; `idSection`), `SDLFramePlan.swift` (a `caps` field: per cap a vertex storage buffer, count and `SectionUniforms`; outline instances as a `Lines` with `ClipUniforms.off`), `SDLViewportRenderer+Plan.swift`, `+Record.swift`, `+IDPass.swift`
- Modify: `Tests/CreatorViewportTests/ShaderSourceTests.swift` (20 → 24 stages, the message "the viewport's 24 SDL_GPU shader stages were found", `stageSources.count >= 24`, the two structs in the `swift` dictionary), `ViewportShaderDirectoryTests` if it counts stages, `Sources/CreatorViewport/ViewportShaderCheck.swift` if it counts
- Test: new `Tests/CreatorViewportTests/SDLSectionTests.swift` (`@Suite(.enabled(if: SDLTestDevice.isAvailable, …))`, `SDLRenderRig`, `RenderFixtures`)

**Interfaces:**
- Consumes: Task 5's `ViewportSection`, `SectionVertex`, `SectionUniforms`, palette fields, draw order and bias.
- Bindings (SDL conventions): vertex storage buffer `StructuredBuffer<SectionVertex>`, vertex uniform slot 1 = `SectionUniforms`; fragment uniform 0 = `SectionUniforms`, 1 = `ClipUniforms`. `id_section` the same, writing 0. Every float computation `precise` is required only of the implicit HLSL, not here; follow `slice.*.hlsl`'s style.

- [ ] **Step 1: Tests.** `SDLSectionTests` mirrors Task 5's render tests: `aCapFillsTheCutWithTheSectionColours`, `aCapCoplanarWithAFaceShowsNotTheFace`, `anOldCapBeyondTheClipIsDiscarded`, `outlinesDrawInTheEdgeColour`, `aClickOnTheCapPicksNothing` (`rig.pick(at:in:)`). `ShaderSourceTests`' counts and struct table updated.
- [ ] **Step 2:** On macOS, `swift test --filter ShaderSourceTests` passes (struct sizes). 
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Linux: `PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH" scripts/linux-test.sh test --filter CreatorViewportTests` passes, the SDL section suite runs (not skipped) under lavapipe with `XP_REQUIRE_GPU=1` (the script's default).
- [ ] **Step 5:** macOS `swift test --filter CreatorViewportTests` and lint 0.
- [ ] **Step 6:** Commit `feat(section): the hatched cap and outlines on SDL GPU`.

### Task 7: `SectionCapModel` in the app

**Files:**
- Create: `Sources/CreatorApp/Section/SectionCapModel.swift`, `Sources/CreatorApp/Section/SectionCaps.swift` (pure helpers)
- Modify: `Sources/CreatorApp/AppModel.swift` (`let sectionCaps`, made with the kernel; `settle()` waits for it; `load` resets it), `AppModel+Scene.swift` (`refreshScene()` and `observeScene()`), `Sources/CreatorApp/Section/SectionPanel.swift` (shows `capProblem` under the note)
- Test: `Tests/CreatorAppTests/SectionCapModelTests.swift` (FakeKernel), `SectionCapOCCTTests.swift` (`#if canImport(CreatorOCCT)`), `SectionCapMeshTests.swift`

**Interfaces:**
- Consumes: Task 2 `Kernel.section`, Task 4 `MeshSlicer.slice`, Task 5 `ViewportSection`, `ViewportModel.showSection`; part A's `SectionModel.shown?.clip`.
- Produces:
```swift
enum SectionCaps {
    static let inset = 1e-4
    static func plane(for clip: ViewportClip) -> Plane      // origin − normal × inset, normal = clip.normal,
                                                             // xAxis = normalized(normal × (the world axis least aligned with normal))
}
@MainActor @Observable final class SectionCapModel {
    init(kernel: any Kernel, tolerance: Double)
    private(set) var revision: Int
    private(set) var section: ViewportSection?
    private(set) var problem: String?                        // nil or capProblem
    static let capProblem = "The cut face couldn't be filled for every part."
    var isComputing: Bool
    func follow(clip: ViewportClip?, items: [ViewportItem]) // nil clip: cancel, clear, bump revision once
    func waitForCaps() async
    func reset()
}
```
- `follow` returns at once when the clip and the capped items (`!isGhost && !isGuide`, compared by `ObjectIdentifier(item.solid)` in order) are unchanged. Otherwise it cancels the running task, bumps its generation and starts one task (the `FieldPreviewModel.sampleSlice` pattern) that, per capped item in order: `solid.displayedMesh` present → `MeshSlicer.slice(positions:triangles:plane:)` of that mesh (`indices`), off the main actor (a nonisolated helper); otherwise `try await kernel.section(solid, by: plane, tolerance: tolerance)`. A `CancellationError` publishes nothing; any other error for an item leaves that item without a cap and sets `problem`. On finish with the current generation: `section = ViewportSection(caps:…, plane:, generation:)` where cap `i` (among items that produced regions or open outlines) has `positions`/`triangles` concatenated from its regions, `outlines` = every piece's polyline plus the open outlines, `hatchAngle(forCap: i)`; an all-empty result publishes `section = nil`; `revision += 1`.
- `refreshScene()`: after `section.update(…)` and `viewport.showClip(…)`, `sectionCaps.follow(clip: section.shown?.clip, items: viewport.items)` then `viewport.showSection(sectionCaps.section)`. `observeScene()` tracks `sectionCaps.revision` like `fieldPreview.revision`. `settle()`'s loop also awaits `sectionCaps.waitForCaps()` and repeats while `sectionCaps.isComputing`. `tolerance` is the viewport's tessellation tolerance (see Decisions).

- [ ] **Step 1: Tests.** FakeKernel (`makeApp`, `GraphBuilder().box()`, part A's helpers): `turningTheSectionOnShowsACap` (on, settle: `viewport.section?.caps.count == 1`, its triangles non-empty, `app.isEdited == false`, `document.canUndo == false`); `turningItOffClearsTheCap`; `sketchModeClearsTheCap`; `aPlaneBesideThePartShowsNoCapAndNoProblem` (offset past the box: `viewport.section == nil`, `sectionCaps.problem == nil`); `aBurstOfMovesPublishesOnlyTheLast` (twenty `setSectionOffset` calls without awaiting, then settle: the cap's positions lie on the last offset's plane minus the inset, and `sectionCaps.revision` grew by fewer than twenty); `aRefusedSectionLeavesNoCapAndSaysSo` (a kernel wrapper around FakeKernel whose `section` throws `.unsupported`: no cap, `problem == SectionCapModel.capProblem`, panel text contains it); `ghostItemsAreNotCapped`; `theOldCapStaysUntilTheNewOneLands` (a kernel whose `section` waits on a continuation the test resumes: after a move and before resuming, `viewport.section` is the previous generation); `planeForAClipIsInsetTowardsTheKeptSide` (pure: `SectionCaps.plane`, origin moved by −normal × 1e-4, `xAxis` unit and perpendicular). OCCT: `sectionFromATopFaceAtOffsetZeroShowsTheFaceAsACap` (OCCT box, Section from Face on its top face, offset 0: one cap, triangle area 200 ± 1e-3); `aPlateWithAHoleShowsTheHoleInTheCap`. Mesh: `aMeshPartIsSlicedAndRefinedMeshesReslice` (a mesh graph as in the 7c app tests: cap present; after a refinement pass (`meshRefinement.waitForRefinement()`, settle) the cap's generation changed).
- [ ] **Step 2:** Run `swift test --filter SectionCap`; expect failures.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test --filter CreatorAppTests` passes; full `swift test` gives twelve "Test run with" lines (the known HLSL agreement failure aside); lint 0.
- [ ] **Step 5:** Commit `feat(section): SectionCapModel computes the cap off the main actor`.

### Task 8: Benchmark, human checks and status

**Files:**
- Create: `Tests/CreatorAppTests/Bench/SectionBench.swift` (`#if canImport(CreatorOCCT)`, `@Suite(.serialized, .enabled(if: Bench.isRequested, …))`)
- Modify: `docs/verification/performance.md` (a "Section analysis (section spec §3.4)" section: row definitions, the run's raw `BENCH` lines, and rows in the consolidated Results table), `docs/verification/human-checks.md` (group SA-B), `CLAUDE.md` (the part A status line extended, the `CreatorViewport` paragraph's cut-view sentence updated: the cap replaces the darkened back faces except as the fallback)

**Interfaces:**
- Consumes: everything above.

Rows (exact names): `sa-1 bracket section per drag step` (the bracket from `makeBracketBenchApp()`, `kernel.section` of its part at 60 offsets 0.25 mm apart across its height, first 5 dropped, `BenchSamples`, budget 16.67 ms recorded not gated); `sa-2 lattice slice per drag step` (the gyroid sheet's preview mesh from `ImplicitBenchFixtures.sheet(...)` with the 7c sizes, `MeshSlicer.slice` at 60 offsets); `sa-3 drag to cap on the bracket` (through `AppModel`: `setSectionOffset` then `settle()`, 60 steps). Benchmarks record, they do not gate (spec §9).

SA-B checks (each a numbered, observable step in the file's style): the bracket sectioned on XY shows a filled, hatched cap with crisp outlines; two touching bodies hatch at different angles; Section from Face at offset 0 shows the face as a cap; dragging the handle quickly never stutters and the cap catches up; a lattice part shows its cut cells capped; clicking the cap selects nothing; the cap follows the theme (switch to Alucard and Nord); Linux and Windows show the same (XP note); sketch mode hides the cap and leaving it brings it back.

- [ ] **Step 1:** Write `SectionBench`; check it compiles and is skipped in a plain `swift test`.
- [ ] **Step 2:** Run `scripts/bench.sh SectionBench` once. If the Mac is loaded, record the numbers as saturated, never as a verdict (project rule).
- [ ] **Step 3:** Write the docs.
- [ ] **Step 4:** Final checks: macOS `swift test` (twelve lines), Linux `scripts/linux-test.sh test` (twelve lines, exit 0), `swiftlint lint --strict` 0.
- [ ] **Step 5:** Commit `docs(section): part B benchmark rows, human checks SA-B and status`.
