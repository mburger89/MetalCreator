# Measure follow-ups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the follow-ups Measure part B and its review left open: an unexplained failed distance, a hover that
projects every section polyline, polyline distances that wait on OpenCascade, the parked minors and the load-sensitive
panel test.

**Architecture:** No new features. Each task owns one area of `Sources/CreatorApp/Measure` (or `CreatorKernel` for the
distances) and ends green on its own.

**Tech Stack:** Swift 6.4, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-30-section-measure-design.md` (§4, Measure). Background: the ledger of
`2026-10-31-measure-b-keep.md` (parked minors) and that plan's Rulings.

## Global Constraints

- OCCT only behind `Kernel`; Swift Testing; `swiftlint lint --strict` 0; 12 "Test run with" lines on macOS and Linux; only
  the known `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine` failure.
- A measurement is view state: no command, no undo step, no edit.
- A speed-up preserves behaviour: same picks, same numbers (within 1e-9 mm where a Swift path replaces OCCT).

## Review Focus

1. A distance that fails then succeeds after an edit shows the number, not the failure.
2. A section outline far off-screen or behind the camera is never hovered.
3. A point exactly on a polyline measures 0 with both witnesses at that point.
4. Two parallel overlapping polyline segments give the right distance and a witness pair on them.
5. Removing a kept measurement while its distance is failing leaves no stale row.

## Rulings

1. **A failed distance** reads "Couldn't measure" in the panel's Distance row (current and kept), and no distance is
   drawn. It is not retried while the picks and their solids are unchanged (the same basis fails the same way); any change
   to them measures again.
2. **Swift distances** cover point–point, point–polyline and polyline–polyline (closest points of segment pairs, a
   polyline's points in order, closed when its last point equals its first). Everything else still goes to the kernel.
   The Swift path runs synchronously on the caller's task (it is cheap: segments × segments; above 250,000 segment pairs
   it defers to the kernel).
3. **Hover pre-check:** each section piece's world bounds are computed once per scene; a piece is projected only when the
   pointer lies within its projected bounds grown by the pick reach. A bounds corner behind the camera makes the piece
   always tested (no false negatives).

---

### Task 1: A failed distance says so

**Files:** `Sources/CreatorApp/Measure/MeasureSession.swift`, `MeasureBook.swift`, `MeasurePanel.swift` (and its
`MeasurePanelText`), tests in `Tests/CreatorAppTests/Measure`.

- [ ] **Step 1: Failing tests.** `aFailedDistanceSaysSo` (session: a kernel that throws for `shortestDistance`; two picks;
  after settling the panel's value rows contain `MeasurePanelText.distanceFailed` = "Couldn't measure" and no distance
  dimension is drawn); `aKeptFailedDistanceSaysSo` (book: same, the kept row reads it); `aFailedDistanceIsNotRetriedUntilAnEdit`
  (count kernel calls: a second refresh with the same scene makes none; replacing a picked solid makes one, and when it
  now succeeds the row shows the number).
- [ ] **Step 2: Implement** Ruling 1: a `distanceFailed: Bool` (or an enum state) on the session's measurement and on
  `MeasureBook.Entry`, set when the kernel throws (not when cancelled), cleared when a new basis starts measuring.
- [ ] **Step 3:** `swift test --filter Measure`, then `CreatorAppTests` (bracket skipped). Commit
  `fix(measure): a failed distance says so`.

### Task 2: Distances to section outlines in Swift

**Files:** Create `Sources/CreatorKernel/PolylineDistance.swift`; modify the two callers of `shortestDistance` in
`Sources/CreatorApp/Measure` (session and book) to try it first; tests in `Tests/CreatorKernelTests/PolylineDistanceTests.swift`
and one app test.

**Interfaces:** `enum PolylineDistance { static func shortest(_ a: MeasureElement, _ b: MeasureElement) -> ShapeDistance? }`
— `nil` when either side is not a point or polyline, or over the pair limit (Ruling 2).

- [ ] **Step 1: Failing tests.** `pointToPoint`; `pointOnAPolylineIsZero` (witnesses equal the point);
  `pointToASegmentInterior` and `…ToAVertex`; `crossingPolylinesAreZero`; `parallelOverlappingSegments` (distance exact,
  both witnesses on their segments, the gap between them equals the distance); `aClosedPolylineIncludesItsClosingSegment`;
  `aCurveDefersToTheKernel` (`nil`); `agreesWithTheKernel` (macOS, `canImport(CreatorOCCT)`: ten random polyline pairs, same
  distance as `OCCTKernel.shortestDistance` within 1e-9 mm). App: `aSectionPolylineDistanceMakesNoKernelCall`.
- [ ] **Step 2: Implement** Ruling 2 with the standard clamped segment–segment closest-points routine (handle parallel and
  degenerate segments).
- [ ] **Step 3:** `swift test --filter PolylineDistanceTests`, `--filter Measure`, `swift test --filter CreatorKernelTests`.
  Commit `perf(measure): distances between outlines without OpenCascade`.

### Task 3: Hover projects only what is near the pointer

**Files:** `Sources/CreatorApp/Measure/MeasureSectionPick.swift` (and where its per-scene state lives); tests beside its
existing ones.

- [ ] **Step 1: Tests.** `aFarPieceIsNotProjected` (count projections through an injected `screenPoint` closure: a pointer
  far from every piece projects only bounds corners); `aPieceBehindTheCameraIsStillTested` (Ruling 3);
  `hoverPicksAreUnchanged` (the existing hover tests still pass unchanged).
- [ ] **Step 2: Implement** Ruling 3.
- [ ] **Step 3:** `swift test --filter Measure`. Commit `perf(measure): hover skips outlines far from the pointer`.

### Task 4: Parked minors and the load-sensitive test

**Files:** as each item needs, under `Sources/CreatorApp/Measure`, `Sources/CreatorKernel` (arc), `AppModel+Measure.swift`,
`AppModel+Scene.swift`; `Tests/CreatorAppTests/MeasurePanelTests.swift`.

For each item, first check it still holds in the current code; fix it if so, with a test where behaviour changes, and say
in the report which were already gone.

- [ ] `MeasureDimensions.curveShapes` uses `length == 0` as a sentinel: replace with an optional or explicit case.
- [ ] `firstIndex(of:)` on section pieces picks the first of two identical pieces: use the piece's index where it is known.
- [ ] An arc's start point is not checked against its radius in the kernel's curve measurement: check it (refuse or
  correct, matching how the kernel treats other malformed input).
- [ ] `MeasureSnap.nearest`'s `<=` tie keeps the last of equal candidates: make it `<` (first wins) unless a test relies on
  the last; say which.
- [ ] A witness test asserts with `||`: assert each witness exactly.
- [ ] Adding or removing a kept measurement refreshes twice; `refreshDimensions` runs twice per `refreshScene`: once each.
- [ ] `MeasurePanelTests.measuringShowsWhileTheDistanceIsHeld` fails under load: find the race (it uses a gate and
  `runUntilIdle`) and make it deterministic — wait on the state it asserts, not on time. Run it 20 times in a loop while a
  release build runs in the background: 20 passes.
- [ ] `swift test --filter CreatorAppTests` (bracket skipped), lint. Commit `fix(measure): parked minors and a steady panel test`.

### Task 5: Records

- [ ] CLAUDE.md's Measure part B sentence: the failed-distance copy, the Swift outline distances, the hover pre-check.
  Human checks ME-B: "a distance OpenCascade can't make reads 'Couldn't measure'".
- [ ] Full `swift test` (12 lines), lint, `scripts/linux-test.sh test`. Commit `docs(measure): follow-up records`.
