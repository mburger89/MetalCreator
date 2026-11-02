# G2 fillet: G1 preview while dragging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While a slider or viewport handle is being dragged, a Curvature (G2) fillet previews as its circular (G1) fillet; the G2
surface is built once the drag ends.

**Architecture:** A drag sets `DocumentModel.isScrubbing`; the evaluator passes it to nodes as `EvalContext.isScrubbing` and puts it
in the cache key of a node whose definition says `readsScrubbing` (exactly as `meshQuality` / `readsMeshQuality`). The Fillet node
reads it. When the drag ends, the flag clears and an evaluation is scheduled, which runs the fillet again at G2 (its key changed).

**Tech Stack:** Swift 6.4, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-01-g2-surfacing-design.md` §G-b (follow-up "G2 drag cost": bench g2-fillet-1, G1 12.9 ms
against G2 354 ms).

## Global Constraints

- Swift Testing; `swiftlint lint --strict` 0; 12 "Test run with" lines on macOS and Linux; only the known HLSL failure.
- A drag is: an inspector slider between `sliderEditingChanged(true)` and `(false)`; a viewport handle from its first `.changed`
  until `.ended`. A typed value, a key step, undo and redo are not drags (they evaluate at G2 at once).
- G1 and G2 fillets carry identical history (tags), so downstream picks hold across the switch; nothing is renamed.
- No warning or message while previewing at G1 (a ruling: the drag is short and the release shows the truth, including a G2
  refusal at the released radius).
- Scrubbing is view state of the session: not saved, no undo step, no edit, no edited dot.

## Review Focus

1. A drag that ends while a G1 evaluation is still running ends with a G2 result (the ending evaluation is not dropped).
2. Undo right after a drag gives G2 (scrubbing is false; the cache does not hand back a G1 result under the G2 key).
3. A drag on a node with no G2 fillet downstream changes nothing in evaluation or caching (only `readsScrubbing` nodes rekey).
4. A G1 (Tangent) fillet during a drag is the same result and cache entry as without the drag.
5. A slider "drag" that is a single key press (true then false at once) ends at G2.

---

### Task 1: The flag through the evaluator, the Fillet node, the editor and the app

**Files:**
- Modify: `Sources/CreatorGraph/EvalContext.swift` (`isScrubbing: Bool`, default false), `NodeDefinition.swift`
  (`static var readsScrubbing: Bool { get }`, default false), `Evaluator.swift` / `Evaluator+Running.swift` (an
  `isScrubbing: Bool = false` parameter on `evaluate`, carried in the setup, hashed when `readsScrubbing`), `DocumentModel.swift`
  (`public var isScrubbing: Bool`; a change to false schedules an evaluation; passed to `evaluate`),
  `Sources/CreatorNodes/Features/FilletNode.swift` (`readsScrubbing = true`; G2 while scrubbing builds `.circular` with no G2
  warnings), `Sources/CreatorEditor/EditorModel+Inspector.swift` (`sliderEditingChanged` sets `document.isScrubbing`),
  `Sources/CreatorApp/AppModel+Viewport.swift` (`handleChanged`: true on `.changed` of a document handle, false on `.ended`; the
  slice and section handles leave it alone)
- Test: `Tests/CreatorGraphTests/ScrubbingEvaluationTests.swift`, `Tests/CreatorNodesTests/FilletScrubbingTests.swift`,
  `Tests/CreatorAppTests/ScrubbingTests.swift`

- [ ] **Step 1: Failing tests:**
  - Graph: `aNodeThatReadsScrubbingRekeys` (a test node counting runs: scrubbing false→true→false runs it 3 times; a node without
    `readsScrubbing` runs once), `endingAScrubSchedulesAnEvaluation`, `scrubbingIsNotAnEdit` (no undo step, `isEdited` false).
  - Nodes (FakeKernel's `filletProfiles` log): `aG2FilletPreviewsCircularWhileScrubbing`, `aG2FilletIsG2WhenNotScrubbing`,
    `aG1FilletIsTheSameWhileScrubbing` (one kernel call across scrub on/off: same cache key).
  - App: `aHandleDragPreviewsG1AndEndsG2` (handle `.changed` steps then `.ended`; after `settle()` the last kernel profile is G2 and
    during the drag the profiles were circular), `aSliderDragPreviewsG1AndEndsG2`, `aKeyStepEndsAtG2` (true/false at once),
    `undoAfterADragIsG2`, `theSectionHandleDoesNotScrub`.
- [ ] **Step 2:** Run them; expect failures.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `swift test --filter 'Scrubbing|Fillet|CreatorGraphTests'`, lint.
- [ ] **Step 5: Commit** `feat(fillet): a G2 fillet previews at G1 while dragging`.

### Task 2: The smooth rounded-loft test, and records

- [ ] `G2FilletCoverageTests.aSmoothRoundedLoftChainBuildsOrIsRefusedAtTheCap`: after the pairing fix (`9a47817`) check whether it
  now builds on macOS and Linux. If it builds on both, rename it `aSmoothRoundedLoftChainBuilds`, require a build (springs G2,
  report its sections) and add the same last-bit radius sweep as `aRoundedLoftChainSurvivesLastBitRadiusChanges`; if it still
  refuses anywhere, leave it and record why in the report.
- [ ] Bench: a `g2-fillet-drag` row in the existing G2 fillet bench (a drag step at G2 while scrubbing, release build) and the number
  in `docs/verification/performance.md` (saturated if the Mac is loaded).
- [ ] CLAUDE.md: one sentence in the G2 fillet / Kernel record on `isScrubbing` / `readsScrubbing`. Human check **G2F-9**: dragging a
  G2 fillet's radius is as smooth as G1 and the stripes snap to G2 at release.
- [ ] Full `swift test` (12 lines), lint, `scripts/linux-test.sh test` (12 lines). Commit `docs(fillet): G1 drag preview records`.
