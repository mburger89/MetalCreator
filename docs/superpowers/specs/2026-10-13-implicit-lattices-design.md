# Implicit geometry and lattices (sub-project 7c) — design

Status: written 2026-10-13 from a design conversation with the user; awaiting the user's review.
Parent spec: `2026-10-07-metalcreator-vertical-slice-design.md` (§4 values and broadcasting, §6 UI, §7 export and
performance), with all its Errata. Sibling specs `2026-10-10-patterns-trees-design.md` (7a: trees, placements; its §1
table places 7c after 7b) and `2026-10-12-fields-design.md` (7b: `Field`, `FieldSampler`, previews, format 7), with all
their Errata.

## 1. Intent

7c adds a second geometry world beside OCCT's exact B-rep: **implicit solids** (signed distance functions) that combine,
blend, shell and fill with **lattices**, and **meshes** made from them for printing. A B-rep part converts into the
implicit world once; everything after that is implicit until it is meshed; a small mesh can come back as a faceted solid.

**Purposes (user, all four):**
1. Lightweight parts: a solid keeps a skin and its inside becomes a lattice.
2. Compliant and cushioning parts: pads, grips, insoles, stiffness graded by a field.
3. Fluid and heat transfer: TPMS sheets that separate two volumes.
4. Look and decoration: the lattice is the design.

**Success.** A gyroid-filled bracket previews within a second of an edit and refines while you look; export at 0.1 mm
is watertight and manifold every time, with warnings for walls too thin to print and voids that can't drain; a 7b field
grades any lattice's thickness, strut radius or cell size; STL and 3MF carry the result.

### Decisions recorded (user, 2026-10-13)

| # | Decision |
|---|---|
| D1 | Purposes: all four above. |
| D2 | Live SDF: solids convert into the implicit world; implicits combine there (union, subtract, intersect, smooth blend, shell, offset) and are meshed at the end. B-rep operations happen only before conversion. |
| D3 | Lattice families: TPMS, periodic struts, Voronoi/stochastic, and conformal (as a mapping on all three). |
| D4 | Resolution: a coarse preview within ~1 s that refines in the background; a separate export resolution with progress and cancel. Metal evaluation, CPU reference and fallback. |
| D5 | Export and printability: 3MF export, thin-wall warning, trapped-volume check with optional drain holes, mesh decimation; every mesh from the mesher is watertight and manifold. |
| D6 | Approach A: an immutable expression tree compiled to Metal, evaluated sparsely (octree pruning by a Lipschitz bound), B-rep converted through OCCT tessellation and a BVH distance, marching cubes, then decimation. No third-party libraries. |
| D7 | Two new socket types, `implicit` and `mesh`. Meshing is an explicit node; an implicit wired into a mesh socket converts implicitly at default settings. |
| D8 | Mesh to Solid: a faceted B-rep, coplanar faces merged, refused above 100,000 triangles. **Amends the 2026-10-10 decision** ("lattice parts export STL/3MF, never STEP"): a mesh that goes through Mesh to Solid is a solid and exports STEP (faceted); a mesh wired to Output stays STL/3MF only. |
| D9 | Sharp B-rep edges come out rounded at one voxel (marching cubes, not dual contouring); accepted, because the manifold guarantee matters more. |
| D10 | Build split: 7c-1 core, then 7c-2 lattices and 7c-3 mesh tools in parallel, then 7c-4 conformal. |

## 2. Values

### 2.1 The implicit solid

- `ImplicitSolid` (new module `CreatorImplicit`, depending on `CreatorGeometry` and `CreatorGraph` for `Field`) is an
  immutable, `Sendable` indirect enum of nodes (primitives, combiners, lattices, conversions, rigid transforms). Its
  value at a point is a signed distance in mm: negative inside, zero on the surface (7b's D5 sign).
- Every node carries a `bounds: BoundingBox` that contains its surface, and a `lipschitz: Double ≥ 1` such that
  |f(a) − f(b)| ≤ lipschitz · |a − b| for all a, b. The evaluator divides by it before pruning (§4.2), so an
  overestimate costs speed, never correctness. Exact distances (primitives, rigid moves) have 1; smooth blends,
  field-graded settings and conformal mappings raise it (§3).
- `ImplicitSolid.description` is a one-line recipe like `Field.description` (e.g.
  `intersect(gyroid(cell 8 mm, sheet, t = remap(distance(edges))), offset(implicit(Bracket), −2 mm))`), shown in a
  read-only "Implicit" inspector row and shortened to 80 characters in socket tooltips.
- `Scalar` gains `.implicit(ImplicitSolid)`; `SocketType` gains `.implicit` ("an implicit solid", its own socket colour
  role). `estimatedBytes` is 64 + 32 per node plus any baked distance blocks (§4.4).
- Implicits are computed, never saved. They broadcast like any item value; a list into Union combines it (§3.3).

### 2.2 The mesh

- `TriangleMesh` (in `CreatorImplicit`): `positions: [Vector3]` (mm, Float storage), `triangles: [UInt32]` (three per
  face, counter-clockwise seen from outside), `resolution: Double` (the voxel size it was made at, 0 when unknown),
  `quality: .preview | .export`, plus optional `highlights: [MeshHighlight]` (a check's flagged triangles and its
  label). Immutable, `Sendable`, never saved.
- `Scalar` gains `.mesh(TriangleMesh)`; `SocketType` gains `.mesh` ("a mesh", taking the type the slice spec reserved).
  `estimatedBytes` is 16 per vertex + 12 per triangle.
- A mesh from the Mesh node is watertight and manifold (every edge has exactly two faces, consistently oriented, no
  self-intersections). Mesh-in, mesh-out nodes keep that true or refuse.

### 2.3 Conversions

| From → to | How |
|---|---|
| implicit → field | implicit: an implicit *is* its signed distance. `Field` gains a `.implicit(ImplicitSolid)` leaf, so Sample Field, Cull by Field, Field Scatter and the field previews accept implicits. |
| field → implicit | only through Isosurface (§3.1). |
| solid → implicit | only through To Implicit (§3.1). |
| implicit → mesh | implicit, at the Mesh node's default settings, when an implicit is wired into a mesh socket (Output, Decimate, the checks). Mirrors 7b's D4. |
| mesh → solid | only through Mesh to Solid (§3.6). |
| mesh → implicit, implicit → solid | none. |

`connectionProblem` refuses every other pairing as a type mismatch.

## 3. Nodes

Two new library categories, **Implicit** and **Mesh**. Field inputs accept numbers (7b's D4). Every field-graded
setting is sampled per point by the implicit's evaluator, never through `FieldSampler` point by point.

### 3.1 Converters

| Node | Inputs and settings | Output |
|---|---|---|
| To Implicit | `solid`; `tolerance` (mm, default 0.01, min 0.001) | implicit: the solid's signed distance. OCCT tessellates at `tolerance` (§4.4). Lipschitz 1. Error if the solid isn't closed: "This solid isn't closed, so inside and outside are undefined." |
| Isosurface | `field`; `level` (default 0); `max slope` (default 1, > 0) | implicit: inside where field < level, value (field − level) / max slope, so lipschitz is 1 when max slope is honest. Bounds from the field's support when known, else a required `bounds` input (a solid, implicit or two corner vectors). Help text says a too-small max slope makes holes in the preview. |

### 3.2 Primitives

Sphere (`radius`), Box (`size` vector, `corner radius`), Cylinder (`radius`, `height`, axis Z), each positioned like the
B-rep primitives (centred on the origin, then Place). Exact distances, lipschitz 1. They exist so drain plugs, cutters
and decorative shapes don't round-trip through OCCT.

### 3.3 Combining

| Node | Settings | Lipschitz |
|---|---|---|
| Union, Subtract, Intersect | `shapes` (a list; Subtract is the first minus the rest); `blend radius` (field, mm, default 0 = sharp). Smooth blends use the polynomial smooth min. | max of inputs (smooth min keeps it) |
| Shell | `thickness` (field, mm); `side`: Inward / Outward / Centred | input's, times (1 + the thickness field's slope bound) |
| Offset | `distance` (field, mm; positive grows) | as Shell |
| Place (existing) | now accepts implicits: a rigid transform per placement, exact | unchanged |

A field's slope bound comes from `Field.slopeBound` (new, conservative: analytic for distance, linear and radial
sources; a declared bound for noise; finite differences over the image's pixels for images; combined by the usual
rules for remap, multiply, clamp). An unknown bound is taken as 10 per mm and the node warns that the preview may be
slow.

### 3.4 Lattices (7c-2)

All three take a required `region` (an implicit; error "Connect a region to fill.") and output lattice ∩ region, plus an
optional `skin` (mm, default 0): when > 0 the output is Shell(region, inward, skin) ∪ (lattice ∩ Offset(region, −skin)),
which turns lightweighting into one node. All take a `mapping` (§3.5, default Straight).

| Node | Settings |
|---|---|
| TPMS | `type`: Gyroid, Schwarz P, Diamond, Neovius, Lidinoid; `form`: Sheet (two separated volumes; thickness is the wall) / Network (one solid side; thickness offsets the level); `cell size` (number or vector, field); `thickness` (field, mm) |
| Strut Lattice | `cell`: Cubic, BCC, FCC, Octet, Kelvin, Diamond; `cell size` (number or vector, field); `strut radius` (field, mm); `node blend` (mm, default 0) |
| Voronoi Lattice | `seeds`: a point list from any 7a/7b source, or, when unconnected, built-in seeds (`count`, `density` field, `seed`, using `SeededRandom` with a new `Purpose`); `form`: Struts (the cell edges) / Foam (the cell walls); `thickness` (field, mm) |

- TPMS values are the standard trigonometric approximations, scaled to mm by a per-type factor so that `thickness`
  is close to the true wall thickness; the factor and its error are pinned in tests (a gyroid's wall within 5%).
- Strut lattices are evaluated as the min over capsules of the current cell and its 26 neighbours (struts that cross
  cell faces). Voronoi uses a uniform hash grid over the seeds: Struts is the distance to the cell-edge network
  (second-nearest minus nearest, thresholded), Foam the walls between cells; both visit at most the 27 neighbouring
  grid cells.
- A `cell size` field warps the coordinates: the cell index uses the field's local value, so the pattern stretches
  where the field changes fast. The lipschitz bound grows with the field's slope bound; the help text says so.
- Warnings: cells smaller than 2 voxels at the current resolution ("Cells are smaller than the preview resolution; the
  preview may look solid."), walls or struts thinner than one voxel, a field-graded thickness or radius below 0
  (clamped to 0).

### 3.5 Mappings (conformal, 7c-4)

`mapping` (segmented) on every lattice node:

| Mapping | Lattice coordinates of a point p |
|---|---|
| Straight | p |
| Cylindrical (`axis`: a plane's normal through its origin) | (angle × mean radius, height, radius): cells wrap around the axis |
| Spherical (`centre`) | (longitude × r₀, latitude × r₀, radius), r₀ the region's mean radius about the centre |
| Face (`face`: a single-face pick on the source solid) | (u × scale, v × scale, signed distance to the face along its normal): cells follow the skin |

- Face mapping projects p onto the face's surface; projections are baked into distance blocks (§4.4) once per face and
  tolerance, so evaluation is a lookup. The face must belong to the solid the region came from (checked by topology
  tag) or the node errors.
- Every mapping scales the lipschitz bound by its maximum stretch over the region, computed when the mapping is built.
  Near a degenerate point (axis, pole, cone apex, a face's singular edge) the stretch is unbounded: the node clips the
  lattice to a 1 mm exclusion there and warns "The mapping is singular near …; cells there are left solid."

### 3.6 Printability and mesh nodes

| Node | Inputs and settings | Output |
|---|---|---|
| Drain Holes (7c-3) | `implicit`; `diameter` (mm, default 2); `direction` (vector, default −Z); `mode`: At Points (a `points` list) / Automatic | implicit minus a cylinder per hole. Automatic finds trapped voids on a coarse grid (§4.6) and drills from each void's lowest point along `direction` to the outside. |
| Mesh | `implicit`; `export resolution` (mm, default 0.1, min 0.01); `preview resolution` (Auto, or mm) | mesh |
| Decimate (7c-3) | `mesh`; `tolerance` (mm, default 0.01) | mesh, flat areas collapsed, Hausdorff distance ≤ tolerance |
| Check Thin Walls (7c-3) | `mesh`; `minimum` (mm, default 0.4) | the same mesh, with a highlight of thinner regions and a warning "Walls thinner than 0.4 mm in N places (thinnest 0.21 mm)." |
| Check Trapped Volumes (7c-3) | `mesh` | the same mesh, highlighting voids, warning "N enclosed voids can't drain." |
| Mesh to Solid (7c-3) | `mesh` | a solid (faceted), refused above 100,000 triangles: "Mesh has N triangles; Mesh to Solid takes at most 100,000. Decimate it first or coarsen the resolution." |

A check run on a preview-quality mesh says "(approximate: preview resolution)" in its warning.

The library grows by 19 nodes (66 → 85): Implicit has 14 (To Implicit, Isosurface, the three primitives, Union,
Subtract, Intersect, Shell, Offset, the three lattices, Drain Holes), Mesh has 5 (Mesh, Decimate, the two checks, Mesh to
Solid).

## 4. The engine

### 4.1 Compilation

- `ImplicitCompiler` turns an `ImplicitSolid` into Metal Shading Language source for one `float sdf(float3 p, …)`
  function plus a compute kernel that evaluates a batch of points. Sources are cached by the tree's **shape** (node
  kinds and wiring, not numbers); numbers go in a parameter buffer, so editing a value never recompiles.
  `MTLDevice.makeLibrary(source:options:)` runs off the main actor; compile errors are programming errors (logged, the
  CPU path takes over, a warning badge says "Running on the CPU").
- Field leaves compile by kind: distance-to-point/edges/plane, linear, radial, remap, maths and noise port to MSL;
  images upload as `r32Float` textures; kernel distances (Distance Field to a solid, edge set or face set) and To
  Implicit are **baked** (§4.4) and uploaded as sparse block tables.
- `ImplicitEvaluator.cpu` evaluates the same tree in Swift (Double), and is the reference: every node's Metal output
  agrees with it within 1e-4 mm on a fixed point set. Tests always use the CPU path except the GPU agreement suite,
  which is skipped without a Metal device.

### 4.2 Sparse evaluation

- The root's bounds, padded by one voxel, are the octree root. Each octree cell evaluates f at its centre; when
  |f| / lipschitz > half the cell's diagonal, the cell is wholly inside or outside and is pruned (its sign recorded).
- Surviving cells subdivide to **bricks** of 8 × 8 × 8 voxels at the target resolution (plus one shared layer), which
  are evaluated in GPU batches of up to 4,096 bricks.
- Memory scales with surface area. Before an export starts, the evaluator estimates samples from a coarse pass; above
  half of physical memory it refuses: "This needs about N GB at 0.1 mm; coarsen to X mm or split the part."
- Coordinates are Float on the GPU. A part whose bounds reach beyond 10 m from the origin warns about precision.

### 4.3 Meshing

- Marching cubes per brick with a fixed table and a fixed rule for ambiguous faces, so neighbouring bricks agree;
  vertices on edges shared between bricks are merged by a global edge key. The result is watertight and manifold by
  construction.
- Each vertex takes one Newton step along the gradient (central differences) towards f = 0, clamped to half a voxel.
- **Preview** (D4): the first pass runs at 128 cells across the largest dimension, then halves the voxel size each pass
  until the preview resolution (Auto: the finest that meshes in under 1 s, estimated from the last pass); each pass
  replaces the viewport mesh. An edit cancels the running passes (`Task.checkCancellation()` between brick batches).
- **Export** evaluates the graph to each Output with `EvaluationContext.meshQuality = .export`, at each Mesh node's
  export resolution, in a progress sheet with Cancel (§5.3).

### 4.4 Baked distances

- `DistanceBlocks`: a sparse table of 8³ blocks of Float distances over the narrow band (within 4 blocks of the
  surface) at a given spacing, plus a coarse conservative distance (the block's lower bound) everywhere else in the
  bounds. Trilinear interpolation inside a block; lipschitz 1 within the band (spacing chosen so interpolation error
  ≤ tolerance).
- To Implicit: OCCT tessellates (existing `cocct_mesh`), Swift builds a BVH over the triangles, unsigned distance is the
  nearest triangle, sign from the angle-weighted pseudonormal (robust on OCCT's watertight tessellations). Kernel
  distances in fields bake the same way from 7b's `Kernel.distances`.
- Bakes are cached in an `ImplicitBakeCache` (actor, keyed by the solid's identity and tolerance, LRU, 512 MB cap).

### 4.5 Decimation

Quadric error metric edge collapse (Garland–Heckbert) with a priority queue; a collapse is refused when it would make
an edge non-manifold, flip a face, or exceed the tolerance (Hausdorff bound tracked per vertex). Boundaries don't exist
(meshes are closed).

### 4.6 Checks and drain holes

- Thin walls: per vertex, a ray inward along −normal against the mesh's BVH; thickness is the first hit distance. Below
  `minimum`, the vertex's faces are highlighted; nearby flagged faces are grouped into "places".
- Trapped volumes: a coarse occupancy grid (2 mm or 32 cells across, whichever is finer) flood-filled from outside;
  unreached empty components larger than one cell are voids. Drain Holes' Automatic mode runs the same test on the
  implicit directly.

### 4.7 Mesh to Solid

The OCCT shim gains `occt_mesh_to_solid(positions, triangles)`: builds a planar face per triangle, sews them
(`BRepBuilderAPI_Sewing`), merges coplanar faces (`ShapeUpgrade_UnifySameDomain`), checks `BRepCheck_Analyzer` and a
closed shell, and makes the solid. A failure returns OCCT's reason as the node's error. Topology tags: every face gets
the node's operation tag (face picks on the result work like on any solid, by tag and normal).

### 4.8 Caching

The Mesh node caches by (tree hash including numbers, resolution, quality); re-exporting an unchanged part is instant.
Caches live in the evaluation context and obey the existing memory budget.

## 5. UI, errors and export

### 5.1 Viewport

- Meshes are `ViewportItem`s like tessellated solids (smooth normals from the mesher). A small badge on the part reads
  "Preview 0.4 mm" and shows a spinner while refining.
- Check highlights tint in the theme's existing warning role.
- **Cut view** (7c-3): a viewport toggle (toolbar and View menu, off by default) clips all items by a movable plane,
  reusing 7b's slice-plane gizmo, so a lattice can be seen inside its skin. The clip runs in the fragment shader; the
  cut face is drawn in the part's colour darkened.
- Field previews (7b) work on implicits, which are fields.

### 5.2 Inspector

Mesh: triangle count, resolution, meshing time, memory. Decimate: triangles before → after. Checks: the thinnest wall
or the void count. To Implicit: bake time and memory.

### 5.3 Export

- File > Export 3MF… joins Export STEP… and Export STL….
- Export STEP refuses an Output holding a mesh: "Output 'Insole' is a mesh; STEP needs solids. Export STL or 3MF, or
  convert it with Mesh to Solid."
- Export runs in a sheet with a progress bar (bricks done / estimated) and Cancel; afterwards a summary lists warnings
  ("Exported with 2 warnings: thin walls on 'Insole' …").
- STL writes meshes directly; solids go through OCCT tessellation as today.
- 3MF: an OPC zip with `[Content_Types].xml`, `_rels/.rels` and `3D/3dmodel.model` (unit `millimeter`, one `<object>`
  per Output named after it, `<build>` items, vertices with six significant digits). The zip writer is ours
  (`ZipWriter` in `CreatorApp`, deflate via Apple's Compression framework, CRC-32 in Swift).

### 5.4 File format 8

`GraphFile.currentFormatVersion` becomes 8: `implicit` and `mesh` socket types may appear on group interfaces, and the
new nodes' settings (TPMS type and form, strut cell, Voronoi form, mapping, resolutions, drain-hole mode) are saved as
the existing integer, number and text settings. Implicits and meshes are never saved. Files of formats 1 to 7 open
unchanged and are written as 8.

## 6. Performance

A new `ImplicitBench` suite (release, idle Mac, `BENCH` lines into `docs/verification/performance.md`):

| Row | Case | Target |
|---|---|---|
| i-1 | Gyroid sheet filling a 100 mm cube: first preview pass | < 1 s |
| i-2 | A thickness value edit (no recompile): one coarse pass | < 100 ms |
| i-3 | To Implicit of the slice's filleted bracket: bake | < 500 ms |
| i-4 | Export i-1 at 0.1 mm: whole pipeline | < 60 s, peak memory < 4 GB |
| i-5 | Decimate a 2,000,000-triangle mesh | < 10 s |
| i-6 | Mesh to Solid, 100,000 triangles | < 15 s |

## 7. Testing

- **Reference values:** every node's CPU distances at hand-worked points; bounds contain the surface; a Lipschitz
  property test on random point pairs for every node and every mapping.
- **GPU agreement:** the same trees on a fixed point set within 1e-4 mm (skipped without Metal).
- **Mesh invariants on every produced mesh:** each edge has two faces, consistent orientation, Euler characteristic
  matching the expected genus; a sphere's volume within 0.5%; a gyroid sheet's volume fraction against its known value.
- **Decimate:** fewer triangles, Hausdorff ≤ tolerance, still manifold.
- **Checks:** fixtures with a 0.2 mm wall and a sealed internal void are found; after Drain Holes (Automatic) the void
  count is 0.
- **Mesh to Solid:** `BRepCheck` valid, volume equals the mesh's within 1e-6 relative, STEP export succeeds, the cap.
- **Export:** 3MF read back by our own reader (valid zip, CRC, XML matching the 3MF core schema, mm, named objects);
  STL round trip; STEP refusal message.
- **Format 8:** save and reopen; formats 1 to 7 open unchanged.
- **Window tests (MetalUITesting):** the export sheet's progress and Cancel, the Cut view toggle, the preview badge.
- **Acceptance (headless, OCCT):** a lightweight bracket. The slice's bracket → To Implicit → TPMS (Gyroid, Sheet,
  thickness graded by a distance field, skin 1.5 mm) → Drain Holes (Automatic) → Mesh (0.3 mm) → Check Thin Walls →
  Check Trapped Volumes → Output, exported as 3MF. Asserts manifold, 0 voids, no walls under the minimum, volume
  between 15% and 40% of the solid's, identical bytes on a second run.
- **Human checks:** group IM: preview refinement feel, Cut view, lattice look, export sheet; 3MF opens in a slicer.

## 8. Build split (D10)

| Plan | Contents | Depends on |
|---|---|---|
| 7c-1 core | `CreatorImplicit`; `ImplicitSolid`, `TriangleMesh`, `.implicit` / `.mesh` sockets and conversions, `Field.implicit` leaf and `Field.slopeBound`; CPU evaluator, `ImplicitCompiler` and the Metal path, sparse octree, marching cubes, `DistanceBlocks` and `ImplicitBakeCache`; To Implicit, Isosurface, the primitives, Union/Subtract/Intersect/Shell/Offset, Place on implicits, Mesh; viewport meshes and the progressive preview; STL of meshes, the export sheet and STEP refusal; format 8; `ImplicitBench` i-1 to i-4 | master |
| 7c-2 lattices | TPMS, Strut Lattice, Voronoi Lattice (Straight mapping), region and skin, field grading of cell size | 7c-1 merged |
| 7c-3 mesh tools | Decimate, Check Thin Walls, Check Trapped Volumes, Drain Holes, Mesh to Solid (+ OCCT shim), 3MF and `ZipWriter`, Cut view, `ImplicitBench` i-5 and i-6, the acceptance test (after 7c-2 merges, whichever lands second adds it) | 7c-1 merged; beside 7c-2 |
| 7c-4 conformal | Cylindrical, Spherical and Face mappings, stretch-scaled lipschitz bounds, singular-region clipping | 7c-2 merged |

7c-2 and 7c-3 share `CLAUDE.md`, `docs/verification/human-checks.md` and `BuiltInNodes`; the second to merge keeps both.

## 9. Out of scope (later)

Importing STL or 3MF as inputs; colour and multi-material 3MF; fitting smooth NURBS to meshes; feature-preserving
meshing (dual contouring); mesh booleans; surface textures and displacement (7d, which will reuse this engine).

## Errata (2026-10-13: portability, user decision)

- **D11. 7c stays portable to Linux and Windows** (user, 2026-10-13, alongside the cross-platform port track). This
  amends D4, D6 and §4.1:
  - The CPU evaluator (`ImplicitEvaluator.cpu`) is a **complete engine**, not only a reference. Every feature (sparse
    evaluation, meshing, preview passes, export) works on it, and it is what runs wherever no GPU evaluator exists.
  - GPU evaluation sits behind a protocol, `ImplicitGPUEvaluator` (compile a tree, evaluate a batch of points or
    bricks, cancel), that the rest of the engine depends on. `MetalImplicitEvaluator` is its only implementation in
    7c and lives in its own file or target, compiled only where Metal is available (`#if canImport(Metal)`). An SDL
    GPU compute implementation comes later, when MetalUI exposes one (gap forwarded 2026-10-13).
  - Nothing outside that implementation imports Metal, simd, CoreGraphics or another Apple-only framework. The GPU
    agreement suite is skipped where no GPU evaluator exists.
  - §6's i-1, i-2 and i-4 targets are for the Metal path on this Mac; the CPU path records its numbers without a budget.
- **D12. Export streams to the file** (user decision on the 7c-1 plan's U5, 2026-10-14). A whole 0.1 mm lattice mesh is
  about 150 million triangles, roughly 22 GB in memory. Export at export resolution therefore never holds it:
  - Bricks are meshed in a fixed order, and each brick's triangles go straight to the STL or 3MF writer. Shared-edge
    vertices are merged within a window of neighbouring bricks, so the file stays watertight.
  - Decimate and the checks run during export on that stream per brick: Decimate collapses inside each brick and never
    moves a brick-boundary vertex. Otherwise they run on an in-memory copy at preview resolution, which is labelled
    "approximate (preview resolution)".
  - i-4 keeps its targets (under 60 s, under 4 GB). The streaming writer belongs to 7c-3.
- **D13. Meshing runs on the GPU too** (user decision on U6, 2026-10-14). Marching cubes, including the shared-edge
  merge and the Newton snap, gets a GPU implementation behind the same protocol as the evaluator. The protocol becomes
  `ImplicitGPUEngine`: evaluate bricks and mesh bricks.
  - `MetalImplicitEngine` comes first.
  - An **SDL3 GPU compute** implementation for Linux and Windows follows, once MetalUI exposes SDL GPU compute to apps
    (gaps XP-G1 and XP-G2, MetalUI S5 and S6). The user asked for it explicitly.
  - The CPU mesher stays the complete reference and fallback. GPU and CPU meshes must agree: the same topology class,
    and vertices within 1e-4 mm after the snap. i-1 and i-2 keep their budgets, measured on the GPU path.
  - Build: a lane "7c-1g GPU meshing" after the Metal evaluator task. The SDL3 engine is its own track, "xp-c", after
    MetalUI S5 and S6.
- **D14. Lattice details** (the user's answers on the 7c-2 plan, 2026-10-14).
  - **Voronoi Struts is the third-nearest seed distance minus the nearest (d3 − d1),** not §3.4's "second-nearest minus nearest". d2 − d1 is zero on every cell wall, so it would draw Foam again; d3 − d1 is small only along the edges where three cells meet. `thickness` is the strut diameter, exact where three equal cells meet.
  - **Where no seed is in range,** for example where a density field falls to 0, the lattice is left **solid** and the node warns.
  - **`cell size` is a field** (a number or graded), **plus a separate `cell stretch` vector** (default 1, 1, 1) for non-uniform cells.
- **D15. GPU meshing details** (the user's answers on the 7c-1g plan, 2026-10-14). These amend D13.
  - **Agreement between GPU and CPU is two checks.**
    - The mesher alone, on identical samples: vertices agree within 1e-4 mm.
    - The whole pipeline: surfaces agree within 1e-4 mm and vertices within 2e-3 mm. A vertex can move further where an edge runs nearly tangent to the surface.
    - Both hold for parts within a few hundred mm of the origin, because positions are stored as Float.
  - **The Auto preview is capped.** It refines until the next pass would exceed about 2,000,000 triangles, or until the time budget runs out, whichever comes first. Export resolution is unaffected.
- **D16. Mesh tools** (the user's answers on the 7c-3 plan, 2026-10-14).
  - **3MF uses Zip64** whenever an entry, an offset or the file passes 4 GB, and plain zip below that. Writing a 3MF needs about twice its XML size free on disk.
  - **Check Trapped Volumes uses a 0.5 mm grid cell within a 32-million-cell budget.** The cell is coarser only for parts over about 150 mm (0.96 mm at 300 mm), and the check then warns that the part is large. Drain Holes warns when a hole is under four cells across. This replaces §4.6's 2 mm / 32-across, which can't see a 2 mm drain hole.
  - **Mesh to Solid builds its faces sharing vertices by index,** because the mesh is already watertight. It doesn't use `BRepBuilderAPI_Sewing`. It still merges coplanar faces and checks the result with `BRepCheck_Analyzer`.
  - **The acceptance bracket's volume is asserted between 15% and 75% of the solid.** The slice's thin bracket measures 50.2% with a 1.5 mm skin.
- **D17. Surface agreement scales with the field's slope** (user, 2026-10-14). This amends D15's whole-pipeline surface check. GPU and CPU agree on the field's value to about 1e-4. Where grading or noise makes the field's slope |∇f| at the surface less than 1, that moves the surface by 1e-4 ÷ |∇f|. So the check allows 1e-4 mm ÷ |∇f| at each compared point, and never less than 1e-4 mm. Plain shapes keep exactly 1e-4 mm.

- **D19. The Auto preview cap is 1M triangles** (user, 2026-10-20, measured; amends D15's "about 2M"). The idle sweep (performance.md, 2026-10-20, MetalUI 711ab9c4, graph panel shown):

  | Triangles | GPU p95 |
  |---|---|
  | 0.57M | 7.55 ms |
  | 1.04M | 9.31 ms |
  | 1.98M | 11.14 ms |

  Window CPU, added footprint and GPU mesh time held at every rung up to 2M. The sweep's strict rule (GPU p95 ≤ 8 ms) picks 0.57M. The user chose 1M for detail, because 9.3 ms leaves headroom in a 16.7 ms frame. Above the cap the preview coarsens; export is always full resolution.

### Errata (7c-3 acceptance, measured)

- **M5. The lightweight bracket does not yet meet "0 voids, no thin walls".** Measured on the exported 3MF (gyroid sheet, cell 10 mm, wall 1.2 mm at the skin to 0.8 mm eight millimetres in, skin 1.5 mm, Drain Holes Automatic 2 mm, Mesh 0.3 mm): a closed manifold, identical bytes on a second run, 67.1% of the solid's volume (D16's 15% to 75%), but Check Trapped Volumes still finds 103 voids of 2 to 12 cells (chambers about 1 mm wide where the sheet meets the skin) and Check Thin Walls 127 places. Drain Holes does drain the 41 larger chambers; its grid (laid over the implicit's loose bounds) and the check's (over the mesh) fall differently on a pocket a cell across, and neither grid's classification is exact for a field that is not a distance. `LightweightBracketAcceptanceTests` keeps the two spec expectations inside `withKnownIssue`, so it fails the day they hold. Fixing it needs Drain Holes and the check to see pockets the same way (a decision for the user). **Resolved by D18 (7c-3f):** the 103 voids were phantoms of the pseudonormal sign, the 127 thin places knife edges of the sharp skin join, and the bracket now measures 0 voids and 0 thin places at the lattice nodes' default blend.
- **M6. `SignedDistanceMesh` counts an arealess triangle for closedness.** A 3MF's six digits turn a few thin triangles of the 0.3 mm mesh into three collinear points; dropping them opened the surface and Check Trapped Volumes refused the file's mesh as not closed. They now close the surface and add no distance.
- **D18. A blended skin join and a check that is not fooled by the junction** (user, 2026-10-20; resolves M5). The 7c-3f diagnosis measured the cause of M5:
  - **The voids are phantoms.** All 103 "voids" are solid material. The field is ≤ 0 at all 425 void-cell centres, and the mesh's winding number is 1 at every sampled cell. Where the gyroid sheet meets the skin tangentially it leaves a wedge narrower than the 0.3 mm mesh cell. There `SignedDistanceMesh`'s pseudonormal sign test reads inside as outside, and the occupancy grid takes those solid cells for empty.
  - **The thin walls are knife edges.** All 127 places are at the same junction. About 70% are real knife edges of the sharp union, and the rest are ray misreads. The graded 0.8 mm wall itself measures ≥ 0.96 mm.

  So:
  - **The lattice nodes' skin join is blended.** TPMS, Strut and Voronoi gain a `blend` input in mm, default 1.0. `LatticeFill` joins the skin and the lattice with the kernel's polynomial smooth union of that radius in place of the sharp union. A blend of 0 is the old sharp join. A file saved before 7c-3f reads `blend` as 0, so a saved graph's geometry doesn't change. On the bracket, measured: r 0.5 gives 1 void, 5 thin places and 67.8%; r 1.0 gives 1, 1 and 70.0%; r 1.5 gives 0, 0 and 73.5%.
  - **Check Trapped Volumes decides inside and outside robustly.** A cell's occupancy comes from the mesh's generalized winding number (inside if ≥ ½), or an equally robust test such as majority ray parity over three or more directions, never from the pseudonormal sign alone. `SignedDistanceMesh` keeps the sign test only where it is reliable, or takes its sign from the same robust test. Drain Holes Automatic classifies the same way.
  - **Check Thin Walls ignores self-adjacent hits.** A ray hit closer than 0.05 mm that leaves through a face sharing a vertex or an edge with the start's own one-ring is skipped, and the ray continues. Real knife edges thinner than the minimum are still reported.
  - **The acceptance test asserts 0 voids and no thin walls** at the default blend, and its `withKnownIssue`s come out. If r 1.0 still leaves a real hit after the check is fixed, the plan raises the bracket's blend, not the node default, and records the measurement here.
  - **Measured by 7c-3f.** With the robust checks, the bracket at the default blend of 1 mm gives 0 voids, 0 thin places and 70.0% of the solid's volume, so the bracket's blend is not raised. Check Trapped Volumes asks the winding number once per region of cells, not once per cell (the cells near the surface come from the unsigned distance, and each pocket the flood fill leaves is inside the material or a cavity as a whole): per cell it cost 18.5 s on a 555,000-triangle sheet and 138.6 s on a 2.55-million-triangle one, against 0.8 s and 3.9 s for the pseudonormal sign, and one question per region costs the same as the pseudonormal sign (`docs/verification/performance.md`, row i-8). Drain Holes Automatic keeps the sign of its own field, which is exact, and uses the same definition of a solid cell as the check (inside, or within half a cell of the surface). **That departs from the first sentence of this erratum's Drain Holes line** ("classifies the same way as the check"), and the grid mismatch of M5 is not fixed: Drain Holes' grid is laid over the implicit's bounds and the check's over the mesh, and a field value is not a distance, so half a cell in field units is not geometric. The two agree on the bracket and on three sheets on a skin (`DrainHolesTests`), not by construction: on a sheet of 6 mm cells in an 8 mm box (region moved by (0.2, 0.7, -0.3), meshed at 0.5 mm) Drain Holes finds 2 voids and the check 3, and one void is left after drilling; in a 12 mm box (moved by (0.3, 0.1, 0.2), meshed at 0.6 mm) Drain Holes finds 10 and the check 3. Closing it means either meshing the implicit for Drain Holes (a meshing pass before every drain) or sampling its field on the check's grid; neither is done (user decision 3). `SignedDistanceMesh.signedDistance` keeps the pseudonormal sign for the bake (To Implicit's meshes are the kernel's clean tessellations); `isInside`, `robustSignedDistance` and `windingNumber` are the winding-number sign.
