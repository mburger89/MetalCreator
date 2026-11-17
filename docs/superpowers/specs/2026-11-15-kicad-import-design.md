# KiCad board import — design

Status: revised 2026-11-16 for full support. The user's requests: "We should be able to import KiCAD" files, then "Let's make sure that we
fully support kicad import and then start building the feature". Full support means every board KiCad can save as `.kicad_pcb` (KiCad 4 to
11) and every 3D model KiCad's own 3D viewer opens, including scaled models and models stored inside the board. KiCad's own behaviour is
taken from its source code; the facts, with file and line, are in `2026-11-16-kicad-format-facts.md` beside this spec. Everything else is marked **(call)** and is open to change. The user's own boards (a 5 × 12 keyboard, KiCad 10, file version
20260206) are the shape of file this is written against: a 1.6 mm board with a rectangle on Edge.Cuts, about 200 drilled holes (185 non-plated
switch pins, round, oval and rectangular plated holes), and component models that are STEP files from KiCad's library and the project's own
`${KIPRJMOD}/3dmodels` folder, plus some VRML (`.wrl`) files there with no STEP twin.

## Intent

MetalCreator is where a part is modelled; KiCad is where a circuit board is drawn. The part most often built around a board is its enclosure,
case or mount, and today the board's outline, holes and parts have to be measured off and retyped. Import makes the board a solid on a wire,
in the right place, with its mounting holes as placements and its components as bodies, so an enclosure can be built against it: walls
offset from the outline, standoffs on the mounting holes, a cut for the USB-C connector, clearance checked with the Section and Measure. When
the board changes in KiCad, the next evaluation brings the change through, and picks on the board (a mounting hole, a connector's face) stay on
the same feature.

## Goals

1. An **Import KiCad Board** node reads any `.kicad_pcb` file (KiCad 4 to 11) and outputs the board as a solid: the Edge.Cuts outline with its
   cutouts, extruded by the board's thickness, with every drilled hole cut through.
2. It outputs the outline as a profile, the mounting holes as placements with their diameters, and the components as bodies at their places
   (top and bottom side), from the 3D models the board names, in every format KiCad's 3D viewer reads (STEP, compressed STEP, IGES, VRML
   1 and 2, compressed VRML, X3D, IDF), scaled as KiCad scales them, whether the model is a file or stored inside the board.
3. Every platform reads the same file to the same geometry (the parser is ours; OpenCascade builds the solids and reads STEP everywhere).
4. Linked files (the board and each model) are watched: a change on disk runs the node again at the next evaluation, and nothing else.
5. Picks on the board and its parts survive the board being edited in KiCad, so long as the picked feature still exists, by naming faces after
   KiCad's own identities (reference designators, pad numbers, outline items), not file order.
6. The file is untrusted input: limits are checked before allocation, the parser cancels, and every failure is a sentence.

## Non-goals

- Copper, traces, silkscreen, solder mask, zones and their colours. The board is one plain solid. **(call)**
- Writing back to KiCad, or any ECAD–MCAD exchange format (IDX, IDF, ODB++). Schematics (`.kicad_sch`) and Gerbers.
- Other ECAD tools (Altium, Eagle, EasyEDA), and KiCad's pre-2016 legacy `.brd` format (refused in words: "This is an old KiCad board
  (.brd). Open it in KiCad and save it as a .kicad_pcb, then try again.").
- IDF board files (`.emn`) named as a model: a whole board, not a part; skipped with a warning naming the component.
- Vias: they are copper-plated holes too small to matter for an enclosure, and a board has thousands. Off by default, a toggle to include them.
  **(call)**
- A guessed body for a component without a 3D model (a box from its courtyard). A made-up height gives a confident wrong clearance; a missing
  model is warned about by reference instead. **(call)**
- Opening a `.kicad_pcb` as a document, drag and drop, a KiCad plugin.

## Anti-goals

- A board in the wrong place or mirrored. KiCad's y axis points down; a back-side part is flipped; a model has its own offset, rotation and
  scale. One wrong sign and an enclosure is cut for a mirror-image board, so placement is pinned by tests against KiCad's own STEP export.
- A slow app because a board has 600 parts. Models are read once per file (one Gateron switch model, 59 placements) and placed as copies.
- Picks that jump to another hole or another part when the board is re-routed or a part is added.
- Different results on different platforms, or a model found on one machine and silently missing on another without a warning.

## Behaviour

### The node

- **Name and place:** Import KiCad Board, category Solid, with no library sub-group (Solid has none, and giving it one would mean naming a
  sub-group for every Solid node). Import Mesh stays in Mesh (moving it would change its category and header colour). **(call)**
- **Setting:** the board file, `NodeSetting.pcbFile`, a new `ConstantValue.pcbFile(ImageReference)`, **linked only**: Choose File… and
  Relink…, no Embed. A board is edited in KiCad and should follow, and its models are found from its folder, which an embedded copy doesn't
  have. **(call)**
- **Inputs:** `placement` (a plane, default XY): the board's origin, KiCad's page origin unless `origin` says otherwise; `origin`, a segmented
  control: Page, Drill/Place origin (the board's `aux_axis_origin`), Board centre (the outline's bounds' centre). Default Board centre, so a
  board lands near the origin and not 150 mm off at the page's corner. **(call)** `vias` (a toggle, off), `components` (a toggle, on).
- **Outputs:**
  - `board`: a solid. The bottom face at z = 0, the top at z = thickness, in the placement's frame. KiCad's y is negated so the board reads as
    it does in KiCad's 3D viewer from the top.
  - `outline`: a profile, the outer Edge.Cuts loop and its cutouts as holes, on the board's top plane.
  - `mounting holes`: placements, one per mounting hole, at the hole's centre on the board's top face facing +z; and `mounting hole
    diameters`, numbers in the same order. A mounting hole is the largest hole of a footprint whose library name starts with `MountingHole` (KiCad's
    library convention; its `_Pad_Via` parts ring that hole with small via pads), or a footprint with exactly one pad which is non-plated, round and at least 2 mm; the rest are just holes.
    Order: by reference designator (natural order: H2 before H10). **(call)**
  - `components`: a list of solids, one per component with a STEP, IGES or IDF model (several models on one footprint are one solid, a compound). Order: by
    reference designator.
  - `component meshes`: a list of meshes, one per component whose model is VRML or X3D only. Order: by reference designator. **(call: two outputs.
    A STEP body keeps exact surfaces and named faces; a VRML model is a triangle soup, often open, which Mesh to Solid would turn into
    thousands of planar faces slowly or refuse. A mesh still works with the Section, Measure, zebra and export.)**
- **Facts** (inspector): the file's name, KiCad version, size (x × y mm), thickness, layer count, holes (drilled, of which mounting), components
  (placed, from STEP, from VRML, without a model).
- **File ▸ Import KiCad Board…** chooses a `.kicad_pcb`, inserts the node and an Output wired to `board`, one undo step "Import KiCad Board".

### Reading the board

- **Format:** KiCad's S-expression format. The parser is ours (`CreatorPCB`, portable, no Foundation parser), a tokenizer and a tree of
  lists, reading only what is needed and skipping the rest without building it. Version from `(version N)` (4 for KiCad 4, 20171130 for 5,
  20211014 for 6, 20221018 for 7, 20240108 for 8, 20241229 for 9, 20260206 for 10, 20261031 for 11's development); a file without one is
  read as 20201115, as KiCad does. Every version is read; one newer than the newest we know is read anyway, with one warning "This board is
  from a newer KiCad than MetalCreator knows. Check the result." **(call)**
- **Old forms** (read by version, as KiCad's own parser does): `module` for `footprint`; up to 20210925 arcs are `(start centre) (end
  first point) (angle degrees)`, the end point the start turned about the centre in the file's y-down coordinates (a positive angle runs
  clockwise on screen; a negative one swaps the ends); a model's `(at (xyz …))` is in inches (× 25.4), `(offset (xyz …))` in mm; the reference
  designator is `(fp_text reference "R1")` before 20230620 and `(property "Reference" "R1")` from it (both are read whatever the version).
  From 20260616 a footprint is placed by `(transform (translate x y) (rotate a) (scale sx sy))` and its children are in its library frame:
  scale, turn, then move them; a scale that isn't positive and finite is 1, as KiCad reads it.
- **Thickness:** `(general (thickness t))`, else the stackup's sum, else 1.6 mm with a warning.
- **Outline:** every item on `Edge.Cuts`, both board graphics (`gr_line`, `gr_arc`, `gr_circle`, `gr_rect`, `gr_poly`, `gr_curve`) and
  footprint graphics on that layer (`fp_*`, transformed by the footprint's place). Arcs are KiCad 6's start/mid/end form. A `gr_curve` is a
  cubic Bézier, carried exactly as a degree-5 spline segment (degree elevation). The pieces are chained into closed loops end to end within
  KiCad's own tolerance for the file's version: 0.005 mm up to KiCad 5, 0.02 mm for KiCad 6 files (before 20221018), 0.01 mm after
  (`DEFAULT_CHAINING_EPSILON_MM`), compared as a distance. The loop with the largest area is the outline; loops
  inside it are cutouts; a loop that does not close, crosses itself or crosses another is refused naming where ("The board outline isn't
  closed near (x, y) mm."), as KiCad's DRC does.
- **Holes:** each pad's drill (round, or an oval as a slot), at the pad's place plus its drill offset, and `np_thru_hole` and `thru_hole` alike.
  A plated hole's finished size is its drill size (KiCad's convention). The board is the outline extruded, then every hole cut in one
  `Kernel.place` of the distinct drill tools and one `Kernel.boolean`, as Hole Pattern does, so each hole's wall carries its own item (below).
  **(call)**
- **Footprints:** `(at x y angle)`, layer `F.Cu` or `B.Cu`. Graphics are stored relative to the footprint and unturned: turn them by the
  footprint's angle, then move them. Pads' positions are relative too, but their angles already include the footprint's. A back footprint's
  pads and graphics are already stored flipped in the file.
- **Flags:** both KiCad 6/7's bare `(hide)` and KiCad 8+'s `(hide yes)` forms are read, for every flag.

### Components

- **Models:** each `(model "path" (offset (xyz …)) (scale (xyz …)) (rotate (xyz …)) (hide) (opacity …))`; hidden ones are skipped. KiCad's
  matrix (`CalcModelMatrix`, and the STEP exporter's identical chain) is, acting on a model's point: scale, then turn about x by −rx, about y
  by −ry, about z by −rz (degrees), then move by the offset (mm), then, for a back footprint, turn 180° about x (a turn, not a mirror, so a
  part keeps its handedness), then turn about z by the footprint's angle, then move to (x, −y) and up to the board's top (or down to its
  bottom for a back footprint). Pinned by tests that place an asymmetric model and check its corners against this chain worked by hand.
- **Scale:** supported. The scale is applied to the model as read, once per distinct (model, scale), before it is placed. A uniform scale is
  an exact similarity (surfaces keep their kind); an uneven one is OpenCascade's general transform, which turns the model's surfaces into
  B-splines with the same faces, so names hold. A mesh is scaled point by point.
- **Paths:** `kicad-embed://name` is a model stored in the board (below). `${KIPRJMOD}` is the board's folder; `${KICADn_3DMODEL_DIR}` (n = 6 to 10) is that environment variable when set, else KiCad's
  library folder where KiCad installs it on this platform (macOS `/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels`, Linux
  `/usr/share/kicad/3dmodels`, Windows `C:\Program Files\KiCad\<n>.0\share\kicad\3dmodels`); `${VAR}` names in KiCad's own `kicad_common.json`
  path table too (KI-2) **(call)**; a relative path is against the board's folder. An absolute path into a known KiCad library folder of any
  platform (any of the three above, any version) is remapped to this platform's folder, because KiCad often writes models that way: on the
  user's board 227 of 348 model paths are absolute macOS paths, which would all be missing on Linux and Windows. **(call)** A `.wrl` whose
  same-named `.step` or `.stp` exists beside it is read as the STEP (KiCad's library ships both).
- **Models stored in the board** (KiCad 9+, from version 20240706): `(embedded_files (file (name "x.step") (type model) (data |…|)
  (checksum "…")))` in the board and in each footprint; a footprint's own files are looked in first, then the board's. The data is base64
  (lines, the first starting and the last ending with `|`) of one zstd frame of the file. Decoded by our own `ZstdDecoder` (RFC 8878, portable,
  no library), bounded: the frame's content size, when stated, is checked against the model limit before allocating, and output stops at the
  limit when it isn't. The checksum (MurmurHash3, or SHA-256 in early 9.0 files) is not checked: a damaged frame fails to decode on its own.
  A stored model is cached by its hash, as an embedded picture is, and is part of the board's stamp.
- **Formats**, chosen by the name's extension as KiCad chooses them, then confirmed by the bytes (a gzip header, `ISO-10303-21`, IGES's
  column-73 section letters, `#VRML V1.0`, `#VRML V2.0`, `<X3D`, IDF's `.HEADER`), in any case:
  - STEP `.step`, `.stp`; compressed STEP `.stpz`, `.stepz`, `.stp.gz`, `.step.gz` (gzip, inflated by our `Inflate`, which moves to a
    portable place both modules can use): solids, read by OpenCascade from bytes.
  - IGES `.igs`, `.iges`: solids through OpenCascade's IGES reader (the `TKDEIGES` toolkit, linked on all three platforms).
  - VRML `.wrl`, compressed VRML `.wrz` (gzip): our `VRMLReader`, VRML 1 and VRML 2, the geometry KiCad's models and exporters use
    (`IndexedFaceSet`, `Coordinate`/`Coordinate3`, `Transform`, `Group`, `Separator`, `MatrixTransform`, `Box`, `DEF`/`USE`), colours
    ignored, anything else skipped with one warning; meshes.
  - X3D `.x3d`: our `X3DReader` over `XMLScanner` (`IndexedFaceSet`, `IndexedTriangleSet`, `Coordinate`, `Transform`, `Group`, `Shape`,
    `DEF`/`USE`); meshes.
  - Units as KiCad's: VRML 1, VRML 2 and X3D coordinates are in 0.1 inch (× 2.54), except a VRML 2 file whose top-level `Transform` has a
    scale other than 1, which KiCad reads as already in mm.
  - IDF `.idf` (a component outline: a closed outline and a height): a solid, the outline extruded, made by the kernel.
- **Reading:** each distinct model once per evaluation, cached by its stamp, then placed with `Kernel.place` (solids) or moved point by
  point (meshes).
- **Mixed:** a footprint with a solid model and a mesh model gives a solid in `components` and a mesh in `component meshes`.
- **Missing:** a model that can't be found or read gives no body, and one warning per kind: "12 components have no 3D model: C1, C2, R4 … (and
  5 more)."; "2 models weren't found: …"; "1 model couldn't be read: … (the STEP file contains no shapes)".

### Names that picks follow

Tags stay what they are (`TopoTag`: node, an `Int` item, a `TopoRole` of integers); KiCad's identities become stable integers.

- **Identity key:** the 64-bit FNV-1a hash of a fixed string kept to its low 60 bits, plus one, negated: a negative `Int` item whose
  magnitude is at most 2^60, which `InstancePath` never reads as a path (its packed paths carry a depth of 2 to 4 in bits 60 to 62): "fp:<reference>" for a
  footprint (its `uuid` where the reference is empty or repeats), "pad:<reference>:<pad number>" for a hole (a pad number that repeats in its footprint, as a connector's shell pads do, gains ":2",
  ":3" in file order; a via is "via:<uuid>"), "edge:<uuid>" for an outline
  item. The hash function is pinned by tests like `SeededRandom`. Two keys that collide in one board refuse in words (never silently share
  a name). **(call)**
- **Hole walls:** each hole's tool is placed with its pad's key as the item, so a pick on a mounting hole follows that pad when parts are
  added, moved or renumbered elsewhere.
- **Outline sides:** `side(loop:segment:)`, with loops ordered by the lowest item key in each and each loop's segments numbered from its
  lowest-keyed piece, so redrawing another part of the outline doesn't renumber this loop; each cutout is cut as a tool named by its lowest key (item), so its walls are `side(loop: 0, segment: k)` qualified by that key and no other cutout can rename them.
- **Component faces:** each component's body is placed with its footprint's key as the item; inside a body, faces are named by a new role
  `TopoRole.imported(face:)`, the face's index in OpenCascade's map of the model as read. That is stable while the model file is unchanged
  (as every face ID is OCCT map order), unlike `unnamed(face:)`. A pick on J1's face follows J1 and says "J1 no longer exists…" when J1 is
  deleted. The new role is part of saved picks, so it is covered by format 13.
- Mounting holes keep their order by reference; a hole added with a later reference doesn't renumber earlier ones.

### Files found while running

The board names its model files, which only the node finds. The evaluator learns them: `NodeOutputs` gains `dependencies`, the
`ImageStamp`s of files a run read, and the evaluator re-stamps them at each evaluation as it does the node's own file setting
(`Evaluator+Running`), so a model edited on disk reruns this node and nothing else. A path that was missing is stamped as missing, so the
file appearing reruns it too. **(call: general graph-engine support, not a node that reruns every time)**

### Limits

- The board file at most 256 MB, nesting depth 64, a string at most 1 MB, at most 100,000 footprints, 1,000,000 pads and 10,000 distinct
  models; each checked as it is reached, before allocation. A STEP or IGES model at most 256 MB (after decompression), a VRML or X3D one at
  most 64 MB and 10,000,000 triangles (Import Mesh's limit), an IDF one 16 MB; a compressed model or a stored one may not inflate past its
  format's limit, and a stored model's base64 is limited by the board's own 256 MB. Over a limit is a sentence naming it. The parser asks about cancellation every 65,536 tokens.

## Construction

- `CreatorPCB` (new module, portable, depends on `CreatorGeometry`): `SExpressionReader`, `KiCadBoardReader` (the board as values:
  `KiCadBoard`, `BoardOutline`, `DrilledHole`, `Footprint`, `ModelReference`, `EmbeddedFile`), `OutlineChainer`, `ModelPathResolver`,
  `ZstdDecoder`, `Base64`, `IDFReader`. No kernel calls.
- `Inflate` (and a gzip wrapper) moves out of `CreatorImplicit` to where `CreatorPCB` can use it too (`CreatorGeometry/Compression`, the
  lowest portable module), unchanged.
- `CreatorImplicit/Import` gains `VRMLReader` and `X3DReader` (KI-3), beside `STLReader`.
- `CreatorKernel`: `Kernel.readModel(_ bytes:, format: .step | .iges)` (the shim's `occt_read_step` becomes a reader from bytes; IGES joins
  it) and `Kernel.scaled(_:by:)` (uniform: a similarity; uneven: the general transform), both refused by `FakeKernel`.
- `CreatorNodes`: `ImportKiCadBoardNode`, with a `KiCadBoardCache` keyed by the board's stamp and each model's stamp, so moving one model on
  disk rereads only that model.
- `CreatorGraph`: `NodeOutputs.dependencies` and the evaluator's re-stamping of them.
- **File format 13:** `ConstantValue.pcbFile` and `TopoRole.imported(face:)` in saved picks, written only when used.

## Sub-projects

- **KI-1, the board:** the reader, outline, holes, thickness, the `board`, `outline` and mounting-hole outputs, origin and placement,
  facts, linking, File ▸ Import KiCad Board…, format 13, the identity keys for holes and outline sides. Tests on small boards made for the
  purpose.
  Every board version, from KiCad 4 to 11's transform form.
- **KI-2, solid components (done 2026-11-17; human checks KI-6 to KI-9 pending):** model paths and remapping, STEP, compressed STEP and IGES, `Inflate` moved, scale, transforms, both sides,
  `TopoRole.imported`, the evaluator's `dependencies`, the warnings.
- **KI-3, mesh and outline components:** `VRMLReader` (1 and 2, `.wrz`), `X3DReader`, the units rule, the `component meshes` output, IDF.
- **KI-4, models stored in the board:** `Base64`, `ZstdDecoder`, `embedded_files` in board and footprints, `kicad-embed://`.

## Tests

- Fixtures are small boards written for the tests (a rectangle with four M3 mounting holes; a rounded outline with arcs, a Bézier edge and a
  cutout; a footprint on each side with a STEP model offset, rotated and scaled; an oval drill; an outline that doesn't close; the same board
  in KiCad 4, 5, 6, 8 and 11 forms; a model in each format; a board with stored models). Models are small and written for the tests (a
  lettered, asymmetric block, so a wrong turn or mirror shows). The user's own
  boards are never checked in; reading them is a human check.
- Placement: the asymmetric model's corners, placed front and back at several angles, offsets, turns and scales, held within 1e-6 mm to
  KiCad's chain worked out by hand in the test. KiCad isn't installed on this Mac, so an export by KiCad itself is a human check (KI group).
- zstd: frames made by the `zstd` command line (raw, RLE and compressed blocks, Huffman and FSE tables, repeat offsets, a dictionary-less
  multi-block frame, a checksum) checked in with their plain bytes; damaged and truncated frames refused in words; a fuzz pass.
- A digest of the outline's segments (pure Swift) pinned on all three platforms, as Import Mesh's are; the board solid's face and edge counts
  and volume (within 1e-6) pinned where OpenCascade runs. A tessellation digest is not pinned: OpenCascade's meshing may differ by platform.
- Damaged files: a truncated file, an unbalanced parenthesis, an enormous string, deep nesting, a footprint count over the limit; each a
  sentence, none a crash; a fuzz pass over the tokenizer.
- Picks: a face pick on a mounting hole's wall and on a component survives a fixture edited to add a part and move another.

## Human checks (group KI)

Import each of the user's keyboard boards: the outline, the switch-pin holes and the USB-C connector's place match KiCad's 3D viewer; the
facts match KiCad's board statistics; a change saved in KiCad shows at the next evaluation; standoffs from the mounting holes line up; models
from KiCad's library and from the project's folder both appear. With KiCad installed, a board's models placed by the import match KiCad's own
STEP export (`kicad-cli pcb export step`) within 0.01 mm.

## Left to the builder

The parser's internals; the exact warning wording beyond what is quoted here; how the outline chaining breaks ties; whether VRML reading
shares code with the 3MF reader's XML-free tokenizer.

## Calls to check when you read this

1. Board centre as the default origin, not KiCad's page origin.
2. Vias off by default; no guessed body for a part without a model.
3. Two component outputs (solids from STEP, meshes from VRML) rather than one.
4. A new "Import" sub-group under Solid; Import Mesh stays where it is.
5. The board is linked only, never embedded.
6. Mounting holes found by KiCad's `MountingHole` footprint names, plus single non-plated pads of 2 mm and up.
7. Full support (2026-11-16): every board version from KiCad 4, scaled models, models stored in the board, and every model format KiCad's
   viewer reads; only the pre-2016 `.brd` format and IDF board files as models are refused.
8. Absolute paths into KiCad's library folders are remapped to this platform's folder.
9. Picks follow KiCad's references through hashed integer keys; faces inside a model are named by their index in the model file. A pick
   whose KiCad item is gone says "The picked feature no longer exists in the imported board." (KI-1; naming the reference is KI-2's).
10. Facts shown for a node that outputs a solid: `NodeOutputs.facts`, a general hook, shown in a "Board" section.

Builder check (2026-11-15): an Opus reader raised nine points; all were settled as calls above (face naming, model files rerunning the node,
back-side turn and scale, absolute paths, embedded models, an embedded board's paths, the reason for two outputs, the library group, flag
forms). None needed the user.
