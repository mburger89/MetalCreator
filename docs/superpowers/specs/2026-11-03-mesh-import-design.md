# Mesh import — design

Status: approved by the user 2026-11-03; written that day without a question round, while the user was away. It follows "Later" in `2026-11-01-zebra-design.md` and
`2026-11-01-g2-surfacing-design.md` ("Mesh import (STL, 3MF), so imported meshes can be checked with zebra too"). The implicit spec's non-goal
"Importing STL or 3MF as inputs" is lifted by this document; its other non-goals stand. The only thing the user has stated is that request.
Everything else is marked **(call)** and is open to change.

## Intent

A part often starts somewhere else: a scan, a download, a print file, an export from another CAD system. Today MetalCreator can write STL and 3MF
but read neither. With import, a mesh file becomes a mesh on a wire, so everything that takes a mesh works on it: zebra stripes, the Section, Measure,
Decimate, the thin-wall and trapped-volume checks, Mesh to Solid and export. The file is untrusted input and is often imperfect, so it must fail in
words and say what is wrong with it, not crash and not quietly repair it.

## Goals

1. An **Import Mesh** node (category Mesh, library section Mesh) reads a binary STL, an ASCII STL or a 3MF and outputs a `mesh` list.
2. Every platform: macOS, Linux and Windows read the same files to the same mesh.
3. The inspector states what was read: triangles, vertices, size in millimetres, and whether it is closed.
4. A mesh with problems still imports: open edges, flipped faces and the like are counted and warned about, never silently fixed.
5. Zebra stripes on an imported mesh show its surface, with hard edges drawn hard. Mesh tools either work on an imperfect mesh or refuse it in words.
6. A linked file that changes on disk updates at the next evaluation, and only that node runs again.

## Non-goals

- Other formats: OBJ, PLY, STEP as a mesh. **(call: STL and 3MF are what was asked; OBJ and PLY are small later additions)**
- Repair: hole filling, reorienting, removing self-intersections. Later, as its own node. **(call)**
- Colour, materials, textures, beam lattices and slices in a 3MF: ignored, with one warning naming them.
- Encrypted 3MF content: refused in words. (The Production extension's parts in other files of the package were a non-goal until erratum 2026-11-03 (3MF parts), below.)
- To Implicit on a mesh, so a scan can take a lattice: `SignedDistanceMesh` could carry it, but it needs a closed mesh and its own design. Later.
- Fitting NURBS to a mesh; drag and drop onto the window; opening an `.stl` directly as a document.
- `Kernel.continuity` on a mesh: Measure already shows no Continuity row for one.

## Anti-goals

- A file that costs the machine's memory before it costs a message. Limits are checked from headers before anything is allocated.
- A silently changed mesh. Welding exact duplicates and dropping zero-area triangles is all that import does, and the second is counted.
- A mesh tool that gives a confident wrong answer on an open mesh. A trapped-volume count from a surface with holes is the risk here.
- Different meshes on different platforms, or a different mesh on the next read of the same bytes.

## Behaviour

### The node

- **Inputs:** `placement` (a plane, default the XY plane), and `units`, a segmented control: From file, mm, cm, m, in. "From file" reads as millimetres for an STL, which has no unit, and
  as the file's `unit` attribute for a 3MF. **(call)** Without `placement` an imported part could not be lined up with anything, because there is no mesh transform node.
- **Setting:** the file, `NodeSetting.meshFile`, a new `ConstantValue.meshFile(MeshFileReference)`, which is `.embedded(hash)` or `.linked(relativePath:absolutePath:)` exactly as `ImageReference` is.
- **Output:** `mesh`, one mesh per build item of a 3MF (each with its transform applied), one mesh for an STL. **(call: a list, not a merged mesh, because each stays a separate body to check and export)**
- **Inspector buttons**, as the Image Field's: Choose File… (links), Relink…, Embed. **Linked is the default**, the reverse of the Image Field's Choose, because mesh files are large and base64 grows them by a third in the `.mcgraph`. Embed is refused above 64 MB. **(call)**
- **Facts** (`PayloadFact`, per mesh): Triangles, Vertices, Size (x × y × z mm), Closed yes or no, and the file's name.
- **File ▸ Import Mesh…** picks a file and inserts the node, wired to a new Output node, as one undo step "Import Mesh". **(call)**

### Reading

- **STL:** the format is detected by size, not by the leading word: 84 + 50 × count equal to the file's size is binary, whatever the header says, because many binary STLs start with "solid". Anything else that parses as ASCII is ASCII. The facet normal is ignored and the winding is trusted. **(call)**
- **3MF:** a zip, located through `_rels/.rels`, read as the core specification: objects, components (with transforms), build items (with transforms). A transform with a negative determinant reverses the triangles' winding, so a mirrored part stays right side out. The `unit` attribute is applied.
- **Welding:** STL has no shared vertices, so vertices are merged by exact position (the bits of the `Float`s, as `MeshSlicer.prepare` does; -0 and +0 are one). No tolerance: closing a gap would be a repair. **(call)** Without this every STL edge would be open and every check would fail.
- **Coordinates:** `Float`, as `TriangleMesh` stores them. Units and `placement` are applied in `Double` and then narrowed.
- **Degenerate triangles** (repeated or coincident vertices after welding) are dropped and counted in a warning.

### Warnings and refusals

Warnings: "This mesh isn't closed: N open edges." · "This mesh has N edges shared by more than two faces." · "N faces are flipped against their neighbours." · "N degenerate triangles were dropped." · "This mesh's color and material data was ignored." · "This mesh has N triangles, so the view may be slow." above 2,000,000. Singular forms as elsewhere.

Refusals, each a node message: "This file isn't an STL or 3MF." · "The STL ends early." · "The STL has a bad number on line N." · "This 3MF has no 3D model part." · "This 3MF has too many parts." · "This 3MF is encrypted." · "This file holds no triangles." · "This file has N triangles; Import Mesh takes at most 10,000,000." · "This file is larger than the 1 GB limit." · the missing-file sentences, as `ImageProblem`'s.

### Limits

Untrusted input, as `ImageLimits` is. `MeshImportLimits`: a file of at most 1 GB; at most 10,000,000 triangles **(call: to be confirmed by the benchmark)**; an embedded file of at most 64 MB. The limits are checked as follows.

- STL: binary from the count in its header; ASCII as it reads, stopping at the limit.
- Zip: an entry's declared size before inflating, at most 2 GB, inflating stops at the declared size, and the CRC is checked.
- 3MF components: the total triangles after instancing are counted **before anything is instantiated**, since a small file can nest components into billions of triangles. A component cycle is refused and nesting stops at depth 32.
- 3MF XML: a `DOCTYPE` is refused outright, so no entity expansion and no external entities.
- Indices out of range and non-finite numbers are refused. A linked path gets `ImageResolver`'s checks: a regular file, no device or pipe.

## Construction

- **Where:** `Sources/CreatorImplicit/Import/`, portable, beside `TriangleMesh`, with the node in `Sources/CreatorNodes/Implicit/MeshTools/ImportMeshNode.swift`. No OpenCascade: STL through OCCT would be macOS-style dependency for no gain, and the kernel can't read 3MF.
- **Inflate is the main platform gap.** `ZipReader` inflates only under `canImport(Compression)` and is documented as for small files, and `ZipWriter` stores off Apple platforms, so nothing has needed to inflate on Linux or Windows. Other tools' 3MFs are deflated, so this needs **our own inflate** (RFC 1951) on every platform **(call)**: one path everywhere, with Apple's `Compression` as the test oracle on the Mac. It streams, so a file is not held whole; `ZipReader` gains or is joined by a reader that seeks with a `FileHandle` and handles Zip64.
- **XML: our own small scanner, not `XMLParser`.** **(call)** `FoundationXML` is a libxml2 dependency off Apple platforms, which the test target tolerates and the shipped packages would have to carry; a vertex-per-element XMLParser delegate is also slow on millions of elements. The 3MF model needs elements and attributes only. The tests use `ThreeMFReading` over `XMLParser` as its oracle where it is available.
- **Shared with images:** the path logic of `ImageResolver` (relative first, then absolute, the regular-file check, the stamp) is lifted to something both use rather than copied, as is `fileData(savingTo:)` and `didSave(to:)`'s rewriting of paths. A stamp goes into the node's cache key through `gather`, as `ImageStamp` does.
- **Cache:** `ImportedMeshCache` holds parsed, welded meshes by stamp, unplaced, and the failures, as `GreyImageCache` does: LRU, 1 GB. Changing `placement` or `units` re-applies a transform without reading the file. A parse runs off the main actor and checks for cancellation every 64 KB of input or 64,000 triangles.
- **The file format is 12.** A new `ConstantValue` kind, plus an optional top-level `meshFiles` table (base64 by SHA-256, sorted, written only when used; a damaged entry is dropped on reading), as `images` is. The session's pool drops unused entries on save, so undo works. The clipboard carries the embedded files its nodes use.

### The display: hard edges

A mesh reaches the viewport as a `Solid(displaying:)` over `TriangleMesh.displayMesh`, whose normals are averaged when a mesh has none. Averaged across a box's edges, an imported CAD part would look melted and its stripes would mean nothing. So `TriangleMesh` gains `creaseAngle: Double?`, set by Import Mesh to 30 degrees **(call)**: `displayMesh` splits a vertex's normal across edges sharper than that. Topology is untouched, because only the de-indexed corners the renderer draws get different normals. Meshes from the Mesh node, which have field-gradient normals, and Decimate's, keep today's behaviour unless a test shows otherwise.

Zebra then needs no new code: an opaque display solid is already striped. The zebra design's own caution stands: stripes on a mesh show its facets, so a coarse STL breaks them however smooth the original was. The legend or panel doesn't need to say so; human check MI-5 records what it looks like. CLAUDE.md lists "a mesh item's zebra (mesh import)" as later while the zebra design says meshes are striped: the first task confirms which is true and corrects the record.

### Downstream: a mesh that isn't closed

`TriangleMesh`'s doc promises a Mesh node's output is watertight and manifold, and consumers were written against that. An imported mesh breaks the promise, so `TriangleMesh` gains no flag; each consumer gets a test with an open mesh, a flipped face and an over-full edge, and these rulings **(calls)**:

| Consumer | With an imperfect mesh |
|---|---|
| Decimate | Works: open edges are already pinned. Over-full edges: a test decides, refuse in words if it can't hold. |
| Check Thin Walls | Refuses when not closed: "Check Thin Walls needs a closed mesh." A ray from a hole has no far side, so it would miss walls. |
| Check Trapped Volumes | Refuses likewise: a void can't be defined through a hole. |
| Mesh to Solid | Refuses when not closed or not manifold, in words, before the kernel is asked. The 100,000 limit stands. |
| Section (`MeshSlicer`) | Works: open outlines are already drawn and an open mesh's cap is already the fallback. |
| Measure (mesh points) | Works. |
| Export STL | Works: an STL writes any triangles. |
| Export 3MF | Warns in the export sheet when not closed, since the format asks for manifold meshes; it still writes. |
| `MeshRefinementModel` | Nothing to refine: `source` is `nil`, as Decimate's output is. |

`quality` is `.export` (the file is what it is at any quality) and `resolution` is 0 (unknown). `readsMeshQuality` stays false, so preview and export share one cache entry. `StreamedExport` already takes a plain `TriangleMesh` beside a `MeshStream`.

## Sub-projects

Each merges on its own.

1. **MI-1, STL:** the reader, welding and limits, the node, the links and the embedded table, format 12, File ▸ Import Mesh…, the facts and warnings, `creaseAngle`, and the consumer rulings above. On its own this is already the useful 80 %.
2. **MI-2, 3MF:** inflate, the streaming zip reader, the scanner, components and transforms, build items as a list.
3. **MI-3, measure and record:** benchmarks, CLAUDE.md, the zebra and implicit specs' "Later" and non-goal lines, and the limit decided.

## Tests

- **Round trips:** a mesh made here, written by `STLWriter` and `ThreeMFWriter`, reads back with the same vertices (exactly) and triangle set, closed.
- **Fixtures by hand, as bytes in the test** so the suite owns no binaries: a binary STL starting with "solid"; ASCII with CRLF, odd spacing, exponents; a truncated binary; a 3MF deflated by another tool (a small one carried as bytes), with components, a mirrored transform, each `unit`, an empty build.
- **Hostile:** a count far above the size, a huge declared zip entry, a zip bomb, nested components totalling billions, a component cycle, a `DOCTYPE`, NaN, an index out of range, a path to a folder and a device. Each refuses in its words, under a memory bound.
- **Inflate:** against `Compression` on the Mac over stored, fixed and dynamic blocks and against a pinned digest everywhere; malformed streams refuse and never trap.
- **Cross-platform:** a digest of the mesh of each fixture, pinned, on all three.
- **Graph:** format 12 round trip, formats 1 to 11 open unchanged; a linked file edited on disk re-runs the node once, and nothing else; moving a document keeps its relative path; embed, undo and save drop the unused bytes; the clipboard carries embedded files.
- **Display:** a welded box's `displayMesh` has six flat normals at 30 degrees; a sphere's stay smooth.
- **Consumers:** the table above, one test per row and imperfection.
- **Benchmarks** (`mesh-import-1` to `-3`, release): 1,000,000 triangles binary STL, ASCII STL and 3MF, read to first display. Targets, to be judged on an idle Mac: binary under 1 s, 3MF under 3 s.
- **Human checks, group MI:** MI-1 import a downloaded STL and a slicer's 3MF. MI-2 the facts are right and a wrong unit is obvious from the size. MI-3 a CAD part's edges look hard, and a sphere is smooth. MI-4 a file with holes warns, and the tools refuse in their words. MI-5 zebra on a fine and on a coarse STL. MI-6 Section and Measure. MI-7 edit the linked file, delete it, relink it, embed it, then save and reopen. MI-8 Linux and Windows read the same files alike.

## Left to the builder

The hash used for welding, the reader's buffering, the zip reader's shape (extend or add), how the path logic is shared, the node's exact inspector order, and the crease split's place between `TriangleMesh.displayMesh` and the kernel's `DisplayMesh`.

## Calls to check when you read this

1. Link by default, embed up to 64 MB (the Image Field embeds by default).
2. STL and 3MF only; repair and To Implicit on a mesh are later.
3. Imperfect meshes import with warnings, and the tools that need a closed mesh refuse.
4. Our own inflate and XML scanner rather than new dependencies, so no new library ships.
5. 10,000,000 triangles and 1 GB as limits, pending the benchmark.
6. A 3MF's build items stay separate meshes in a list.
7. A `placement` plane and a `units` control on the node, since nothing else can move a mesh.

## Errata

### 2026-11-03 (MI-1)

1. **One embedded table.** `ConstantValue.meshFile` holds an `ImageReference`, and embedded mesh bytes sit in the document's existing `images` table and pool, which are keyed by hash and don't care what the bytes are. There is no `MeshFileReference` and no `meshFiles` table. The table's per-entry cap is `ImageTable.maxEntryBytes`, the larger of the picture limit and `MeshImportLimits.maxEmbeddedBytes` (64 MB), so a mesh file embeds up to 64 MB and a picture keeps its own 16 MB.
2. **Files are read, not mapped.** A linked file is read whole into `Data` through the descriptor `openedRegularFile` already opened and checked (`ImageResolver.meshFileBytes`), up to the 1 GB limit, with no second open by path. This replaces the first plan, `Data(contentsOf:options:.alwaysMapped)`: a mapped file that another program truncates while it is parsed ends the process with SIGBUS (reproduced on Linux), and the file is untrusted. Reading also removes the swap race between a check and a second open, and any Windows locking window. A file that shrinks after its size was taken gives the shorter bytes, which the reader judges (`endsEarly` and the like). The cost is that a large file is held in memory while it is parsed (the cache keeps the parsed mesh, not the bytes).
3. **`EdgeCounts`.** Closed-ness comes from a sort-based count of edges (open, over-full, flipped), not `MeshTopology`'s dictionaries, which are slow at these sizes.
4. **The flipped warning** reads "N edges join faces flipped against each other." (singular "1 edge joins faces flipped against each other."), because it counts edges, not faces.
5. **Decimate on an over-full edge** pins the edge's ends like an open edge's, so it keeps the surface rather than refusing.
6. **The 3MF warning** for an imperfect mesh arrives in the "Exported with N warning(s)" alert after the file is written, naming the Output node, since the export sheet has no place for one.
7. **The closed-mesh guard sees every mesh value.** `MeshInput.checkable` and `collected` call `requireClosed` on every `.mesh` value, a Mesh node's preview too (the mesher's output is closed by construction, so it passes); only a `MeshStream` skips it.
8. **`EdgeCounts` is edge-only.** A bow-tie vertex (two fans of faces sharing only a vertex) passes the guards. Mesh to Solid and Check Trapped Volumes refuse such a mesh on their own, and Check Thin Walls may be less reliable on one.
9. **Zebra needed nothing new.** A mesh item was always striped like any opaque solid; CLAUDE.md's "later" line is corrected.
10. **ASCII STL is read by word, and a stray count is not an STL** (final review). Keywords are case-insensitive and may share a line; line numbers count LF, or CR when the file has no LF; a file with no `solid` line is ASCII when a `facet` or `vertex` word opens its first kilobyte; cancellation is asked every 64 KB. A binary header's count above the limit is `tooManyTriangles` only when the file's size is exactly that count's; a count the size cannot hold (a 3MF or other binary renamed .stl, whose `PK` start is refused first) is `notAMeshFile`, and `endsEarly` stays for a count within the limit that the size does not reach.

### 2026-11-03 (MI-2)

1. **Inflate takes the whole buffer.** It does not stream: the file is read whole (erratum 2 of MI-1) and the model entry is bounded at 2 GB, so `Inflate` inflates the entry in one call into a buffer sized by the zip's declared size, refused as `modelTooLarge` when the declared size, or what it could inflate to, passes the bound.
2. **One budget for the model.** The 3MF's model is held to one budget (`ThreeMFLimits`: triangles, vertices and records, with fixed bounds on namespace declarations and listed extensions) rather than a limit per part; the triangle limit is checked while reading and again when the build is placed.
3. **Supports are left out with a warning (the sentence and what `other` covers are revised by erratum 8 of 2026-11-03 (3MF parts)).** Objects of type `support`, `solidsupport` and `other` are not part of the model and are left out; the meshes made say "This 3MF's support structures were left out." (`ImportedMesh.supportsLeftOut`). Colours, materials, textures, slices and beam lattices are ignored with "This mesh's color and material data was ignored."
4. **A required extension we don't support is refused,** against the spec's "ignored": a `requiredextensions` entry that is not the core, Production or Materials extension (or is not declared) is `unsupportedExtension`, since the 3MF core specification says a consumer that cannot honour one must not open the file. A repeated `requiredextensions` or `unit` attribute on the model is refused as malformed.
5. **A mesh and components on one object are refused,** as the core specification forbids them together.
6. **The Production sentence.** A part kept in another file of the package (the Production extension's `path`, as Bambu Studio's project files do) is refused with "This 3MF keeps parts in other files, which isn't supported. Export it as a generic 3MF."
7. **Detection is by bytes.** `PK\x03\x04` at the start means 3MF wherever the file came from, whatever its name, in `ImportMeshNode.parse`; `STLReader` still refuses a zip for its direct callers. The parse cache holds `[ImportedMesh]`. `units` "From file" reads each mesh's own unit (an STL's reads as 1); an explicit unit replaces the file's, so `in` on a 3MF in millimetres reads its numbers as inches.
8. **A list of meshes exports as one object each.** Any list of meshes wired to one Output (an Import Mesh node's, or another node's) are written as one 3MF object per mesh, named "<Output> 1", "<Output> 2" and so on (solids, if any, in the first); one mesh stays the Output's one object. Warnings for the meshes are said once per sentence.

### 2026-11-03 (3MF parts, MI-2b)

The user decided to lift the non-goal on the Production extension's parts within one package, so Bambu Studio and Orca project files open. Erratum 6 above (the Production sentence) is withdrawn; "This 3MF keeps parts in other files..." is gone from the refusal list and `MeshImportProblem.otherFiles` with it. Encrypted content stays refused. The rules:

1. A `path` attribute in the Production namespace (found through the xmlns declarations, whatever the prefix) on a `<component>` or `<item>` of the root model names a part of the same zip, looked up as the start part is (exact, percent-decoded, case-folded). A path equal to the root part is the root. On any other element, or without the namespace, it names nothing.
2. Only the root model may carry a path. One in another part is refused as damaged, naming the part ("in the part <name cut to 80>, ..."; so is any other damage in a part), so parts cannot chain and no cycle crosses parts (the Production specification: consumers MUST error on it). A part's build section is skipped unread, so an `<item/>` in it never refuses (the specification: consumers MUST ignore the build section entries of child models). `p:UUID` is ignored.
3. Parts are found from the root's references, then read in the order the root first names them, each inflated and parsed once however many components name it, its buffer released before the next; a part nothing names is never read. Every name is looked up before any part is inflated, so a missing part is refused at once, "it names the part <name cut to 80 characters>, which the file doesn't have."
4. One budget across the file: inflated model bytes at most 2 GB in total (`modelTooLarge`); records, vertices and stored triangles shared; at most 4,096 distinct part names ("This 3MF has too many parts.", checked while the root is read, before anything is inflated); the instanced triangle count is checked across parts before anything is instantiated. A part's size is checked against what is left of the byte budget before it is inflated.
5. A part's `requiredextensions` and DOCTYPE rules are the root's. Its unit must equal the root's (the specification is silent on units across parts): a different one is "a part of the file uses a different unit from the model." An encrypted part is `encrypted`. An object id missing from the named part is refused like a missing id in the root. Objects are keyed by part and id, so the same id in two parts is two objects. Support types, transforms and mirrors apply as in one part.
6. Nothing is ever written to disk by name; the order of reading, and so the output, is the same on every platform. Nothing here has seen a real Bambu or Orca file (check MI-9 proves it).
7. Part names are found through two dictionaries built once from the zip's entries (exact and case-folded; first entry in zip order wins a shared key; an entry whose name is not UTF-8 reads as "" in `ZipReader` and is never found, so a part under such a name is "missing"), and the lookups ask about cancellation every 256 names. An empty `path`, or one that is only "/", is refused in words.
8. **Left-out parts are more than supports (revises erratum 3).** Bambu Studio and Orca write negative parts, modifiers and support enforcers and blockers as `type="other"` (objects of type `support`, `solidsupport` and `other` are still left out). A mesh reader cannot cut, so a negative part would come in uncut if kept; it is left out instead, with: "This 3MF's support, modifier and negative parts were left out, so the shape may differ." (`ThreeMFReader.partsLeftOutWarning`, `ImportedMesh.partsLeftOut`.) Generated tree or normal supports are not objects, so a plain project says nothing.
9. **Painting is dropped like a colour.** `paint_color`, `paint_seam` and `paint_supports` on a triangle set `ignoredExtras`, so the colour warning appears (the flag is the file's, so it is on every mesh of it).
