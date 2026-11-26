# CreatorImplicit (implicit geometry, lattices, meshes)

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

Implicit geometry, sub-project 7c-1 (the core: the `CreatorImplicit` module, the `implicit` and `mesh` socket types, the CPU and Metal
evaluators, the sparse octree, the manifold mesher, baked distances, the eleven Implicit and Mesh nodes, mesh items and the progressive
preview in the viewport, STL of meshes with the export sheet, file format 8 and `ImplicitBench` rows i-1 to i-4; plan
`docs/superpowers/plans/2026-10-13-7c-core.md`, spec `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §2 to §6 and the
7c-1 errata in the plan's header) code is done; its human checks (group IM) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`.
Implicit geometry, sub-project 7c-1g (meshing on the GPU, spec Errata D13: `ImplicitGPUEngine.meshBricks`, the Metal marching-cubes
kernels with a CPU-against-GPU mesh agreement suite, and rows i-1 and i-2 measured on that path; plan
`docs/superpowers/plans/2026-10-14-7c-1g-gpu-meshing.md`) code is done; its human check (IM-13) is pending and its benchmark numbers are
recorded in `docs/verification/performance.md`. Linux and Windows follow macOS since xp-c (below).
Implicit geometry, sub-project 7c-3 (the mesh tools: Decimate, Check Thin Walls, Check Trapped Volumes, Drain Holes and Mesh to Solid;
3MF with our own `ZipWriter`; the streamed export of spec Errata D12; the Cut view (since replaced by the Section); `ImplicitBench` rows i-4b to i-7; the lightweight
bracket acceptance test; plan `docs/superpowers/plans/2026-10-14-7c-3-mesh-tools.md`, spec `2026-10-13-implicit-lattices-design.md` §3.6,
§4.5 to §4.7, §5 and §7 with Errata D12 and D16) code is done; its human checks (group MT) are pending and its benchmark numbers are
recorded in `docs/verification/performance.md`. Mesh to Solid is macOS-only (OpenCascade); everything else runs on
Linux and Windows.
Implicit geometry, sub-project 7c-3f (spec Errata D18, resolving M5: the TPMS, Strut Lattice and Voronoi Lattice nodes gain a `blend` input, default 1 mm, the radius of the smooth union that joins the skin and the lattice, `typeVersion` 2 with a migration that gives a saved graph's node a blend of 0; Check Trapped Volumes decides inside by the mesh's generalized winding number, asked once per region of cells; Check Thin Walls skips a hit under 0.05 mm on a face of the start vertex's one-ring; the lightweight bracket acceptance test asserts 0 voids and 0 thin places, its `withKnownIssue`s gone; plan `docs/superpowers/plans/2026-10-20-7c-3f-skin-blend-and-robust-checks.md`) code is done; its human check IL-10 is pending.
Implicit geometry, blend continuity (G-a of `docs/superpowers/specs/2026-11-01-g2-surfacing-design.md`, plan G-a, branch `g2a-implicit`): `BlendContinuity` (`CreatorGeometry`: `g1`, `g2`, `g3`) names how a smooth union, subtraction or intersection joins its operands, with h = max(k−|a−b|, 0)/k: G1 is `min − h²k/4`, G2 `min − h³k/6` and G3 `min − h⁴(h²−6h+10)k/32`, a true C3 smooth minimum (the kernel (15/16)(1−s²)², not Quilez's quartic), their deepest dips k/4, k/6 and 5k/32. `ImplicitSolid.union/subtract/intersect(…continuity:)` and `StrutLattice.nodeContinuity` carry it; the MSL `smoothMin2` and `smoothMin3` and their HLSL twins are emitted only when a tree uses them (strut joints use a derived copy, `ContinuityLibrary.strutCopy`), and a blend of 0 compiles as G1, the sharp min. Union, Subtract and Intersect (`typeVersion` 2) and TPMS, Strut Lattice and Voronoi Lattice (`typeVersion` 3, where the one socket governs the skin and the strut joints) have a `continuity` socket, a segmented G1 / G2 / G3 defaulting to G2 on Union, Subtract and Intersect and to G1 on the three lattices (their skin join is tuned for printability, and G2 at the default 1 mm blend left two voids on the lightweight bracket; G2 and G3 stay selectable, at a wider blend for the same dip: 1.5 mm for G2, 1.6 mm for G3, which instead leave 2 thin places there; spec erratum 2026-11-01); a saved node migrates to G1, so an old file looks as it did. `BlendZebraTests` (`CreatorAppTests`) holds the result to the zebra check; human checks (group GA) are pending.

Mesh import, MI-1 (STL: spec `docs/superpowers/specs/2026-11-03-mesh-import-design.md`, plan `docs/superpowers/plans/2026-11-03-mesh-import.md`, the
Import Mesh node, `CreatorImplicit/Import`, linking and embedding a file, file format 12, File ▸ Import Mesh…, the facts and warnings, `creaseAngle`
and the tools' rulings on an imperfect mesh) code is done; its human checks (group MI) are pending. Mesh import, MI-2 (3MF: our own `Inflate`, `ZipReader` for other tools' zips, `XMLScanner`, `ThreeMFReader`; one mesh per build item, units, transforms and components, supports left out, extensions refused; detection by the file's bytes; a list of meshes exports one 3MF object each) code is done; its human checks (group MI) are pending. The benchmarks (MI-3, `Tests/CreatorAppTests/Bench/MeshImportBench.swift`, rows `mesh-import-1` to `-8`) are recorded in `docs/verification/performance.md` ("Mesh import"): a million triangles read to the first display in 0.16 s (binary STL), 0.33 s (ASCII) and 0.56 s (3MF), and the 10,000,000-triangle limit kept (a height field peaks at 2.4 GB, an all-distinct soup at 5.9 GB, 2 to 4.4 s; drawing and orbiting it is human check MI-10). `EdgeCounts` is computed once at parse and kept in `ImportedMesh.edgeCounts`.

Implicit lattices, sub-project 7c-2 (the TPMS, Strut Lattice and Voronoi Lattice nodes with the Straight mapping only, a region and a
skin, field grading of cell size, thickness and strut radius, a separate cell stretch vector, their warnings, and `ImplicitBench`'s sheet
swapped to a gyroid; plan `docs/superpowers/plans/2026-10-14-7c-2-lattices.md`, spec
`docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §3.4 and Errata D14) code is done; its human checks (group IL) are pending
and the benchmark rows have not been re-run with the gyroid.
Implicit lattices, sub-project 7c-4 (conformal mappings: a `mapping` setting on the TPMS, Strut Lattice and Voronoi Lattice nodes, Straight / Cylindrical /
Spherical / Face; `LatticeMapping` in `CreatorImplicit/Mapping`, `FaceChart` and `FaceChartCache` for the baked projections of a face,
`Kernel.faceParametrization` and `Kernel.faceCoordinates` with the OCCT shim `cocct_face_chart.cpp`, the Metal functions `mapCylindrical`,
`mapSpherical`, `mapFace` and `mappingJoin`, "Pick Face in View…" for a lattice node, `ImplicitBench` rows i-9 and i-10; plan
`docs/superpowers/plans/2026-10-21-7c-4-conformal-mappings.md`, spec `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §3.5 and Errata D20)
code is done; its human checks (IM-14 to IM-18) are pending and its benchmark rows have not been run. `mapping`, `axis` and `centre` are ordinary inputs
and the face is `NodeSetting.face`, all saved within format 8: a file from before 7c-4 reads Straight and its geometry is unchanged. A lattice is the
lattice read at the mapped coordinates, with the mapping's singular set (the axis, the polar axis, the cells of a face's chart that stretch the map by more
than 25) left solid within 1 mm and fading in over the next 0.5 mm (`LatticeMapping.join`), and its lipschitz bound is its own times the mapping's stretch
(`LatticeMapping.stretch`, fixed when the mapping is built, over the region and a 4 mm margin) plus the join's term. The turn of a periodic coordinate is
wound on a radius that makes a whole number of cells go round (`LatticeMapping.turnRadius`), and a Voronoi lattice copies the seeds near the cut across
it (`VoronoiSeeds.mapped`). `NodeDefinition.inspector(for:)` is what shows only the active mapping's inputs.

Cross-platform, sub-project xp-c (implicit evaluation and meshing on SDL GPU, Linux and Windows; plan `docs/superpowers/plans/2026-10-22-xp-c-sdl-gpu-meshing.md`, erratum E8, implicit D21): `ImplicitCompiler.Generator` has a `ShaderDialect` (the MSL is byte-identical, `MetalSourceDigests` pins it; edit a generator case once, for both). `ImplicitCompiler.compileHLSL` and `HLSLShaderLibrary`/`HLSLMeshShaderLibrary` are the HLSL side (edit the MSL library and its HLSL twin together; `HLSLSourceTests` checks the `sdf` statement for statement, the registers and the forbidden constructs). Every float computation of the HLSL is `precise` (the `sdf`, each library function, each float local: DXC makes the rest `fast` and reassociates; D21 (7), `HLSLSourceTests.everyFloatComputationIsPrecise`). Native Metal is exact too since 2026-10-23: both libraries are compiled with `MetalImplicitEngine.exactCompileOptions()` (`mathMode = .safe`, `mathFloatingPointFunctions = .precise`; never compile an engine library with `options: nil`). `HLSLImplicitEngine` runs over `ImplicitComputeBackend` (`SDLComputeBackend` with an `SDLKernelProvider`; `MSLComputeBackend` in the Mac's tests). The offline kernels come from `scripts/linux-test.sh kernels` into `.build/generated-kernels` and `GeneratedKernels.solids` (add a new test shape there). Engines report `availability`. Off macOS the app's engine is `HLSLImplicitEngine.sdl` (MetalUI XP-G25 adopted): `SDLRuntimeKernels` compiles each kernel on `SDLCompileWorker`'s thread through MetalUI's `SDLGPUShaderCompiler`; the tests find the library through `METALUI_SHADERCROSS_LIB` (`scripts/linux-test.sh` and CI set it; `RuntimeCompileUnderTest`), and the Mac, whose build has no SDL, compiles the same HLSL to MSL at run time through `MetalUIShaderRuntime` (a test-only dependency; `METALUI_SHADERCROSS_LIB` plus `libSDL3.0.dylib` beside it) and runs it on `MSLComputeBackend`, else keeps the offline kernels. The GPU suites run over `GPUEnginesUnderTest.names`. XP-G23 to XP-G26 are adopted (the device's name is the adapter's, "(software)" on lavapipe and WARP, which are always used; `limits` are floors); XP-G27 is adopted too (2026-10-29, MetalUI `abc2bf46`); human checks XP-27 to XP-29.

- `CreatorImplicit`: implicit solids and meshes (implicit spec §2 to §4; `Mapping/` is §3.5: `LatticeMapping` over `CylindricalMap`, `SphericalMap` and, in
  `Mapping/Face/`, `FaceMap` on a `FaceChart` that `FaceChartBaker` measures through the kernel and `FaceChartAssembler` builds from samples): the `ImplicitSolid` value, the CPU batch evaluator, the Metal
  compiler (gated with `#if canImport(Metal)`), the sparse octree (`BrickPlan`), `MeshingBudget` and the mesher. Portable (declared on every
  platform); depends on `CreatorGraph` for `Field`, which holds these only as `ImplicitPayload` and `MeshPayload`. Tests:
  `swift test --filter CreatorImplicitTests`.

- `CreatorImplicit` (depends on Graph, Kernel and Geometry; implicit spec §2 to §4): `ImplicitSolid` (an indirect enum of sphere, box,
  cylinder, rigid move, union / subtract / intersect with a graded blend, offset, shell, baked distance blocks, isosurface and the three
  lattices `tpms`, `struts` and `voronoi` (`Lattice/`: `TPMSLattice`, `StrutLattice`, `VoronoiLattice` with their `LatticeCells`,
  `TPMSType`, `StrutCell` and `VoronoiSeeds`; each is cut to its region's box and the lattice nodes intersect it with the region); every
  case has `bounds`, `lipschitz`, `exactReach` and a one-line `description`, in `Solid/`), `Grading` (a setting that may vary over space:
  a `Field` with the kernel distances in it baked, and its range and slope), `DistanceBlocks` (sparse 8³ blocks of `Float` distances,
  trilinear, with a conservative bound for unstored blocks) and `TriangleMesh` (positions, normals, triangles, `resolution`, `quality`,
  optional `MeshSource` for the progressive preview; `MeshTopology` checks closed, oriented and manifold). `CPUEvaluation` (`Double`) is
  a complete engine on every platform, and the reference the GPU is held to; `ImplicitCompiler` generates Metal source whose text depends
  on the tree's shape only (numbers go in the buffers) and imports nothing. **The module builds on Linux and Windows (Errata D11):** the
  GPU sits behind `ImplicitGPUEngine` (`GPU/`: prepare, compile, evaluate a batch, mesh bricks, cancel), whose only
  implementation is `MetalImplicitEngine` (an actor that compiles each shape once; the one file that imports Metal, compiled only under
  `#if canImport(Metal)`), `ImplicitGPUEngines.platformDefault` is the machine's engine or `nil`, and `ImplicitPortabilityTests` fails
  on an Apple-only import or a Metal type anywhere else in the module. The agreement suite `GPUAgreementTests` holds Metal to the CPU
  within 1e-4 mm (skipped without a Metal device). `ImplicitEvaluators.make` picks the engine and falls back to the CPU, warning
  "Running on the CPU" when a solid will not compile (the reason is `Selection.diagnostic`, not shown). `BrickPlan` is the sparse octree (prune by |f| / lipschitz; 8³-voxel
  bricks), `MarchingCubesTable` is generated by a fixed rule (never join inside corners across a face; no triangle flat in a face), and
  `ImplicitMesher` meshes brick batches into a watertight, manifold mesh (global edge keys, a Newton snap, the memory refusal
  `MeshingBudget`); `PreviewSchedule` is the passes of the progressive preview (Auto goes on while four times the last pass is under a
  second and four times its triangles are within `maximumTriangles`, 2,000,000: the cap of Errata D15). **Meshing on the GPU (Errata D13):** `ImplicitMesher`
  first offers the plan's bricks to the evaluator (`ImplicitBatchEvaluator.meshBricks`, which `GPUBatchEvaluator` passes to
  `ImplicitGPUEngine.meshBricks(_:_:progress:)`: a `BrickMeshRequest` in, a `BrickMesh` of flat arrays out, no GPU type in either). The
  default requirement returns `nil`, and the mesher then meshes on the CPU, which stays the reference and the fall-back: it also
  takes over when the engine fails, returns arrays that do not fit (`BrickMesh.isConsistent`), or a request is beyond the engine's
  limits (a window of more than 32-bit edge keys, a table over `largestTable`). **That fall-back is silent: test and measure
  `ImplicitMesher.meshReportingPath(...).path` (or `MetalImplicitEngine.meshesMade`), never just the mesh.**
  `MetalImplicitEngine+Meshing` runs the five kernels of `ImplicitMeshShaderLibrary` (Metal source as text, so an SDL3 engine
  translates it) over `BrickLattice`'s window with `MarchingCubesBuffers`, the CPU's table as a buffer; the order of vertices and
  triangles is the threads', the set is fixed. `GPUMeshAgreementTests` holds the GPU mesher to the CPU mesher's topology, triangle
  count, vertices (1e-4 mm on the same samples, for parts near the origin), normals and enclosed volume. `SignedDistanceMesh` (BVH; `signedDistance(at:)` takes its sign from the pseudonormal, for the bake, and `isInside(_:)`, `robustSignedDistance(at:)` and `windingNumber(at:)` from `WindingNumber`, the generalized winding number summed exactly near the point and as dipoles of BVH clusters far from it, which the checks use; `LazyWindingNumber` builds its clusters on the first such question, so the bake never does),
  `DistanceBaker`, `ImplicitBakeCache` (actor, 512 MB, LRU, keyed by solid identity and tolerance) and `GradingBaker` bake a solid or a
  field's kernel distances. `STLWriter` writes binary STL. CreatorGraph cannot name `ImplicitSolid` (it depends on Graph for `Field`), so
  a value on a wire is an `ImplicitPayload` in an `ImplicitReference` (`Scalar.implicit`, `Field.implicit`) and a mesh a `MeshPayload`
  (`Scalar.mesh`); `ImplicitReference.solid` reads the solid back. `Scalar.converted(to: .mesh)` leaves an implicit as it is: the node
  that takes a mesh socket meshes it (`MeshInput` in CreatorNodes). `EvalContext` carries `meshQuality` (`.preview` / `.export`;
  `NodeDefinition.readsMeshQuality` puts it in a node's cache key), `implicitEngine` and `meshProgress`. Tests:
  `swift test --filter CreatorImplicitTests`.
  The mesh tools (7c-3, `Mesh/`): `MeshDecimator` is quadric error edge collapse (`Quadric`, `EdgeHeap`, `MeshDecimationState`): a
  collapse is refused when it breaks the link condition, flips a face or costs more than the tolerance (the cost is the quadric error
  at the new vertex, so its square root bounds the distance to every triangle plane absorbed), vertices on an open or over-full edge are pinned, and
  a closed mesh stops at a tetrahedron. `ThinWallCheck` (a ray inwards from each vertex against `TriangleBVH`, the far side must
  face back; the two sides of a wall are one place; a hit under 0.05 mm on a face that touches the vertex's one-ring is the mesh folding on itself and is skipped, Errata D18), `TrappedVolumeCheck` over `OccupancyGrid` (0.5 mm cells within a 32-million-cell
  budget, Errata D16; solid within half a cell of the surface, the cells near the surface from `unsignedDistance`) and `EnclosedVoids` (flood fill from the padded corner; with `isInside` it asks the winding number about five cells of each pocket, judged once the pocket has 4,096 cells listed, and drops a pocket that is inside the material, once per pocket and never per cell: per cell it is 23 to 35 times slower, Errata D18), and `DrainHoles`
  (the same test on the implicit, whose inside is the sign of its own field; a hole is `subtract` of a moved `cylinder`, so no new `ImplicitSolid` case). `MeshWelder` merges
  vertices before `Kernel.meshToSolid` (the OCCT shim `occt_mesh_to_solid`: a planar face per triangle sharing vertices by index,
  `ShapeUpgrade_UnifySameDomain`, voids as inner shells, `BRepCheck_Analyzer`; no `BRepBuilderAPI_Sewing`). Export (spec Errata D12):
  `StreamingMesher` takes the plan's bricks in runs of whole columns (windows), meshes and snaps each on the CPU over the evaluator's
  values (GPU values when the engine is a GPU's), may decimate it (`MeshStage`), and hands it to a `MeshSink` as a `MeshWindow` whose
  vertices carry their number in the file; a vertex on the plane two windows share is matched by its bits and written once, and when the
  new window has triangles on that plane every vertex the previous window made exactly on it must be matched, or the export stops with
  `seamsDidNotJoin` (a separate body that stops short of the plane needs nothing). `STLFileWriter` and `ThreeMFWriter` are the sinks (the
  3MF writes each object's vertices and triangles to two temporaries and joins them in the zip); `ZipWriter` streams with data
  descriptors, dates fixed, Zip64 where a size, offset or count reaches 4 GB, and deflates through `RawDeflater` where
  `canImport(Compression)`, else stores. `MeshStream` is what a Mesh node returns while `EvalContext.meshQuality` is
  `.streamedExport`: the implicit, the resolution and the stages.
  Mesh import (`Import/`, mesh import spec): `STLReader` reads binary and ASCII STL (the file is read whole through the one descriptor that was opened and checked, never mapped, since a mapped file truncated mid-parse is a SIGBUS; ASCII is scanned by token, keywords in any case; limits are checked from the header and the size, and a count above the limit that the size cannot hold is `notAMeshFile`),
  `VRML/` and `X3D/` (KI-3) hold `VRMLReader` and `X3DReader`; `ExactWeld` welds by exact position and drops degenerate triangles, and `ImportedMesh` carries the mesh (the node makes the facts). `ImportMeshNode`
  (`CreatorNodes/Implicit/MeshTools`) holds the file as `ConstantValue.meshFile`, an `ImageReference` whose embedded bytes live in the document's
  `images` table (no table of its own), and warns about open, over-full and flipped edges. `EdgeCounts` (`Mesh/`) counts open, over-full and flipped
  edges by sorting edge keys, and is edge-only: a bow-tie vertex passes it, so Mesh to Solid and Check Trapped Volumes refuse such a mesh on their own.
  `TriangleMesh`'s watertight and manifold promise is the Mesh node's alone now; an imported mesh may be open, flipped or over-full; the tools that need a closed mesh refuse through `MeshInput.requireClosed`
  (`EdgeCounts`), and Section, Measure, Decimate and STL export deliberately don't.
  3MF (MI-2): `ThreeMFReader.read(_:isCancelled:)` returns `[ImportedMesh]`, one per build item (a PrusaSlicer object with two instances is two meshes; a unit, transforms and components applied; `ignoredExtras` and `partsLeftOut` carry the two warnings). The zip is `ZipReader` (also other tools' zips), entries inflate through our own `Inflate` (whole buffer, bounded at 2 GB; no Compression framework), the XML is read by `XMLScanner` (no Foundation parser; a single budget for the model, `ThreeMFLimits`; repeated `unit` and `requiredextensions` refused; attribute runs ask about cancellation) and `ThreeMFModelParser` resolves namespaces by URI. Unsupported required extensions and encrypted content are refused in words. Parts in other files of the package (the Production `path` on the root's components and build items: Bambu Studio and Orca projects; MI-2b, spec erratum 2026-11-03 (3MF parts)) are read: each named part once, in the root's first-seen order, one inflated at a time, against one budget (2 GB of model bytes, records, vertices and triangles shared, 4,096 parts: "This 3MF has too many parts."); only the root may carry a path, a part's unit must equal the root's, and `ThreeMFModel.append(part:)` merges a part so objects are keyed by part and id. Part names are found through `PartNames` (two dictionaries built once, cancellation asked in the loop), a part's build section is skipped, a damaged part is named, `paint_color`, `paint_seam` and `paint_supports` set `ignoredExtras`, and objects of type support, solidsupport or other (Bambu's negative parts and modifiers too) are left out with `partsLeftOutWarning`. `ImportMeshNode.parse` picks the reader by the bytes (`PK\x03\x04` is a 3MF whatever the name; `STLReader` still refuses a zip), `ImportedMeshCache` holds `[ImportedMesh]`, `units` From file reads each mesh's own unit and an explicit unit replaces it, and several meshes are a list output with their warnings said once per sentence. `ImportedMeshDigestTests` pins a SHA-256 of an STL binary, an STL ASCII and a 3MF fixture's mesh on all three platforms. `StreamedExport` writes one 3MF object per mesh of any list on an Output (named "<Output> 1", "<Output> 2"; one mesh keeps the Output's name). A failed inflate allocation is `notEnoughMemory` (never remembered); the parser asks about cancellation every 65,536 events and every 1 MiB of attribute bytes, counted once per element.
