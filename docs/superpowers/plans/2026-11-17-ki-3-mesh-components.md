# KI-3: KiCad board import — mesh and outline components — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Components whose models are VRML 1, VRML 2, compressed VRML, X3D or IDF appear: VRML and X3D as meshes on the node's
`component meshes` output, IDF as solids on `components`, placed exactly as KI-2 places STEP models.

**Architecture:** `VRMLReader` and `X3DReader` join `STLReader` in `CreatorImplicit/Import` and return a `TriangleMesh` in the file's units;
`IDFReader` in `CreatorPCB/Models` returns an outline `Profile2D` and a height, which the kernel extrudes. The node (KI-2's
`BoardComponents`) routes each model by `ModelFormat`, caches meshes beside solids, scales and places mesh points through the same
`ModelPlacement` frame and the board frame.

**Tech Stack:** Swift 6.4, Swift Testing, `XMLScanner` (X3D), our own tokenizer (VRML), `Gzip` (`.wrz`).

**Spec:** `docs/superpowers/specs/2026-11-15-kicad-import-design.md` (§Components: Formats, Units, Mixed, Missing; §Limits; KI-3). Facts:
`docs/superpowers/specs/2026-11-16-kicad-format-facts.md` §4 (VRML units), §7.

## Global Constraints

- Worktree `/Users/maxburger/Developer/kicad-import/MetalCreator`, branch `kicad-ki-3` (stacked on `kicad-ki-2`; KI-2 merges first). Never touch MetalUI.
- Every file is untrusted: a VRML or X3D model at most 64 MB after decompression and 10,000,000 triangles (Import Mesh's limit); an IDF one
  16 MB; nesting depth 256; cancellation asked at least every 65,536 tokens or elements. Every refusal is a sentence; nothing traps.
- Portable: no Foundation XML or regex parser, no dictionary iteration where order reaches output; `CreatorPCB` stays kernel-free.
- Units (facts §4): VRML 1, VRML 2 and X3D are in 0.1 inch: the whole mesh is multiplied by 2.54 after reading, except a VRML 2 file
  whose top-level `Transform` has a `scale` other than (1, 1, 1), which is taken as millimetres (no factor). IDF: `MM` as is, `THOU` × 0.0254.
- Colours, normals, texture coordinates, materials, lights, viewpoints and every other node are ignored; an ignored geometry node
  (`Sphere`, `Cone`, `Cylinder`, `ElevationGrid`, `Extrusion`, `IndexedLineSet`, `PointSet`, `Text`) sets `skippedGeometry` (one warning per
  model file: "<file> has shapes that aren't read (spheres, cylinders and the like).").
- Fixtures are written in the tests as text. Swift Testing; `swiftlint lint --strict` zero violations. Format stays 13, 14 test targets,
  89 nodes. Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings

- R1. Faces of an `IndexedFaceSet` are fan-triangulated from their first vertex (KiCad's models are triangles and convex quads); a face
  with fewer than 3 indices is dropped; an index out of range refuses the file ("<file> has a face that names a point it doesn't have.").
  `ccw FALSE` reverses each triangle. `solid` is ignored.
- R2. One mesh per footprint: its VRML and X3D models' meshes are concatenated (vertices not welded across models). Not welded inside a
  model either beyond `ExactWeld` (which drops degenerate triangles).
- R3. The mesh moves point by point: scale, then the model frame (KI-2 Task 3), then the board frame. Normals are recomputed by whatever
  `TriangleMesh` does for an imported mesh (as Import Mesh does); `creaseAngle` 30 as Import Mesh sets it.
- R4. An IDF model is an extruded outline: the first `.ELECTRICAL` or `.MECHANICAL` section's loop 0 is the outline, other loops are holes;
  height from the section's header; bottom at z = 0 of the model. Its faces are tagged like a read model (`.imported(face: i)` from the
  kernel's face order after extrusion: the node re-tags the extruded solid's faces by index).
- R5. KI-2's "isn't read yet" reasons for VRML, X3D and IDF are removed; `kicad-embed://` keeps its reason until KI-4.
- R6. Facts: "Components" becomes "<placed> placed, <solids> as solids, <meshes> as meshes, <without> without a 3D model" (a footprint with both
  counts once in each).

## Review Focus

1. A KiCad library VRML (VRML 2, `Transform` with `rotation`, `scale` 1, nested `children`, `DEF`/`USE` of a `Shape`) lands where the same
   part's STEP lands (the library ships both): Task 4 compares a VRML and a STEP of one block placed on one footprint (bounds within 1e-4).
2. A hostile VRML: unbalanced braces, a 2^31 index, a `USE` of itself, a 60 MB `point` list, deep nesting: a sentence, no trap or hang. Task 1.
3. VRML 1's state: `Coordinate3` and transforms inside a `Separator` don't leak out of it. Task 1.
4. An X3D with a namespace prefix or a `<Scene>` inside `<X3D>` with `DEF`/`USE`. Task 2.
5. A footprint with a STEP and a VRML model gives one solid and one mesh, and the facts count both. Task 4.

---

### Task 1: `VRMLReader` (VRML 1 and 2)

**Files:** Create `Sources/CreatorImplicit/Import/VRML/VRMLTokenizer.swift`, `VRMLReader.swift` (+ extensions as needed);
`Tests/CreatorImplicitTests/VRMLReaderTests.swift`.

**Produces:**
```swift
public struct ImportedModelMesh: Sendable { public var mesh: TriangleMesh; public var skippedGeometry: Bool; public var isMillimetres: Bool }
public enum VRMLReader {
    /// `#VRML V1.0 ascii` or `#VRML V2.0 utf8` (first line). Points in file units; `isMillimetres` true only for the VRML 2 exception.
    public static func read(_ data: Data, isCancelled: () -> Bool) throws(MeshImportProblem) -> ImportedModelMesh
}
```
Tokenizer: `#` comments to end of line, whitespace and commas separate, `{ } [ ]` tokens, quoted strings with `\"`, numbers through
`ASCIINumber`. VRML 2 nodes: `Transform` (translation, rotation axis+angle radians, scale, scaleOrientation, center: M = T·C·R·SR·S·SR⁻¹·C⁻¹),
`Group`, `Collision`, `Switch` (`choice` / `children`: only `whichChoice` if ≥ 0), `Anchor`, `Billboard` (as a group), `Inline` (skipped,
warns as skipped geometry), `Shape` (geometry), `IndexedFaceSet` (coord, coordIndex, ccw), `Coordinate`, `Box` (size, centred), `DEF`/`USE`
(a `USE` before its `DEF`, or of a node being defined, refuses: "<file> uses a shape before it is defined."). VRML 1: `Separator`
(saves and restores state), `Group`, `TransformSeparator` (saves transform only), `Coordinate3`, `IndexedFaceSet`, `Transform`, `Translation`,
`Rotation`, `Scale`, `MatrixTransform` (row-major 4×4, row vector convention), `Cube` (width/height/depth), `ShapeHints` (`vertexOrdering
CLOCKWISE` reverses), `DEF`/`USE`. Unknown nodes are skipped by balanced brackets. Limits from Global Constraints; 10,000,000 triangles counted
as they are made.

- [ ] Tests (each a small text file in the test): VRML 2 triangle and quad (fan); `Transform` rotation 90° about z then translation;
  `scale` + `scaleOrientation` + `center` against the formula worked by hand; nested transforms; `DEF`/`USE` instancing a `Shape` twice under
  two transforms (6 triangles); `Box` 2×2×2 (12 triangles, bounds ±1); `ccw FALSE` reverses winding; `Switch whichChoice 1`; top-level
  `scale 0.3937 …` → `isMillimetres`; `Sphere` → `skippedGeometry`; VRML 1 `Separator` scope (a `Translation` inside doesn't move a later
  sibling), `MatrixTransform`, `Cube`, `ShapeHints CLOCKWISE`; refusals: no header, unbalanced `{`, index out of range, `USE` undefined,
  self-`USE`, depth 300, triangles over a test limit (inject a small limit through an internal overload), cancellation; a fuzz pass of 2,000
  random mutations of a valid file (seeded `SeededRandom`): never traps.
- [ ] `swift test --filter CreatorImplicitTests`, lint, commit "Mesh import: a VRML reader".

### Task 2: `X3DReader`

**Files:** Create `Sources/CreatorImplicit/Import/X3D/X3DReader.swift`; `Tests/CreatorImplicitTests/X3DReaderTests.swift`.

**Produces:** `public enum X3DReader { public static func read(_ data: Data, isCancelled: () -> Bool) throws(MeshImportProblem) -> ImportedModelMesh }`
over `XMLScanner`: `X3D`/`Scene`, `Transform` (as VRML 2), `Group`, `Switch`, `Shape`, `IndexedFaceSet` (`coordIndex`, `ccw`, child
`Coordinate point`), `IndexedTriangleSet` (`index`), `Coordinate`, `Box`, `DEF`/`USE` attributes. Element names compared after any `prefix:`.
`isMillimetres` is always false (facts §4).

- [ ] Tests: triangle set; face set quad; transform; `DEF`/`USE`; namespaced elements (`x3d:Shape`); `Box`; `Sphere` skipped; refusals
  (bad index, `USE` undefined, a `DOCTYPE` (the scanner's refusal), depth); fuzz pass as Task 1.
- [ ] Run, lint, commit "Mesh import: an X3D reader".

### Task 3: `IDFReader` (component outlines)

**Files:** Create `Sources/CreatorPCB/Models/IDFReader.swift`; `Tests/CreatorPCBTests/IDFReaderTests.swift`.

**Produces:**
```swift
public struct IDFOutline: Sendable, Equatable { public var profile: Profile2D /* on Plane.xy, mm */; public var height: Double }
public enum IDFReader { public static func read(_ data: Data, isCancelled: () -> Bool) throws(KiCadProblem) -> IDFOutline }
```
IDF 3.0 library file: `.HEADER … .END_HEADER`, then the first `.ELECTRICAL`/`.MECHANICAL` section: a line `"geometry" "part" MM|THOU
height`, then points `loop x y angle`: angle 0 a line from the previous point, 360 a full circle (the previous point is the centre, this point
on it), else an arc of that many degrees (positive counter-clockwise) from the previous point to this one; a loop ends when a point equals
its first. Quoted or bare names. An `.emn`/board file (`.BOARD_OUTLINE` first) refuses: "This IDF file is a whole board, not a part." (the
node turns that into its warning naming the component, spec §Non-goals).

- [ ] Tests: a rectangle MM height 5; THOU units; an arc corner (90°, centre worked by hand); a full circle; a hole loop; the board file
  refusal; a loop that doesn't close; junk; cancellation.
- [ ] Run, lint, commit "KiCad import: an IDF component reader".

### Task 4: The node: meshes and outlines

**Files:** Modify `Sources/CreatorNodes/Import/BoardComponents*.swift`, `ComponentModelCache.swift` (a mesh table beside the solids, same
LRU budget by bytes, same stamp keys and stale-read rule), `BoardFacts.swift`, `ImportKiCadBoardNode.swift` (`component meshes`);
`Tests/CreatorNodesTests/ImportKiCadMeshComponentsTests.swift`.

**Behaviour:** `.vrml` read with `VRMLReader`; `.vrmlGzip` gunzipped (64 MB) first; `.x3d` with `X3DReader`; units per Global Constraints;
scale (the model's `scale`, R3; R3 of KI-2 for a non-positive scale), frame, board frame; one mesh per footprint (R2) in natural reference
order on `component meshes` as a mesh value (as Import Mesh outputs one; find how it makes its `Scalar`); `.idf` read with `IDFReader`,
extruded by the kernel (`Kernel.extrude`, re-tagged `.imported(face: i)` by face index, R4), then handled exactly as a read STEP solid
(scaled, placed, compounded). A `.wrl` with a STEP twin still reads the STEP (KI-2). Warnings: skipped geometry (Global Constraints),
"couldn't be read" with the reader's sentence as the reason; the IDF board refusal as "couldn't be read … (it is a whole board, not a part)".
Facts R6. Dependencies as KI-2.

- [ ] Tests: a VRML 2 block and a STEP block of the same shape on one footprint each, same placement (back, rotated): bounds equal within
  1e-4 after units; `.wrz`; X3D; IDF rectangle → a solid with the right bounds and `.imported` tags; a footprint with STEP + VRML → one solid,
  one mesh, facts count both; the persistent-evaluator rerun test of KI-2 for a VRML file (edited → reruns); a model with a `Sphere` warns once;
  `components` off reads nothing.
- [ ] Run `swift test --filter CreatorNodesTests`, lint, commit "KiCad import: VRML, X3D and IDF components".

### Task 5: Docs and the suite

CLAUDE.md (KI paragraph: KI-3 done; `VRMLReader`, `X3DReader`, `IDFReader`; the units rule), human checks group KI (a project VRML with no
STEP twin appears; a VRML exported from KiCad with a top-level scale lands at the right size), the full suite on macOS (14 lines) and Linux,
`swiftlint lint --strict`. Commit "Docs: KI-3".
