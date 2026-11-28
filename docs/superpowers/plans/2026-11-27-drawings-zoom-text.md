# Drawings Zoom Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `drawing-5-warm zoom` (idle Mac 2026-11-27: median 17.97 ms) under its 16.67 ms budget by letting sheet lettering survive a zoom step without being rebuilt.

**Architecture:** Upright sheet text is laid out at a *reference zoom* (the power of two nearest the current zoom) inside an `.equatable()` group and drawn under `scaleEffect(zoom / reference)`. MetalUI re-rasterises text under a uniform scale on its 2^(1/8) ladder (`TZ-A`, divergence 106 narrowed), so a zoom step within one octave band re-evaluates no text and re-shapes no glyph. Rotated text stays on today's path (built at the true zoom), because MetalUI resamples text under a scale that sits outside a rotation (divergence 106 (1)); that is logged as a MetalUI gap, fixed there later.

**Tech Stack:** Swift 6.4, MetalUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md` (line weights and dashes are paper millimetres, "scaled by the sheet, never by zoom", line 95; text is paper geometry). Investigation behind this plan: profiled drawing-5-warm, text is the whole overrun (removing text: zoom 18.8 → 11.0 ms); a prototype of this design measured zoom 18.8 → 13.7 ms (p95 14.8), drawing-2-warm zoom 15.25 → 13.2, pan unchanged.

## Rulings (made without a question round, per the user's standing instruction)

- R1: The reference zoom is `SheetTextZoom.reference(for: zoom) = 2^round(log2(zoom))`, so the applied scale is within [2^-0.5, 2^0.5]. Why: a fixed reference (the prototype used 4.0) runs into MetalUI's quarter-scale floor and 256 px em cap at extreme zooms; an octave band never does, and text keeps within one ladder rung of exact. Cost if wrong: one full text rebuild per octave crossed (a single frame like today's).
- R2: Only texts whose angle is 0 (exactly, after `angle.remainder(dividingBy: 2 * .pi) == 0`) go into the scaled group; every other text is built at the true zoom as today. Why: divergence 106 (1) would make rotated (vertical-dimension) text soft. Cost if wrong: rotated text keeps today's per-step cost.
- R3: Within one layer, upright texts paint before rotated texts (two `ZStack` children). Text paint order inside a layer was index order; texts are one ink (warning texts aside) and do not overlap by design, so the split is not visible. Cost if wrong: a warning-coloured rotated text could paint over an overlapping upright one.
- R4: Strokes, fills and the 1 pt width floor are unchanged (investigation fix B: only 0.4 ms, and it would drop the floor).
- R5: `SheetSelectionLayer`'s texts take the same path (it uses `SheetTexts`), so a selected label does not shift by a rung's resample against its unselected twin.
- R6: The MetalUI gap is logged in `docs/metalui-gaps.md` as: "text under a uniform `scaleEffect` that encloses a `rotationEffect` keeps its device-scale raster (divergence 106 (1)); a similarity (uniform scale with rotation) should re-key like a bare scale". Also log the other two gaps the investigation found: (a) CPU path rasters are redone in full on every scale change (no rung ladder for paths); (c) the idle-frame build+layout floor (about 6.2 ms for 1166 unchanged elements on drawing-5-warm).

## Global Constraints

- `CreatorDrawingEditor` depends on Drawing, Kernel, Geometry, Style and MetalUI only.
- A file importing both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle`.
- Tests use Swift Testing; `swiftlint lint --strict` reports zero violations.
- Pass rules: `swift test` exit 0, 16 "Test run with" lines, no "recorded an issue" or "failed after".
- MetalUI gaps are fixed in MetalUI, never worked around here (R2 is not a work-around: rotated text keeps today's correct rendering).

## Review Focus

1. Zoom far out (0.05) and far in (40): upright text must stay where it is today (same top left, same advance) — a scale anchor other than the paper origin would drift it.
2. A zoom step that crosses an octave boundary (e.g. 1.41 → 1.42) must rebuild text once, and the next step within the band must not.
3. A pan must still evaluate no text layer (today's `aPanSkipsEveryView`).
4. A text at angle 2π or -0 counts as upright; a text at π (upside down) does not.
5. Lost/notice text colour (warning) must survive the split.

---

### Task 1: Upright sheet text at a reference zoom

**Files:**
- Modify: `Sources/CreatorDrawingEditor/Views/SheetStrokeGroups.swift` (`SheetTexts`)
- Create: `Sources/CreatorDrawingEditor/Views/SheetTextZoom.swift`
- Modify: `Sources/CreatorDrawingEditor/Views/SheetFrameLayer.swift`, `SheetAnnotationLayer.swift`, `SheetSelectionLayer.swift` only if their `==` must change (see Step 3)
- Modify: `Sources/CreatorDrawingEditor/CLAUDE.md`, `docs/metalui-gaps.md`
- Test: `Tests/CreatorDrawingEditorTests/SheetTextZoomTests.swift`, `Tests/CreatorDrawingEditorTests/SheetCanvasSkipTests.swift`

**Interfaces:**
- Produces: `enum SheetTextZoom { static func reference(for zoom: Double) -> Double; static func isUpright(_ text: SheetText) -> Bool }`; `SheetTexts` keeps its initialiser (`texts:zoom:paperHeight:ink:warning:`).

- [ ] **Step 1: Write the failing tests** in `SheetTextZoomTests`:
  - `referenceIsTheNearestPowerOfTwo`: `reference(for: 1) == 1`, `reference(for: 1.4) == 1`, `reference(for: 1.42) == 2`, `reference(for: 3) == 4`, `reference(for: 0.3) == 0.25`, `reference(for: 40) == 32`; and for zoom in [0.05, 0.1, 0.7, 1.5, 6, 40], `zoom / reference(for: zoom)` is within `[pow(2, -0.5), pow(2, 0.5)]`.
  - `uprightMeansAngleZeroModuloATurn`: angles 0, -0.0, 2π, -2π upright; π/2, π, 1e-3 not.
  - `uprightTextLandsWhereItDidBefore`: render one upright `SheetText` (height 3.5, origin (20, 30), paper height 297) through `SheetTexts` at zooms 0.3, 1.7 and 12 with the target's render harness (see `SheetLayerPaintTests` for how a layer is rendered and its glyph rectangles read); the first glyph's left edge and baseline match `SheetTextView`'s placement at that zoom (`origin.x * zoom`, `(paperHeight - origin.y) * zoom`) within 0.5 px.
  - `warningTextKeepsItsColourInBothGroups`: an upright and a rotated text, both `isLost`, render in the warning colour.
  In `SheetCanvasSkipTests` replace `aZoomEvaluatesEveryLayer` with:
  - `aZoomWithinABandEvaluatesNoText`: zoom 1.1 → 1.2 → 1.3 (one band); after the first step, the text components (`SheetTextView`, counted the way the file counts layer evaluations) evaluated on the later steps are only the rotated ones (the fixture's texts are upright, so 0).
  - `aZoomAcrossABandRebuildsTextOnce`: 1.3 → 1.45 rebuilds the upright texts; 1.45 → 1.5 rebuilds none.
  Keep `aPanSkipsEveryView` passing unchanged.

- [ ] **Step 2: Run them to see them fail**
  Run: `swift test --filter 'CreatorDrawingEditorTests.SheetTextZoomTests'` and `--filter 'CreatorDrawingEditorTests.SheetCanvasSkipTests'`. Expected: compile failure (no `SheetTextZoom`), then the band tests fail.

- [ ] **Step 3: Implement** `SheetTextZoom` and the split in `SheetTexts`:
  `SheetTexts.content` is a `ZStack(alignment: .topLeading)` of (a) an `.equatable()` component holding the upright texts, built with `zoom: reference` and `paperHeight`, wrapped so `scaleEffect(zoom / reference, anchor: .topLeading)` applies to it (`scaleEffect` is ProposalBase-only: wrap the equatable component in a `ZStack` and scale that); its `==` compares the texts (the layer's bucket version already decides content; compare the `[SheetText]` value), the reference, paper height and colours, never the raw zoom; (b) the rotated texts as today, at the true zoom. The scale anchor is the paper's top left, which is the stack's top left (`paperStack` places every layer at paper (0, 0)); check that the upright group's frame starts there and not at its content's bounds, or the anchor drifts (Review Focus 1). If a layer's own `==` compares `zoom` for its texts' sake only, leave it: the layer still re-evaluates on zoom for its strokes; what must not re-run is the upright text group.

- [ ] **Step 4: Run the tests to see them pass**, then `swift test --filter CreatorDrawingEditorTests` (all pass).

- [ ] **Step 5: Notes and gaps.** In `Sources/CreatorDrawingEditor/CLAUDE.md`, replace the drawings-speed R6 sentence that says a zoom rebuilds every layer with: upright text is laid out at the octave-band reference zoom and scaled (R1-R3 of this plan, named by file); rotated text and strokes still rebuild per zoom step. Add the three gaps of R6 to `docs/metalui-gaps.md` in that file's format, each naming the measured cost.

- [ ] **Step 6: Full suite and lint.** `swift test 2>&1 | tee <log>`: exit 0, 16 "Test run with" lines, no "recorded an issue"/"failed after". `swiftlint lint --strict`: 0.

- [ ] **Step 7: Commit** ("Lay out upright sheet text at an octave-band reference zoom and scale it").

### Task 2: Idle-Mac numbers

Done by the controller (needs an idle Mac): `scripts/bench.sh DrawingBench` on Task 1's head; then fill `docs/verification/performance.md`'s "numbers owed: idle Mac" rows with the 2026-11-27 pre-fix run (pan 8.90 / 10.16, zoom 14.84 / 17.97, drag 13.39) and this run, and rename the section heading so it no longer says numbers are owed. Commit ("Record idle-Mac drawing pan, zoom and drag numbers").
