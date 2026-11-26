# CreatorPCB (KiCad import)

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

KiCad import, KI-1 (the Import KiCad Board node: spec `docs/superpowers/specs/2026-11-15-kicad-import-design.md`, format facts
`2026-11-16-kicad-format-facts.md`, plan `docs/superpowers/plans/2026-11-16-ki-1-board.md`; `creator.importKiCadBoard` reads a `.kicad_pcb`
into a board solid with its pad holes (and, on request, vias) drilled, its outline as a profile, its mounting holes as placements and
diameters (the `component meshes` output is declared; KI-3 fills it); `placement`, `origin` (board centre, page, drill/place), `vias` and `components` are its
inputs; `CreatorPCB` is the portable reader; the node's `factsTitle` "Board" hook lists KiCad version, size, thickness, copper layers, holes
and components; File ▸ Import KiCad Board… inserts it wired to an Output as one step "Import KiCad Board"; the file is
`NodeSetting.pcbFile`, linked only, never embedded; file format 13) code is done; its human checks (group KI) are pending.
KiCad import, KI-2 (solid components: plan `docs/superpowers/plans/2026-11-17-ki-2-components.md`; the `components` output is one solid per footprint,
read from its STEP, compressed STEP (`.stpz`, `.step.gz`) or IGES models, scaled, then placed by KiCad's chain (`ModelPlacement`), the top side at the board's
thickness and the back side at 0 turned Rx(π); faces are `.imported(face:)`, several models of a footprint are compounded with the face number `(k << 32) + i`; items
are footprint keys `fp:<token>`; the warnings are "no model", "not found" and "couldn't be read"; the "Components" fact; the `components` toggle) code is done; its human
checks (group KI) are pending. `CreatorPCB/Models`: `ModelPathResolver` (relative to the board, the project, KiCad's library folders), `KiCadPathVariables`, `ModelFormat` and
`ModelPlacement`. `Inflate`, `CRC32` and `Gzip` now live in `CreatorGeometry/Compression` (3MF and compressed STEP share them). `Kernel.readModel` (OCCT: STEP read from a
zero-copy stream, IGES through a 0600 temp file, `xstep.cascade.unit` MM; TKDEIGES is linked on every platform, the Linux Dockerfile included), `Kernel.scaled` and
`Kernel.compound` (`FakeKernel` refuses all three, as the protocol defaults do). `FileDependency` / `NodeOutputs.dependencies`: a node names the files its result read beyond its settings; the
evaluator re-stamps them each evaluation and downstream keys include them, so a model edited on disk updates the board. `ComponentModelCache` reads each model once per file
stamp across nodes (a sentinel tag retargeted per node); `BoardComponents.environment` is a TaskLocal. A model stored in the board is KI-4's (below).
KiCad import, KI-3 (mesh and outline components: plan `docs/superpowers/plans/2026-11-17-ki-3-mesh-components.md`; a footprint's VRML (1 and 2, `.wrl`, `.wrz` through `Gzip`), X3D or IDF model is read and
placed by KI-2's chain) code is done; its human checks (group KI) are pending. `VRMLReader` (`CreatorImplicit/Import/VRML`: our own tokenizer, explicit stacks, never recursion; VRML 1's state
scoped by `Separator`, VRML 2's `Transform` (translation, rotation, scale, scaleOrientation, center), `DEF`/`USE`, `IndexedFaceSet` fan-triangulated, `Sphere` and the like left out as skipped geometry;
node visits at most 5,000,000 and a work budget of 4 x the triangle limit + 64,000,000, kept apart, so a runaway `USE` stops; `Inline` is not read and is warned about) and `X3DReader` (`CreatorImplicit/Import/X3D`, over `XMLScanner`, namespaces and `DEF`/`USE`, per-element attributes) return a `TriangleMesh` in the file's units;
`IDFReader` (`CreatorPCB/Models`) returns the first `.ELECTRICAL` or `.MECHANICAL` section's outline (the first closed loop, whatever its label: a label is IDF 3.0's winding flag, not outline against hole; the other loops are holes) with its holes and a height, which the kernel extrudes, so an IDF part is a solid on `components` (`MM` as is, `THOU` x 0.0254).
The units rule: VRML 1, VRML 2 and X3D are in 0.1 inch, so the mesh is multiplied by 2.54, except a VRML 2 file whose top-level `Transform` has a `scale` other than (1, 1, 1), which is taken as millimetres
(no factor; `isMillimetres`). `component meshes` is one mesh per footprint (a footprint's VRML and X3D meshes concatenated, not welded across models), `creaseAngle` 30; budgets, applied before any point is moved (`Placer.admitMeshes`): a footprint's mesh at most
10,000,000 triangles (else that footprint's meshes are left out with "U3's component meshes were left out: they have more than 10,000,000 triangles together."), the board's component meshes at most 20,000,000 in all (later footprints in natural order left out, one warning); a footprint left out by either budget still counts as having a model in the facts.
Reader sentences become reasons by `ModelFiles.readerReason` (the "This <FORMAT> file" subject replaced by "it", the final period dropped). The facts read "N placed, S as solids, M as meshes, W without a 3D model".
KiCad import, KI-4 (models stored in the board: plan `docs/superpowers/plans/2026-11-17-ki-4-stored-models.md`; a footprint model path `kicad-embed://name` is read from the board's own `embedded_files`, so a KiCad 9 board
imports complete with no project folder or library beside it) code is done; its human checks (group KI) are pending. The reader keeps only `(type model)` entries, each as its base64 text left undecoded (a `String`)
until a footprint names it (a board with stored datasheets costs nothing); the footprint's own table is searched first, then the board's, names compared exactly. `CreatorPCB/Embedded`: `Base64` (the `|…|` block's whitespace skipped),
`XXH64` (the zstd frame's content checksum; KiCad's own MurmurHash3 or SHA-256 checksum is not checked) and `ZstdDecoder` (`Zstd/`: RFC 8878 decoding, portable, no dependency; raw, RLE and compressed blocks, Huffman and FSE tables, repeat offsets; limits on window, content size and output, so a hostile frame
is a sentence, never a trap; the frame's content checksum is checked; dictionaries are refused). The format comes from the stored name's extension (`ModelFormat(fileName:)`), then the decoded bytes are checked against it and go the way a file's do (`.stpz` or `.gz` through `Gzip`). `ComponentModelCache` keys a stored model by the SHA-256 of its
base64 text plus the format (`ImageHash(ofUTF8:)`; the hash is memoised per parsed board so two footprints naming one model hash it once); the board's own stamp covers it, so there is no `FileDependency`. `KiCadBoardCache` is injectable (`KiCadBoardCache.current`, a TaskLocal) and holds at most 512 MB of boards (`ParsedBoard.byteCount`, mostly the stored text), least recently used first, always keeping the newest. Wording: an empty `(data)` (KiCad 9.0.0's writer bug) is "couldn't be read … (it is empty)",
a name in neither table "wasn't found: kicad-embed://<name>".

- `CreatorPCB`: the KiCad board reader (KI-1; `Sources/CreatorPCB`). Portable (declared everywhere); depends on `CreatorGeometry` only (Foundation
  `Data`, no CryptoKit, CoreGraphics or Foundation XML or regex parsers, no dictionary iteration where order reaches output). `SExpression/`
  parses the file, `Board/` reads the board (KiCad's y-down millimetres are negated to y up as every point is read), `Outline/` chains the
  edge cuts into closed loops, and `Identity/` makes the stable keys (`-(Int(fnv1a64(text) & 0x0FFF_FFFF_FFFF_FFFF) + 1)`) that name a pad's
  walls. **A board file is untrusted input**: 256 MB, nesting depth 64, strings 1 MB, 100,000 footprints and 1,000,000 pads, cancellation
  asked every 65,536 tokens, and every refusal a full sentence. `Models/` (KI-2) resolves a footprint's model paths, expands KiCad's variables and builds the placement chain; it reads no model (the kernel does). `Embedded/` (KI-4) holds `Base64`, `XXH64` and `ZstdDecoder` for the models a board stores. Tests: `swift test --filter CreatorPCBTests`.
