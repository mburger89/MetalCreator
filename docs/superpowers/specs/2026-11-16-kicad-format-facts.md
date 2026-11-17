# KiCad .kicad_pcb facts, read from source (gitlab.com/kicad/code/kicad)

Branches read: master (this is KiCad 11 development; its board version is 20261031), 10.0 (board version 20260206), and the 5.1, 6.0, 7.0 branches for history.
Paths are for master unless a branch is named.

## 1. Board outline chaining tolerance
- **Answer: 0.01 mm in master and 7.0 or later.** It is `DEFAULT_CHAINING_EPSILON_MM`, defined as `#define DEFAULT_CHAINING_EPSILON_MM 0.01` in `pcbnew/board.h` line 95.
  `BOARD::BOARD` sets `m_outlinesChainingEpsilon = pcbIUScale.mmToIU( DEFAULT_CHAINING_EPSILON_MM )` (`pcbnew/board.cpp` line 119).
  `BOARD::GetBoardPolygonOutlines` (board.cpp ~3651) passes `GetOutlinesChainingEpsilon()` to `BuildBoardPolygonOutlines` -> `ConvertOutlineToPolygon` in `pcbnew/convert_shape_list_to_polygon.cpp`.
- The epsilon can be changed per board, because it is a board member and not a constant. I did not look up where the user edits it. The STEP exporter has a separate parameter, `m_BoardOutlinesChainingEpsilon` (exporter_step.cpp ~1319).
- The test is `close_enough` (convert_shape_list_to_polygon.cpp line 86-89): `( aLeft - aRight ).SquaredEuclideanNorm() <= SEG::Square( aLimit )`. It is a Euclidean distance with `<=`.
  Segments are chained by endpoints in both orientations. The neighbour search is a k-d tree, `findNeighbours` with radius `aChainingEpsilon`.
- 6.0 branch: hardcoded `int chainingEpsilon = Millimeter2iu( 0.02 );` (pcbnew/board.cpp:1840).
- 5.1 branch: no epsilon. `ConvertOutlineToPolygon( ..., aTolerance, ...)` is called with `ARC_HIGH_DEF = Millimeter2iu( 0.005 )` (include/convert_to_biu.h:108 / class_board.cpp:2977), so 0.005 mm.
- Master also has `aAllowDisjoint` and an error handler. Multiple outlines are reported as "(multiple board outlines not supported)" unless disjoint is allowed.

## 2. Embedded files (KiCad 9+; file version 20240706 and later)
Source: `common/embedded_files.cpp` (`WriteEmbeddedFiles` line 210, `ParseEmbedded` line 440), `include/embedded_files.h`.
- **Form** (a top-level token of `(kicad_pcb`; footprints may carry their own too):
  ```
  (embedded_fonts no)
  (embedded_files
    (file (name "foo.step") (type model)
      (data
        |<base64 line, 76 chars>
        <base64 line>
        <last base64 line>|
      )
      (checksum "<hex>")
    )
  )
  ```
  The writer prints `(embedded_files `, then per file `(file (name %s)(type %s)(data ... )(checksum %s))`.
  `type` is one of datasheet, font, model, worksheet, other.
  `data` is bar-delimited: `(data`, then each 76-character chunk on its own line. The format string is `"\n%1s%.*s%s\n", first ? "" : "|"` where `first` is the byte offset, so the FIRST chunk gets a leading `|` and the LAST chunk a trailing `|`. Middle chunks have none. The parser calls `NeedBAR()` and then concatenates all symbol tokens until the closing `|`. Parse it as: strip the bars, drop all whitespace, base64-decode.
  Version 9.0.0 had a writer bug: `(data)` can be empty. The parser tolerates that.
  The `|` is a token only from version 20240706 (`SetKnowsBar( m_requiredVersion >= 20240706 )`).
- **Encoding of data** (`CompressAndEncode`, line 271): the file bytes go through `ZSTD_compress(..., level 15)` and then wxBase64Encode (standard base64, with padding). It is one zstd frame. It is not chunked compression. The decoder uses `ZSTD_getFrameContentSize`, so the frame header carries the size.
- **Checksum**:
  - Current: MurmurHash3 x64 128 (`MMH3_HASH`, `libs/kimath/include/mmh3_hash.h`, "streaming equivalent of MurmurHash3_x64_128"), seed `0xABBA2345` (`EMBEDDED_FILES::Seed()`), over the DECOMPRESSED bytes, written as `HASH_128::ToString()`. I did not read the hex layout of `ToString`.
  - Introduced at board version 20240819 ("Embedded Files - Update hash algorithm to Murmur3").
  - Files from 20240706 to before 20240819 carry a 64-hex-char SHA-256 of the decompressed data (the decoder checks `data_hash.length() == 64`).
  - Files saved before the "tail-byte alignment fix" use a V1 murmur variant (`addDataV1`).
  - You can ignore the checksum for import. It is only a validation.
- **Model reference**: a footprint `(model "kicad-embed://name.step" ...)`. The prefix is `FILEEXT::KiCadUriPrefix = "kicad-embed"` (common/wildcards_and_files_ext.cpp:221), and `GetLink()` is `"%s://%s"` with the name (embedded_files.cpp:63-66).
  The step exporter detects `m_Filename.StartsWith( "kicad-embed://" )` (exporter_step.cpp ~603). The name matches an `(embedded_files (file (name ...)))` entry in the footprint or in the board. The 3D viewer looks in the footprint's files first and then the board's (create_scene.cpp ~2310).
- The board writer collects every footprint's embedded files into one board-level `(embedded_files` block (pcb_io_kicad_sexpr.cpp ~1050-1061). Footprints inside a board are written without data, via `WriteEmbeddedFiles( *m_out, !( m_ctl & CTL_FOR_BOARD ) )` (line 1795). So for a board, look the file up in the board-level table by name.
- Also `(embedded_fonts yes|no)` precedes it.

## 3. 3D model transform
A model has `(model "path" (offset (xyz x y z)) (scale (xyz sx sy sz)) (rotate (xyz rx ry rz)) [(opacity o)] [(hide yes)])`. See the parser, pcb_io_kicad_sexpr_parser.cpp `parseFP_3DMODEL`, line 955-1070.
- Offset is in mm (comment "3D model offset is in mm"). Rotate is in degrees. Scale is a unitless multiplier.
- Viewer: `CalcModelMatrix` (3d-viewer/3d_math.cpp:34) is
  `translate(offset) * Rz(-rz) * Ry(-ry) * Rx(-rx) * scale(sx,sy,sz)`.
  Rotation angles are NEGATED (`glm::radians( -aRotation.z )`). Acting on a model vertex: scale first, then Rx, then Ry, then Rz (all with negated angles), then the offset. The comment in the same file: "CalcModelMatrix() builds Rz( -rz ) * Ry( -ry ) * Rx( -rx )".
  Full chain: `world = FootprintMatrix * CalcModelMatrix * v` (create_scene.cpp ~2325).
- Footprint matrix (`BOARD_ADAPTER::GetFootprintMatrix`, board_adapter.cpp:1182):
  `translate(pos.x, -pos.y, zOfSide) * Rz(fpAngle) * [if flipped: Ry(pi) then Rz(pi)] * scale(mm->3D units)`.
  Ry(pi) then Rz(pi) is the same as a rotation by pi about X. The Y axis is negated for the position only (KiCad Y points down, 3D Y points up). The footprint angle is used as-is (not negated) as Rz.
  So the offset and the model rotation are applied in the footprint frame AFTER the flip. For a flipped footprint the offset is mirrored by the X-axis rotation. Z of the translation is the board's top or bottom surface.
- STEP exporter (`STEP_PCB_MODEL::getModelLocation`, step_pcb_model.cpp:3904): comment "Order of operations: a. aOrientation is applied -Z*-Y*-X; b. aOffset is applied (Top ? add thickness to the Z offset); c. Bottom ? Rotate on X axis (in contrast to most ECAD which mirror on Y), then rotate on +Z; Top ? rotate on -Z; d. aPosition is applied. Note: Y axis is inverted in KiCad".
  In code, pos = translate(x, -y, 0). Top: `lPos *= Rz(fpAngle)`, `offset.z += top`. Bottom: `offset.z -= bottom`, `lPos *= Rz(fpAngle)`, then `lPos *= Rx(pi)`. Then `lPos *= translate(offset)`, then `*= Rz(-oz)`, `*= Ry(-oy)`, `*= Rx(-ox)`.
  This is the same chain as the viewer. Rotate angles are applied as -x, -y, -z. The rotation is converted degrees to radians at exporter_step.cpp ~635 (`modelRot *= M_PI; /= 180`). The offset is passed in mm (`fp_model.m_Offset`), and the footprint position is passed in mm. The model's scale is applied to the geometry itself (`rescaleShapes` from `transferModel`, step_pcb_model.cpp:4104) before the placement transform.
  `top` and `bottom` are the board body's top and bottom Z plus the copper thickness.
- Back-side footprint: `Rz(fpAngle)` then a 180 degree rotation about X (not a mirror). The footprint angle (`GetOrientation()`) is used unchanged; no sign flip. In the file, a B.Cu footprint's coordinates are stored already flipped, so no further mirroring is needed.

## 4. VRML units
- Yes for legacy VRML. 1 VRML unit = 0.1 inch = 2.54 mm: vertices, translation, center and box sizes are multiplied by 2.54.
  - VRML2: `plugins/3d/vrml/v2/vrml2_coords.cpp:143-154` ("For legacy KiCad VRML files (1U = 0.1 inch), convert to mm." `sP->x *= 2.54f`), `v2/vrml2_transform.cpp:168-174, 246-252` (center, translation), `v2/vrml2_box.cpp:126` (`size *= 2.54`).
  - VRML1: `v1/vrml1_coords.cpp:134-143` and `v1/vrml1_transform.cpp:151` ("assuming legacy KiCad expectation of 1U = 0.1 inch").
- It is conditional in current master, in v2 files only: `WRL2BASE::m_applyUnitConversion` defaults to true (vrml2_base.cpp:52). It is switched OFF when a top-level Transform has a non-unity scale (vrml2_transform.cpp ~205-213: "PCBnew-exported VRML which includes a top-level scale factor, meaning coordinates are already properly scaled"). The VRML1 path is not conditional.
  If a file has a top-level `scale`, treat its units as already correct (mm after that scale). Otherwise multiply by 2.54.
  I did not trace whether the scale then also gets applied in mm terms. Verify against a real file.
- X3D: yes, the same legacy factor. `plugins/3d/vrml/x3d/x3d_coords.cpp:88-102` ("coordinates are multiplied by 2.54 to retain legacy behavior of 1 X3D unit = 0.1 inch; the SG* classes expect all units in mm") and `x3d/x3d_transform.cpp:101`. I did not check whether X3D has the top-level-scale exception. The grep found none in x3d_coords.cpp, so it seems unconditional.

## 5. KiCad 5 files
- Model `(at (xyz x y z))` is in INCHES. The parser multiplies by 25.4 (pcb_io_kicad_sexpr_parser.cpp:989-991, comment "Prior to KiCad v5, model offset was designated by 'at', and the units were in inches"). There is NO version check: any `(at (xyz))` is inches. `(offset (xyz))` is mm (line 1011-1025). Board version 20171114 changed it to mm; 20171130 renamed it to `offset`.
- Legacy arc `(gr_arc|fp_arc (start cx cy) (end x y) (angle a))` (parser ~3980-4010, `m_requiredVersion <= LEGACY_ARC_FORMATTING` = 20210925):
  - `start` is the arc CENTRE ("In legacy files the start keyword actually gives the arc center").
  - `end` is the arc START POINT ("the end keyword gives the start point of the arc").
  - `angle` is in degrees. The code calls `shape->SetArcAngleAndEnd( EDA_ANGLE( angle, DEGREES_T ), true )` (common/eda_shape.cpp:1574): `m_end = m_start; RotatePoint( m_end, m_arcCenter, -angle.Normalize720() ); if( angle < 0 ) swap( start, end )`.
  - `RotatePoint(pt, c, a)` uses `x' = x cos a + y sin a; y' = y cos a - x sin a` (libs/kimath/src/trigo.cpp:256-257) on raw file coordinates (y down), with a = -angle.
  - So with `dx,dy = start_point - centre` and theta = angle in radians: `end = centre + (dx cos(theta) - dy sin(theta), dx sin(theta) + dy cos(theta))`. That is the standard rotation by +theta in raw file coordinates. Visually on screen (y down), a positive angle sweeps clockwise from the start point.
  - A negative angle: the end point is computed the same way (rotating by theta, which is negative) and then start and end are swapped, so the final arc always runs start -> end in the file's positive sense (the swapped result). The arc's middle is then derived. Sweep magnitude is |angle|, normalised through Normalize720.
  - For fp_arc the coordinates are footprint-relative, as for other shapes.
  - Versions after 20210925 use `(start)(mid)(end)` instead (parser lines after 4012).
- Also: files without `(version)` are treated as 20201115 (parseHeader line 1940-1965).

## 6. File version numbers
Active `#define SEXPR_BOARD_FILE_VERSION` at the tip of each release branch (pcbnew/.../pcb_io_kicad_sexpr.h, earlier pcb_plugin.h or kicad_plugin.h):
| KiCad | branch tip version | note |
|---|---|---|
| 4 | `(version 4)` | 4.0 branch: reversed cu stack, Inner* to In* |
| 5 (5.0 and 5.1) | 20171130 | both branches identical |
| 6 | 20211014 | 6.0 branch tip; "Arc formatting" |
| 7 | 20221018 | "Via & pad zone-layer-connections" |
| 8 | 20240108 | "Convert teardrop parameters to explicit bools" |
| 9 | 20241229 | "Expand User layers to arbitrary count" |
| 10 | 20260206 | "Fix barcode and variant attribute serialization" |
| 11 (master, in development) | 20261031 | "Non-component pads" |
Section markers in master's header: "Start of 5.0 development" after version 4, 6.0 after 20171130, 7.0 after 20211014, 8.0 after 20221018, 9.0 after 20240108, 10.0 after 20241229, 11.0 after 20260206 (first 11 entry is 20260410, Extruded 3D body).
Released minor versions may write slightly different numbers than the branch tip at some point. I only know the tips.
- Oldest accepted: the current parser has NO minimum-version check. I grepped `m_requiredVersion` and found no rejection of old files. Missing `(version)` defaults to 20201115. The only rejection is for NEWER files (`m_tooRecent`, `FUTURE_FORMAT_ERROR` when `m_requiredVersion > SEXPR_BOARD_FILE_VERSION`).
  Version-gated compatibility code reaches back to 20171114 in comments and to `(at (xyz))` inch handling (always on). The lowest numeric gate in the parser is `< 20200826`. I did not test a `(version 4)` file against the current parser, so I cannot confirm KiCad 4 files load in 10 or 11.
- Other gates worth knowing: 20210606 (overbar syntax `~...~` to `~{...}`), 20210925 (last legacy arcs), 20220815 (last net-tie keywords), 20230620 (PCB fields), 20240706 (embedded files, `|` token), 20250210 (hatching, fill normalization), 20260616 (footprint affine transform, see 9).

## 7. 3D plugin extensions (current master, plugins/3d/*)
- **vrml** (`plugins/3d/vrml/plugin.cpp:59-66`): `wrl`, `wrz`, `x3d` (X3D is handled by the same plugin; there is no separate x3d plugin). Filters: "VRML 1.0/2.0 (*.wrl;*.wrz)" and "X3D (*.x3d)". On case-sensitive platforms upper-case variants are added.
- **oce** (`plugins/3d/oce/oce.cpp:73-76`): `stp`, `step`, `stpz`, `stp.gz`, `step.gz`, `igs`, `iges`. (`plugins/3d/model_import.cpp:393-398` also recognises `stepz`.)
- **idf** (`plugins/3d/idf/s3d_plugin_idf.cpp:226-227`): `idf`, `emn`.
- `model_import.cpp` (new in master) picks the format from the extension: stp, step, stpz, stepz, `.stp.gz`, `.step.gz` -> STEP; igs, iges -> IGES; wrl, wrz -> VRML; x3d -> X3D.
- `.wrz` is a gzip-compressed VRML (vrml.cpp ~161 "wrz load failed").

## 8. Reference designator storage
- KiCad 6/7: `(fp_text reference "R1" (at ...) (layer F.SilkS) (effects ...))` and `(fp_text value ...)`.
- KiCad 8+: `(property "Reference" "R1" (at ...) (layer ...) (effects ...))`, plus Value, Datasheet, Description and user fields.
- The switch is board version 20230620, "PCB Fields" (header list; KiCad 8 development, between 20230517 and 20230730).
  Parser evidence: pcb_io_kicad_sexpr_parser.cpp:6459 `if( m_requiredVersion < 20230620 )` handles "Prior to PCB fields, we used to use properties for special values", and line 6536 hides legacy fields that had no text effects.
  Writer: pcb_io_kicad_sexpr.cpp:1518-1526 writes every field as `(property "<name>" "<text>"` then `format( field )`.
- The current parser still reads `(fp_text reference|value ...)` from older files (case `T_fp_text`, which maps to Reference or Value fields, parser line 6817-6835).

## 9. Footprint graphics coordinates
Applies to files before 20260616 (that is, KiCad 6, 7, 8, 9, 10). The 10.0 branch is the reference.
- `fp_line`, `fp_arc`, `fp_circle`, `fp_rect`, `fp_poly`: coordinates are stored RELATIVE TO THE FOOTPRINT ORIGIN and UNROTATED (as drawn in the library). The parser then does `shape->Rotate( { 0, 0 }, parentFP->GetOrientation() ); shape->Move( parentFP->GetPosition() );` (10.0 pcb_io_kicad_sexpr_parser.cpp:3766-3769). So the reader must rotate by the footprint angle and then add the footprint position. The footprint's `(at x y a)` is read before its children.
  The footprint angle is in degrees and is applied with KiCad's `Rotate` (the same y-down sense as RotatePoint above; positive = counter-clockwise on screen). Positions are in the file's y-down mm.
- Same for `fp_text` (text angle is stored in the file ABSOLUTE for text: the parser sets `SetTextAngle( angle - fpOrientation )` and rotates the position, lines 4799-4806 in master, 4082-4085 in 10.0) and for text boxes (4444), which are rotated by the footprint orientation.
- Pads: `(at x y [angle])`. Position is footprint-relative and unrotated: `pad->SetFPRelativePosition( pt )` (10.0 parser:6015). I did not read the body of `SetFPRelativePosition`; by name and by the writer's use of `GetFPRelativePosition` it rotates by the footprint angle and adds its position.
  Angle: ABSOLUTE (includes the footprint rotation). The parser does `pad->SetOrientation( angle )` directly, with no offset. The writer writes `aPad->GetOrientation()` (the absolute value), not `GetFPRelativeOrientation` (writer line 1698-1700). For a footprint at 90 degrees with an unrotated pad, the file says `(at x y 90)`.
- `(at x y a)` of the footprint: the angle is in degrees. Back-side footprints (layer B.Cu) have their children's layers already swapped and their geometry already mirrored in the file (flip is stored baked in).
- **Master (KiCad 11 development, version >= 20260616 `FIRST_FP_AFFINE_TRANSFORM`)** changes this:
  - The footprint writes `(transform (translate x y) (rotate a) (scale sx sy))` instead of `(at x y a)` (writer line 1503; parser `T_transform` at line 6382).
  - Children are stored in LIBRARY frame. Text uses `SetLibTextPos`. Zone outlines and points before 20260616 were in board frame and are un-baked on load.
  - Therefore, for >= 20260616 the reader applies the footprint transform (scale, rotate, translate) to children. Older files rotate by the angle. I did not read how master treats fp_line coordinates beyond the transform comment ("First version that stores footprint children in library frame"), and I did not check the pad angle semantics in master. Check `PAD` handling before relying on it.
  - Footprint scale can be non-1 in this format, but the parser forces non-positive or non-finite scales to 1.
- Note for rotated back-side footprints: not verified. Test with a real B.Cu footprint.

## Things I could not confirm
- Exact `HASH_128::ToString()` format.
- Whether X3D has the top-level-scale exception.
- The body of `PAD::SetFPRelativePosition`.
- That KiCad 4 `(version 4)` files load in 10 or 11.
