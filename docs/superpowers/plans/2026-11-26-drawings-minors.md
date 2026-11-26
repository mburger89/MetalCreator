# Drawings minors (DR-1 to DR-5 parked follow-ups) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the small defects, wording slips and test gaps parked during DR-1 to DR-5, so the drawings feature has no known minor faults.

**Architecture:** No new feature and no new module. Each task is a group of independent small fixes in one area (model, composer and writers, dimensions, symbols, sections, editor, DR-5 editor, MCP, performance, tests). Every fix comes with the test that pins it.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, MetalUI, OpenCascade 7.9 behind `Kernel`.

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md`, with the DR-1 to DR-5 plans (`docs/superpowers/plans/2026-11-24-dr-1-*.md`, `2026-11-25-dr-2-*.md`, `2026-11-26-dr-3-*.md`, `2026-11-26-dr-4-*.md`, `2026-11-26-dr-5-*.md`) and their rulings. The source of the items is the drawings backlog (copied into each task below).

## Global Constraints

- Notes for the module go in `Sources/CreatorDrawing/CLAUDE.md` or `Sources/CreatorDrawingEditor/CLAUDE.md` (the root `CLAUDE.md` holds cross-module rules only). Update a note only where a fix changes what it says.
- File format stays 21. No change may make a file written by the current build unreadable; decoding may repair more, never less.
- PDF, DXF and SVG bytes stay identical on every platform (no locale, clock, hash seed or `sin`/`cos` in drawn constants). A digest test that changes must change because of the fix, and the commit says why.
- Sentences shown to the person are full sentences in the app's plain voice; undo names come from `DrawingStepName` and never include typed text or numbers.
- Every edit is still one `DrawingCommit`; a cancelled gesture leaves no undo step.
- Tests use Swift Testing. `swiftlint lint --strict` reports 0 violations.
- Every item that is already fixed on this branch is reported as such (with the test or commit that shows it) and not redone.
- Each task runs `swift test --filter CreatorDrawingTests` and `swift test --filter CreatorDrawingEditorTests` (plus the targets it touches, e.g. `CreatorAppTests`, `CreatorMCPTests`, `CreatorOCCTTests`), never the full suite; the full suites run once at the end.

## Rulings (made without a question round, as the user asked)

- R1. A section view whose stored cutter is damaged (fewer than two points, a zero or non-finite `viewing`, or any non-finite point) is dropped on decoding, like a derived view with a missing derivation, never repaired into a degenerate frame. Its own derived views follow the existing missing-parent rules. Cost if wrong: a damaged file loses a view instead of showing a nonsense one.
- R2. A view with no projection (its placeholder) is an on-screen notice only: the PDF, DXF and SVG leave it out, and the export warnings say "View <label> has nothing drawn." once per such view (reuse an existing sentence if one says this). Cost: a person exporting a sheet with an empty view sees a warning instead of a box.
- R3. A non-finite coordinate never reaches a writer: a stroke, fill or text with one is left out of the picture and counted, and the export warns "Some lines couldn't be drawn because a measurement isn't a number." once per export. `PDFNumber.format` keeps returning a string, but tests show it is never asked about a non-finite value through the composer.
- R4. Each fill is its own path filled nonzero, so overlapping fills never cancel whatever their winding; `overlappingFillsDoNotCancel` must fail if two fills are put back into one path.
- R5. A stepped blind hole (its last step ends on a floor face) reads blind, with the depth to the deepest floor; a hole reads THRU only when its bore leaves the part.
- R6. `HoleReader` reads the whole run at the mouth: a full circle split into two arcs (or more) is one circle when the pieces share centre, radius and axis within the resolver's `joinTolerance` and `joinAngle`.
- R7. `series()` (baseline, chain, ordinate) takes three or more anchors; two are refused at the pick with the sentence the plan's R6 gives (or, if it gives none, "A series needs at least three places; add another.").
- R8. An aligned dimension between two points that lie at different depths along the view direction is refused at the pick ("These points aren't at the same depth in this view, so the length would be foreshortened."); an aligned dimension to an outline is refused at the pick ("An outline can't take an aligned dimension.").
- R9. Nudging a linear dimension along its measured direction slides its label along the dimension line (the stored label offset), by the nudge step; across the direction it moves the line, as now.
- R10. Changing a tolerance's upper value never re-rounds the lower one (and the reverse): each keeps what the person typed, at full precision.
- R11. A duplicated sheet is named "<name> copy", then "<name> copy 2", "<name> copy 3" and so on, the first free one in the drawing; a rename is trimmed, and a blank name is refused with "A sheet needs a name.", a duplicate one with "Another sheet already has that name."; the same rules hold for templates.
- R12. `setSource` on an assembly view is refused with "This view shows an assembly; change its parts in the Parts section." (nothing changes). `setPart` re-showing a part puts it back at its place in `sources` order.
- R13. Copy, cut and paste take ⌘C, ⌘X and ⌘V (`.primary`) with no other modifier; ⌘⌃C/X/V and the like fall through to whatever else handles them.
- R14. MCP `get_sheet` reports `complete: false` while any view on the sheet is failed or pending, with the failed view's sentence in its entry; `export_drawing` composes each sheet once per export; `list_drawings` names a removed part by its remembered name (the name the sheet shows), never "?".
- R15. `DrawingAnchorResolver.scope` caches `Topology.restricted(toFaces:)` per span for one compose (a cache owned by the compose, dropped after it), never across composes.
- R16. DR-5 plan erratum: R15's "TEXT on TEXT" for a balloon's number in a view's DXF is wrong; the number is on DIMENSION as R4 says (code unchanged; the plan file gets an erratum line).
- R17. The DR-1 R10 erratum: the shim's polyline sampler is its own bisection (at least 8 pieces, depth 16), not GCPnts (the plan file gets an erratum line).
- R18. A mixed value (a closed solid beside a sheet) cut by a section keeps the sheet's remainder: the solid and the sheet are cut separately and the remainders compounded, each with its own names.
- R19. The logo notice ("The picture isn't in this document." and the like) is drawn in the sheet notes area above the title block (DR-4's `SheetNotes` place), never at the frame's bottom left.
- R20. An export refusal's title names the sheet ("Sheet 2 couldn't be exported"), never `sources.first?.name`.

Parked (not done here, recorded in the drawings backlog memory): `ProjectedCurve`/`ProjectionSource` name clash (no defect), a test of the in-flight OCCT hide cancel, recomposing the whole sheet per drag step, the "The view was cancelled." spec wording, OCCT `cutAway` cancellation after the boolean, `keepingFacesOutside`'s own sentences, the sheet cut-edge naming erratum, and the multi-sheet order of lost and check sentences.

## Review Focus

1. A file saved by the current build with a damaged section, balloon or table still opens, with the damage repaired or the view dropped in words (R1), never a crash or a silent nonsense frame.
2. PDF, DXF and SVG digests changed by R2, R3 or R4 change identically on macOS and Linux (no float formatting or ordering that depends on the platform).
3. Picks refused by R7 and R8 are refused at the pick, before any step is made, and the tool stays armed.
4. Renames and duplicates (R11) under Unicode: "Sheet 1" and "Sheet 1 " are the same name after trimming; "ß" and "SS" are different names.
5. MCP answers (R14) for a sheet with one failed view among good ones: `complete: false`, the good views still listed.

---

### Task 1: Model, decoding and geometry primitives (CreatorDrawing)

**Items:**
- `ProjectionFrame.make` tests parallel `up` on the un-normalised residual (a huge near-parallel `up` gives a garbage frame). Normalise before the test; a test with `up` = 1e9 × (direction + 1e-12 × e) refuses.
- `SheetSegment.transformed` keeps an ellipse's majorAxis: wrong for mirroring scales. Transform the axes with the matrix (a mirror reverses the sweep); test: an elliptic arc mirrored in x gives the mirrored points at 5 sample parameters within 1e-9.
- `DrawingSheet.repairingAlignments` and `ViewPlacement.isAligned` free more views than needed around a cycle or a missing grandparent. Free only the views whose alignment chain is broken; test: a chain A ← B ← C with A missing frees only B (C stays aligned to B); a two-view cycle frees one view (the higher `ViewID`).
- R1 (damaged section cutter dropped on decode); test with each damage kind.
- `dimensionEnd` decoded unclamped (DR-4): clamp on decode as when drawn; datum distances under `DatumLayout.minimumDistance` are clamped when written (the editor's setter and decoding), not only when drawn.
- `revisionShown` returns a blank or invalid last row's letter: return the last valid row's letter (nil when none).
- The composer duplicates `Balloon.part(in:)`: use the model's one.
- A format-18 fixture with views (the existing one has none): add one with two views and a dimension, and a test that it decodes and is written as 21.

**Steps:** for each item: write the failing test, run it (fails), fix, run (passes). Then `swift test --filter CreatorDrawingTests`, `swiftlint lint --strict`, commit.

### Task 2: Composer, picture and writers (CreatorDrawing)

**Items:**
- R2 (placeholder on screen only; exports warn). Test: a sheet with one empty view gives a DXF with no entity on FRAME beyond the frame's own and a warning.
- R3 (non-finite coordinates). Test: a hand-built picture with a NaN point exports, leaves that stroke out and warns once.
- R4 (fills separate). The test fails when fills are joined.
- R19 (logo notice placement) and R20 (export refusal title).
- SVG: test rotated text (a 90° note's `transform` and its position); make `strokesMatchThePDFsPath` compare the paths point by point (parse both), not a substring; filter XML-illegal control characters (U+0000 to U+001F except tab, LF, CR) out of `<title>` and every text.
- ISO and ASME hidden dashes are both 3/1.5: replace the test that claimed to tell them apart with one that pins each standard's dash constants by value.
- Stale comments at `AnnotationComposer+Kinds.swift:33` and `AnnotationRefresh.swift:7` (balloons are refreshed): correct them.
- R16 and R17 errata lines in the DR-5 and DR-1 plan files.

### Task 3: Anchors, dimensions and measuring (DR-2 items)

**Items:**
- R5, R6 (`HoleReader`). Tests: OCCT full circle split into two π arcs reads as a hole of the right diameter; a stepped blind hole reads blind with the deepest floor's depth.
- R7, R8 (picks). Tests through `DrawingPick` with the sentences.
- Re-attach refusal reuses `LostReason`'s "no longer…" sentence: give it its own ("That line can't hold this dimension: …" naming why); a hole callout's cross-view refusal says "A hole callout takes…", not "A dimension takes…".
- "1 decimals": singular for one.
- The non-finite refusal also on the hole-callout path (DR-4 item).
- Tests: ISO 286 k8/K9 thresholds at the table's boundaries; the limits tolerance's grade refusal; an outline linear anchor's sign; an angle's supplementary extension at its vertex; `drawing-3-warm` asserts its annotations are held, not lost.

### Task 4: GD&T symbols (DR-4 items)

**Items:**
- A lost datum beyond its edge loses its extension line: keep the edge ends in `LastGood`'s `.attachment` (an optional key, no format bump) and draw the extension from them.
- A frame on a partial arc puts its foot on the full circle: `SymbolFoot` honours the arc's sweep (the foot lies on the arc, nearest the frame).
- `AnnotationRefresh` is told a view is pictorial: a symbol in a view turned isometric is lost (`LostReason` as DR-4's) and its `LastGood` stops refreshing.
- The editor's `nothingDrawnSentence` and the composer's `LostReason.noPart`: one sentence, the composer's.
- `circled()`, `datumTriangle`/`datumSquare` and the surface symbol take the standard as a parameter instead of reading `SymbolStyle.of(.iso)`; the characteristic glyph switches list every case (no `default`).
- The surface note's "(" ")" sit around the symbol's middle (baseline so their centre is the symbol's centre).
- Tests: a symbol on a hole callout and on a cylinder outline; the DXF symbols test checks every entity kind written (LINE, TEXT, SOLID or HATCH as used); a lost datum's "?" and a frame's datum cell in app-level tests (`CreatorAppTests`); basic dimensions' `toA`/`toB` by value; `aDatumOnADimension` asserts its distance.

### Task 5: Sections, details and marks (DR-3 items)

**Items:**
- R18 (mixed value cut). Test in `CreatorOCCTTests`: a box beside a sheet crossing the cut keeps the sheet's remainder.
- Hatch: decide the thin-region fallback per band piece after band and clip trimming. Test: a sliver inside a stepped band is hatched; an extent ending exactly on a hatch line is hatched. Add a test pinning `SectionMarkStyle`'s R6 constants.
- Detail: find ellipse–circle crossings by sign change plus a minimum-distance check per step (so tangent and close crossings are found), refined by bisection to 1e-12 of the parameter; join a cut full circle's two arcs at angle 0 into one where the clip leaves it whole; make `anArcStaysAnArc` assert centre, radius and both angles.
- Marks: `appendMarks` leaves a derived view's cutting line, arrows or boundary out with a `DerivedViewNotices` sentence when the parent has no mapping; a view's 1:1 DXF with annotations carries the parent's cutting chain with its arrows and letters, or none of it; a zero-length last chain segment keeps its thick end (use the previous segment's direction).
- Editor: the cutting-line preview uses the same snapping (corner, centre, 5°, Shift slant) as the click, through one function. Fix `DrawingToolbarTests`'s "eleven" message.
- Tests: `FakeKernel`'s `aHookCanSuspend` proves suspension (the hook is awaiting while the caller is observed suspended, via a `HookGate`, never a semaphore); `aCutEdgeDimensionIsLost` checks it is listed; rename `aDetailOfTheSection…` to what it tests (a detail of Top); the `drawing-4` fixture proves its line crosses the holes (count the cut faces' inner loops it hits); `ProjectionCache`'s cut: a cancelled caller sharing a flight returns at once while the flight goes on; "1,234" with the comma decimal sign reads 1.234, and with the point sign is refused.

### Task 6: Editor (DR-1 and DR-2 editor items)

**Items:**
- R11 (sheet names). Tests for duplicate naming and both refusals.
- The "+" tab is a borderless `Image("plus")` icon button with `.accessibilityLabel("Add Sheet")` and `.help`; `ScaleControl`'s `isCustom` state is keyed by the sheet's ID (`.id(sheet.id)`), so switching sheets doesn't carry it over.
- `fitsOnNextSize` is cleared after the next layout pass whether or not the size changed.
- The draft composes exactly what the click would commit (Shift's aligned too), through one function.
- `show(sheet:)` clears `addingLeader` and `hoverCandidate`.
- R9 (nudge along a linear dimension) and R10 (tolerance values).
- Tests: the R12 1 pt stroke floor at a small zoom (a render test); Custom… scale chosen and typed through the rendered `ScaleControl`.

### Task 7: DR-5 editor, paste and templates

**Items:**
- R12 (`setSource`, `setPart`). `balloonFoot`'s cache cleared in `replaceDocument`. `SheetBitmaps` pruned to the pictures the document still uses on `replaceDocument` and after each commit that removes a logo.
- Paste: `SheetCopy.shifted` shifts a symbol on a dimension once when both are pasted without their view; `refusal` checks the host against what is pasted, not what is offered; R13.
- Templates: the folder's `load()` treats a missing file as missing on every platform (check existence before reading, or match `ENOENT`/`ERROR_FILE_NOT_FOUND` too, not only `CocoaError.fileReadNoSuchFile`); the `.mctemplate` filter ignores case; R11 for template names.
- `BalloonInspector` never falls back to a random `ViewID()`: with no view, the row is not shown.
- Wording: the assembly section's "the Output's curves" says "the parts' curves"; "The picture isn't in this document." and "The decoding was cancelled." stay (recorded in the DR-5 plan file as an erratum).

### Task 8: MCP drawing tools (DR-5)

**Items:** R14, and a test of the multi-sheet export's one deadline (a `FakeKernel` hook that suspends the second sheet's projection past a short test deadline gives the timeout sentence, and the first sheet's work counted against the same deadline). Tests in `CreatorMCPTests` and, where the app session is needed, `CreatorAppTests`.

### Task 9: Anchor resolution per compose (DR-5 performance)

**Items:** R15. Test: one compose of a sheet with N anchors on one span calls `restricted(toFaces:)` once for that span (count through an injected counter or a test hook), and a second compose calls it again. Record `drawing-5` and `drawing-5-warm` only if run on an idle Mac; otherwise leave the numbers and say so.

### Task 10: DR-5 test gaps

**Items:** tests only (fix what they find): the hatch index with a left-out earlier part; `restricted()` with an edge crossing two spans; the span wiring in `AnnotationViewState.of` and `pickContext`; a balloon's centre equals its sheet foot plus its offset; the refresh of a cut assembly view; `assemblyDocument(parts:)` evaluated (not just built) in a test.

### Task 11: DR-1 test gaps and the load-sensitive test

**Items:** a test of `.curve(index:piece:)` with piece > 0 through the shim; a test of mesh-count grouping in the view's source sentence; `ControlNetGroupTests.aConstantXNetGroupsQuickly` asserts a bound that doesn't depend on wall-clock time (count the grouping's comparisons, or its complexity, instead of 5 s), so it can't fail under load.
