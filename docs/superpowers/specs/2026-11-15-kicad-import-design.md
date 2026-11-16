# KiCad board import — design

Status: draft, 2026-11-15, written without a question round (the user's standing preference). The user's request: "We should be able to import
KiCAD" files. Everything else is marked **(call)** and is open to change. The user's own boards (a 5 × 12 keyboard, KiCad 10, file version
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

1. An **Import KiCad Board** node reads a `.kicad_pcb` file (KiCad 6 to 10) and outputs the board as a solid: the Edge.Cuts outline with its
   cutouts, extruded by the board's thickness, with every drilled hole cut through.
2. It outputs the outline as a profile, the mounting holes as placements with their diameters, and the components as bodies at their places
   (top and bottom side), from the 3D models the board names.
3. Every platform reads the same file to the same geometry (the parser is ours; OpenCascade builds the solids and reads STEP everywhere).
4. Linked files (the board and each model) are watched: a change on disk runs the node again at the next evaluation, and nothing else.
5. Picks on the board and its parts survive the board being edited in KiCad, so long as the picked feature still exists, by naming faces after
   KiCad's own identities (reference designators, pad numbers, outline items), not file order.
6. The file is untrusted input: limits are checked before allocation, the parser cancels, and every failure is a sentence.

## Non-goals

- Copper, traces, silkscreen, solder mask, zones and their colours. The board is one plain solid. **(call)**
- Writing back to KiCad, or any ECAD–MCAD exchange format (IDX, IDF, ODB++). Schematics (`.kicad_sch`) and Gerbers.
- Other ECAD tools (Altium, Eagle, EasyEDA) and KiCad 5 and older files (refused in words: "This board was saved by KiCad 5 or older. Open it
  in a newer KiCad and save it, then try again.").
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

- **Name and place:** Import KiCad Board, category Solid, in a new "Import" library sub-group of Solid. Import Mesh stays in Mesh (moving it
  would change its category and header colour). **(call)**
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
    diameters`, numbers in the same order. A mounting hole is a pad of a footprint whose library name starts with `MountingHole` (KiCad's
    library convention), or a footprint with exactly one pad which is non-plated, round and at least 2 mm; the rest are just holes.
    Order: by reference designator (natural order: H2 before H10). **(call)**
  - `components`: a list of solids, one per component with a STEP model (several models on one footprint are one solid, a compound). Order: by
    reference designator.
  - `component meshes`: a list of meshes, one per component whose model is VRML only. Order: by reference designator. **(call: two outputs.
    A STEP body keeps exact surfaces and named faces; a VRML model is a triangle soup, often open, which Mesh to Solid would turn into
    thousands of planar faces slowly or refuse. A mesh still works with the Section, Measure, zebra and export.)**
- **Facts** (inspector): the file's name, KiCad version, size (x × y mm), thickness, layer count, holes (drilled, of which mounting), components
  (placed, from STEP, from VRML, without a model).
- **File ▸ Import KiCad Board…** chooses a `.kicad_pcb`, inserts the node and an Output wired to `board`, one undo step "Import KiCad Board".

### Reading the board

- **Format:** KiCad's S-expression format. The parser is ours (`CreatorPCB`, portable, no Foundation parser), a tokenizer and a tree of
  lists, reading only what is needed and skipping the rest without building it. Version from `(version N)`: KiCad 6 is 20211014; older is
  refused; newer than the newest we know is read anyway, with one warning "This board is from a newer KiCad than MetalCreator knows. Check
  the result." **(call)**
- **Thickness:** `(general (thickness t))`, else the stackup's sum, else 1.6 mm with a warning.
- **Outline:** every item on `Edge.Cuts`, both board graphics (`gr_line`, `gr_arc`, `gr_circle`, `gr_rect`, `gr_poly`, `gr_curve`) and
  footprint graphics on that layer (`fp_*`, transformed by the footprint's place). Arcs are KiCad 6's start/mid/end form. A `gr_curve` is a
  cubic Bézier, carried exactly as a degree-5 spline segment (degree elevation). The pieces are chained into closed loops end to end within
  KiCad's own tolerance, 1 µm **(call: to be checked against KiCad's source in KI-1)**. The loop with the largest area is the outline; loops
  inside it are cutouts; a loop that does not close, crosses itself or crosses another is refused naming where ("The board outline isn't
  closed near (x, y) mm."), as KiCad's DRC does.
- **Holes:** each pad's drill (round, or an oval as a slot), at the pad's place plus its drill offset, and `np_thru_hole` and `thru_hole` alike.
  A plated hole's finished size is its drill size (KiCad's convention). The board is the outline extruded, then every hole cut in one
  `Kernel.place` of the distinct drill tools and one `Kernel.boolean`, as Hole Pattern does, so each hole's wall carries its own item (below).
  **(call)**
- **Footprints:** `(at x y angle)`, layer `F.Cu` or `B.Cu`. A back footprint's pads and graphics are already stored flipped in the file; its
  models are turned 180° about the board's y axis and placed under the board (a turn, not a mirror, so a part keeps its handedness), as
  KiCad's 3D viewer and STEP export do. Pads' `at` angles include the footprint's in KiCad 6 and later.
- **Flags:** both KiCad 6/7's bare `(hide)` and KiCad 8+'s `(hide yes)` forms are read, for every flag.

### Components

- **Models:** each `(model "path" (offset (xyz …)) (scale (xyz …)) (rotate (xyz …)) (hide) (opacity …))`; hidden ones are skipped. The
  transform is applied in KiCad's order (rotate about z, y, x, then offset, then the footprint's place and turn) **(call: pinned by a
  test against a board KiCad exported to STEP)**. A scale other than 1 is not supported (`Kernel.place` moves and turns, and scaling a STEP
  body turns it into B-splines): that component is left out with a warning naming it. **(call)**
- **Paths:** `${KIPRJMOD}` is the board's folder; `${KICADn_3DMODEL_DIR}` (n = 6 to 10) is that environment variable when set, else KiCad's
  library folder where KiCad installs it on this platform (macOS `/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels`, Linux
  `/usr/share/kicad/3dmodels`, Windows `C:\Program Files\KiCad\<n>.0\share\kicad\3dmodels`); `${VAR}` names in KiCad's own `kicad_common.json`
  path table too (KI-2) **(call)**; a relative path is against the board's folder. An absolute path into a known KiCad library folder of any
  platform (any of the three above, any version) is remapped to this platform's folder, because KiCad often writes models that way: on the
  user's board 227 of 348 model paths are absolute macOS paths, which would all be missing on Linux and Windows. **(call)** A `.wrl` whose
  same-named `.step` or `.stp` exists beside it is read as the STEP (KiCad's library ships both). Models embedded in a KiCad 9+ board
  (`embedded_files`, `kicad-embed://`, zstd-compressed) are not read yet: one warning names them. A zstd decoder of our own is later work.
  **(call)**
- **Reading:** STEP through OpenCascade's reader (the shim has `occt_read_step`), each distinct file once per evaluation and cached by its stamp,
  then placed with `Kernel.place`. VRML 2 (`.wrl`): our own reader for what KiCad's models use, `IndexedFaceSet` under `Transform` and `Shape`,
  colours ignored, anything else skipped with a warning; it makes a `TriangleMesh`.
- **Missing:** a model that can't be found or read gives no body, and one warning per kind: "12 components have no 3D model: C1, C2, R4 … (and
  5 more)."; "2 models weren't found: …"; "1 model couldn't be read: … (the STEP file contains no shapes)".

### Names that picks follow

Tags stay what they are (`TopoTag`: node, an `Int` item, a `TopoRole` of integers); KiCad's identities become stable integers.

- **Identity key:** a 62-bit FNV-1a hash of a fixed string, as a negative `Int` item outside `InstancePath`'s range: "fp:<reference>" for a
  footprint (its `uuid` where the reference is empty or repeats), "pad:<reference>:<pad number>" for a hole, "edge:<uuid>" for an outline
  item. The hash function is pinned by tests like `SeededRandom`. Two keys that collide in one board refuse in words (never silently share
  a name). **(call)**
- **Hole walls:** each hole's tool is placed with its pad's key as the item, so a pick on a mounting hole follows that pad when parts are
  added, moved or renumbered elsewhere.
- **Outline sides:** `side(loop:segment:)`, with loops ordered by the lowest item key in each and each loop's segments numbered from its
  lowest-keyed piece, so redrawing another part of the outline doesn't renumber this loop. **(call)**
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
  models; each checked as it is reached, before allocation. A STEP model at most 256 MB, a VRML one at most 64 MB and 10,000,000 triangles
  (Import Mesh's limit). Over a limit is a sentence naming it. The parser asks about cancellation every 65,536 tokens.

## Construction

- `CreatorPCB` (new module, portable, depends on `CreatorGeometry`): `SExpressionReader`, `KiCadBoardReader` (the board as values:
  `KiCadBoard`, `BoardOutline`, `DrilledHole`, `Footprint`, `ModelReference`), `OutlineChainer`, `ModelPathResolver`. No kernel calls.
- `CreatorImplicit/Import` gains `VRMLReader` (KI-3), beside `STLReader`.
- `CreatorKernel`: `Kernel.readSTEP(at:)` (the shim exists; give it limits, cancellation between files and a test on every platform).
- `CreatorNodes`: `ImportKiCadBoardNode`, with a `KiCadBoardCache` keyed by the board's stamp and each model's stamp, so moving one model on
  disk rereads only that model.
- `CreatorGraph`: `NodeOutputs.dependencies` and the evaluator's re-stamping of them.
- **File format 13:** `ConstantValue.pcbFile` and `TopoRole.imported(face:)` in saved picks, written only when used.

## Sub-projects

- **KI-1, the board:** the reader, outline, holes, thickness, the `board`, `outline` and mounting-hole outputs, origin and placement,
  facts, linking, File ▸ Import KiCad Board…, format 13, the identity keys for holes and outline sides. Tests on small boards made for the
  purpose.
- **KI-2, STEP components:** model paths and remapping, STEP models, transforms, both sides, `TopoRole.imported`, the evaluator's
  `dependencies`, the warnings; the placement test against KiCad's own STEP export of the same board.
- **KI-3, VRML components:** `VRMLReader` and the `component meshes` output.

## Tests

- Fixtures are small boards written for the tests (a rectangle with four M3 mounting holes; a rounded outline with arcs, a Bézier edge and a
  cutout; a footprint on each side with a STEP model offset and rotated, and one scaled (left out with its warning); an oval drill; an outline
  that doesn't close). The user's own
  boards are never checked in; reading them is a human check.
- Placement: a board fixture exported by `kicad-cli pcb export step` once (the exported STEP checked in beside it), and the imported
  components' bounds held to that file's within 1e-3 mm. **(call: generated once on a machine with KiCad; KiCad is not a CI dependency)**
- A digest of the board solid's tessellation and the outline's segments pinned on all three platforms, as Import Mesh's are.
- Damaged files: a truncated file, an unbalanced parenthesis, an enormous string, deep nesting, a footprint count over the limit; each a
  sentence, none a crash; a fuzz pass over the tokenizer.
- Picks: a face pick on a mounting hole's wall and on a component survives a fixture edited to add a part and move another.

## Human checks (group KI)

Import each of the user's keyboard boards: the outline, the switch-pin holes and the USB-C connector's place match KiCad's 3D viewer; the
facts match KiCad's board statistics; a change saved in KiCad shows at the next evaluation; standoffs from the mounting holes line up; models
from KiCad's library and from the project's folder both appear.

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
7. A model with a scale other than 1 is left out with a warning; models embedded in the board (KiCad 9+) are not read yet.
8. Absolute paths into KiCad's library folders are remapped to this platform's folder.
9. Picks follow KiCad's references through hashed integer keys; faces inside a model are named by their index in the model file.

Builder check (2026-11-15): an Opus reader raised nine points; all were settled as calls above (face naming, model files rerunning the node,
back-side turn and scale, absolute paths, embedded models, an embedded board's paths, the reason for two outputs, the library group, flag
forms). None needed the user.
