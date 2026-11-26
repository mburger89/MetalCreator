# DR-5: Assemblies, revisions and the rest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assembly views (several Outputs in one view, each its own body for hidden lines, so parts hide each other), balloons held
on a part's edges by lasting anchors, a parts list kept in step with them, a revision table whose letters bump on demand and feed the
title block, drawing templates kept as an app preference (sheet size, standard, title-block defaults, company name, a logo), SVG
export, a PDF of one sheet beside the PDF of all sheets, and MCP read and export tools; saved as file format 21. This is the last
drawings sub-project.

**Architecture:** `CreatorDrawing` gains `DrawingView.assembly` (the Outputs a view shows), `PartSpan` (which faces and curves of the
compound belong to which Output), `AnchorTarget.onPart` (an anchor names its part, so two copies of one part each hold their own edge),
three annotation kinds (`balloon`, `partsList`, `revisionTable`), computed item numbers (`PartItems`), table layouts, `SheetImage` for
the title block's logo, an `SVGWriter` beside `PDFWriter` and `DXFWriter`, and the template model and file. `CreatorDrawingEditor`
gains four tools, the template store and folder, copy and paste, and the inspector pages. The app projects an assembly through DR-1's
multi-solid compound, decodes logos (untrusted input) off the main actor, owns the template store, and serves `CreatorMCP`'s three new
drawing tools. No kernel or shim change.

**Tech Stack:** Swift 6.4, Swift Testing, MetalUI (existing canvas, inspector controls, `Image` of an `ImageBitmap`). No OpenCascade change.

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md`. Read it whole; build §DR-5 and what §Model, §Drawing mode (MCP),
§Export, §Constraints and "Decisions after the builder check" say (decision 2 in full: an annotation never guesses its anchor;
decision 4: isometric views take balloons). DR-1 to DR-4's plans (`docs/superpowers/plans/2026-11-24-dr-1-sheets-views-pdf.md`,
`2026-11-25-dr-2-dimensions-notes.md`, `2026-11-26-dr-3-sections-details.md`, `2026-11-26-dr-4-gdt-symbols.md`) hold the rulings this
plan builds on; CLAUDE.md's "Drawings, DR-1" to "Drawings, DR-4" paragraphs say what exists.

## Global Constraints

- **Worktree and branch.** `/Users/maxburger/Developer/MetalCreator-dr5`, branch `dr-5`. Never touch `../MetalUI`. A MetalUI shortcoming is
  logged in `docs/metalui-gaps.md` (a `DR-5-x` entry) and reported, never worked around. Never run `git stash` in any form.
- **No kernel change.** No new `Kernel` call, no C++. An assembly is DR-1's multi-solid path (`ProjectionCache.projection(of:curves:compoundTag:…)`
  compounds two or more solids once); anchors read only `Topology`, `EdgeInfo.curve`, `FaceInfo` and the frame (`DrawingAnchorResolver`,
  never `Topology.resolution`, never `EdgeKey.operandKeys`).
- **Module rules.** `CreatorDrawing` depends on `CreatorGeometry` and `CreatorKernel` only; `CreatorDrawingEditor` on `CreatorDrawing`, `CreatorKernel`,
  `CreatorGeometry`, `CreatorStyle` and MetalUI only; **`CreatorMCP` gains `CreatorDrawing`** (portable; still never the editor or the app).
  `CreatorGeometry` gains `Files/RegularFile.swift` (R23; Foundation and the platform's `open`/`fstat`, as `ImageResolver` uses them today).
  `CreatorMCPTests` gains `CreatorDrawing` in its dependencies (Task 13).
  No CoreGraphics, CoreText, ImageIO or Metal in any of them. Nothing iterates a dictionary where order reaches output (pictures, item
  numbers, warnings, JSON, PDF, DXF and SVG bytes, saved order). Files importing MetalUI and CreatorGeometry write `CreatorGeometry.Angle`.
- **Untrusted input.** A logo (a file the person picks, or a template's bytes) and a template file are untrusted: read bounded through
  `RegularFile.read(_:limit:)` (R23: a regular file, opened without blocking and checked on the descriptor, at most limit + 1 bytes read), checked
  before a pixel is decoded (`GreyImageDecoder.inspect`, `ImageLimits`, `LogoLimits`), decoded off the main actor, every refusal a full sentence (R11, R10).
- **Bytes.** PDF, DXF and SVG bytes are identical on every platform: numbers by `PDFNumber.format`, no clock, locale or hash seed. The DR-1 to
  DR-4 digests do not change (R13: image objects follow the pages; a page without images is written as before).
- **Dates come from the person.** A revision row's date is typed, never filled from the clock (R9). The title block's creation date stays as DR-1 made it.
- **File format 21** (`GraphFile.currentFormatVersion`): files of format 1 to 20 open unchanged and are written as 21 (R17).
- **Undo names** are fixed strings in `DrawingStepName` (R16): no numbers, no typed text (an item's material, a revision's description, a
  template's name are typed text). Template edits are app preferences, not undo steps.
- **Messages** are full sentences in the app's voice, exactly as written here.
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; never block a pool thread in a test (`HookGate`, a
  suspending kernel hook); `swiftlint lint --strict` reports 0; macOS and Linux each print **16** "Test run with" lines (no new test target) and
  never "recorded an issue" or "failed after".
- **Commit trailer** (every commit):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec; each says why and what it costs if wrong)

- **R1. Assembly views.** `DrawingView.assembly: [NodeID]?`: nil for DR-1's single-Output view (it shows `source`), else the Outputs the view
  shows, in order, at least one, with `source == assembly[0]` (decoding repairs: an empty list reads nil, duplicates are dropped keeping the first,
  `source` is set to the first). `DrawingView.outputs: [NodeID]` is `assembly ?? [source]` and `isAssembly` is `assembly != nil`; every reader that
  means "what this view shows" reads `outputs`. The **Assembly View** tool places a Front base view whose `assembly` is every Output in the editor's
  `sources` (the Final preview's parts, in their NodeID order); a first view on a sheet sets the sheet's scale from the union of the parts' bounds
  (DR-1 R8). Projected, section, detail and auxiliary views carry their parent's `assembly` as they carry its `source` (DR-3 R10), and changing a
  view's parts changes its descendants'. The view inspector of an assembly view (PARTS) lists every Output in `sources`, then every part of the view's `assembly` that is no
  longer in `sources` (its Output deleted), named "\(name) (removed)" from `partFacts` ("? (removed)" with no remembered name) and shown on, each with a Show
  toggle, so a removed part can be unticked; turning off the last one refuses
  "An assembly view shows at least one part." An Output added to the model later is not added to an existing assembly by itself. Why: a stored list
  keeps balloons and item numbers stable when the graph grows. Cost: the person ticks a new part in.
- **R2. One hidden-line run for the whole assembly.** The parts' solids, in `assembly` order and each part's own order (`DrawingSession.content(of:in:)`),
  are projected as one compound (`compoundTag` `NodeTag(node: view.source, item: 0)`), so each part is its own body and parts hide each other.
  `ViewContent.parts: [PartSpan]` (`PartSpan { output: NodeID; faces: Range<Int>; curves: Range<Int> }`, positions in the compound topology's
  `faces` array and in the curves list) is filled for assembly views only (a single-Output view keeps `[]`, so DR-1 to DR-4 contents are unchanged).
  Spans come from cumulative face counts: OCCT's `compound` keeps the sources' face order (`solid(from:keepingTagsOf:)` refuses otherwise; an OCCT
  test pins it). A solid object already given by an earlier part is drawn once and warns `DrawingProjector.sharedSolidSentence(name:other:)`
  ("“\(name)” shows the same solid as “\(other)”, so this view draws it once."), since one shape twice in a compound would not map face for face.
  **The span rules are one helper**, `PartSpan.layout(_ parts: [PartSolids]) -> PartLayout` (`PartSolids { output: NodeID; solids: [Solid]; curves:
  [Curve] }` per shown part in `outputs` order, the solids already cut to their remainders for a section; `PartLayout { solids: [Solid]; curves: [Curve];
  spans: [PartSpan]; shared: [(part: NodeID, other: NodeID)] }`: the deduplicated solids in order, the curves concatenated, the spans from cumulative face
  counts (`Solid.topology.faces.count`) and curve counts, a part whose solids were all given earlier keeping an empty face range at the running count),
  which `DrawingProjector` and the app's last-good refresh (`AppModel+DrawingRefresh`) both call, so the spans an anchor is judged against on screen and
  in the refresh can never differ (Task 12 pins it). Two known limits, accepted: **(a)** the dedupe is by `Solid` identity (`===` of its shape object), so two
  distinct `Solid` values wrapping one OCCT shape at one location (no node makes those today; a future node could) are not caught, and the compound then
  throws "its faces couldn't be matched"; the view fails with DR-1's `unprojectableSentence` ("The view couldn't be projected."), never a wrong drawing.
  **(b)** Hatching (spec §Section views: "each part of an assembly at its own angle"): in an assembly view a `HatchRegion`'s `part` is the part's index in
  `outputs`, not the solid's index, so every solid of one part shares one angle and neighbouring parts alternate; a single-Output view keeps DR-3's solid
  index (its pictures unchanged). Both the projector and the refresh pass that index to `ProjectionCache.sectionCut(of:index:…)`, so they share cache entries.
  Part states: any part **failed** fails the whole view (its last lines stay faded with `DrawingProjector.partFailedSentence(name:message:)`, "“\(name)”
  can't be drawn: \(message)"), never a partial assembly shown as whole; any part **evaluating** keeps the view pending; a **removed** part (its Output
  deleted) is left out with `partRemovedSentence` ("One of this view's parts was removed from the model, so it isn't drawn."), every part removed is
  DR-1's `removedSentence`; a part with **nothing drawable** is left out with `partEmptySentence(name:)` ("“\(name)” holds nothing to draw, so this view
  leaves it out."); a part's **meshes** warn `partMeshesSentence(name:count:)` ("This view leaves out “\(name)”'s mesh; drawings show solids, sheets
  and curves." / "… “\(name)”'s \(n) meshes; …", the count by `Locale.messages`); all parts empty or meshes only: DR-1's two sentences. A **section**
  of an assembly cuts each solid (DR-3, hatched by part index, (b) above) and builds its spans over the remainders through `PartSpan.layout` (a part cut away entirely gets empty ranges);
  a **detail** copies its parent's spans (`DetailClip.content`). Cost: one failing part blanks the assembly's fresh lines until it is fixed (by design).
- **R3. Anchors name their part.** `AnchorTarget` gains `indirect case onPart(NodeID, AnchorTarget)` (coded `"onPart"`, keys `part`, `target`;
  decoding flattens nesting to the innermost part and reads `.onPart(_, .point(p))` as `.point(p)`), `AnchorTarget.part: NodeID?` and
  `unwrapped: AnchorTarget`. In an assembly view every pick is wrapped with the part its line lies on: an edge's part is the span holding its first
  face, an outline's the span holding its face; the picker names and judges the anchor against `Topology.restricted(toFaces:)` of that span (faces in
  the range, edges whose faces all lie in it, IDs unchanged), so **two copies of one part** (one producer moved twice, identical tags) each name their
  own edges, and naming is unique within the part. A line on no span (a curve) is refused as DR-2 refuses free curves. Single-Output views never wrap.
  The resolver unwraps (`DrawingAnchorResolver.scope(of:in:parts:)`), and **every** resolve passes the view's spans
  (`resolve(_:in:frame:parts:)`, no default value, so the compiler finds every call); HoleReader and `DrawingMeasure` read the scoped topology. A wrapped
  anchor whose part has no span is lost with the new `LostReason.partNotShown` ("The part it was on isn't in this view any more."). An unwrapped anchor
  in an assembly view (a view whose parts were changed under it) resolves against the whole compound and is lost `.several` when the tags repeat.
  Group, Ungroup and Make Unique rename the inner target (`DrawingDocument+TagRenaming`); Outputs are top level, so the part never changes. Pulled in
  (DR-4 R19): `.several` and `.severalFaces` now read "What it was attached to now fits \(n) edges, and a drawing never guesses which." (faces
  likewise), since balloons, symbols and dimensions all share them. Cost: DR-2's pinned sentences change in their tests.
- **R4. Balloons.** `AnnotationKind.balloon(Balloon)` (coded `"balloon"`), `Balloon { leader: LeaderEnd; offset: Vector2 }` (`offset` sheet mm from
  the foot to the circle's centre); always on a view. Its part is `Balloon.part(in view: DrawingView) -> NodeID`: the target's `onPart` part, else the
  view's `source`. Picked with `PickPurpose.balloon`: what `.leader` takes (any lasting edge, a corner's edge, a circle, a cylinder outline), in any
  view **including isometric ones** (decision 4); refusals worded through `PickWording.balloons` (R16's sentences). The foot is DR-2's note leader
  landing (the point of the anchor's projected lines nearest the hint, else its exact geometry), so it works on ellipses in pictorial views. Drawn by
  `BalloonLayout` (ISO 6433 item reference in a circle, ASME Y14.34 balloon; one form for both): the number, cap `BalloonStyle.text` × h
  (`h = DrawingStyle.notesHeight(for:)`, `text` = 2), centred on the circle; the circle of radius `max(BalloonStyle.radius × h, run width / 2 +
  BalloonStyle.padding × h)` (`radius` 2, `padding` 0.5), thin; a thin leader from the circle's edge toward the foot, ending in DR-2's filled
  arrowhead (`AnnotationStyle.arrowLength`) on the foot; no leader when the foot lies inside the circle; everything on `.dimension`. Lost by DR-2's
  rules plus `.partNotShown`: drawn from its `LastGood` (`values: []`, `lines: [number]`, `figure: .leaders([foot])`, model plane), every piece
  `isLost`, the number followed by "?" ("3?"), listed, exported with DR-2's lost sentence; report label "Balloon \(n)". Never re-attached by itself;
  Select's click on a line re-attaches it ("Reattach Balloon"), refused when the line is on another part ("A balloon stays on its part; add a new
  balloon for another part."). `AnnotationRefresh` returns nil for a balloon (its foot comes from composes, as a note's leaders do). Cost: a dot-ended
  leader (ISO 6433's form for a leader inside an outline) is parked; every balloon ends in an arrowhead on its line.
- **R5. Item numbers are computed.** `DrawingDocument.items: [PartItem]` (written only when not empty), `PartItem { part: NodeID; material: String;
  partNumber: String }`; the array's order is the person's item order. `PartItems.wanted(in:) -> [NodeID]` is every Output any view of any sheet shows
  (sheets in tab order, views in `views` order, `outputs` in order) and every balloon's part, each once. `PartItems.numbered(_:names:) -> [NumberedItem]`
  (`NumberedItem { part: NodeID; number: Int; material: String; partNumber: String }`): first the wanted parts that `items` lists, in `items` order, then
  the other wanted parts by name (`String <`), ties by `NodeID`, and after them the wanted parts that have no name at all, by `NodeID`; numbers 1, 2, 3…
  with no gap. **A removed part keeps its place**: `names` is `PartItems.names(of: facts)`, which holds the live Output's name, else the part's remembered
  name, and only a part with neither sorts last. Remembered names work as DR-2's `LastGood` does: the editor's `rememberedPartNames: [NodeID: String]` (in
  memory, never an edit) is refreshed by the app from every facts build for each wanted part with a live Output and seeded from the file's
  `DrawingDocument.partNames: [PartName]` (`PartName { part: NodeID; name: String }`, sorted by `part`, written only when not empty); `documentForSaving()`
  writes the remembered names of the wanted parts into it (no undo step, the document not marked edited). So with Bolt 1, Nut 2, Plate 3 unpinned,
  deleting Plate's Output leaves Bolt 1, Nut 2, Plate 3, in the session and after a save and reopen. `TitleBlockFacts.parts` holds every wanted part: a
  live one as `PartFacts(name:quantity:isRemoved: false)`, a removed one with its remembered name (or "?" with none), quantity nil and `isRemoved: true`,
  built once per facts build by the app. **The editor gets the same dictionary**: `DrawingEditorModel.partFacts: [NodeID: PartFacts]`, set by the app
  from the facts it hands the composer, and `pinningOrder`, the inspector's numbers and the PARTS section all read `PartItems.names(of: partFacts)`, so
  the order the editor pins is exactly the order the balloons show. So balloons and the parts list can
  never disagree, and a number never names a part the drawing doesn't show. **Any item edit first writes the whole current order into `items`**
  (Move Up, Move Down, a material or part number), so editing one item never renumbers another; parts added later follow the pinned ones. An entry whose
  part is no longer wanted stays (its material comes back with the part) and takes no number. `PartFacts { name: String; quantity: Int?; isRemoved: Bool }`
  arrive in `TitleBlockFacts.parts: [NodeID: PartFacts]` (read by lookup only): the name is the Output node's (or the remembered one), the quantity the
  number of solid values (solids and sheets) the Output holds, nil ("?") without a result or for a removed part. A part is no longer wanted once the person
  unticks it from every assembly that lists it and deletes its balloons (R1: the PARTS section lists a removed part with its toggle, Task 10). Cost: before the person pins the order, renaming an Output or adding a part can renumber; balloons
  and the list follow in the same compose (Review Focus 3).
- **R6. Mass of an assembly sheet.** DR-1 R16's mass field shows when one view's `outputs` contain every Output any view of the sheet shows: the sum
  over those Outputs' closed solids (each Output once), times the density. Otherwise it stays empty, as before. Cost: a sheet of two unrelated parts
  still shows no mass.
- **R7. The parts list.** `AnnotationKind.partsList(PartsList)` (coded `"partsList"`), a free sheet annotation (`view` nil), at most one per sheet
  (the tool refuses "This sheet has a parts list already; drag it to move it."; decoding keeps the first by id), `PartsList { bottomRight: Vector2? }`
  (nil: standing on the title block, its bottom right on the block's top right). It lists every numbered item of the drawing (R5), not only the
  sheet's. `PartsListLayout` (ISO 7573, ASME Y14.34): 180 mm wide (`TitleBlockLayout.width`), rows `rowHeight` = 7 mm, the header row at the bottom and
  item 1 just above it, rising. Columns, left to right: ISO "Item" 15, "Qty" 15, "Name" (the rest), "Part number" 40, "Material" 40; ASME "QTY" 15,
  "PART NO." 40, "DESCRIPTION" (the rest), "MATERIAL" 40, "ITEM" 15; the part-number column is left out when no listed item has one (the name
  column widens). Outline `DrawingStyle.frame`, inner lines `DrawingStyle.zone`, lines and header labels on `.frame`, cells on `.text`, cap h, fitted
  by `DrawingText.fitted` within 1.5 mm insets, numbers and quantities centred, text left; a quantity nil reads "?"; a removed part's row reads its remembered name followed by "?"
  ("Plate?", as a lost balloon's number), or "?" alone with no remembered name.
  DR-4's sheet notes stand above a parts list that stands on the block (`SheetNotesLayout.picture(…, base:)`). Cost: per-sheet lists, a mass column and
  house column sets are parked.
- **R8. Revision letters** (`RevisionLetters`): A B C D E F G H J K L M N P R T U V W Y (ASME Y14.35 leaves out I, O, Q, S, X and Z; ISO 7200's
  revision index is free-form, so one rule serves both), then AA, AB … with both letters from those 20 (bijective, as `ViewLetters`).
  `next(after rows: [RevisionRow]) -> String` is the letter after the last row whose letter is valid, else "A". Rows are never re-lettered.
- **R9. The revision table.** `AnnotationKind.revisionTable(RevisionTable)` (coded `"revisionTable"`), free, at most one per sheet (refusal "This
  sheet has a revision table already; drag it to move it."), `RevisionTable { rows: [RevisionRow]; topRight: Vector2? }` (nil: the frame's inside
  top-right corner), `RevisionRow { letter: String; description: String; date: String; approved: String }`. "New Revision" appends a row with
  `RevisionLetters.next` and empty description, date and approved; **the date is typed by the person, never read from the clock**, so a file's
  bytes depend only on what was typed; only the last row can be removed ("Remove Last Revision"). Layout (`RevisionTableLayout`): the header row at
  the top, rows below it oldest first; columns ISO "Rev." 15, "Description" 100, "Date" 30, "Approved" 35, ASME "REV", "DESCRIPTION", "DATE",
  "APPROVED", same widths; weights, layers, row height and fitting as R7. The title block's revision field shows `DrawingSheet.revisionShown`: the last
  row's letter when the sheet's table has rows, else the typed `titleBlock.revision` (kept, never overwritten); the inspector's Revision field reads
  "From the revision table" and is disabled then. Cost: ASME's ZONE column and a per-document revision are parked (each sheet keeps its own).
- **R10. Templates.** `DrawingTemplate { id: String; name: String; size: SheetSize; orientation: SheetOrientation; standard: DrawingStandard;
  titleBlock: TitleBlock; logo: Data? }` (only `owner` (the company name), `drawnBy`, `material` and `density` of the title block are kept: the
  others and `logo` are cleared when made). File `<id>.mctemplate`, JSON (`DrawingTemplateFile`, keys `version` 1, `name`, `size`, `orientation`,
  `standard`, `titleBlock`, `logo` base64, sorted keys), read and written by `DrawingTemplateFolder` (`~/Library/Application Support/MetalCreator/
  Drawing Templates`, `$XDG_DATA_HOME/MetalCreator/Drawing Templates`, `%APPDATA%\MetalCreator\Drawing Templates`, through `UserDataFolder.url` lifted
  out of `ThemeFolder` into `CreatorStyle`), held by `@MainActor @Observable DrawingTemplateStore` (folder nil: memory only, every test's; templates
  sorted by name with `localizedStandardCompare`, then id; each change saved at once; `loadProblems` one sentence per skipped file). **Ids**: a template's
  `id` is a `UUID().uuidString`, made by the app when it calls `DrawingTemplate.made(from:…id:)`; `DrawingTemplateFolder.isUsable(_ id:)` checks it as
  `ThemeFolder.isUsable` does (not empty, no path separator, no leading ".", no control character, at most 200 UTF-8 bytes), and on loading the file's stem
  is read back as the id (a stem that isn't usable is skipped: "“\(file)” was skipped: its name can't be a template's id."), so `add(_:)`, the file and
  `made(from:…)` agree. **Reads are bounded** (R23): each file goes through `RegularFile.read(_:limit: DrawingTemplateLimits.maximumFileBytes)`
  (3 MiB = 3,145,728 bytes: a 2 MiB logo's base64 is 2,796,203 bytes, plus the JSON), and a larger one is skipped unread: "“\(file)” was skipped: it is
  larger than 3 MB."; one that isn't a regular file: "“\(file)” was skipped: it isn't a file."; a read that fails: "“\(file)” was skipped: \(reason)"
  (the system's sentence). Decoding refuses in
  words: "“\(file)” was skipped: it isn't a drawing template." (bad JSON or a missing key), "… it was saved by a newer MetalCreator." (version > 1),
  "… its logo is larger than 2 MB." (`LogoLimits.maximumBytes`), "… its logo isn't readable." (bad base64). **Saving and deleting** go to the folder
  before the store changes (as `ThemeStore` does): on failure the store is left as it was and `saveProblem` holds "“\(name)” couldn't be saved:
  \(reason)" (`save`) or "“\(name)” couldn't be deleted: \(reason)" (`remove`), the reason the system's sentence or "its id can't be a file name."; the
  sheet inspector's TEMPLATES section shows `saveProblem` under its rows until the next change succeeds. **New Sheet from Template**: the sheet's
  size, orientation and title block (owner, drawn by, material, density; the logo's bytes added to the document's `images` table and named by hash;
  today's date as DR-1 does), named as `addSheet` names; the template's standard is applied only to a drawing's first sheet. **Save Sheet as
  Template**: the open sheet's size, orientation, the drawing's standard, its owner, drawn by, material, density and logo bytes, named after the owner,
  else "Template", made unique with " 2", " 3"…; rename (blank refused "A template needs a name.") and delete in the sheet inspector. A template is never
  in `.mcgraph`: a sheet keeps only the values it set. Cost: importing and exporting template files, and templates carrying notes or tolerances, are parked.
- **R11. The logo.** `TitleBlock.logo: String?` (an `ImageHash`'s 64 hex digits, written only when set; a damaged value reads nil; counted in
  `Graph.embeddedImageHashes` so saving keeps its bytes). The app checks every logo before using it, from a file or a template. A chosen file is read
  through `RegularFile.read(_:limit: LogoLimits.maximumBytes)` (R23: at most 2 MiB + 1 bytes read; a larger file is refused from its size, unread, with
  the sentence below; not a regular file: "The logo isn't a file."; a failed read: "The logo couldn't be read: \(reason)"); a template's logo is bounded
  by the template's own limit and checked again here. Then `GreyImageDecoder.inspect`
  (PNG and JPEG, `ImageLimits`) then `LogoLimits` (`maximumBytes` 2 MiB = 2,097,152 bytes: "A logo file is at most 2 MB."; `maximumSide` 1024: "A logo is at
  most 1,024 pixels on a side; this picture is \(w) × \(h).", `w` and `h` formatted with `Locale.messages` (`Int.display`'s formatter, so 2000 reads
  "2,000" and 1024 "1,024")). Failures reach the person as an alert: from Choose Logo… `AppProblem("The logo couldn't be used", sentence)`; from New
  Sheet from Template `AppProblem("The template's logo couldn't be used", sentence + " The sheet was made without it.")`. It decodes off the main actor with `GreyImageDecoder.decode(_:background: .white)` (a transparent
  background is paper; the black default stays the fields'), converts to 8 bits (`(v + 128) / 257`) and hands a `GreyPixels` to the composer as
  `TitleBlockFacts.logo` (`LogoFact.picture(GreyPixels)` or `.unreadable(String)`), cached per hash. Drawn in the owner field **below its label**: the field is 10 mm tall
  and its label ("Owner" / "COMPANY", cap 1.8 mm) has its baseline `TitleBlockLayout.labelBaseline` = 2.5 mm below the field's top, so its ink fills about
  7.5 to 9.3 mm above the field's bottom (descenders about 0.52 mm below the baseline, so its lowest ink is about 36.98 in a 30..40 field). The logo's band (`TitleBlockLayout.logoBand(in owner: Rect2D) ->
  Rect2D`) runs from the bottom inset (1.5 mm) up to `labelBaseline + logoLabelGap` below the top (`logoLabelGap` = 1 mm), so it is 10 − 1.5 − 3.5 = 5 mm
  tall; `logoRect` fits the picture in it with its aspect kept, at most `logoMaximumWidth` = 40 mm wide, at the field's left inset, vertically centred in
  the band; the owner text then starts 1.5 mm right of it (the value's baseline is the field's bottom inset, as DR-1 has it, so it shares the band). An unreadable logo draws nothing and says "The title block's logo couldn't be read: \(reason)" as a sheet notice on
  screen and an export warning. Cost: logos are grey (one decoder, pinned on every platform, and print is mostly black); colour is parked.
- **R12. Pictures of images.** `SheetPicture.images: [SheetImage]` (`append` carries them), `SheetImage { rect: Rect2D; pixels: GreyPixels; layer:
  DrawingLayer }`; `GreyPixels` is a `final class` (`Sendable`, immutable: `key: String` (the hash), `width`, `height`, `bytes: [UInt8]`, a failable
  init checking `bytes.count == width * height`), equal and hashed by key, width and height, so comparing pictures never compares a megabyte. The screen
  draws it as MetalUI `Image(decorative: ImageBitmap(width:height:rgba:), scale:)` `.resizable()`, the bitmap made once per key and kept by the editor model.
- **R13. Writers.** PDF: one `/XObject /Image` per distinct key in first-seen order (`/Width`, `/Height`, `/ColorSpace /DeviceGray`,
  `/BitsPerComponent 8`, the bytes raw, top row first), numbered after every page object, so a document without images writes the same objects as
  before; a page with images gains `/XObject << /Im1 n 0 R >>` in its resources and draws them first (`q w 0 0 h x y cm /Im1 Do Q`), under the ink.
  DXF: a picture can't be held, so the image's rectangle is written as an LWPOLYLINE on FRAME and the export warns "The DXF leaves out the title block's
  logo; DXF files can't hold a picture." (once per file). SVG (`SVGWriter`, R14) embeds it as a grey PNG data URI from our own `GreyPNG` (stored deflate
  blocks, `CRC32` from `CreatorGeometry`, our Adler-32), so its bytes are fixed. Compressed PDF streams stay parked: `RawDeflater` exists only where
  `canImport(Compression)`, and a portable deterministic deflater is a project of its own.
- **R14. SVG.** `SVGWriter.write(_ page: SheetPicture, title: String) -> SVGOutput` (`data`, `replacedTexts`), one sheet per file: `<?xml version="1.0"
  encoding="UTF-8"?>`, `<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="Wmm" height="Hmm" viewBox="0 0 W H">`, `<title>`, one `<g
  transform="matrix(1 0 0 -1 0 H)">` (sheet millimetres, y up), the images first, then a `<g id="LAYER">` per `DrawingLayer.allCases` that has anything,
  holding its strokes (`<path d>` with M, L and C from the same segments, arcs and ellipses as `SheetSegment.cubics()`; `stroke-width`; dashes from the
  page's `DrawingStyle` as the PDF writes them; `fill="none"`, `stroke-linecap="butt"`, `stroke-linejoin="round"`), its fills and its texts, in picture
  order. A text is `<text>` at its origin with `transform` turning it upright again and by its angle (degrees from radians through `PDFNumber.format`),
  `font-family="Helvetica, Arial, sans-serif"`, `font-size` the em in mm, `textLength` its Helvetica width with `lengthAdjust="spacingAndGlyphs"`
  (any viewer's sans-serif lands at the same width, so screen and paper agree), its WinAnsi bytes mapped back to Unicode
  (`HelveticaMetrics.unicode(forWinAnsi:)`) and XML-escaped. Ink `#000`, no background, notices never written, numbers by `PDFNumber.format(_,
  decimals: 4)`. An image, inside that flipped group, would come out upside down, so each `<image>` carries its own un-flip about its rect's middle:
  `<image x="x0" y="y0" width="w" height="h" preserveAspectRatio="none" transform="matrix(1 0 0 -1 0 (y0 + y1))" href="data:image/png;base64,…">` (with
  `xlink:href` too, `xmlns:xlink` on the root, for older viewers), so the picture's top row (row 0) lands on the rect's top edge (`y1`, sheet y up), as the
  PDF's `cm` places it. Cost: SVG viewers without Helvetica stretch Arial to the widths.
- **R15. Export kinds.** `DrawingExportKind` gains `pdfSheet` (the open sheet, "Export PDF of Sheet…") and `svgSheet` ("Export SVG of Sheet…"); `.pdf`
  stays every sheet in tab order, one page each, retitled "Export PDF of All Sheets…". Every export's warnings run sheet by sheet in tab order: the lost
  annotations, then the checks, then the logo's (pulled in: DR-4 left the multi-sheet order unpinned). The export sheet and the top bar's Export menu list
  the two new kinds; `ContentType.svg` (extension "svg"). **DXF of View at 1:1 with Annotations** (DR-2 R22's `dxfViewWithAnnotations`) carries the
  view's balloons as it carries its notes: each piece mapped back to model millimetres (the circle as a CIRCLE and the leader on DIMENSION, the number as
  TEXT on TEXT, sizes divided by the view's scale as DR-2 does a note's lettering), a lost balloon with its "?" and DR-2's lost warning; the parts list and
  the revision table are free sheet annotations and are left out, as DR-2 leaves out free notes, and so is the logo (the view's DXF has no title block, so it
  gives no logo warning).
- **R16. Tools, keys, picks and steps.**
  - `DrawingTool` gains `assemblyView` ("Assembly View", after Projected View, not an annotation tool, no key), and after `surfaceFinish` `balloon`
    ("Balloon", key B), `partsList` ("Parts List", key P) and `revisionTable` ("Revision Table", no key); twenty-one tools beside Select.
  - Balloon: the first click names a line (`PickPurpose.balloon`), shown as the draft following the pointer; the next click places the circle there
    (`offset` = click − foot on the sheet); one step, selected, tool kept; Esc drops the target, then the tool (DR-4's flow). Parts List and Revision
    Table: one click places the table; within 10 mm of the title block's top right (of the frame's inside top right) it stands there (`nil`), else at the
    click. Dragging or nudging a balloon moves `offset`; a table moves its corner (a standing one becomes free); the inspector's "Stand on Title Block" /
    "Move to Corner" sets it back.
  - Pick wording (`PickWording.balloons`, `DrawingPick` statics): `balloonNoEdgeNameSentence` "This edge has no lasting name, so a balloon can't hold on to
    it.", `balloonSharedEdgeSentence` "This line's edge shares its name with other edges, so a balloon can't hold on to it.",
    `balloonNoCylinderNameSentence` "This cylinder has no lasting name, so a balloon can't hold on to it.", `balloonSharedCylinderSentence` "This
    cylinder shares its name with other faces, so a balloon can't hold on to it."; `PickCandidate.balloonFreeCurveSentence` "This line is a free curve;
    balloons attach to a part's edges."
  - `DrawingStepName` gains (in `all`): "Add Balloon", "Move Balloon", "Delete Balloon", "Reattach Balloon", "Add Parts List", "Move Parts List",
    "Delete Parts List", "Change Item", "Move Item", "Add Revision Table", "Move Revision Table", "Delete Revision Table", "Add Revision", "Change
    Revision", "Remove Revision", "Change Parts", "Change Logo", "Paste", "Cut". A mix of kinds moved or deleted stays "Move Annotations" / "Delete
    Annotations". A setter whose value equals the current one commits nothing.
- **R17. File format 21.** A format-20 reader can't decode `onPart` anchors or the three kinds, so the version is bumped. `GraphFile`'s comment gains
  "21: DR-5's assembly views (`DrawingView.assembly`), part anchors (`AnchorTarget.onPart`), balloons, parts lists and revision tables
  (`AnnotationKind`), the drawing's `items` and `partNames` and a title block's `logo`; a version-20 reader cannot decode the new anchors and kinds." Decoding repairs: R1's
  list; R3's nesting; a balloon with no view dropped; a second parts list or revision table on a sheet dropped (the first by id kept); a parts list or
  revision table with a view reads as free; `items` with a part twice keep the first; `partNames` with a part twice keep the first, sorted again by part.
- **R18. Copy and paste** (pulled in; spec §Model: "Copy and paste of views and annotations stays within a drawing"). ⌘C, ⌘X and ⌘V over the sheet canvas
  (`DrawingKey.copy`, `.cut`, `.paste`; `.primary`, so Ctrl elsewhere) use the editor's own `DrawingClipboard` (in memory, one per editor; never the
  system pasteboard; New and Open replace it with the editor). Copy takes the selected views with all their annotations, plus the selected annotations of
  views not copied; a selected section, detail or auxiliary view whose parent isn't selected refuses "Copy a section, detail or auxiliary view together with
  the view it was made from." Paste puts everything on the open sheet with new IDs (views, annotations, alignments, derivations, `.dimension` attachments
  remapped as `duplicateSheet` does, one shared helper `SheetCopy`), pasted views and free annotations moved by (10, −10) mm per paste since the copy, an
  alignment or derivation to a view not pasted dropped (the view is free; a derived view keeps its parent only when the parent was pasted), derived views
  given fresh letters (`ViewLetters.next`), annotations of views neither pasted nor on this sheet skipped with "Some annotations belong to a view on another
  sheet, so they weren't pasted.", and a parts list or revision table skipped when the sheet has one ("This sheet has a parts list already." / "This sheet
  has a revision table already."); the pasted things are selected; one step "Paste". Cut is Copy then one step "Cut". **Scale**: the clipboard keeps the
  source sheet's scale (`DrawingClipboard.sheetScale`); a pasted view whose `scale` is nil (it follows its sheet) is given that scale explicitly when the
  target sheet's scale differs, so it keeps its size on paper and its dimensions their placements (relative to the geometry, DR-2 R7); a view with its own
  scale (a detail's, or one the person set) keeps it; on a sheet of the same scale nothing is set, and the first view pasted onto an empty sheet still sets
  nothing (the sheet keeps the scale it has). Why: a paste should look like what was copied. Cost: a pasted view no longer follows its new sheet's scale
  until the person sets it to "Sheet". Pasting between documents is parked.
- **R19. MCP.** `CreatorMCP` gains `DrawingTools` (`list_drawings`, `get_sheet`, `export_drawing`), reading tools that work in every mode, and an export that is
  refused whenever edits are (the session's edit refusal). No drawing edit through MCP (parked: placing a dimension needs a pick). The session protocol gains
  `drawingSheet(_ id: SheetID) async -> DrawingSheetSnapshot?` (`DrawingSheetSnapshot { picture: SheetPicture; facts: TitleBlockFacts; views: [ViewID: ViewStatus] }`, the sheet composed
  as an export composes it: evaluation awaited, views projected, notices off) and `exportDrawing(_ kind: String, sheet: SheetID?, view: ViewID?, to: URL,
  overwrite: Bool) async -> SessionOutcome`. `DocumentModelSession` takes both as hooks (`drawingSheetProvider`, `drawingExporter`; nil answers nil /
  refuses "Drawings can't be exported from this session."), set by tests; `AppDocumentSession` implements them over `AppModel`. Addressing: a sheet by id or
  unique name ("Say which sheet, by its ID or name.", "There's no sheet with ID \(text).", "There's no sheet called “\(text)”.", "Two sheets are called
  “\(text)”; use the sheet's ID."), a view by id on that sheet ("There's no view with ID \(text) on “\(sheet)”."). Export kinds `pdf`, `pdf_sheet`,
  `dxf_sheet`, `dxf_view`, `dxf_view_annotations`, `svg_sheet` ("Drawing export kinds are pdf, pdf_sheet, dxf_sheet, dxf_view, dxf_view_annotations and
  svg_sheet."); the sheet kinds need `sheet` ("Say which sheet to export."), the view kinds `sheet` and `view` ("Say which view to export."). Paths, overwrite
  and results as `export`. `docs/mcp.md` lists the three tools. **Limits**: `get_sheet` and `export_drawing` wait as the edit tools do, one limit of 60 s
  (`EditOutcome`'s `.seconds(60)`, named `DrawingTools.settleLimit`) for the evaluation and the sheet's projections together (`AppDocumentSession` races the
  whole wait once, as `settle(within:)` does). `get_sheet` answers at the limit with what it has: a view whose projection hasn't landed is drawn as DR-1 R19
  draws a pending view (its previous lines), its annotations judged against the previous topology (DR-2 R25), and the JSON's `views` array gives each view's
  `status` ("drawn", "pending" or "failed", with `problem` for a failed one), and a top-level `"complete": false` when any view is pending. An export
  whose projections are still pending at the limit is refused: "MetalCreator is still drawing this sheet. Try again in a moment."
- **R20. Performance.** `drawing-5`: a sheet of ten parts (each a 40 × 30 × 10 box less a Ø10 hole, 50 mm apart along x, one Output each), the Assembly View
  in Front with its Top and Right projected views, from the edit that adds them to the last projection landing, projection cache emptied, 10 runs, budget 1 s;
  `drawing-5-warm`: 60 pan steps and 60 zoom steps of that sheet with ten balloons and the parts list, warm window CPU per frame, budget 16.67 ms. Recorded,
  not gated. Composing the list is linear in items; numbering sorts once per compose.
- **R21. Pulled in from the backlog:** the AnnotationRefresh pictorial notice (DR-4: `AnnotationRefresh.lastGood` and `lostReason` take `isPictorial`, and
  return nil for dimensions and symbols in a pictorial view, so a symbol lost in a view turned isometric stops refreshing its foot; Task 3); R3's rewording of
  `.several` (DR-4 R19); unique sheet names (DR-1: a duplicate is "\(name) Copy", then "\(name) Copy 2"…; Task 9) and rename trimming whitespace and keeping the
  old name for a blank one (DR-1; Task 9); the "+" tab as a `plus` icon menu (DR-1; Task 10); the multi-sheet export warning order (DR-4; R15, Task 12);
  copy and paste (DR-1's parked feature; R18, Task 11).
- **R22. Parked.** Exploded views (a non-goal), dot-ended balloon leaders, stacked balloons, renumbering items by balloon position, quantity overrides, a mass
  column, per-sheet parts lists, house column sets, ASME's ZONE column, multi-line table cells, a revision per document, colour logos, a DXF IMAGE entity,
  template import and export and templates carrying notes or tolerances, Outputs joining an assembly by themselves, drawing edits through MCP, pasting
  between documents, compressed PDF streams (R13), `HLRBRep_PolyAlgo`, cancelling inside OCCT's hide, a font subset, dragging tabs to reorder, ANSI Y14.1 zone
  counts and margins, hidden tangent lines, DXF text widths, an export progress sheet (projections are cached and `drawing-5` is well under its second), and every
  other DR-1 to DR-4 item in `.superpowers/sdd/2026-11-26-dr-5-assemblies-revisions/backlog.md` and CLAUDE.md's parked lists.
- **R23. Bounded reads** (added in review). `RegularFile.read(_ url: URL, limit: Int) throws(RegularFileProblem) -> Data` in `CreatorGeometry/Files`
  (`RegularFileProblem`: `.notAFile`, `.tooLarge(size: Int)`, `.unreadable(reason: String)`) is `ImageResolver.openedRegularFile`'s code lifted so that
  `CreatorDrawingEditor` (which can't import `CreatorGraph`) and the app share it: the file opened without blocking, its descriptor checked as a regular
  file of at most `limit` bytes by `fstat` before a byte is read (Windows: the attributes, as today, with the same caveat), then at most `limit + 1` bytes
  read and a longer result refused (a file that grew). `ImageResolver.openedRegularFile` and `read` call it and map its problems to `ImageProblem` as now
  (their sentences and tests unchanged). Callers: the logo file (R11, limit `LogoLimits.maximumBytes`) and each `.mctemplate` (R10, limit
  `DrawingTemplateLimits.maximumFileBytes`). Why: both are files a person or another program put there; an unbounded read of a huge or special file would
  hang or exhaust memory. Cost: none beyond the lift.

## Review Focus

1. **Two copies of one part in an assembly.** One Box moved twice into two Outputs has identical tags in both: each balloon and dimension names its own copy
   (`onPart`), stays on it through a width change, and never jumps to the twin. Task 3 (`twinPartsEachHoldTheirOwnEdge`), Task 12 (`twinPartsKeepTheirBalloons`).
2. **A part leaving the view.** Unticked, deleted, failing or emptied: its anchors are lost `.partNotShown` (listed, "?"), a balloon keeps its number with "?",
   a failing part keeps the whole view's last lines faded with its sentence, never a partial assembly presented as whole. Task 2 (`aFailedPartFailsTheView`,
   `aRemovedPartIsLeftOutWithAWarning`), Task 3 (`anUntickedPartLosesItsAnchors`), Task 4 (`aLostBalloonKeepsItsNumber`), Task 12 (`deletingAPartsOutputLosesItsBalloon`).
3. **Numbers in step.** Editing one item's material never renumbers another; renaming an Output or adding a part may renumber unpinned items, and balloons and
   the list follow in the same compose; a part with no balloon is listed; deleting a part's Output renumbers nothing (its remembered name keeps its place) and the
   removed part can be unticked; the editor pins exactly the composed numbers. Task 4 (`balloonsAndListAgree`, `editingAnItemPinsTheOrder`,
   `aRemovedPartKeepsItsNumber`), Task 9 (`settingAMaterialNeverRenumbers`, `pinningKeepsTheNumbersShown`), Task 10 (`aRemovedPartCanBeUnticked`), Task 12
   (`deletingAnOutputRenumbersNothing`).
4. **Untrusted logos and templates.** A 4,000-pixel PNG, a truncated JPEG, a 10 MB file, garbage base64, a template from a newer version, a 1 GB sparse template
   file, a FIFO named `.mctemplate`: refused in words without reading them whole, the sheet still made, nothing decoded on the main actor. Task 7
   (`badTemplatesAreSkippedInWords`, `aHugeTemplateIsSkippedUnread`, `RegularFileTests`), Task 12 (`oversizedLogosAreRefused`, `aBrokenTemplateLogoMakesTheSheetWithoutIt`).
5. **Fixed bytes.** PDF with a logo, SVG and DXF of an assembly sheet with balloons, both tables and a logo: one digest each on macOS and Linux; a new revision
   row has no date. Task 6 (`assemblyPageDigest`, `svgDigest`), Task 9 (`aNewRevisionHasNoDate`).
6. **Copy and paste with derived views and symbols.** IDs remapped, letters fresh, no attachment to a dimension that wasn't pasted, undo takes it back in one step.
   Task 11 (`pastingRemapsEverything`, `aSymbolWithoutItsDimensionIsNotPasted`).
7. **MCP while the person is busy.** `export_drawing` refused under the edit refusal; `get_sheet` projects outside Drawing mode and lists lost annotations with
   their sentences. Task 13 (`exportIsRefusedWhileEditsAre`, `getSheetListsLostAnnotations`).

---

### Task 1: The model and file format 21

**Files:**
- Create: `Sources/CreatorDrawing/Model/Annotations/Balloon.swift`, `Sources/CreatorDrawing/Model/Annotations/PartsList.swift`,
  `Sources/CreatorDrawing/Model/Annotations/RevisionTable.swift` (`RevisionTable`, `RevisionRow`), `Sources/CreatorDrawing/Model/PartItem.swift`,
  `Sources/CreatorDrawing/Model/RevisionLetters.swift`
- Modify: `Model/DrawingView.swift` (R1), `Model/Annotations/AnchorTarget.swift` (R3's case and coding), `Model/Annotations/DrawingAnnotation.swift` and
  `Annotations+Coding.swift` (the kinds), `Model/DrawingDocument.swift` (`items`, `partNames`), `Model/TitleBlock.swift` (`logo`), `Model/DrawingSheet.swift` (R17's
  repairs, `partsList`, `revisionTable`, `revisionShown`), `Sources/CreatorGraph/GraphFile.swift` (21 and its comment),
  `Sources/CreatorGraph/Groups/DrawingDocument+TagRenaming.swift` (`onPart`), `Sources/CreatorGraph/Images/Graph+Images.swift` (logos in
  `embeddedImageHashes`). Every exhaustive `switch` that stops compiling gets the new cases as "draws nothing / not movable / no anchors / no page"
  placeholders marked `// DR-5 Task N`: 3 (resolver, picker, evaluator), 4 (composer, refresh), 5 (tables in the composer), 8 (editor model), 10 (views).
- Test: `Tests/CreatorDrawingTests/AssemblyModelTests.swift`, `Tests/CreatorDrawingTests/RevisionLettersTests.swift`,
  `Tests/CreatorGraphTests/DrawingsFileTests.swift` (additions; `aNewerFileIsRefused` moves to 22), the drawing-anchor renaming test file
  (`grep -rl renamingTags Tests/CreatorGraphTests`), `Tests/CreatorGraphTests/` the embedded-images saving test file (`grep -rl embeddedImageHashes Tests/CreatorGraphTests`)

**Interfaces:**
- Produces: R1's `DrawingView.assembly`, `outputs`, `isAssembly` (the memberwise `init` gains `assembly: [NodeID]? = nil`); R3's `AnchorTarget.onPart`,
  `part`, `unwrapped`; `Balloon { leader: LeaderEnd; offset: Vector2 }` with `part(in:) -> NodeID`; `PartsList { bottomRight: Vector2? }`;
  `RevisionTable { rows: [RevisionRow]; topRight: Vector2? }`, `RevisionRow { letter, description, date, approved: String }`; `AnnotationKind.balloon`,
  `.partsList`, `.revisionTable`; `PartItem { part: NodeID; material: String; partNumber: String }`, `DrawingDocument.items: [PartItem]`;
  `PartName { part: NodeID; name: String }`, `DrawingDocument.partNames: [PartName]` (R5);
  `TitleBlock.logo: String?`; `DrawingSheet.partsList: (id: AnnotationID, list: PartsList)?`, `revisionTable: (id: AnnotationID, table: RevisionTable)?`,
  `revisionShown: String`; `RevisionLetters.letter(at: Int) -> String`, `isValid(_: String) -> Bool`, `next(after: [RevisionRow]) -> String`;
  `GraphFile.currentFormatVersion == 21`. All new types `Hashable, Codable, Sendable` with `public init`s whose optional parameters default to nil or empty.

- [ ] **Step 1: Tests.**
  - `AssemblyModelTests`: `assemblyRoundTrips` (a view with three parts: JSON key `assembly`, `outputs` the three; a single view writes no `assembly` key);
    `assemblyIsRepaired` (an empty list reads nil; `[B, A, B]` reads `[B, A]` with `source` B); `onPartRoundTrips` (`"type": "onPart"`, `part`,
    `target`); `nestedOnPartIsFlattened` (`.onPart(a, .onPart(b, .edge(e)))` reads `.onPart(b, .edge(e))`; `.onPart(a, .point(p))` reads `.point(p)`);
    `balloonsAndTablesRoundTrip` (a balloon, a parts list standing and one free, a revision table with two rows); `aSecondTableIsDropped` (two parts lists
    and two revision tables: the first of each by id kept); `aBalloonWithoutAViewIsDropped`; `aTableWithAViewReadsFree`; `itemsAreWrittenOnlyWhenSet`
    (an empty `items` writes no key; a duplicated part keeps the first); `partNamesAreWrittenOnlyWhenSet` (empty: no key; given out of order: written sorted by
    part; a part twice keeps the first); `theLogoIsWrittenOnlyWhenSet` (a 63-digit value reads nil);
    `revisionShownFollowsTheTable` (no table: the typed revision; rows A and B: "B"; an empty table: the typed one); `balloonPartIsItsWrapperOrTheSource`.
  - `RevisionLettersTests`: `theTwentyLetters` (`letter(at: 0...19)` is "ABCDEFGHJKLMNPRTUVWY" letter by letter; I, O, Q, S, X, Z invalid);
    `afterYComesAA` (20 → "AA", 21 → "AB", 39 → "AY", 40 → "BA"); `nextFollowsTheLastValidRow` ([] → "A"; [A, B] → "C"; [A, "Q"] → "B"; [H] → "J").
  - `DrawingsFileTests`: `aFormat20FileOpensAndIsWrittenAs21`; `aNewerFileIsRefused` (22); `dr5RoundTrips` (a document with an assembly view, an onPart
    dimension, a balloon, both tables, items, part names and a logo).
  - Renaming test: `partAnchorsAreRenamed` (Group's table renames the inner pick of `.onPart`; the part is unchanged).
  - Saving test: `aLogoKeepsItsImage` (`fileData` of a document whose sheet's logo names an image in `images` writes that image; an image nothing uses is dropped).
- [ ] **Step 2: Run** `swift test --filter 'AssemblyModelTests|RevisionLettersTests|DrawingsFileTests'` and the two CreatorGraph test files; compile failure.
- [ ] **Step 3: Implement** R1's model, R3's case, the kinds, R5's `items`, R8's letters, R9's model, R11's `logo`, R17.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`, `--filter CreatorGraphTests`, `--filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: assembly views, part anchors, balloons, tables, items and logos in the model, file format 21".

### Task 2: Assembly content: one compound, part spans

**Files:**
- Create: `Sources/CreatorDrawing/Views/PartSpan.swift` (`PartSpan`, `PartSolids`, `PartLayout`, `PartSpan.layout(_:)`, `[PartSpan].span(containingFace:)`,
  `span(containingCurve:)`),
  `Sources/CreatorDrawing/Anchors/Topology+Parts.swift` (`Topology.restricted(toFaces:)`), `Sources/CreatorDrawing/Projection/DrawingProjector+Assembly.swift`
- Modify: `Views/ViewContent.swift` (`parts`, default `[]`), `Projection/DrawingProjector.swift` (the section path builds spans over remainders when given
  parts, through `PartSpan.layout`; an assembly's hatch index is the part's index in `outputs`, R2 (b)), `Sections/DetailClip.swift` (copies `parts`)
- Test: `Tests/CreatorDrawingTests/AssemblyContentTests.swift` (FakeKernel with a compound hook that concatenates topologies in order),
  `Tests/CreatorOCCTTests/AssemblyProjectionTests.swift` (`#if canImport(CreatorOCCT)`)

**Interfaces:**
- Consumes: Task 1's `DrawingView.outputs`.
- Produces: `PartSpan { output: NodeID; faces: Range<Int>; curves: Range<Int> }`; `PartSolids { output: NodeID; solids: [Solid]; curves: [Curve] }`;
  `PartLayout { solids: [Solid]; curves: [Curve]; spans: [PartSpan]; shared: [(part: NodeID, other: NodeID)] }` (not `Hashable`: a value of the moment);
  `PartSpan.layout(_ parts: [PartSolids]) -> PartLayout` (R2: the one span rule, consumed by `DrawingProjector` here and by the app's refresh in Task 12);
  `ViewContent.parts: [PartSpan]`; `Topology.restricted(toFaces range:
  Range<Int>) -> Topology` (faces at those positions, edges whose every face lies among them, IDs unchanged); `DrawingProjector.content(for view:
  DrawingView, scale: Double, parts: [DrawingSourceContent], previous: ViewContent?) async -> ViewContent` (R2; the single-Output `content(for:scale:source:previous:)`
  unchanged); R2's sentences as `DrawingProjector` statics: `partFailedSentence(name:message:)`, `partRemovedSentence`, `partEmptySentence(name:)`,
  `partMeshesSentence(name:count:)`, `sharedSolidSentence(name:other:)`.

- [ ] **Step 1: Tests.**
  - `AssemblyContentTests`: `spansFollowFaceCounts` (parts of 6, 7 and 6 faces: spans 0..<6, 6..<13, 13..<19; curves likewise); `layoutIsTheProjectorsSpans`
    (`PartSpan.layout` of the parts' solids equals the `ViewContent.parts` the projector returns, for a plain assembly, one with a shared solid and a section);
    `aSharedSolidsSpanIsEmptyAtTheRunningCount` (parts A [s1], B [s1, s2]: solids [s1, s2], A's faces 0..<6, B's 6..<12 for s2 alone, `shared` [(B, A)]; parts
    A [s1], B [s1]: B's span 6..<6); `hatchesGoByPart` (a section of an assembly whose first part has two solids: both of its solids' regions carry part 0,
    the second part's part 1; a single-Output view of two solids keeps 0 and 1); `restrictedKeepsOnlyThePart`
    (the middle span: 7 faces, only edges between them, IDs as in the compound); `aFailedPartFailsTheView` (the previous lines kept, `isPending` false,
    problem "“Bolt” can't be drawn: …"); `anEvaluatingPartKeepsTheViewPending`; `aRemovedPartIsLeftOutWithAWarning` (the others drawn, the sentence once;
    every part removed: `removedSentence`); `anEmptyPartIsLeftOut`; `meshesWarnPerPart` (“Board”'s 3 meshes: the exact sentence); `aSharedSolidIsDrawnOnce`
    (the same `Solid` in two parts: one compound entry, the second span empty, the sentence); `allPartsMeshesIsOnlyMeshes` (DR-1's sentence);
    `aSectionOfAnAssemblyHasSpansOverTheRemainders` (FakeKernel's section hook cuts one part away: its ranges empty); `aDetailCopiesItsParentsSpans`;
    `aSingleOutputViewHasNoSpans` (DR-1's path: `parts == []`, cache key unchanged).
  - `AssemblyProjectionTests` (OCCT): `partsHideEachOther` (a 20 mm cube in front of a 40 mm cube along Front's direction: the big cube's edges behind the
    small one are hidden or cut, the small cube's all visible); `compoundKeepsPartFaceOrder` (the compound of three solids: faces 0..<6 carry the first
    solid's tags, and so on); `twinCopiesProjectApart` (one Box moved twice: two spans, each edge's source in its own span).
- [ ] **Step 2: Run** `swift test --filter 'AssemblyContentTests'` and `--filter AssemblyProjectionTests`; fail.
- [ ] **Step 3: Implement** R2.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`, `--filter CreatorOCCTTests`; pass.
- [ ] **Step 5: Commit** "Drawings: assembly views projected as one compound with part spans".

### Task 3: Anchors on parts

**Files:**
- Modify: `Anchors/DrawingAnchorResolver.swift` (`scope(of:in:parts:)`, `resolve(_:in:frame:parts:)` with no default), `Anchors/LostReason.swift`
  (`.partNotShown`; R3's rewording), `Anchors/HoleReader.swift` and `Dimensions/DrawingMeasure.swift` (scoped topology), `Picks/DrawingPick.swift`
  (`anchor(…, parts: [PartSpan]?)`: restrict, judge, wrap; `PickPurpose.balloon`, `PickWording.balloons`, R16's balloon sentences),
  `Picks/PickCandidate.swift` (`balloonFreeCurveSentence`), `Picture/AnnotationComposer.swift` (`AnnotationViewState.annotated` carries the spans;
  `AnnotationContext.parts`), `AnnotationComposer+Kinds.swift`, `AnnotationComposer+Notes.swift`, `AnnotationComposer+Symbols.swift`,
  `AnnotationEvaluator+Symbols.swift`, `Picture/AnnotationRefresh.swift` (`parts`, `isPictorial`, R21), and every other resolve call the compiler finds
  (`CreatorDrawingEditor/DrawingEditorModel+Symbols.swift`, `+SymbolInspector.swift`, `+Picking.swift` pass the content's spans)
- Test: `Tests/CreatorDrawingTests/PartAnchorTests.swift`, `AnchorResolverTests.swift` and `AnnotationRefreshTests.swift` (additions), and every test that pins
  the old `.several` / `.severalFaces` text (grep "never guesses which")

**Interfaces:**
- Consumes: Task 1's `onPart`, Task 2's `PartSpan`, `restricted(toFaces:)`.
- Produces: `DrawingAnchorResolver.scope(of target: AnchorTarget, in topology: Topology, parts: [PartSpan]) -> Result<(target: AnchorTarget, topology:
  Topology), LostReason>`; `resolve(_ target: AnchorTarget, in topology: Topology, frame: ProjectionFrame, parts: [PartSpan]) -> AnchorResolution`;
  `LostReason.partNotShown`; `DrawingPick.anchor(for:click:purpose:topology:frame:mapping:isIsometric:parts:)` (`parts` nil for a single-Output view);
  `PickPurpose.balloon`; `AnnotationRefresh.lastGood(for:topology:frame:format:standard:parts:isPictorial:)` and `lostReason(of:…:parts:isPictorial:)`.

- [ ] **Step 1: Tests** (fixture: an assembly topology of two copies of one box, identical tags, spans 0..<6 and 6..<12, Front frame).
  - `PartAnchorTests`: `aPickInAnAssemblyIsWrapped` (an edge of the second copy: `.onPart(second, .edge(pick))`, `matchCount` 1 within its part);
    `twinPartsEachHoldTheirOwnEdge` (the same key wrapped for each copy resolves to that copy's edge ID); `withoutWrappingTwinsAreSeveral` (the bare pick
    resolves `.several(2)` against the compound); `aSingleViewNeverWraps` (`parts` nil: DR-2's result unchanged); `anUntickedPartLosesItsAnchors`
    (spans without the part: `.partNotShown` with its sentence); `aCurveOnNoPartIsRefused`; `holeCalloutsReadTheirPart` (a hole in copy 2 read through
    the scoped topology); `aDimensionBetweenTwoParts` (anchors on both copies, each held, the measured distance between them); `balloonPicksTakeWhatLeadersTake`
    (an edge, a circle, an outline, a corner's edge; in an isometric view too); `balloonRefusalsSayBalloon` (an unnamed edge: `balloonNoEdgeNameSentence`;
    the same edge for `.leader` keeps DR-2's sentence).
  - `AnchorResolverTests`: `severalSaysADrawingNeverGuesses` (the exact new sentences for edges and faces).
  - `AnnotationRefreshTests`: `pictorialViewsRefreshNoDimensionsOrSymbols` (a held dimension and a datum in a view marked pictorial: nil from both functions);
    `aPartAnchorRefreshes` (an onPart dimension with spans: its `LastGood`).
- [ ] **Step 2: Run** `swift test --filter 'PartAnchorTests|AnchorResolverTests|AnnotationRefreshTests'`; fail.
- [ ] **Step 3: Implement** R3, R16's pick wording and R21's pictorial refresh. DR-1 to DR-4 tests unchanged except the reworded sentences.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`, `--filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: anchors name their part in assembly views".

### Task 4: Item numbers and balloons on the sheet

**Files:**
- Create: `Sources/CreatorDrawing/Items/PartItems.swift` (`wanted`, `numbered`, `NumberedItem`), `Sources/CreatorDrawing/Items/PartFacts.swift`,
  `Sources/CreatorDrawing/Style/BalloonStyle.swift`, `Sources/CreatorDrawing/Layout/BalloonLayout.swift`,
  `Sources/CreatorDrawing/Picture/AnnotationComposer+Balloons.swift`
- Modify: `Sheet/TitleBlockFacts.swift` (`parts`), `Picture/AnnotationComposer.swift` (dispatch), `Picture/AnnotationPass.swift` (numbering once per compose
  from the document and `PartItems.names(of: facts.parts)`), `Picture/SheetComposer.swift` (passes facts to the pass), `Picture/AnnotationRefresh.swift` (balloons return nil)
- Test: `Tests/CreatorDrawingTests/PartItemsTests.swift`, `Tests/CreatorDrawingTests/BalloonComposerTests.swift`, `Tests/CreatorDrawingTests/BalloonLayoutTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces: `PartItems.wanted(in document: DrawingDocument) -> [NodeID]`, `PartItems.numbered(_ document: DrawingDocument, names: [NodeID: String]) ->
  [NumberedItem]`, `NumberedItem { part: NodeID; number: Int; material: String; partNumber: String }`, `[NumberedItem].number(of part: NodeID) -> Int?`,
  `PartItems.pinningOrder(_ document: DrawingDocument, names: [NodeID: String]) -> [PartItem]` (R5: the current numbered order written as `items`, each entry's
  material and part number kept, entries of parts no longer wanted kept after them); `PartItems.names(of facts: [NodeID: PartFacts]) -> [NodeID: String]`
  (every entry's name, a removed part's remembered one included; an entry whose name is "?" (no remembered name) left out, so it sorts last);
  `PartFacts { name: String; quantity: Int?; isRemoved: Bool }`, `TitleBlockFacts.parts: [NodeID: PartFacts]` (default empty); `BalloonStyle { text 2, radius 2, padding 0.5 }`
  (factors of h, `static func of(_ standard:)`); `BalloonLayout.draw(number: String, center: Vector2, foot: Vector2?, h: Double, style: AnnotationStyle) ->
  AnnotationDrawing`.

- [ ] **Step 1: Tests.**
  - `PartItemsTests`: `wantedFollowsSheetsViewsAndParts` (two sheets, an assembly view and a single view, a balloon on a part no view shows: that order, each
    once); `unpinnedPartsGoByName` (names "Plate", "Bolt", "Nut": Bolt 1, Nut 2, Plate 3; equal names by NodeID); `pinnedPartsComeFirst` (`items` [Plate]:
    Plate 1, Bolt 2, Nut 3); `numbersHaveNoGaps` (an item whose part is no longer wanted takes no number); `aRemovedPartKeepsItsNumber` (Bolt 1, Nut 2,
    Plate 3 unpinned; Plate's facts become `isRemoved` with its remembered name "Plate": still Bolt 1, Nut 2, Plate 3; Bolt removed the same way: still 1);
    `aPartWithNoNameSortsLast` (a removed part with no remembered name, wanted through a balloon: after Bolt, Nut and Plate, whatever its NodeID); `editingAnItemPinsTheOrder` (the helper
    `PartItems.pinningOrder(_:names:)` writes the current order into `items` with each entry's material kept); `aPartWithNoBalloonIsListed`.
  - `BalloonLayoutTests` (h 2.5): `theCircleAndNumber` (radius 5, number cap 5 centred: run centre x and cap middle y within 1e-9 of the centre);
    `aWideNumberWidensTheCircle` ("123"); `theLeaderStartsOnTheCircle` (the line's first point at centre + 5 × unit(foot − centre); the arrowhead's tip on the
    foot); `aFootInsideTheCircleDrawsNoLeader`; `everythingIsOnTheDimensionLayer`.
  - `BalloonComposerTests` (fixture: the two-copy assembly of Task 3 on a sheet, a balloon on each copy): `balloonsShowTheirItemNumbers` (names "Left",
    "Right": the texts "1" and "2"); `balloonsAndListAgree` (the report labels "Balloon 1", "Balloon 2" and `numbered` give the same numbers; after renaming
    "Left" to "Z" both read the swap); `aBalloonFollowsItsEdge` (the copy's edge moved: the foot moved, held); `aLostBalloonKeepsItsNumber` (the part unticked:
    `.partNotShown`, every piece `isLost`, the text "1?", listed); `aLostBalloonWithNoLastGoodIsALoneQuestionMark`; `aBalloonInAnIsometricView` (held, its foot on
    the projected ellipse nearest the hint); `aBalloonRemembersItsFoot` (`current` is `.leaders([foot])` with `lines` ["1"]); `refreshSkipsBalloons`.
- [ ] **Step 2: Run** `swift test --filter 'PartItemsTests|BalloonLayoutTests|BalloonComposerTests'`; fail.
- [ ] **Step 3: Implement** R4's drawing and lost rules, R5.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: item numbers and balloons".

### Task 5: The parts list, the revision table and the title block

**Files:**
- Create: `Sources/CreatorDrawing/Sheet/PartsListLayout.swift`, `Sources/CreatorDrawing/Sheet/RevisionTableLayout.swift`,
  `Sources/CreatorDrawing/Sheet/SheetTable.swift` (the shared row and cell drawing: `TableColumn`, lines, fitted cells),
  `Sources/CreatorDrawing/Picture/AnnotationComposer+Tables.swift`, `Sources/CreatorDrawing/Model/GreyPixels.swift`, `Sources/CreatorDrawing/Model/LogoLimits.swift`
- Modify: `Sheet/TitleBlockLayout.swift` (`revisionShown`; the logo in the owner field, `logoMaximumWidth`, `logoRect`), `Sheet/TitleBlockFacts.swift`
  (`logo: LogoFact?`), `Sheet/SheetNotesLayout.swift` (`base`), `Picture/SheetComposer.swift` (the notes' base when a parts list stands on the block; the logo
  notice), `Picture/SheetPicture.swift` (`images`, `SheetImage`, `append`)
- Test: `Tests/CreatorDrawingTests/PartsListLayoutTests.swift`, `RevisionTableLayoutTests.swift`, `TitleBlockTests.swift` (additions), `SheetNotesTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 and 4.
- Produces: `PartsListLayout.rowHeight = 7`, `PartsListLayout.height(rows: Int) -> Double` (rows + header), `PartsListLayout.columns(for: DrawingStandard,
  showsPartNumber: Bool) -> [TableColumn]`, `PartsListLayout.draw(_ items: [NumberedItem], facts: [NodeID: PartFacts], bottomRight: Vector2, standard:
  DrawingStandard, h: Double) -> AnnotationDrawing`; `RevisionTableLayout.columns(for:)`, `RevisionTableLayout.draw(_ table: RevisionTable, topRight: Vector2,
  standard: DrawingStandard, h: Double) -> AnnotationDrawing`; `TableColumn { title: String; width: Double; alignment: .centred / .left }`; `GreyPixels`
  (R12); `SheetImage`; `SheetPicture.images`; `LogoFact` (`.picture(GreyPixels)`, `.unreadable(String)`); `TitleBlockFacts.logo`; `LogoLimits.maximumBytes`,
  `maximumSide`; `TitleBlockLayout.logoMaximumWidth = 40`, `logoLabelGap = 1`, `logoBand(in owner: Rect2D) -> Rect2D` (R11: 5 mm tall below the label),
  `logoRect(width: Int, height: Int, in owner: Rect2D) -> Rect2D`;
  `SheetNotesLayout.picture(for:settings:format:base: Double? = nil)`; `SheetComposer.logoUnreadableSentence(_ reason: String) -> String`.

- [ ] **Step 1: Tests.**
  - `PartsListLayoutTests` (h 2.5, ISO): `theHeaderIsAtTheBottom` (header labels "Item", "Qty", "Name", "Part number", "Material" in the bottom row; item 1 one row
    above); `columnsAddUpTo180` (both standards, with and without the part-number column); `asmeColumnsRunTheOtherWay` ("QTY" left, "ITEM" right);
    `noPartNumberNoColumn`; `aLongNameIsFitted` (shrunk, then cut with "…"); `unknownQuantityReadsAQuestionMark`; `linesOnFrameCellsOnText` (outline width
    `DrawingStyle.frame`, inner `zone`); `anEmptyListDrawsItsHeader`.
  - `RevisionTableLayoutTests`: `theHeaderIsAtTheTop` (rows below, oldest first); `columnsAndLabels` (ISO and ASME); `typedTextIsFitted`.
  - `TitleBlockTests`: `theRevisionFieldFollowsTheTable` (the block's revision text "C" with rows A to C; the typed one without); `theLogoSitsInTheOwnerField`
    (the owner field 0..110 × 30..40: the band is x from 1.5, y 31.5..36.5; a 200 × 100 logo: rect 10 × 5 at (1.5, 31.5); a 1000 × 50 one: 40 × 2, centred in
    the band at y 33..35; the owner text starts 1.5 mm right of the rect; **the rect does not overlap the label's text**: for both standards ("Owner",
    "COMPANY") the rect's top lies at least 0.4 mm below the label run's lowest point (its baseline 37.5 minus Helvetica's descender at the label height, about
    36.98), and the rect lies inside the field); `noLogoNoImage`;
    `anUnreadableLogoGivesANotice` (on screen only: the exact sentence, `isNotice`).
  - `SheetNotesTests`: `notesStandAboveAStandingPartsList` (bottom line `notesGap` above the list's top); `aFreePartsListLeavesTheNotesOnTheBlock`.
- [ ] **Step 2: Run** `swift test --filter 'PartsListLayoutTests|RevisionTableLayoutTests|TitleBlockTests|SheetNotesTests'`; fail.
- [ ] **Step 3: Implement** R7, R9's layout, R11's placement, R12's types; tables drawn through the annotation pass (free annotations, report labels "Parts list",
  "Revision table", held).
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: the parts list, the revision table and the title block's logo".

### Task 6: Images in the PDF, the DXF's stand-in, and the SVG writer

**Files:**
- Create: `Sources/CreatorDrawing/Export/SVGWriter.swift`, `Sources/CreatorDrawing/Export/GreyPNG.swift`
- Modify: `Export/PDFWriter.swift` (R13's XObjects), `Export/DXFWriter.swift` (the image rectangle; `DXFOutput.leftOutImages: Bool`),
  `Text/HelveticaMetrics.swift` (`unicode(forWinAnsi:)`), `Tests/CreatorDrawingTests/Support/DrawingFixtures.swift` (`assemblySheet(standard:) -> SheetPicture`:
  a two-part assembly view, three balloons, the parts list standing, a revision table with two rows, a 4 × 3 synthetic `GreyPixels` logo)
- Test: `Tests/CreatorDrawingTests/SVGWriterTests.swift`, `GreyPNGTests.swift`, `PDFWriterTests.swift` and `DXFWriterTests.swift` (additions),
  `Tests/CreatorDrawingTests/Support/SVGStructureReader.swift` (a small reader: element names, attributes, the `<g id>` order)

**Interfaces:**
- Consumes: Task 5's `SheetPicture.images`.
- Produces: `SVGWriter.write(_ page: SheetPicture, title: String) -> SVGOutput` (`data: Data`, `replacedTexts: [String]`); `GreyPNG.encode(_ pixels: GreyPixels)
  -> Data`; `HelveticaMetrics.unicode(forWinAnsi byte: UInt8) -> Unicode.Scalar?`; `DXFOutput.leftOutImages`.

- [ ] **Step 1: Tests.**
  - `GreyPNGTests`: `aPNGOfFourPixels` (signature, IHDR colour type 0 bit depth 8, IDAT a zlib stream of stored blocks whose Adler-32 and every chunk CRC check;
    the bytes pinned by SHA-256); `aRowLongerThanABlockSplits` (a 70,000-byte image: two stored blocks).
  - `SVGWriterTests`: `theSheetIsInMillimetres` (width "420mm", viewBox "0 0 420 297", the flip matrix); `layersInOrder` (`<g id>` in `DrawingLayer.allCases`
    order, empty ones absent); `strokesMatchThePDFsPath` (a line, a polyline and an arc: the same coordinates as the PDF content stream's path, `C` for arcs);
    `dashesFollowTheStandard` (hidden `stroke-dasharray` "3 1.5" in ISO); `textsCarryTheirWidth` (`textLength` equals the run's width; "Ø20" written as
    UTF-8 "Ø20"; "<" escaped); `theLogoIsAPNG` (an `<image>` with `data:image/png;base64,` decoding to `GreyPNG.encode`'s bytes, at the rect, `preserveAspectRatio="none"`);
    `theLogoIsUpright` (a 4 × 3 logo whose top row is black and the rest white, at rect (10, 20)–(14, 23): composing the image's own transform with the group's
    flip maps the image's local (x0, y0), where SVG draws row 0, to sheet (10, 23), the rect's top, and (x0, y1) to (10, 20), the bottom; the transform text is
    exactly `matrix(1 0 0 -1 0 43)`); `noticesAreNotWritten`;
    `svgDigest` (`DrawingFixtures.assemblySheet()`: SHA-256 pinned; two writes equal).
  - `PDFWriterTests`: `assemblyPageDigest` (pinned); `imagesFollowThePages` (the reader finds the pages' objects where DR-1 put them and one `/Image` after them,
    `/Width 4 /Height 3 /DeviceGray /BitsPerComponent 8`, its stream 12 bytes); `aLogoOnTwoPagesIsOneObject`; `noImagesNoChange` (DR-1 to DR-4 digests unchanged).
  - `DXFWriterTests`: `theLogoIsARectangleOnFrame` (an LWPOLYLINE of the logo's rect on FRAME; `leftOutImages` true); `balloonsOnDimensionTablesOnFrameAndText`
    (every entity of a balloon on DIMENSION; table lines and header labels on FRAME, cells on TEXT); `assemblySheetDXFDigest` (pinned, two writes equal).
- [ ] **Step 2: Run** `swift test --filter 'GreyPNGTests|SVGWriterTests|PDFWriterTests|DXFWriterTests'`; fail.
- [ ] **Step 3: Implement** R13 and R14.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: SVG export, logos in the PDF and the DXF's stand-in".

### Task 7: Templates: the model, the file, the folder and the store

**Files:**
- Create: `Sources/CreatorDrawing/Templates/DrawingTemplate.swift`, `Sources/CreatorDrawing/Templates/DrawingTemplateFile.swift`
  (`encode`, `decode`, `DrawingTemplateProblem`, `DrawingTemplateLimits`), `Sources/CreatorStyle/UserDataFolder.swift`,
  `Sources/CreatorDrawingEditor/Templates/DrawingTemplateFolder.swift`, `Sources/CreatorDrawingEditor/Templates/DrawingTemplateStore.swift`,
  `Sources/CreatorGeometry/Files/RegularFile.swift` (R23)
- Modify: `Sources/CreatorStyle/ThemeFolder.swift` (reads `UserDataFolder.url`; behaviour unchanged), `Sources/CreatorGraph/Images/ImageResolver.swift`
  (`openedRegularFile` and `read` over `RegularFile`, problems mapped as now)
- Test: `Tests/CreatorDrawingTests/DrawingTemplateFileTests.swift`, `Tests/CreatorDrawingEditorTests/DrawingTemplateStoreTests.swift` (a temporary folder made
  and removed by each test), `Tests/CreatorGeometryTests/RegularFileTests.swift`, `Tests/CreatorStyleTests/ThemeFolderTests.swift` and the `ImageResolver`
  tests in `Tests/CreatorGraphTests` (unchanged; must still pass)

**Interfaces:**
- Consumes: Task 1's `TitleBlock`, Task 5's `LogoLimits`.
- Produces: R10's `DrawingTemplate` with `static func made(from sheet: DrawingSheet, standard: DrawingStandard, logo: Data?, name: String, id: String) ->
  DrawingTemplate` (keeps only owner, drawn by, material and density); `DrawingTemplateFile.encode(_ template: DrawingTemplate) -> Data`,
  `DrawingTemplateFile.decode(_ data: Data, id: String) throws(DrawingTemplateProblem) -> DrawingTemplate` (`DrawingTemplateProblem.message` is the part after
  "was skipped:"); `DrawingTemplateLimits.maximumFileBytes = 3_145_728`; `RegularFile.read(_ url: URL, limit: Int) throws(RegularFileProblem) -> Data`
  and `RegularFileProblem` (R23); `UserDataFolder.url: URL`; `DrawingTemplateFolder` (`url`, `static var applicationSupport`, `static func isUsable(_ id:
  String) -> Bool`, `load() -> (templates:, problems:)` (each file through `RegularFile.read` with the template limit, its stem the id),
  `save(_:) throws(DrawingTemplateProblem)`, `remove(_ id:) throws(DrawingTemplateProblem)`, each failure's message R10's "couldn't be saved" / "couldn't be
  deleted" sentence); `@MainActor @Observable public final class DrawingTemplateStore`
  (`init(folder: DrawingTemplateFolder? = nil)`, `templates: [DrawingTemplate]`, `loadProblems: [String]`, `saveProblem: String?`, `add(_:)` (unique name by
  " 2"…; an id that isn't usable sets `saveProblem` and adds nothing), `rename(_ id: String, to name: String)` (trimmed; blank refused "A template needs a name."), `remove(_ id: String)`, `template(_ id: String) ->
  DrawingTemplate?`, `uniqueName(_ base: String) -> String`).

- [ ] **Step 1: Tests.**
  - `DrawingTemplateFileTests`: `aTemplateRoundTrips` (with and without a logo; keys sorted; base64 logo); `onlyTheDefaultsAreKept` (`made(from:)` drops title,
    number, revision, date and the logo hash); `badTemplatesAreSkippedInWords` (not JSON, a missing `size`, version 2, a 2.5 MB logo, bad base64: R10's four
    messages exactly); `unknownKeysAreIgnored`.
  - `RegularFileTests` (a temporary folder): `aSmallFileIsRead`; `aFileAtTheLimitIsRead` (limit bytes exactly); `aLargerFileIsRefusedFromItsSize` (a 1 GB sparse
    file made with `FileHandle.truncate(atOffset:)`: `.tooLarge(size: 1_073_741_824)`, the size the descriptor reported, so nothing was read); `aFolderIsNotAFile`;
    `aFIFOIsNotAFile` (`mkfifo`, not on Windows: refused at once, never blocking); `aMissingFileIsUnreadable` (the system's sentence).
  - `DrawingTemplateStoreTests`: `aMemoryStoreSavesNothing` (folder nil: add, rename, remove, no file); `changesAreSavedAtOnce` (a folder: the file appears,
    renaming rewrites it, removing deletes it); `templatesSortByName` ("b", "A", "c": A, b, c); `namesAreUnique` ("Acme" twice: "Acme", "Acme 2");
    `aBlankNameIsRefused`; `skippedFilesAreListed` (a damaged file in the folder: one `loadProblems` sentence naming it; the good ones load);
    `aHugeTemplateIsSkippedUnread` (a 1 GB sparse `.mctemplate`: "“big.mctemplate” was skipped: it is larger than 3 MB.", the others load);
    `aFolderNamedLikeATemplateIsSkipped` ("… it isn't a file."); `theStemIsTheID` (a file `X.mctemplate` loads with id "X"; a template added with a UUID id
    is written as `<uuid>.mctemplate` and reloads with that id); `anUnusableIDIsRefused` (id "../a": `saveProblem` "“Acme” couldn't be saved: its id can't be
    a file name.", nothing added, no file); `aFailedSaveLeavesTheStore` (a read-only folder: `saveProblem` the "couldn't be saved" sentence, `templates`
    unchanged; a failed remove: "“Acme” couldn't be deleted: …", the template kept).
- [ ] **Step 2: Run** `swift test --filter 'DrawingTemplateFileTests|DrawingTemplateStoreTests|RegularFileTests|ThemeFolderTests'`; fail.
- [ ] **Step 3: Implement** R23's reader (lifted out of `ImageResolver` first, its tests green) and R10's model, file, folder and store.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`, `--filter CreatorDrawingEditorTests`, `--filter CreatorStyleTests`, `--filter CreatorGeometryTests`,
  `--filter CreatorGraphTests`; pass.
- [ ] **Step 5: Commit** "Drawings: templates kept as an app preference".

### Task 8: The editor's Assembly View, Balloon, Parts List and Revision Table tools

**Files:**
- Create: `Sources/CreatorDrawingEditor/BalloonDraft.swift`, `Sources/CreatorDrawingEditor/DrawingEditorModel+Assembly.swift` (placing, `setParts`,
  `setPart`), `Sources/CreatorDrawingEditor/DrawingEditorModel+Balloons.swift` (clicks, draft, placing), `Sources/CreatorDrawingEditor/DrawingEditorModel+Tables.swift`
  (placing, standing)
- Modify: `DrawingTool.swift` (R16's cases, titles, `isAnnotationTool`), `DrawingStepName.swift` (R16's names, in `all`), `DrawingEditorModel.swift`
  (`balloonDraft`; `replaceDocument` pruning), `DrawingEditorModel+Pointer.swift`, `DrawingEditorModel+Annotations.swift` (Esc order),
  `DrawingEditorModel+AnnotationSelection.swift` (moves and nudges of R16, group names by kind), `DrawingEditorModel+Picking.swift` (the content's spans to
  every pick; a balloon's purpose and its reattach rule), `DrawingEditorModel+Views.swift` (descendants carry `assembly`), `DrawingEditorModel+DerivedViews.swift`
  (derived views copy `assembly`), `Views/SheetCanvasInput.swift` (B, P)
- Test: `Tests/CreatorDrawingEditorTests/AssemblyToolTests.swift`, `BalloonToolTests.swift`, `TableToolTests.swift`, `DrawingStepNameTests.swift` and
  `SheetCanvasInputTests.swift` (additions), `ReattachTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: `DrawingTool.assemblyView`, `.balloon`, `.partsList`, `.revisionTable`; `public internal(set) var balloonDraft: BalloonDraft?` (`BalloonDraft { view:
  ViewID; anchor: PickedAnchor; hint: Vector2 }`); `setParts(_ parts: [NodeID], of id: ViewID)` (refusing an empty list with R1's sentence),
  `setPart(_ part: NodeID, shown: Bool, of id: ViewID)`; `standPartsListOnTitleBlock()`, `moveRevisionTableToCorner()`; R16's `DrawingStepName` statics
  (`addBalloon` … `cut`).

- [ ] **Step 1: Tests** (fixtures: `AnnotationEditorFixtures` extended with three sources and a two-copy assembly content with spans).
  - `AssemblyToolTests`: `theToolPlacesEveryOutput` (three sources: `assembly` the three in order, Front, "Add View", selected); `aFirstViewSetsTheScaleFromAllParts`;
    `projectedViewsCarryTheParts` (a Top view dropped from it: the same `assembly`); `turningAPartOffChangesDescendants` ("Change Parts"); `theLastPartStays` (R1's
    sentence, nothing committed); `withNoOutputItRefuses` (no sources: DR-1's "Add an Output node and wire the part into it first.", the one
    `DrawingEditorModel+Views` already gives for a base view, nothing committed).
  - `BalloonToolTests`: `aBalloonOnALine` (B, a click on copy 2's edge, a click 15 mm up-right: one "Add Balloon", target `.onPart(copy 2, …)`, `offset` = click −
    foot, selected, tool kept); `aBalloonInASingleView` (unwrapped target); `isometricViewsTakeBalloons`; `aBalloonRefusesAFreeCurve` (the sentence);
    `escapeDropsTheTargetThenTheTool`; `theDraftFollowsThePointer`; `draggingABalloonMovesItsOffset` ("Move Balloon", coalesced); `nudgingABalloon`;
    `deletingABalloon` ("Delete Balloon"); `aMixIsMoveAnnotations`.
  - `TableToolTests`: `aPartsListStandsOnTheBlockNearIt` (a click 6 mm from the block's top right: `bottomRight` nil, "Add Parts List"); `aPartsListElsewhereIsFree`;
    `aSecondPartsListIsRefused` (the sentence); `aRevisionTableSnapsToTheCorner`; `aSecondRevisionTableIsRefused`; `draggingAStandingListFreesIt` ("Move Parts
    List"); `standingAgain` (`standPartsListOnTitleBlock`: nil, "Move Parts List"); `deletingTables` ("Delete Parts List", "Delete Revision Table").
  - `ReattachTests`: `aLostBalloonReattachesOnItsPart` ("Reattach Balloon"); `aBalloonRefusesAnotherPart` (R4's sentence, nothing committed).
  - `DrawingStepNameTests`: R16's nineteen names in `all`, each made by its method (the setters' in Task 9, Paste and Cut in Task 11).
  - `SheetCanvasInputTests`: `theLettersBAndPChooseTools` (lower and capital).
- [ ] **Step 2: Run** `swift test --filter 'AssemblyToolTests|BalloonToolTests|TableToolTests|ReattachTests|DrawingStepNameTests|SheetCanvasInputTests'`; fail.
- [ ] **Step 3: Implement** R1's editor side and R16's flows.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: the Assembly View, Balloon, Parts List and Revision Table tools".

### Task 9: The editor's setters: items, revisions, logos, templates and sheet names

**Files:**
- Create: `Sources/CreatorDrawingEditor/DrawingEditorModel+Items.swift`, `Sources/CreatorDrawingEditor/DrawingEditorModel+Revisions.swift`,
  `Sources/CreatorDrawingEditor/DrawingEditorModel+Templates.swift`, `Sources/CreatorDrawingEditor/DrawingEditorRequest.swift`
- Modify: `DrawingEditorEvents.swift` (`requested`), `DrawingEditorModel.swift` (`templateChoices`, `partFacts`, `rememberedPartNames`), `DrawingEditorModel+Sheets.swift` (unique duplicate names,
  rename trimming: R21), `DrawingEditorModel+Inspector.swift` (the title block's Revision field refuses while a revision table has rows: "The revision comes from
  the revision table.")
- Test: `Tests/CreatorDrawingEditorTests/ItemModelTests.swift`, `RevisionModelTests.swift`, `TemplateModelTests.swift`, `SheetEditingTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1, 4, 7, 8.
- Produces (each one step named as R16 says, committing nothing when unchanged): `setItemMaterial(_ text: String, of part: NodeID)`, `setItemPartNumber(_ text:
  String, of part: NodeID)` (both "Change Item", trimmed, both through `PartItems.pinningOrder`), `moveItem(_ part: NodeID, by offset: Int)` ("Move Item"; at an
  end nothing); `addRevision()` ("Add Revision"; with no table refuses "Add a revision table first."), `setRevision(_ field: RevisionField, text: String, row: Int)`
  (`RevisionField` `.description`, `.date`, `.approved`; "Change Revision"), `removeLastRevision()` ("Remove Revision"); `setLogo(_ hash: String?, of sheet:
  SheetID)` ("Change Logo"); `addSheet(from template: DrawingTemplate, logo: String?)` ("Add Sheet", R10); `public var templateChoices: [DrawingTemplateChoice]`
  (`DrawingTemplateChoice { id: String; name: String }`, set by the app); `public var partFacts: [NodeID: PartFacts]` (R5: set by the app from the same facts
  build it hands the composer, so every item setter pins with `PartItems.pinningOrder(document, names: PartItems.names(of: partFacts))`); `public
  internal(set) var rememberedPartNames: [NodeID: String]` and `rememberPartNames(_ names: [NodeID: String])` (R5: in memory, never an edit; seeded from
  `document.partNames` by `replaceDocument`; `documentForSaving()` writes the wanted parts' names into `partNames`); `request(_ request: DrawingEditorRequest)` passing to `events.requested`;
  `DrawingEditorRequest` cases `newSheetFromTemplate(String)`, `saveSheetAsTemplate(SheetID)`, `chooseLogo(SheetID)`, `renameTemplate(String, to: String)`,
  `deleteTemplate(String)`; `DrawingEditorEvents.requested: @MainActor (DrawingEditorRequest) -> Void` (default does nothing).

- [ ] **Step 1: Tests.**
  - `ItemModelTests`: `settingAMaterialNeverRenumbers` (unpinned Bolt 1, Nut 2, Plate 3; Plate's material "S235": `items` the three in that order, numbers
    unchanged, one "Change Item"); `movingAnItem` (Nut up: Nut 1, Bolt 2, Plate 3, "Move Item"); `movingPastTheEndDoesNothing`; `sameValueNoCommit`;
    `aNewPartFollowsThePinned` (after a pin, a fourth part named "Axle" numbers 4); `pinningKeepsTheNumbersShown` (four parts with `partFacts` names
    "Plate", "Bolt", "Nut" and a removed "Axle": the numbers `PartItems.numbered(document, names: PartItems.names(of: partFacts))` gives before a material edit
    equal the numbers after it, part for part, and `items` lists them in that order); `rememberedNamesAreSaved` (`rememberPartNames` of two parts, one no
    longer wanted: `documentForSaving().partNames` holds only the wanted one; no undo step, nothing committed); `openingSeedsRememberedNames`.
  - `RevisionModelTests`: `aNewRevisionHasNoDate` (letter A, description, date and approved empty; then B); `revisionsSkipTheStandardsLetters` (after H comes
    J, after N comes P); `typedFieldsAreStored` ("Change Revision"); `onlyTheLastIsRemoved` ("Remove Revision"); `withoutATableAddRevisionRefuses`;
    `theTitleBlockRevisionIsRefusedWhileTheTableHasRows` (the sentence; nothing committed).
  - `TemplateModelTests`: `aSheetFromATemplate` (size, orientation, owner, drawn by, material, density and logo from it; title empty; today's date; "Sheet 2");
    `theStandardOnlyOnTheFirstSheet` (an ASME template on an empty ISO drawing: ASME; on a drawing with a sheet: still ISO); `requestsReachTheHost`
    (`saveSheetAsTemplate`, `chooseLogo`, `renameTemplate`, `deleteTemplate`, `newSheetFromTemplate` each arrive once); `settingALogo` ("Change Logo"; nil removes).
  - `SheetEditingTests`: `duplicateNamesAreUnique` ("Plate Copy", then "Plate Copy 2"); `renamingTrims` ("  Assembly  " stores "Assembly"; "   " keeps the old name,
    nothing committed).
- [ ] **Step 2: Run** `swift test --filter 'ItemModelTests|RevisionModelTests|TemplateModelTests|SheetEditingTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: editing items, revisions, logos and sheets from templates".

### Task 10: The editor's views

**Files:**
- Create: `Sources/CreatorDrawingEditor/Views/BalloonInspector.swift`, `PartsListInspector.swift`, `RevisionTableInspector.swift`, `PartsSection.swift`
  (the view inspector's Show toggles), `TemplatesSection.swift`, `SheetImageLayer.swift`
- Modify: `Views/AnnotationInspector.swift` (the three pages), `Views/ViewInspector.swift` (PARTS for assembly views, Source for the rest), `Views/SheetInspector.swift`
  (Logo row: "Choose Logo…" / "Remove Logo"; Revision read-only "From the revision table"; TEMPLATES: "Save Sheet as Template", each template's name field and
  Delete), `Views/SheetTabs.swift` (the "+" a `plus` icon `Menu`: "New Sheet", then "New Sheet from “\(name)”" per template; R21), `Views/SheetFrameLayer.swift`
  (draws `SheetImageLayer` under the ink), `Views/DrawingToolbar.swift` (doc comment: twenty-one tools), `DrawingEditorModel.swift` (`@ObservationIgnored` bitmap
  cache by key)
- Test: `Tests/CreatorDrawingEditorTests/DrawingToolbarTests.swift`, `DrawingInspectorTests.swift`, `SheetTabsTests.swift`, `SheetCanvasRenderTests.swift` (additions),
  `SheetViewEqualityTests.swift` (new properties' variants)

**Interfaces:**
- Consumes: Tasks 8 and 9; views only. Every new `.equatable()` view's `==` covers its stored properties (`expectEqualityCovers`).

- [ ] **Step 1: Tests.** `DrawingToolbarTests.everyToolHasAButtonOrMore` (twenty-one tools; Assembly View after Projected View; Balloon, Parts List and Revision
  Table after Surface Finish; overflow into More); `DrawingInspectorTests`: `aBalloonPageNamesItsItem` ("Item 2 · Right"), `aRemovedPartCanBeUnticked` (an assembly view of A, B, C with C no
  longer in `sources` and remembered as "Plate": PARTS reads A, B, then "Plate (removed)" with its toggle on; turning it off reaches `setPart(C, shown: false,
  of:)`, one "Change Parts"), `thePartsListPageEditsItems` (a material
  typed reaches `setItemMaterial`; Move Up and Down buttons; quantity "?" shown read-only), `theRevisionPageAddsAndEdits`, `anAssemblyViewShowsParts` (a toggle per
  source; no Source menu), `theSheetPageHasLogoAndTemplates`, `theRevisionFieldIsReadOnlyWithATable`; `SheetTabsTests.thePlusMenuListsTemplates`;
  `SheetCanvasRenderTests` (pixels through `PixelReader`): `aBalloonIsDrawnInInk`, `theLogoIsDrawnUnderTheInk` (a black 4 × 3 logo inks its rect),
  `aLostBalloonIsWarningColoured`.
- [ ] **Step 2: Run** `swift test --filter 'DrawingToolbarTests|DrawingInspectorTests|SheetTabsTests|SheetCanvasRenderTests|SheetViewEqualityTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: balloon, parts list, revision and template pages, and the logo on screen".

### Task 11: Copy and paste of views and annotations

**Files:**
- Create: `Sources/CreatorDrawingEditor/DrawingClipboard.swift`, `Sources/CreatorDrawingEditor/SheetCopy.swift` (the id remapping shared with
  `duplicateSheet`), `Sources/CreatorDrawingEditor/DrawingEditorModel+Clipboard.swift`
- Modify: `DrawingKey.swift` (`.copy`, `.cut`, `.paste`), `Views/SheetCanvasInput.swift` (⌘C, ⌘X, ⌘V with `.primary`; other ⌘ chords still go to the menus),
  `DrawingEditorModel+Keys.swift`, `DrawingEditorModel+Sheets.swift` (`duplicateSheet` through `SheetCopy`)
- Test: `Tests/CreatorDrawingEditorTests/ClipboardTests.swift`, `SheetCanvasInputTests.swift` (additions), `SheetEditingTests.swift` (unchanged duplicate tests must pass)

**Interfaces:**
- Consumes: Tasks 1 and 8.
- Produces: `copySelection()`, `cutSelection()` ("Cut"), `paste()` ("Paste"); `public internal(set) var clipboard: DrawingClipboard?` (`DrawingClipboard {
  sheet: SheetID; sheetScale: DrawingScale; views: [DrawingView]; annotations: [DrawingAnnotation]; pastes: Int }`); `SheetCopy.copy(views: [DrawingView], annotations:
  [DrawingAnnotation], onto sheet: DrawingSheet, offset: Vector2) -> (sheet: DrawingSheet, views: [ViewID], annotations: [AnnotationID], skipped: [String])`.

- [ ] **Step 1: Tests.** `pastingRemapsEverything` (a base view with a projected child, a section, a dimension, a datum on that dimension and a balloon, copied and
  pasted on another sheet: every id new, the child aligned to the pasted base, the section's derivation names the pasted base and has a fresh letter, the datum's
  `.dimension` attachment names the pasted dimension; one "Paste"; undo removes it all); `pastingTwiceOffsetsTwice` ((10, −10) then (20, −20)); `pastingOntoAnotherScaleKeepsTheSize` (a base view following its 1:2 sheet and its projected
  child, pasted onto a 1:5 sheet: both pasted views' `scale` is 1:2, a dimension's offset from its geometry unchanged; pasted on a 1:2 sheet: `scale` stays nil;
  a detail with its own 2:1 keeps 2:1);
  `aDerivedViewAloneIsRefused` (R18's sentence; the clipboard unchanged); `annotationsAlonePasteOnTheirSheet` (a selected note of a view, pasted on its sheet: on that
  view, moved; on another sheet: skipped with R18's sentence); `aSymbolWithoutItsDimensionIsNotPasted` (a frame on a dimension copied without the dimension, pasted on
  another sheet: skipped); `aSecondPartsListIsSkipped`; `cutIsCopyThenDelete` ("Cut", the clipboard holds them); `theClipboardIsTheEditors` (a new editor has none);
  `SheetCanvasInputTests.primaryCXVAreClipboardKeys` (⌘C, ⌘X, ⌘V on macOS, Ctrl elsewhere through `.primary`; ⌘S still nil).
- [ ] **Step 2: Run** `swift test --filter 'ClipboardTests|SheetCanvasInputTests|SheetEditingTests'`; fail.
- [ ] **Step 3: Implement** R18.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: copy and paste of views and annotations".

### Task 12: Assemblies, items, logos, templates and exports in the app

**Files:**
- Create: `Sources/CreatorApp/Drawing/DrawingSession+Assembly.swift` (requests and keys for assembly views), `Sources/CreatorApp/Drawing/DrawingSession+Logos.swift`
  (decoding and caching by hash), `Sources/CreatorApp/Drawing/AppModel+DrawingTemplates.swift` (the store, requests, Choose Logo…), `Sources/CreatorApp/AppDrawingTemplates.swift`
- Modify: `Drawing/DrawingSession.swift` (`request` and `requestKey` over `outputs`; `RequestKey` with per-part counts and states), `DrawingSession+Facts.swift` (`parts`
  facts for every sheet, removed parts with their remembered names (R5), R6's mass, the logo; the same `parts` dictionary set on `editor.partFacts`, and live
  names passed to `editor.rememberPartNames`), `AppModel+DrawingRefresh.swift` (`RefreshKey` and jobs over every part; each part's solids cut as now (the
  hatch index the part's index in `outputs`, R2 (b)), then `PartSpan.layout` for the shown solids and the spans, never a span rule of its own; `isPictorial`),
  `AppModel+DrawingExport.swift` (assembly refusals by part, `pdfSheet`, `svgSheet`, R15's warning order and the logo's DXF warning, balloons in the DXF of a view with
  annotations (R15; through DR-2's model-millimetre mapping, wherever it lives), `drawingExportPlan(_:sheet:view:)` for MCP), `Export/DrawingExportKind.swift`, `ContentType+MetalCreator.swift` (`.svg`), `AppCommands.swift` and the top bar's Export menu (titles),
  `Sources/CreatorNodes/Fields/GreyImageDecoder.swift` and `GreyImageDecoder+MetalUI.swift` (`GreyBackground`, `decode(_:background:)`), `Sources/MetalCreatorApp/main.swift`
  (the template store, as the theme store), the save path (it already saves `editor.documentForSaving()`, which carries `partNames` since Task 9; `deletingAnOutputRenumbersNothing` checks it); `AppModel+DrawingTemplates.swift`'s
  `chooseLogo` reads the file through `RegularFile.read` (R23)
- Test: `Tests/CreatorAppTests/DrawingAssemblyTests.swift` (FakeKernel with hooks), `Tests/CreatorAppTests/DrawingAssemblyOCCTTests.swift` (`#if canImport(CreatorOCCT)`),
  `Tests/CreatorAppTests/DrawingTemplateAppTests.swift`, `Tests/CreatorAppTests/DrawingExportTests.swift` (additions), `Tests/CreatorNodesTests/Fields/` the decoder tests (addition)

**Interfaces:**
- Consumes: Tasks 1 to 11.
- Produces: `GreyBackground` (`.black`, `.white`), `GreyImageDecoder.decode(_ data: Data, background: GreyBackground) async throws -> GreyImage` (the one-argument form
  is `.black`); `DrawingExportKind.pdfSheet`, `.svgSheet`; `AppModel.drawingExportPlan(_ kind: DrawingExportKind, sheet: SheetID?, view: ViewID?) throws(AppProblem)
  -> DrawingExportPlan`; `AppModel.exportDrawingReturningWarnings(_ kind: DrawingExportKind, sheet: SheetID?, view: ViewID?, to url: URL) async throws(AppProblem) ->
  [String]` (the old form passes the open sheet and the selection); `AppDrawingTemplates.store() -> DrawingTemplateStore`; `AppModel.chooseLogo(for sheet: SheetID,
  using picker: any FilePicker) async`; `ViewStatus` (`CreatorDrawing/Views/ViewStatus.swift`: `.drawn`, `.pending`, `.failed(String)`, from a `ViewContent`);
  `DrawingSession.sheetSnapshot(_ id: SheetID, within limit: Duration) async -> (picture: SheetPicture, facts: TitleBlockFacts, views: [ViewID: ViewStatus])?`
  (for MCP: one race of `limit` over the evaluation and the sheet's projections, then the sheet composed as it stands, R19).

- [ ] **Step 1: Tests.**
  - `DrawingAssemblyTests`: `anAssemblyProjectsEveryPart` (three Outputs: one projection request with the three parts' solids, `ViewContent.parts` three spans);
    `tickingAPartReRequests`; `aFailedPartKeepsTheViewFaded`; `partsFactsNameAndCount` (an Output of four solids reads quantity 4; a failed one nil; names follow a
    rename); `massOfAnAssemblySheet` (density 7.85: the sum over the three; a sheet with an unrelated single view beside it: no mass); `deletingAPartsOutputLosesItsBalloon`
    (the balloon `.partNotShown`, "1?", listed in the PDF export's warnings); `deletingAnOutputRenumbersNothing` (Bolt, Nut and Plate unpinned with balloons;
    Plate's Output deleted: the balloons read "1", "2" and "3?", the parts list "Plate?" in row 3; saved and reopened: the same numbers);
    `theEditorPinsWhatTheSheetShows` (after an evaluation `editor.partFacts` equals the composed facts' `parts`; a material typed on the second item leaves every
    balloon's number as it was); `refreshSpansEqualProjectedSpans` (an assembly of three parts, the second sharing the first's solid, with a section view of it:
    the spans the refresh judged its anchors against (a test hook on `lastGood(of:)` reporting them) equal the section view's `ViewContent.parts`, and an onPart
    dimension on the third part is remembered with the value the compose shows); `refreshReadsEveryPart` (after an evaluation `remembered` holds an onPart dimension's value;
    the document not edited); `exportRefusesAFailedPart` ("“Bolt” can't be drawn").
  - `DrawingAssemblyOCCTTests` (three Box-minus-Cylinder Outputs, two of them the same producer moved twice): `twinPartsKeepTheirBalloons` (a balloon on each twin, a
    width change: both held, each on its own twin); `partsHideEachOtherOnTheSheet` (hidden lines on, the back part's hidden strokes exist).
  - `DrawingTemplateAppTests`: `savingASheetAsATemplate` (the store holds its size, owner and the logo's bytes from `images`); `aSheetFromATemplateEmbedsItsLogo`
    (`document.images` gains the bytes; the sheet's `logo` is their hash; one undo step); `oversizedLogosAreRefused` (a 2,000 × 10 PNG: R11's sentence; a 3 MB file:
    the other); `aBrokenTemplateLogoMakesTheSheetWithoutIt` (a truncated PNG in a template: the sheet made, no logo, the decoder's sentence in an alert);
    `logosDecodeOffTheMainActor` (the decode awaited through a suspending hook; the main actor free); `aTransparentLogoIsWhite` (a fully transparent pixel reads 255);
    `aLogoFileIsReadBounded` (a 1 GB sparse "logo.png": refused from its size with "A logo file is at most 2 MB.", unread; a folder: "The logo isn't a
    file."); `logoAlertsSayWhatFailed` (from Choose Logo…: title "The logo couldn't be used"; from a template: title "The template's logo couldn't be used" and the
    body ending "The sheet was made without it."); `theLogoSizeUsesMessageNumbers` (the 2,000 × 10 PNG's sentence reads "… this picture is 2,000 × 10.").
  - `DrawingExportTests`: `aPDFOfOneSheet` (`pdfSheet`: one page); `allSheetsInOnePDF` (three sheets: three pages in tab order); `aViewDXFWithAnnotationsCarriesBalloons`
    (`dxfViewWithAnnotations` of an assembly view with a balloon, beside a parts list, a revision table and a logo on the sheet: the balloon's CIRCLE and leader on
    DIMENSION and its number on TEXT, at model millimetres (the circle's radius 5 / scale); no entity of either table; no logo rectangle and no logo warning); `warningsRunSheetBySheet` (two sheets
    each with a lost dimension and a check: sheet 1's lost, its check, sheet 2's lost, its check); `anSVGOfTheSheet` (`svgSheet` writes the composed sheet);
    `theDXFSaysTheLogoIsLeftOut` (R13's sentence once).
  - Decoder test: `decodingOverWhite` (a black pixel with alpha byte 128, colour bytes 0: exactly 32,639 = (255 − 128) × 257 over white, the decoder's integer
    sum, and exactly 0 over black; an opaque white pixel 65,535 on both).
- [ ] **Step 2: Run** `swift test --filter 'DrawingAssemblyTests|DrawingAssemblyOCCTTests|DrawingTemplateAppTests|DrawingExportTests'` and the decoder test; fail.
- [ ] **Step 3: Implement** R2's session side, R5's facts, R6, R10's and R11's app side, R15; fix anything the integration finds (with a test).
- [ ] **Step 4: Run** `swift test --filter CreatorAppTests`, `--filter CreatorNodesTests`, `--filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: assemblies, items, logos, templates and the new exports in the app".

### Task 13: MCP drawing tools

**Files:**
- Create: `Sources/CreatorMCP/Tools/DrawingTools.swift` (the three tools), `Sources/CreatorMCP/Tools/DrawingAddressing.swift`,
  `Sources/CreatorMCP/Session/DrawingSheetSnapshot.swift`
- Modify: `Package.swift` (`CreatorMCP` depends on `CreatorDrawing`; `CreatorMCPTests` gains `CreatorDrawing` beside `CreatorMCP`, `CreatorNodes` and
  `CreatorKernel`, since its tests build `SheetPicture`s and `DrawingDocument`s), `Sources/CreatorMCP/Session/DocumentSession.swift` (R19's two members),
  `Sources/CreatorMCP/Session/DocumentModelSession.swift` (`drawingSheetProvider`, `drawingExporter` hooks), `Sources/CreatorMCP/Tools/MCPCatalogue.swift`,
  `Sources/CreatorApp/MCP/AppDocumentSession.swift` (both over `AppModel`: the snapshot through `DrawingSession.sheetSnapshot`, the export under `askRefusal()`, the
  overwrite rule and the warnings heading as `export`), `docs/mcp.md` (the three tools under a new "Drawings" heading; the Rules' "No picks yet" gains "Drawings are
  read and exported, not edited.")
- Test: `Tests/CreatorMCPTests/DrawingToolTests.swift`, `Tests/CreatorAppTests/MCPDrawingTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 12.
- Produces: `DrawingSheetSnapshot { picture: SheetPicture; facts: TitleBlockFacts; views: [ViewID: ViewStatus] }` (`ViewStatus` from Task 12; R19); `DrawingTools.settleLimit: Duration = .seconds(60)` (the default of `AppDocumentSession.drawingSettleLimit`, which tests set short); `DocumentSession.drawingSheet(_ id: SheetID) async -> DrawingSheetSnapshot?`
  and `exportDrawing(_ kind: String, sheet: SheetID?, view: ViewID?, to url: URL, overwrite: Bool) async -> SessionOutcome`; `DrawingTools.tools: [MCPTool]`;
  `DrawingAddressing.sheet(_ ref: JSONValue?, in: DrawingDocument) -> Result<SheetID, Refusal>` (the existing `Refusal` of `Addressing.swift`),
  `DrawingAddressing.view(_ ref: JSONValue?, on sheet: DrawingSheet) -> Result<ViewID, Refusal>`.
- JSON (keys exact): `list_drawings` → `{"standard": "iso", "sheets": [{"id", "name", "size": "A3", "orientation", "scale": "1 : 2", "revision", "views": [{"id",
  "kind", "letter"?, "orientation": "Front" | "custom", "scale", "parts": [{"node", "name"}]}], "annotations": n}]}`; `get_sheet` → `{"sheet": {"id", "name"},
  "complete": true | false, "views": [{"id", "status": "drawn" | "pending" | "failed", "problem"?}],
  "annotations": [{"id", "kind": the coding type, "view"?, "label", "status": "held" | "lost", "reason"?, "warnings"?}], "parts_list": [{"item", "name", "quantity",
  "material", "part_number"}], "revisions": [{"letter", "description", "date", "approved"}]}` (annotations in sheet order; `parts_list` the numbered items even without a
  list drawn; empty arrays written).

- [ ] **Step 1: Tests.**
  - `DrawingToolTests` (a `DocumentModelSession` with hooks): `listDrawingsDescribesSheetsAndViews` (two sheets, an assembly view with two parts: the JSON above);
    `getSheetListsLostAnnotations` (a picture with one lost dimension: status "lost", the reason sentence; a held balloon "held"); `getSheetListsItemsAndRevisions`; `aPendingViewIsReported` (a snapshot with one view pending: its status "pending", `complete` false, its annotations
    as the snapshot judged them);
    `sheetsByNameOrID` (R19's four sentences); `exportDrawingChecksItsArguments` (an unknown kind, a missing sheet, a view kind without a view, a relative path: the
    sentences); `exportDrawingPassesThrough` (the hook gets kind, sheet, view, url and overwrite); `withoutHooksDrawingsAreRefused`.
  - `MCPDrawingTests` (the app over FakeKernel): `getSheetProjectsOutsideDrawingMode` (Model mode: the annotations judged against fresh projections);
    `exportIsRefusedWhileEditsAre` (a sketch open: the sketch sentence; an alert up: its sentence); `getSheetAnswersAtTheLimit` (a kernel hook that holds a
    projection (`HookGate`), the limit injected short: the answer arrives with that view "pending" and `complete` false; an export under the same hold refuses
    "MetalCreator is still drawing this sheet. Try again in a moment."); `exportWritesAndWarns` (a PDF at a temporary path; a lost annotation's
    sentence in the message); `anExistingFileNeedsOverwrite`.
- [ ] **Step 2: Run** `swift test --filter DrawingToolTests` and `--filter MCPDrawingTests`; fail.
- [ ] **Step 3: Implement** R19 and the docs.
- [ ] **Step 4: Run** `swift test --filter CreatorMCPTests`, `--filter CreatorAppTests`; pass.
- [ ] **Step 5: Commit** "MCP: read drawings and export them".

### Task 14: The assembly benchmarks

**Files:**
- Modify: `Tests/CreatorAppTests/Bench/DrawingBench.swift` (`drawing-5`, `drawing-5-warm`), `Tests/CreatorAppTests/Bench/DrawingBenchFixtures.swift` (`assemblyDocument(parts:
  Int) -> (DocumentModel, [NodeID])`, R20's ten parts), `Tests/CreatorAppTests/Bench/DrawingBenchFixturesTests.swift` (the fixture checked in the default run)
- Test: the fixture test runs in every `swift test`; the bench rows only under `scripts/bench.sh DrawingBench`

**Interfaces:**
- Consumes: Task 12.

- [ ] **Step 1: Tests.** `DrawingBenchFixturesTests.theAssemblyFixtureHasTenParts` (ten Outputs, each one closed solid with a hole; the sheet's three views evaluate and
  project on OCCT, `#if canImport(CreatorOCCT)`, with ten spans in the Front view).
- [ ] **Step 2: Run** `swift test --filter DrawingBenchFixturesTests`; fail.
- [ ] **Step 3: Implement** R20's rows: `drawing-5` gives views new IDs every round and checks the cache's kernel calls grew by at least three per round (as `drawing-1`
  does); `drawing-5-warm` uses `WarmBenchWindow` and asserts every balloon held.
- [ ] **Step 4: Run** `swift test --filter DrawingBenchFixturesTests`; pass. Then `scripts/bench.sh DrawingBench` on this Mac (release) and record the two rows in
  `docs/verification/performance.md` under "Drawings" as the earlier rows are (saturated if the Mac is loaded).
- [ ] **Step 5: Commit** "Bench: drawing-5, a ten-part assembly sheet".

### Task 15: Docs and the suites

**Files:**
- Modify: `CLAUDE.md` (a "Drawings, DR-5" paragraph after DR-4's: assembly views and one compound (R1, R2), part anchors (R3), balloons (R4), computed item numbers
  (R5), assembly mass (R6), the parts list (R7), revision letters and table (R8, R9), templates (R10), logos (R11, R12), writers and SVG (R13, R14), export kinds (R15),
  tools, keys and steps (R16), format 21 (R17), copy and paste (R18), MCP (R19), benchmarks (R20), the pulled-in backlog (R21), the parked list (R22) and bounded reads (R23, `RegularFile` in the `CreatorGeometry` entry); the file-format
  sentence becomes "File format is version 21 (… 21 added assembly views, part anchors, balloons, parts lists, revision tables, the drawing's items and a title block's
  logo …); files of format 1 to 20 open unchanged and are written as 21"; the `CreatorDrawing` module entry names `Items/`, `Templates/`, `SVGWriter`; the
  `CreatorDrawingEditor` entry names `Templates/` and the clipboard; the `CreatorMCP` entry says it depends on `CreatorDrawing`; the MCP-1 paragraph's "no edge or face
  picks yet" gains the drawing tools), `docs/verification/human-checks.md` (group DR-5, below), `docs/superpowers/specs/2026-11-24-drawings-design.md` (Status line:
  "… DR-4 done (…). DR-5 done (<date>; human checks group DR-5 pending; R3: an assembly view's anchors name their part; R5: item numbers are computed, the person's
  order pinned by `items`). Drawings DR-1 to DR-5 done."), `docs/metalui-gaps.md` (only if a task logged a `DR-5-x` gap), and the workspace's
  `.superpowers/sdd/2026-11-26-dr-5-assemblies-revisions/backlog.md` (append DR-5's parked minors from the ledger)
- Group DR-5 checks: DR5-1 an assembly of three parts in Front and isometric: parts hide each other, hidden lines on; DR5-2 two copies of one part ballooned, then a width
  change: each balloon stays on its copy; DR5-3 untick a part, delete a part's Output, break a part: the view's words and the "?" balloons; DR5-4 the parts list on the title
  block and free, ISO and ASME columns, material and part number typed, Move Up and Down, a part with no balloon listed; DR5-5 balloons in an isometric view, dragged and
  nudged; DR5-6 the revision table: New Revision A, B, … H then J, typed dates, the title block's revision following, Remove Last Revision; DR5-7 a template saved with a
  logo, a new sheet from it after relaunch, the logo in the owner field, a transparent PNG's background white; DR5-8 a 3,000-pixel logo and a broken template file:
  the sentences; DR5-9 Export PDF of All Sheets, PDF of Sheet, SVG of Sheet: open the SVG in a browser and Inkscape (layers named, lettering the PDF's width), the PDF in
  Preview and Acrobat, the logo grey; the DXF in LibreCAD with the logo's rectangle; DR5-10 copy, cut and paste views with sections and symbols across sheets, then undo;
  DR5-11 an AI client lists the drawings, reads a sheet with a lost dimension, exports a PDF, and is refused while a sketch is open; DR5-12 the keys B and P; DR5-13
  Linux and Windows: the assembly page's PDF and SVG SHA-256 equal the Mac's.
- [ ] **Step 1:** docs.
- [ ] **Step 2:** `swift test` on macOS (16 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=dr-5 IMAGE=metalcreator-linux:dr-5
  scripts/linux-test.sh test` (16 lines; afterwards remove only this run's Docker volume and image); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: DR-5 assemblies, revisions and the rest".
