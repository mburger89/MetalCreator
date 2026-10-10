# Final-Review Follow-ups: Graph, Kernel and Sketch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the graph, kernel and sketch findings left open by the final review: edge-run counting (BUG-3), a projected edge whose kind changes upstream (BUG-4), and the quality items GK-1 to GK-8, GK-11 and the one live part of ED-14, each with a test that fails before its fix. Items found already fixed, unreachable or unreproducible are dropped with their evidence (table below).

**Architecture:** Every task is small and independent except Task 11 (needs Task 1). Behaviour fixes sit where the behaviour is: `Topology.runCount` (CreatorKernel), `TermBuilder` (CreatorSketch), `LoftNode`, `FakeKernel`, `KernelError`, the evaluator's one message, the sketch editor's Project refusal. The rest are pinning tests. No file format changes, no new module, no new dependency.

**Tech Stack:** Swift 6.4 strict concurrency, Swift Testing, `@MainActor @Observable` models, OCCT (Homebrew), SwiftLint. MetalUI is untouched.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` §5.3 rules 5 and 6 and its Errata (naming: merged faces), §3 (errors), §7.1 (Loft); `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` §7 and §8 and its Errata (S4). The triage entry for each item is `scratchpad/followups-triage.md` (cites file:line on master `4dff87b`).

**Branch and baseline:** worktree `/Users/maxburger/Developer/MetalCreator-fu-kernel`, branch `followups-kernel`, off master `4dff87b` (2142 tests). Run every command from that worktree; never `cd` into `/Users/maxburger/Developer/MetalCreator` or another worktree; never edit `Package.swift`'s MetalUI path; never touch `../MetalUI`.

**Shared files (merge order: editor, then kernel, then app).** No file here is a source file of the other tracks' areas (CreatorEditor, CreatorGraph/Groups, CreatorApp, CreatorViewport, scripts). The files below are shared or could be:

| File | Task | Other track | What the side that merges second must keep |
|---|---|---|---|
| `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` | 12 | app (owns shared docs; its Task 10 re-wraps the Errata bullet for edge keys) | The two edits sit in the same section, "Errata (naming: merged faces)". The bullet the app re-wraps is the first one, "§5.3 rules 3 and 5: a remembered edge key that matches no edge is retried **narrowed**" (about 8 lines, ending "so every pick that resolved before resolves the same way."). The kernel's bullet is a **separate bullet** that starts "§5.3 rule 6's runs, refined (follow-ups, kernel)" and goes in right after the rule-6 bullet ("§5.3 rule 6: a pick of every edge its key names also counts **runs**", ending "master warned \"Matched 2 edges, expected 1.\" there)."), before "- Errata (M6)'s polygon swap". The kernel never touches the rule-5 bullet's text or wrapping. The app, merging last, re-applies its re-wrap to the rule-5 bullet (anchored by its first words) on top of the kernel's merge, and keeps the kernel's bullet verbatim. If git reports a conflict in that hunk, take both: the app's re-wrapped rule-5 bullet, then the unchanged rule-6 bullet, then the kernel's. |
| `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` | 12 | app | Kernel adds one bullet at the end of "Errata (S4)" (after the bullet "§7's evaluate does not store the solve's warm start", before "## Errata (S5a)"). Keep it; the app track's edits to this spec (if any) go elsewhere. |
| `Sources/CreatorGraph/Evaluator+Running.swift` | 7 | editor (CreatorGraph) | One string literal changes (line 41-42). The editor track is on Groups, so a conflict is unlikely; if it touches that line, keep the new wording. |
| `Tests/CreatorGraphTests/OptionalOutputTests.swift` (also Task 8, one test appended; new file `Tests/CreatorGraphTests/Support/BoolListNode.swift`, not added to `testRegistry` because `GroupModelTests` counts that registry's nodes), `Tests/CreatorNodesTests/GraphParameterNodeTests.swift` | 7, 8 | editor/app | They assert the reworded sentence. A test that either track adds and that asserts the old sentence "which that node doesn't produce with its current settings." must take the new one: "which that node doesn't have, or doesn't produce with its current settings." |
| `Tests/CreatorNodesTests/BracketAcceptanceTests.swift` | 7 | editor (adds Groups acceptance in `BracketAcceptanceTests+Groups.swift`) | Task 7 adds a helper `expectSelections` and calls it twice; the editor's tests are in separate files. Keep both. |
| `Sources/CreatorKernel/KernelError.swift`, `Sources/CreatorKernel/Locale+Messages.swift` and `Double+Millimetres.swift` (new), `Sources/CreatorNodes/Support/Locale+Messages.swift` (deleted) | 3, 6 | any track that writes a message with a number | `Locale.messages` now lives in CreatorKernel and is `public`; CreatorNodes sees it through its existing `import CreatorKernel`. A new file in the other tracks that formats a number should keep using `.locale(.messages)`. |
| `CLAUDE.md` | none | app (owns it) | Kernel edits nothing there. Sentences that should change are listed under "CLAUDE.md sentences for the app track" below. |

**CLAUDE.md sentences for the app track** (kernel does not edit CLAUDE.md):

1. Line 225, "drift counts edges and runs (`EdgePick.runCount` ...)": add "a run is edges that continue each other end to end (ends within 1e-4 mm, leaving that point in opposite directions to within 0.01 rad), so two edges meeting at a corner are two runs".
2. Line 236, "Loft refuses profiles with holes. Create nodes only with `NodeRegistry.makeNode`. Numbers in node messages use `Locale.messages` (`Double.display`, `Int.display`).": say "Loft refuses profiles with holes, before it compares segment counts (`KernelError.loftWithHoles`)." and "Numbers in node and kernel messages use `Locale.messages` (defined in CreatorKernel; `Double.display`, `Int.display` in CreatorNodes; `KernelError.userMessage` uses it too)." The two general rules should be their own bullet (that is DOC-1, the app track's).
3. Line 38, "`FakeKernel` for tests": add "(it refuses extruded holes that lie outside the outline's bounds, as OCCT refuses strays)".
4. The sketch paragraph (S4, near line 170-178): add "a constraint or dimension on a projected edge of the wrong kind is skipped and named in a warning, like one on a suspended edge".

## Global Constraints

- Swift 6 strict concurrency; Swift Testing (`@Test`, `#expect`, `#require`); `@MainActor @Observable` models; behaviour in models and thin views.
- No force unwraps, no force `try`, no GCD; `FormatStyle` for numbers (`.formatted(.number...)`, never `String(format:)`); `foregroundStyle`, `clipShape(.rect(cornerRadius:))` and the other rules of `AGENTS.md` for any view code (this plan writes none).
- One type per file (Task 1 adds `TermBuilder+Terms.swift`, Task 4 `FakeKernel+Holes.swift`, Task 6 `Locale+Messages.swift` and `Double+Millimetres.swift` in CreatorKernel, Task 8 `Tests/CreatorGraphTests/Support/BoolListNode.swift`).
- `swiftlint lint --strict` reports zero violations before every commit (140-column lines, trailing commas in multi-line literals, function body at most 50 lines, type body at most 250).
- The `.mcgraph` file format version stays 4 and no key is added or removed: `EdgePick.runCount` keeps its meaning and its optional key (Task 2 only changes how a run is counted). Naming must keep every existing pick resolving the same way: `BracketAcceptanceTests` and `EdgeTagMatch*` tests pass unchanged.
- MetalUI gaps go in `docs/metalui-gaps.md` (the entry and the summary table row) and are never worked around. This plan finds none.
- A full `swift test` run passes only if the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear. Add up the "Test run with N tests" numbers for the count.
- New or changed lines add no compiler warnings (master has exactly one, `ContextMenuTests.swift:140` "'underPointer' mutated after capture by sendable closure").
- Test counts: master has 2142. After Task 1: master + 3 = 2145; Task 2: master + 8 = 2150; Task 3: master + 9 = 2151; Task 4: master + 12 = 2154; Task 5: master + 16 = 2158; Task 6: master + 20 = 2162; Task 7: master + 22 = 2164; Task 8: master + 37 = 2179; Task 9: master + 38 = 2180; Task 10: master + 39 = 2181; Task 11: master + 41 = 2183; Task 12 (docs only): 2183.
- Every behaviour fix gets a test that fails before the fix (the Red step shows how). Pinning tests for behaviour that is already right pass at once; they say so.

## Review Focus

The inputs and failure modes the specs imply but a straight reading of the tasks would not test, most likely first. Each has a test in the task that owns the code.

1. **A split edge whose halves end micrometres apart.** After a blend OCCT edge ends sit up to the vertex tolerance (often 1e-5 mm) from the shared vertex; the person expects one picked edge and no "now matches N edges" warning. Pinned: `halvesThatEndAFewMicrometresApartAreStillOneRun` (Task 2), and a hundredth of a millimetre stays a gap.
2. **Two different edges that meet at a corner.** Picking both must not read as one run (so that losing one is a warning, not silent). Pinned: `twoEdgesMeetingAtACornerAreTwoRuns` (Task 2), also for a bend of 1.7 degrees; a line and an arc that continue each other, and the halves of a split arc, are still one run.
3. **A sketch whose projected edge turned from a line into an arc.** The person expects the rest of the sketch to keep solving and to be told which constraint is ignored, not an error on the whole Sketch node. Pinned: `aProjectedEdgeThatChangedKindDoesNotFailTheSketch` (Task 1), `aConstraintOnAProjectedEdgeThatChangedKindIsIgnoredAndSaid` and `aSuspendedProjectionIsNotSaidTwice` (Task 11).
4. **A Loft of sections with holes and different segment counts.** The person expects the holes sentence, not advice to "loft between profiles of the same kind". Pinned: `holedSectionsAreRefusedBeforeTheirSegmentCountsAreCompared` (Task 3).
5. **Numbers in a kernel message on a non-English host.** "Radius 2.5 mm", never "2,5". Pinned: `userMessageWritesItsNumbersInLocaleMessages`, and with a German locale passed explicitly (so they bite on an en_US machine too) `aFilletFailureWritesEachNumberInTheLocaleItIsGiven`, `aSizeIsWrittenInTheLocaleItIsGiven`, `aChamferMessageWritesItsSizesInTheLocaleItIsGiven` (Task 6).

## Disposition of every item

**Fixed in this plan:** BUG-3 (Task 2), BUG-4 (Tasks 1 and 11), GK-1 (3), GK-2 (4, partly), GK-3 (5), GK-4 (6), GK-5 (7), GK-6 (7), GK-7 (7), GK-8 (8, partly: the mixed-absent broadcast is pinned there, `Evaluator+Running.swift` has its own path for it), GK-11 (5), ED-14 (9, one live part).

**Dropped, with the evidence** (each re-verified against master `4dff87b`):

| Item | Verdict |
|---|---|
| GK-9 (no cancellation checkpoint in the Sketch node's broadcast) | Already fixed. `Evaluator+Running.swift:77` calls `try Task.checkCancellation()` before every broadcast item, so a 50-item broadcast stops between items. A single solve is not cancellable mid-solve; left. |
| GK-10, GK-13 | Editor track's. |
| GK-12 (a) third operand cutting a merged face | Superseded. `EdgeKey.operandKeys` and `BracketAcceptanceTests+HoleThroughMergedSide` (`aHoleRimPickedOnAMergedSideSurvivesTheFlangeChangingWidth`, the hexagon swap) cover a hole through a merged side; spec Errata (naming) says so. |
| GK-12 (b) `locate` sums matches across references | Latent: harmless for one reference in every test and no case with several references fails. Left until multi-reference sketches are common. |
| GK-12 (c) `edges(resolving:)` has no Sources caller | It is the tested spelling of `resolution(of:).edges` (`EdgeKeyNarrowingTests`, `EdgeOperandKeyTests` call it 7 times). Deleting it would only rewrite tests. Left. |
| GK-14 (a) polish only below 1e-9 | Not reproduced. A point held on a line tangent to a circle (the double root that makes LM converge linearly) was solved from four starts (0.1/4.9, 1/4, 0.01/5.2, 2/5.5): every circle residual ended at about 1e-10, under `residualTolerance`, so polishing ran and nothing stopped in (1e-9, 1e-7]. Without a failing case the change is risk without evidence. |
| GK-14 (b) `mu` without a floor | The mechanism is real (`dampedStep` on a rank-deficient J returns `nil` for damping at or below 1e-12), but 44 accepted steps in a row are needed to get there. The same double-root sketch solved from 0.5 m, 6 m, 141 m and 10 km away, all `.solved`. Not reproduced; dropped. |
| GK-14 (c) pinched loop from a tangent circle | Not a bug: a circle tangent to a plate edge from inside gives the outer loop with the circle as a clockwise notch arc, and OCCT builds both faces: volumes `3 * (400 - 25 pi)` and `3 * 25 pi`, exact. Task 10 pins it. |
| ED-14 (a) radius / arc-end click snaps to a curve with no glyph | Already fixed: `DrawState.snapsToCurves` is false for `.circleAround` and `.arcFrom`; `SnapAndTangentCoverageTests` pins it. |
| ED-14 (b) hover scans curves twice | Performance only; `hover` already computes the anchor only for tools that place points. No failing case. |
| ED-14 (c) a reference dimension shows its stored value when the measurement is missing | Unreachable. A label needs a placement and a measurement needs the same shapes: whenever `solution.measurements[id]` is missing the placement is `nil` too (length on a projected arc, radius on a line, distance between two lines), so no label is drawn. The fallback is dead code. |
| ED-14 (d) "Only a flat face can hold a sketch." for a flat face with no normal | A face of kind `.plane` always has a normal from the kernel. Also `AppModel+NewSketch.swift` is CreatorApp, the app track's. The second half (only `left.first` of several skipped reasons) is live: Task 9. |
| ED-14 (e) inference tests missing | Already there: `SnapAndTangentCoverageTests` has the circle centre and the 3-point arc ends on a curve, the tangent from an arc's start and the 3-point end on the start's point. |
| GK-8: broadcast over items whose node call has different IDs ("mixed-ID") | The triage gives no behaviour to pin and no distinct code path was found: a broadcast item's tags differ only by item index, and `Topology` matching is by tag subsets, which the naming tests cover. |
| GK-8: `EdgeFilter` NaN bounds from a wired value | No node produces NaN; the result is an error with a misleading "is more than" text, safe. |
| GK-8: unused `.vector` on `VectorNode` | `VectorNode` binds `.number` controls; there is no unused control to remove. |
| GK-8: `midpointOrder` is not a strict weak ordering | Not changed: a saved pick's ordinals index that order, so any change moves saved picks in the pathological case. Comment added; see User decisions. |
| GK-2: overlapping holes in the FakeKernel | Not checked (see Task 4); stated in its doc comment. |

**Verified not as the triage described:** GK-5 cites `Evaluator+Running.swift:41-42` (still right); GK-3's tangent hole is rejected by OCCT's checker, not accepted (the test pins the rejection).

## User decisions (defaults chosen in this plan)

1. **BUG-4: say which constraint is ignored.** The triage fix only suspends it. Silent suspension leaves a person with a sketch that moved and no reason (the edge does not turn red, because only its pick is suspended). Default: suspend and add a warning "<constraint> is ignored: its projected edge is a different kind of curve now." (Task 11; Task 1 suspends only when the wrong-kind operand is, or is paired with, a projected edge, so the sentence is true). Alternatives: suspend silently (drop Task 11); also mark the projected edge suspended (red). Recommendation: the default.
2. **BUG-3: run-join tolerances.** Ends within 1e-4 mm (was 1e-6) and leaving in opposite directions within 0.01 rad. Alternative from the triage: have the C++ shim return vertex tolerances (rebuild of the shim, same result for the bracket). Recommendation: the default; both numbers are constants in `Topology+EdgeRuns.swift`.
3. **BUG-3 and saved picks.** No pick selects different edges (the bracket, naming and sketch-projection tests pass unchanged, and `runCount` only feeds the drift warning; no file is rewritten and no stop condition of the brief triggers). But the effect on **old saved files is wider than "can now warn"**. `EdgePick.hasDrifted` compares the current run count with the saved `runCount` once the edge count changes. Under the old rule a saved pick of a whole loop of straight edges that meet at corners (a plate's rim, a box's top face) recorded `runCount` 1 (the corners joined into one run; recorded because runs != matches). Under the new rule that loop is 4 runs. So **every such old pick now warns "Matched N edges, expected M." the first time its edge count changes** (an edge is split by a later fillet or cut, say), where it stayed silent before. The reverse also happens: an old pick whose `runCount` counted a split edge as two runs stops warning when it should not. New picks are not affected (they record `runCount` nil when runs equal matches, and the new count of a corner loop equals its edges). A changed edge count is itself a change the person usually wants to hear about, but for the corner-loop case the warning is a false alarm.
   Options: (A) accept (default); (B) mitigate: keep the old joiner as `Topology.legacyRunCount` (1e-6 mm, any direction, ~12 lines) and make `hasDrifted` take a third argument: when `runs != runCount`, still drift only if `legacyRuns != runCount` too. That keeps old corner-loop picks silent, costs one extra function, a changed `EdgePick.hasDrifted` signature (spec §5.3 rule 6 text) and a small risk of hiding drift when the two counts coincide; (C) drop Task 2 and keep the bug (a split edge warns, a corner pair can pass). Recommendation: (A), with the scope stated in the Errata bullet (Task 12) and in Task 2's Risks, so it is a known behaviour.
4. **GK-3: a hole touching the outline or another hole at one point** is rejected by OCCT with "a hole in the profile is outside the outline or overlaps another loop." Task 5 pins that. Alternative: a message that says "touches". Recommendation: keep the sentence (it is true enough and changing the shim's text is a larger change).
5. **GK-2: how strict the FakeKernel is.** It now refuses a hole whose sample points leave the outline's bounds (stray and most crossing holes) and still accepts a hole that crosses the outline inside those bounds, a hole touching the bounds, and overlapping holes. Alternative: a true point-in-loop test. Recommendation: the default; a test double that is wrong in the strict direction breaks graph tests for no reason.
6. **GK-8 `midpointOrder`**: leave the comparator (above). Alternative: quantise midpoints to 1e-6 before comparing, which is a strict weak ordering but renumbers ordinals for edges whose midpoints differ by under a micrometre. Recommendation: leave.

## New MetalUI gaps

None.

## File Structure

Created:
- `Sources/CreatorSketch/Solver/TermBuilder+Terms.swift` (Task 1): the constraint and dimension loops of `TermBuilder.build()`, moved out so the struct stays under 250 lines and `build()` under the complexity limit.
- `Sources/CreatorKernel/FakeKernel+Holes.swift` (Task 4): the stand-in's hole containment check.
- `Sources/CreatorKernel/Locale+Messages.swift` (Task 6): `Locale.messages`, moved from CreatorNodes. `Sources/CreatorKernel/Double+Millimetres.swift` (Task 6): the one formatter for sizes in kernel messages. `Tests/CreatorGraphTests/Support/BoolListNode.swift` (Task 8): a test node.
- Tests: `Tests/CreatorKernelTests/EdgeOrderTests.swift`, `KernelErrorMessageTests.swift`; `Tests/CreatorNodesTests/NodeEdgeCaseTests.swift`, `PieceCountTests.swift`.

Modified: `TermBuilder.swift`, `SolveFailure.swift`, `EdgeCurve+Ends.swift`, `Topology+EdgeRuns.swift`, `Topology+EdgePicks.swift` (comment), `KernelError.swift`, `FakeKernel.swift`, `LoftNode.swift`, `OCCTKernel.swift` (one line), `KernelError+Blend.swift`, `TopoRole+Codable.swift`, `Evaluator+Running.swift`, `EdgesByDirectionNode.swift` (comment), `SketchSolve.swift`, `SketchEditorModel+Project.swift`; the tests listed in each task; two spec Errata (Task 12).

Deleted: `Sources/CreatorNodes/Support/Locale+Messages.swift` (moved).

Helper for every run step below (from the worktree root): a "full run" is `swift test 2>&1 | tee /tmp/full.log`, then check `exit code 0` (use `swift test; echo "exit $?"`), `grep -c "recorded an issue\|failed after" /tmp/full.log` is `0`, and `grep -c "Test run with" /tmp/full.log` is `11`; sum the counts with `grep "Test run with" /tmp/full.log | awk '{s+=$5} END {print s}'`. Lint is `swiftlint lint --strict`. (If you keep logs in the session scratchpad rather than `/tmp`, that is fine.)

---

### Task 1: BUG-4, a projected edge of the wrong kind suspends its constraints

**Files:**
- Modify: `Sources/CreatorSketch/Solver/TermBuilder.swift`, `Sources/CreatorSketch/Solver/SolveFailure.swift`
- Create: `Sources/CreatorSketch/Solver/TermBuilder+Terms.swift`
- Test: `Tests/CreatorSketchTests/TermBuilderTests.swift`

**Interfaces:**
- Consumes: `ProjectionSource`, `ProjectedCurve` (`.arc(center:radius:start:end:)`), `SolveFailure` (internal, `reason`), `SketchConstraintRef`.
- Produces: `SolveFailure.blamesProjection: Bool` (default false); `TermBuilder.wrongKind(_:needs:blaming:)` (the operands that decide the refusal) and `TermBuilder.isProjected(_:)`; `TermBuilder.addConstraintTerms(to:)` and `addDimensionTerms(to:)` (internal, `throws(SolveFailure)`); `TermBuilder.Output.suspended` now also holds constraints and dimensions whose projected operand has the wrong kind. Task 11 reads `SketchSolution.suspended`.

**Why:** sketcher spec §7 says a projected edge that no longer fits is suspended, its constraints skipped, not deleted. Today `line()`/`circle()` throw `wrongKind` for a `.projected` operand of the other kind (`TermBuilder.swift` `line()`/`circle()`), `SketchSolver.solve` returns `.failed`, and the Sketch node errors. Reachable: constrain a projected line, then fillet that edge upstream (the Sketch node refreshes `source.curve` to an arc, `SketchProjections.resolve`). Only a refusal that a projected operand causes is turned into a suspension: the thrown `SolveFailure` says so (`blamesProjection`), set where the wrong-kind operand is a projected edge (`line()`, `circle()`) or where a pair check (Equal, Tangent) fails with a projected edge among the pair. A constraint that is wrong on its own (Parallel on a circle, even beside a projected line) still fails the sketch with its sentence.

- [ ] **Step 1: Write the failing tests (this reproduces BUG-4)**

Modify `Tests/CreatorSketchTests/TermBuilderTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -147,4 +147,54 @@ struct TermBuilderTests {
     }
 
+    /// A projected edge that was a line when the constraint was made and is an arc now (a fillet added upstream).
+    func sketchWithProjectedArc() -> (sketch: Sketch, arc: SketchEntityID) {
+        var sketch = Sketch()
+        let arc = sketch.add(SketchEntity(.projected(ProjectionSource(
+            reference: "e", curve: .arc(center: .zero, radius: 5, start: .degrees(0), end: .degrees(90))))))
+        return (sketch, arc)
+    }
+
+    @Test func aConstraintOrDimensionOnAProjectedEdgeOfTheWrongKindIsSuspended() throws {
+        var (sketch, arc) = sketchWithProjectedArc()
+        let line = sketch.addLine(Vector2(0, 10), Vector2(8, 11))
+        let horizontal = sketch.add(.horizontal(arc))
+        let equal = sketch.add(.equal(line, arc))
+        let length = sketch.addDimension(.length(arc), value: 4)
+        let output = try build(sketch)
+        #expect(output.suspended == [.constraint(horizontal), .constraint(equal), .dimension(length)])
+        #expect(output.terms.isEmpty)
+    }
+
+    @Test func aProjectedEdgeThatChangedKindDoesNotFailTheSketch() throws {
+        var (sketch, arc) = sketchWithProjectedArc()
+        let line = sketch.addLine(.zero, Vector2(10, 3))
+        sketch.add(.horizontal(line))
+        sketch.addDimension(.length(line), value: 10)
+        let onArc = sketch.add(.horizontal(arc))
+        let solution = SketchSolver.solve(sketch)
+        if case .failed(let reason) = solution.status {
+            Issue.record("the sketch failed: \(reason)")
+            return
+        }
+        #expect(solution.suspended == [.constraint(onArc)], "only the constraint on the arc is skipped")
+        let (start, end) = sketch.ends(line)
+        #expect(isClose(try #require(solution.points[start]).y, try #require(solution.points[end]).y), "the line still solves")
+    }
+
+    /// The projected line is not what is wrong here (a circle was never a line), so the sketch still fails with the
+    /// sentence, and the constraint is not suspended in its place.
+    @Test func aWrongKindOperandThatIsNotProjectedStillFailsTheSketch() {
+        var sketch = Sketch()
+        let projected = sketch.add(SketchEntity(.projected(ProjectionSource(
+            reference: "e", curve: .line(Vector2(0, 0), Vector2(10, 0))))))
+        let circle = sketch.addCircle(center: Vector2(0, 20), radius: 3)
+        let parallel = sketch.add(.parallel(projected, circle))
+        if case .failed(let reason) = SketchSolver.solve(sketch).status {
+            #expect(reason == "\(sketch.label(of: .constraint(parallel))) needs two lines.")
+        } else {
+            Issue.record("the sketch should fail")
+        }
+    }
+
     @Test func refusalsAreInPlainLanguage() {
         var sketch = Sketch()
```


- [ ] **Step 2: Run them to see the bug**

Run: `swift test --filter TermBuilderTests`
Expected: FAIL, two tests. `aConstraintOrDimensionOnAProjectedEdgeOfTheWrongKindIsSuspended` records `Caught error: SolveFailure(reason: "Horizontal on Projected edge 1 needs a line.")`; `aProjectedEdgeThatChangedKindDoesNotFailTheSketch` records "the sketch failed". `aWrongKindOperandThatIsNotProjectedStillFailsTheSketch` passes at once: it guards the fix against suspending too much.

- [ ] **Step 3: Implement**

`build()` gains two catch clauses (in the new file), and the two loops move there because `build()` would exceed SwiftLint's cyclomatic complexity (12 > 10) and the struct its 250-line body limit (251) if left inline. The catch is narrow: it suspends a constraint only when the failure says a projected edge caused it.

Modify `Sources/CreatorSketch/Solver/SolveFailure.swift` (a `+` line added):

```diff
@@ -2,3 +2,6 @@
 struct SolveFailure: Error, Hashable, Sendable {
     var reason: String
+    /// The refusal is a wrong-kind operand that is, or pairs with, a projected edge. Such an edge's kind follows the model
+    /// upstream, so the constraint is suspended rather than the sketch failed (sketcher spec §7).
+    var blamesProjection = false
 }
```

Modify `Sources/CreatorSketch/Solver/TermBuilder.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -14,5 +14,6 @@ struct TermBuilder {
     struct Output: Sendable {
         var terms: [SolverTerm]
-        /// Constraints and dimensions skipped because they touch a suspended projected edge.
+        /// Constraints and dimensions skipped because they touch a suspended projected edge, or a projected edge
+        /// whose kind no longer fits them (a line that an upstream fillet made an arc).
         var suspended: [SketchConstraintRef]
     }
@@ -20,30 +21,7 @@ struct TermBuilder {
     func build() throws(SolveFailure) -> Output {
         try validateEntities()
-        var terms: [SolverTerm] = []
-        var suspended: [SketchConstraintRef] = []
-        for id in sketch.constraintIDs {
-            guard let constraint = sketch.constraints[id] else { continue }
-            let ref = SketchConstraintRef.constraint(id)
-            try requireExisting(constraint.entities, ref)
-            if touchesSuspended(constraint.entities) {
-                suspended.append(ref)
-                continue
-            }
-            for equation in try equations(for: constraint, ref) where !isTriviallyMet(equation) {
-                terms.append(SolverTerm(role: .user(ref), equation: equation))
-            }
-        }
-        for id in sketch.dimensionIDs {
-            guard let dimension = sketch.dimensions[id], dimension.isDriving else { continue }
-            let ref = SketchConstraintRef.dimension(id)
-            try requireExisting(dimension.kind.entities, ref)
-            if touchesSuspended(dimension.kind.entities) {
-                suspended.append(ref)
-                continue
-            }
-            try validate(dimension)
-            let equation = try equation(for: dimension, ref)
-            if !isTriviallyMet(equation) { terms.append(SolverTerm(role: .user(ref), equation: equation)) }
-        }
+        var output = Output(terms: [], suspended: [])
+        try addConstraintTerms(to: &output)
+        try addDimensionTerms(to: &output)
         for id in sketch.entityIDs {
             guard case .arc(let center, let start, let end) = sketch.entities[id]?.kind else { continue }
@@ -51,7 +29,7 @@ struct TermBuilder {
                                               start: try point(start, ref: nil, needs: ""),
                                               end: try point(end, ref: nil, needs: ""))
-            terms.append(SolverTerm(role: .implicit, equation: equation))
+            output.terms.append(SolverTerm(role: .implicit, equation: equation))
         }
-        return Output(terms: terms, suspended: suspended)
+        return output
     }
 
@@ -87,7 +65,13 @@ struct TermBuilder {
     // MARK: Operands
 
-    func wrongKind(_ ref: SketchConstraintRef?, needs: String) -> SolveFailure {
+    /// `blaming` are the operands that are the wrong kind, or whose kind decides the refusal: when one is a projected
+    /// edge, the kind followed the model upstream and the constraint is suspended instead of failing the sketch.
+    func wrongKind(_ ref: SketchConstraintRef?, needs: String, blaming operands: [SketchEntityID] = []) -> SolveFailure {
         let name = ref.map { sketch.label(of: $0) } ?? "A constraint"
-        return SolveFailure(reason: "\(name) needs \(needs).")
+        return SolveFailure(reason: "\(name) needs \(needs).", blamesProjection: operands.contains(where: isProjected))
+    }
+
+    func isProjected(_ id: SketchEntityID) -> Bool {
+        if case .projected = sketch.entities[id]?.kind { true } else { false }
     }
 
@@ -103,5 +87,5 @@ struct TermBuilder {
         case .projected(let source):
             if case .line(let a, let b) = source.curve { return LineOperand(start: .constant(a), end: .constant(b)) }
-            throw wrongKind(ref, needs: needs)
+            throw wrongKind(ref, needs: needs, blaming: [id])
         default:
             throw wrongKind(ref, needs: needs)
@@ -123,5 +107,5 @@ struct TermBuilder {
                 return CircleOperand(center: .constant(center), radius: .constant(radius), endpoints: [])
             case .line:
-                throw wrongKind(ref, needs: needs)
+                throw wrongKind(ref, needs: needs, blaming: [id])
             }
         default:
@@ -217,5 +201,5 @@ struct TermBuilder {
                 return [.equalLength(try line(a, ref: ref, needs: needs), try line(b, ref: ref, needs: needs))]
             }
-            guard isCircular(a), isCircular(b) else { throw wrongKind(ref, needs: needs) }
+            guard isCircular(a), isCircular(b) else { throw wrongKind(ref, needs: needs, blaming: [a, b]) }
             return [.equalRadius(try circle(a, ref: ref, needs: needs), try circle(b, ref: ref, needs: needs))]
         case .midpoint(let p, let l):
@@ -239,5 +223,5 @@ struct TermBuilder {
         if isLine(a) || isLine(b) {
             let (lineID, circleID) = isLine(a) ? (a, b) : (b, a)
-            guard !isLine(circleID) else { throw wrongKind(ref, needs: needs) }
+            guard !isLine(circleID) else { throw wrongKind(ref, needs: needs, blaming: [a, b]) }
             let l = try line(lineID, ref: ref, needs: needs)
             let c = try circle(circleID, ref: ref, needs: needs)
```

Create `Sources/CreatorSketch/Solver/TermBuilder+Terms.swift`:

```swift
extension TermBuilder {
    /// Adds a term for each constraint, skipping (and recording) those that touch a suspended projected edge or
    /// one whose kind no longer fits them.
    func addConstraintTerms(to output: inout Output) throws(SolveFailure) {
        for id in sketch.constraintIDs {
            guard let constraint = sketch.constraints[id] else { continue }
            let ref = SketchConstraintRef.constraint(id)
            try requireExisting(constraint.entities, ref)
            if touchesSuspended(constraint.entities) {
                output.suspended.append(ref)
                continue
            }
            let equations: [Equation]
            do {
                equations = try self.equations(for: constraint, ref)
            } catch where error.blamesProjection {
                output.suspended.append(ref)
                continue
            }
            for equation in equations where !isTriviallyMet(equation) {
                output.terms.append(SolverTerm(role: .user(ref), equation: equation))
            }
        }
    }

    /// The same for each driving dimension.
    func addDimensionTerms(to output: inout Output) throws(SolveFailure) {
        for id in sketch.dimensionIDs {
            guard let dimension = sketch.dimensions[id], dimension.isDriving else { continue }
            let ref = SketchConstraintRef.dimension(id)
            try requireExisting(dimension.kind.entities, ref)
            if touchesSuspended(dimension.kind.entities) {
                output.suspended.append(ref)
                continue
            }
            try validate(dimension)
            let equation: Equation
            do {
                equation = try self.equation(for: dimension, ref)
            } catch where error.blamesProjection {
                output.suspended.append(ref)
                continue
            }
            if !isTriviallyMet(equation) { output.terms.append(SolverTerm(role: .user(ref), equation: equation)) }
        }
    }
}
```

What stays a failure, on purpose: a wrong-kind operand that is not projected (the existing `refusalsAreInPlainLanguage` pins "Parallel on Line 1 and Circle 1 needs two lines."; the new `aWrongKindOperandThatIsNotProjectedStillFailsTheSketch` pins the same with a projected line beside the circle), and every other `SolveFailure` (a missing entity, a bad value). `equal(projected line, circle)` and `tangent(projected line, line)` are suspended, because the pair check cannot tell which side changed and a projected edge is the only side whose kind can change under the person.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter TermBuilderTests`
Expected: PASS (15 tests).

- [ ] **Step 5: Full run, lint, commit**

Full run: exit 0, no issue lines, 11 "Test run with" lines, sum **2145** (master + 3). `swiftlint lint --strict`: zero violations.

```bash
git add Sources/CreatorSketch/Solver Tests/CreatorSketchTests/TermBuilderTests.swift
git commit -m "fix(sketch): a projected edge of the wrong kind suspends its constraints instead of failing the sketch"
```

---

### Task 2: BUG-3, edge runs join only where edges continue each other

**Files:**
- Modify: `Sources/CreatorKernel/EdgeCurve+Ends.swift`, `Sources/CreatorKernel/Topology+EdgeRuns.swift`
- Test: `Tests/CreatorKernelTests/EdgeRunTests.swift`

**Interfaces:**
- Consumes: `EdgeCurve.ends`, `Vector3.dot/cross/normalized`.
- Produces: `EdgeCurve.endDirections: [Vector3]` (same order and count as `ends`; empty when `ends` is empty or the curve is degenerate); `Topology.runCount(_:)` unchanged signature; `Topology.runJoinTolerance = 1e-4`, `Topology.runJoinAngle = 0.01` (internal).

**Why:** `runCount` joined any two edges whose end points were within 1e-6 mm: (a) OCCT edge ends sit up to the vertex tolerance (often 1e-5) from a shared vertex, so a split edge counted as two runs and warned; (b) two distinct edges meeting at a corner counted as one run, so losing one of them could pass without a warning. No saved file changes: `EdgePick.runCount` keeps its meaning (see User decisions 2 and 3). The shim is not touched: tangents come from the exact line or circle in `EdgeCurve`.

- [ ] **Step 1: Write the failing tests**

Modify `Tests/CreatorKernelTests/EdgeRunTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -61,4 +61,53 @@ struct EdgeRunTests {
     }
 
+    @Test func twoEdgesMeetingAtACornerAreTwoRuns() {
+        let across = line(0, .zero, Vector3(10, 0, 0)), up = line(1, Vector3(10, 0, 0), Vector3(10, 10, 0))
+        #expect(Topology.runCount([across, up]) == 2, "a right-angle corner is two edges to a person picking")
+        let almost = line(2, Vector3(10, 0, 0), Vector3(20, 0.5, 0))
+        #expect(Topology.runCount([across, almost]) == 2, "even a shallow bend is a corner")
+    }
+
+    @Test func aStraightRunAndATangentArcAreOneRun() {
+        let across = line(0, .zero, Vector3(10, 0, 0))
+        // A quarter arc leaving (10, 0) upwards: centre (10, 5), radius 5, from (10, 0) round to (15, 5).
+        let arc = EdgeInfo(id: EdgeID(1), kind: .circle, direction: .unitZ, length: 5 * .pi / 2, midpoint: Vector3(13.5, 1.5, 0),
+                           convexity: .convex, faces: [FaceID(0), FaceID(1)],
+                           curve: .circle(center: Vector3(10, 5, 0), axis: .unitZ, radius: 5, start: Vector3(10, 0, 0), sweep: .pi / 2))
+        #expect(Topology.runCount([across, arc]) == 1, "the arc leaves the line's end along the line")
+        let corner = line(2, Vector3(10, 0, 0), Vector3(10, 10, 0))
+        #expect(Topology.runCount([corner, arc]) == 2, "the arc turns away from a line that leaves the same point at an angle")
+    }
+
+    @Test func halvesOfASplitArcAreOneRun() {
+        func piece(_ id: Int, from degrees: Double) -> EdgeInfo {
+            let start = Vector3(5 * cos(degrees * .pi / 180), 5 * sin(degrees * .pi / 180), 0)
+            return EdgeInfo(id: EdgeID(id), kind: .circle, direction: .unitZ, length: 1, midpoint: start, convexity: .convex,
+                            faces: [FaceID(0), FaceID(1)],
+                            curve: .circle(center: .zero, axis: .unitZ, radius: 5, start: start, sweep: .pi / 4))
+        }
+        #expect(Topology.runCount([piece(0, from: 0), piece(1, from: 45)]) == 1)
+        #expect(Topology.runCount([piece(0, from: 0), piece(1, from: 90)]) == 2, "a gap")
+    }
+
+    /// OCCT edge ends sit up to the vertex tolerance (often 1e-5 mm) from the vertex they share after a blend.
+    @Test func halvesThatEndAFewMicrometresApartAreStillOneRun() {
+        let first = line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6))
+        let second = line(1, Vector3(-30, 12.00002, 6), Vector3(-30, 15, 6))
+        #expect(Topology.runCount([first, second]) == 1)
+        let apart = line(2, Vector3(-30, 12.01, 6), Vector3(-30, 15, 6))
+        #expect(Topology.runCount([first, apart]) == 2, "a hundredth of a millimetre is a real gap")
+    }
+
+    @Test func anEdgeLeavesEachEndAlongItself() throws {
+        #expect(EdgeCurve.line(start: .zero, end: Vector3(0, 4, 0)).endDirections == [Vector3(0, 1, 0), Vector3(0, -1, 0)])
+        let quarter = EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2)
+        let directions = quarter.endDirections
+        try #require(directions.count == 2)
+        #expect(near(directions[0], Vector3(0, 1, 0)), "counter-clockwise from (2, 0)")
+        #expect(near(directions[1], Vector3(1, 0, 0)), "back along the arc from (0, 2)")
+        #expect(EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: 2 * .pi).endDirections.isEmpty)
+        #expect(EdgeCurve.line(start: .zero, end: .zero).endDirections.isEmpty)
+    }
+
     /// Face 0: top. Face 1: the side. `split` cuts the top-side edge in two at y = 12.
     func topology(split: Bool) -> Topology {
```


- [ ] **Step 2: Run to see the compile error, then add `endDirections` alone**

Run: `swift test --filter EdgeRunTests`
Expected: build FAIL, "value of type 'EdgeCurve' has no member 'endDirections'".

Add only the new property (source part A):

Modify `Sources/CreatorKernel/EdgeCurve+Ends.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -16,3 +16,21 @@ extension EdgeCurve {
         }
     }
+
+    /// For each of `ends`, the unit direction in which the edge leaves that end (into the edge). Two edges that
+    /// meet at a point continue each other when they leave it in opposite directions. Empty when the ends aren't
+    /// known or the curve is degenerate.
+    public var endDirections: [Vector3] {
+        switch self {
+        case .line(let start, let end):
+            guard let along = (end - start).normalized else { return [] }
+            return [along, -along]
+        case .circle(let center, let axis, _, let start, let sweep):
+            let points = ends
+            guard points.count == 2, let k = axis.normalized,
+                  let first = k.cross(start - center).normalized, let last = k.cross(points[1] - center).normalized else { return [] }
+            // Counter-clockwise about the axis for a positive sweep, clockwise for a negative one.
+            let travel = sweep < 0 ? -1.0 : 1.0
+            return [first * travel, -last * travel]
+        }
+    }
 }
```


Run: `swift test --filter EdgeRunTests`
Expected: FAIL, three tests, the bug itself: `twoEdgesMeetingAtACornerAreTwoRuns` (`runCount([across, up]) == 2` fails, it is 1), `aStraightRunAndATangentArcAreOneRun` (`runCount([corner, arc]) == 2` fails) and `halvesThatEndAFewMicrometresApartAreStillOneRun` (`runCount([first, second]) == 1` fails, it is 2). `anEdgeLeavesEachEndAlongItself` and `halvesOfASplitArcAreOneRun` pass.

- [ ] **Step 3: Replace `runCount`**

Modify `Sources/CreatorKernel/Topology+EdgeRuns.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -1,8 +1,17 @@
 import CreatorGeometry
+import Foundation
 
 extension Topology {
-    /// How many runs `edges` form: chains of edges that meet end to end (to 1e-6 mm). An edge an operation
-    /// split in two is still one run, so a run is what a person picking sees as one edge. An edge whose ends
-    /// aren't known (no `curve`, or a full circle) is a run of its own.
+    /// Edge ends this close (mm) meet. OCCT edge curves can end up to the vertex tolerance (often 1e-5 mm) from the
+    /// vertex they share after a blend, so the old 1e-6 split one edge into two runs.
+    static let runJoinTolerance = 1e-4
+    /// Edges meeting at a point continue each other when they leave it within this many radians of opposite
+    /// directions, so two distinct edges that meet at a corner stay two runs.
+    static let runJoinAngle = 0.01
+
+    /// How many runs `edges` form: chains of edges that continue each other end to end (ends within
+    /// `runJoinTolerance`, leaving that point in opposite directions). An edge an operation split in two is still one
+    /// run, so a run is what a person picking sees as one edge; two edges that meet at a corner are two. An edge whose
+    /// ends aren't known (no `curve`, or a full circle) is a run of its own.
     public static func runCount(_ edges: [EdgeInfo]) -> Int {
         var parent = Array(edges.indices)
@@ -12,8 +21,11 @@ extension Topology {
             return index
         }
-        let ends = edges.map { $0.curve?.ends ?? [] }
+        let ends = edges.map { edge in zip(edge.curve?.ends ?? [], edge.curve?.endDirections ?? []).map { (point: $0, leaving: $1) } }
+        let straightest = -cos(runJoinAngle)
         for i in edges.indices {
             for j in edges.indices where j > i {
-                let meet = ends[i].contains { p in ends[j].contains { q in (p - q).length <= 1e-6 } }
+                let meet = ends[i].contains { p in
+                    ends[j].contains { q in (p.point - q.point).length <= runJoinTolerance && p.leaving.dot(q.leaving) <= straightest }
+                }
                 if meet { parent[root(j)] = root(i) }
             }
```


- [ ] **Step 4: Run the tests, then the naming tests**

Run: `swift test --filter EdgeRunTests`
Expected: PASS (19 tests).
Run: `swift test --filter "BracketAcceptanceTests|EdgeTagMatch|SketchProjection|EdgeKeyNarrowingTests"`
Expected: PASS unchanged: every existing pick resolves the same way. If any fails, stop: that is a change to how a saved pick resolves and goes to the user (User decision 3), not a test to edit.

- [ ] **Step 5: Full run, lint, commit**

Full run: sum **2150** (master + 8). Lint clean.

```bash
git add Sources/CreatorKernel Tests/CreatorKernelTests/EdgeRunTests.swift
git commit -m "fix(naming): edge runs join only edges that continue each other, to the vertex tolerance"
```

---

### Task 3: GK-1, a Loft of holed sections says so before comparing segment counts

**Files:**
- Modify: `Sources/CreatorKernel/KernelError.swift`, `Sources/CreatorKernel/FakeKernel.swift`, `Sources/CreatorOCCT/OCCTKernel.swift`, `Sources/CreatorNodes/Solids/LoftNode.swift`
- Test: `Tests/CreatorNodesTests/LoftTransformNodeTests.swift`

**Interfaces:**
- Produces: `KernelError.loftWithHoles` (public static, `.invalidInput("A loft can't use profiles with holes yet.")`), used by both kernels and the Loft node, so the sentence exists once.

- [ ] **Step 1: Write the failing test**

The Sketch node can output holed regions; here one sketch gives a four-segment plate with a hole and a triangle, wired together into `sections`.

Modify `Tests/CreatorNodesTests/LoftTransformNodeTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -47,4 +47,18 @@ struct LoftTransformNodeTests {
     }
 
+    /// Regions of one sketch: a 60 × 40 plate with a hole (four outer segments) and, apart from it, a triangle (three).
+    @Test func holedSectionsAreRefusedBeforeTheirSegmentCountsAreCompared() async throws {
+        var plate = RectangleSketch(width: 60, height: 40)
+        plate.addHole(center: Vector2(15, 20), radius: 5)
+        let corners = [Vector2(100, 0), Vector2(110, 0), Vector2(105, 8)].map { plate.sketch.addPoint($0) }
+        for k in 0..<3 { plate.sketch.addLine(from: corners[k], to: corners[(k + 1) % 3]) }
+        var h = Harness()
+        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(plate.sketch)])
+        let loft = h.add(LoftNode.self)
+        h.wire(sketch, "profiles", to: loft, "sections")
+        let report = try await h.run([loft], kernel: OCCTKernel())
+        #expect(report.error(loft) == "A loft can't use profiles with holes yet.")
+    }
+
     @Test func oneSectionIsNotALoft() async throws {
         var h = Harness()
```


- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter LoftTransformNodeTests`
Expected: FAIL, `holedSectionsAreRefusedBeforeTheirSegmentCountsAreCompared`: the error is the "Loft sections need the same number of segments, but section 1 has ..." text instead of the holes sentence.

- [ ] **Step 3: Implement**

Modify `Sources/CreatorKernel/KernelError.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -9,4 +9,7 @@ public enum KernelError: Error, Equatable, Sendable {
     case exportFailed(String)
 
+    /// The refusal every kernel gives a loft through profiles with holes, and the Loft node gives it first.
+    public static let loftWithHoles = KernelError.invalidInput("A loft can't use profiles with holes yet.")
+
     public var userMessage: String {
         switch self {
```

Modify `Sources/CreatorKernel/FakeKernel.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -43,5 +43,5 @@ public actor FakeKernel: Kernel {
         operationLog.append("loft")
         guard sections.allSatisfy(\.holes.isEmpty) else {
-            throw KernelError.invalidInput("A loft can't use profiles with holes yet.")
+            throw KernelError.loftWithHoles
         }
         throw KernelError.unsupported("loft")
```

Modify `Sources/CreatorOCCT/OCCTKernel.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -58,5 +58,5 @@ public actor OCCTKernel: Kernel {
         guard sections.count >= 2 else { throw KernelError.invalidInput("A loft needs at least two sections.") }
         guard sections.allSatisfy(\.holes.isEmpty) else {
-            throw KernelError.invalidInput("A loft can't use profiles with holes yet.")
+            throw KernelError.loftWithHoles
         }
         guard Set(sections.map(\.segments.count)).count == 1 else {
```

Modify `Sources/CreatorNodes/Solids/LoftNode.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -5,5 +5,6 @@ import CreatorKernel
 /// A solid through a list of closed sections, in list order (spec §7.1, Solids). Wire a
 /// broadcast profile in, for example a Circle over several planes. Sections must have the
-/// same number of segments; resampling is deferred, so a mismatch is explained instead.
+/// same number of segments; resampling is deferred, so a mismatch is explained instead. Sections with holes are
+/// refused first (the kernels don't loft them yet).
 public enum LoftNode: NodeDefinition {
     public static let typeID = "creator.loft"
@@ -23,4 +24,6 @@ public enum LoftNode: NodeDefinition {
                 + "Wire in a list of profiles, such as a Circle broadcast over several planes.")
         }
+        // Checked first: a holed section is refused whatever its segment count, so the count mismatch is not the news.
+        guard sections.allSatisfy({ $0.holes.isEmpty }) else { throw KernelError.loftWithHoles }
         let counts = sections.map(\.segments.count)
         if let mismatch = counts.indices.first(where: { counts[$0] != counts[0] }) {
```


- [ ] **Step 4: Run the tests**

Run: `swift test --filter "LoftTransformNodeTests|FakeKernelHoleTests|HoleConformanceTests"`
Expected: PASS (the kernels' own `aLoftRefusesProfilesWithHoles` tests still see the same sentence).

- [ ] **Step 5: Full run, lint, commit**

Full run: sum **2151** (master + 9). Lint clean.

```bash
git add Sources Tests/CreatorNodesTests/LoftTransformNodeTests.swift
git commit -m "fix(nodes): a Loft of holed sections gives the holes message before the segment-count one"
```

---

### Task 4: GK-2, the FakeKernel refuses stray holes as OCCT does

**Files:**
- Create: `Sources/CreatorKernel/FakeKernel+Holes.swift`
- Modify: `Sources/CreatorKernel/FakeKernel.swift`
- Test: `Tests/CreatorKernelTests/FakeKernelHoleTests.swift`

**Interfaces:**
- Produces: `FakeKernel.holesAreInsideOutline(_ profile: Profile2D) -> Bool` (static, internal); `extrude` throws `.operationFailed(operation: "extrude", reason: "a hole in the profile is outside the outline or overlaps another loop.")`, the exact error `HoleConformanceTests` pins for OCCT.

**Why:** a graph test on the FakeKernel passed with inflated bounds where OCCT errors. `KernelUnderTest` runs every conformance test on OCCT only, and adding `.fake` would run volume tests the fake cannot pass, so the parity is a small test file instead.

- [ ] **Step 1: Write the failing tests**

Modify `Tests/CreatorKernelTests/FakeKernelHoleTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -57,3 +57,29 @@ struct FakeKernelHoleTests {
         }
     }
+
+    /// The OCCT kernel's message (HoleConformanceTests): the stand-in must fail the same way, or a graph test passes on it
+    /// that fails for a person.
+    static let strayHole = KernelError.operationFailed(
+        operation: "extrude", reason: "a hole in the profile is outside the outline or overlaps another loop.")
+
+    @Test func aHoleOutsideTheOutlineIsRefused() async {
+        let stray = Profile2D(plane: .xy, outer: outline, holes: [Profile2D.circle(radius: 1, center: Vector2(20, 0), plane: .xy).segments])
+        await #expect(throws: Self.strayHole) {
+            try await FakeKernel().extrude(stray, distance: 1, mode: .oneSided, tag: tag)
+        }
+    }
+
+    @Test func aHoleCrossingTheOutlineIsRefused() async {
+        let crossing = Profile2D(plane: .xy, outer: outline,
+                                 holes: [Profile2D.circle(radius: 2, center: Vector2(4, 0), plane: .xy).segments])
+        await #expect(throws: Self.strayHole) {
+            try await FakeKernel().extrude(crossing, distance: 1, mode: .oneSided, tag: tag)
+        }
+    }
+
+    @Test func aHoleInsideTheOutlineStillExtrudes() async throws {
+        let inside = Profile2D(plane: .xy, outer: outline, holes: [Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments])
+        let solid = try await FakeKernel().extrude(inside, distance: 1, mode: .oneSided, tag: tag)
+        #expect(solid.bounds.size.x == 10)
+    }
 }
```


- [ ] **Step 2: Run to see them fail**

Run: `swift test --filter FakeKernelHoleTests`
Expected: FAIL, `aHoleOutsideTheOutlineIsRefused` and `aHoleCrossingTheOutlineIsRefused` ("an error was expected but none was thrown"). `aHoleInsideTheOutlineStillExtrudes` passes (it guards against over-refusing).

- [ ] **Step 3: Implement**

Create `Sources/CreatorKernel/FakeKernel+Holes.swift`:

```swift
import CreatorGeometry
import Foundation

extension FakeKernel {
    /// Whether every hole of `profile` lies inside its outline's bounds. The OCCT kernel refuses a hole outside the
    /// outline, crossing it, or overlapping another (`a hole in the profile is outside the outline or overlaps another
    /// loop`); this stand-in checks what its bounds-only geometry can: each hole's sample points against the outline's
    /// bounds. A hole that crosses the outline inside those bounds, or overlaps another hole, still passes.
    static func holesAreInsideOutline(_ profile: Profile2D) -> Bool {
        guard !profile.holes.isEmpty else { return true }
        let corners = profile.outer.flatMap(\.boundingPoints)
        guard let first = corners.first else { return true }
        var low = first
        var high = first
        for corner in corners {
            low = Vector2(min(low.x, corner.x), min(low.y, corner.y))
            high = Vector2(max(high.x, corner.x), max(high.y, corner.y))
        }
        let slack = 1e-9
        return profile.holes.joined().flatMap(samples).allSatisfy {
            $0.x >= low.x - slack && $0.x <= high.x + slack && $0.y >= low.y - slack && $0.y <= high.y + slack
        }
    }

    /// Points on `segment`: its ends and middle, and eight steps round an arc (a full circle's quadrants included).
    private static func samples(of segment: Segment2D) -> [Vector2] {
        switch segment {
        case .line(let a, let b):
            return [a, (a + b) * 0.5, b]
        case .arc(let center, let radius, let start, let end):
            return (0...8).map { step in
                let angle = start.radians + (end.radians - start.radians) * Double(step) / 8
                return center + Vector2(cos(angle), sin(angle)) * radius
            }
        }
    }
}
```

Modify `Sources/CreatorKernel/FakeKernel.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -23,4 +23,8 @@ public actor FakeKernel: Kernel {
             throw KernelError.invalidInput("The profile is not a closed loop.")
         }
+        guard Self.holesAreInsideOutline(profile) else {
+            throw KernelError.operationFailed(
+                operation: "extrude", reason: "a hole in the profile is outside the outline or overlaps another loop.")
+        }
         let normal = profile.plane.normal
         let (back, front) = mode == .symmetric ? (-distance / 2, distance / 2) : (0, distance)
```


The check is bounds-only on purpose (User decision 5): it never refuses a legitimate hole, because arcs are sampled (ends, middle and eighths) against the outline's conservative bounds.

- [ ] **Step 4: Run, full run, lint, commit**

Run: `swift test --filter FakeKernelHoleTests`: PASS. Full run: sum **2154** (master + 12). Lint clean.

```bash
git add Sources/CreatorKernel Tests/CreatorKernelTests/FakeKernelHoleTests.swift
git commit -m "fix(kernel): the FakeKernel refuses a hole outside the outline's bounds, as OCCT does"
```

---

### Task 5: GK-3 and GK-11, OCCT pins for touching holes and notched hole walls, and a TopoRole that encodes only what it decodes

**Files:**
- Modify: `Sources/CreatorKernel/TopoRole+Codable.swift`
- Test: `Tests/CreatorOCCTTests/HoleConformanceTests.swift`, `Tests/CreatorOCCTTests/ClockwiseArcConformanceTests.swift`, `Tests/CreatorKernelTests/TopoRoleLoopTests.swift`

**Interfaces:** `TopoRole.encode(to:)` throws `EncodingError.invalidValue` for `.side(loop: n < 0, ...)`, the case `init(from:)` already refuses.

**Why:** a hole tangent to the outline or to another hole at one point is unpinned (OCCT's answer is whichever it is; the header of `HoleConformanceTests` says "without touching"); the hole-wall naming on a notched hole confirms that `TopoDS::Edge(make.Edge().Reversed())` keeps edge identity for the history lookup on hole loops (the outer loop is covered). `.side(loop: -1, ...)` could be encoded but not decoded.

- [ ] **Step 1: Write the tests**

Modify `Tests/CreatorOCCTTests/HoleConformanceTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -101,4 +101,28 @@ struct HoleConformanceTests {
     }
 
+    /// OCCT's answer to a hole that touches the outline or another hole at one point, pinned so a change in OCCT is seen:
+    /// the checker rejects the face, and the error is the plain one for a stray hole.
+    @Test(arguments: KernelUnderTest.allCases)
+    func aHoleTouchingTheOutlineAtAPointIsAPlainError(_ under: KernelUnderTest) async {
+        let touching = Profile2D(plane: .xy, outer: plate.outer,
+                                 holes: [Profile2D.circle(radius: 2, center: Vector2(3, 0), plane: .xy).segments])
+        let error = await #expect(throws: KernelError.self) {
+            try await under.make().extrude(touching, distance: 1, mode: .oneSided, tag: newTag())
+        }
+        #expect(error == .operationFailed(operation: "extrude",
+                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
+    }
+
+    @Test(arguments: KernelUnderTest.allCases)
+    func twoHolesTouchingAtAPointAreAPlainError(_ under: KernelUnderTest) async {
+        let holes = [Vector2(-2, 0), Vector2(2, 0)].map { Profile2D.circle(radius: 2, center: $0, plane: .xy).segments }
+        let error = await #expect(throws: KernelError.self) {
+            try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: holes), distance: 1,
+                                           mode: .oneSided, tag: newTag())
+        }
+        #expect(error == .operationFailed(operation: "extrude",
+                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
+    }
+
     @Test(arguments: KernelUnderTest.allCases)
     func aZeroAreaHoleIsAPlainError(_ under: KernelUnderTest) async {
```

Modify `Tests/CreatorOCCTTests/ClockwiseArcConformanceTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -43,4 +43,23 @@ struct ClockwiseArcConformanceTests {
     }
 
+    /// The notch stays one hole wall of its own loop, named by its segment: the history lookup after the shim reverses the
+    /// edge for a clockwise arc finds the hole loop's wall as it does the outer loop's (`aNotchedPlateExtrudesToItsAnalyticVolume`).
+    @Test(arguments: KernelUnderTest.allCases)
+    func aNotchedHolesWallsAreNamedByTheirLoopAndSegment(_ under: KernelUnderTest) async throws {
+        let tag = newTag()
+        let outline = Profile2D.rectangle(width: 40, height: 30, plane: .xy).segments
+        let profile = Profile2D(plane: .xy, outer: outline, holes: [Self.notchedPlate(offset: Vector2(-10, -5))])
+        let solid = try await under.make().extrude(profile, distance: 2, mode: .oneSided, tag: tag)
+        // Four outer walls, six hole walls, two caps.
+        #expect(solid.topology.faces.count == 12)
+        for segment in 0..<6 {
+            #expect(faces(solid, role: .side(loop: 1, segment: segment), of: tag).count == 1, "hole wall \(segment)")
+        }
+        let notchWall = try #require(faces(solid, role: .side(loop: 1, segment: 3), of: tag).first)
+        #expect(notchWall.kind == .cylinder)
+        #expect(isClose(notchWall.area, 2 * 4 * Double.pi))
+        #expect(!solid.topology.faces.contains { face in face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
+    }
+
     @Test(arguments: KernelUnderTest.allCases)
     func aNotchedPlateRevolves(_ under: KernelUnderTest) async throws {
```

Modify `Tests/CreatorKernelTests/TopoRoleLoopTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -50,4 +50,10 @@ struct TopoRoleLoopTests {
     }
 
+    /// `.side(loop: -1, ...)` can be built, but decoding refuses it, so encoding must too: a file that can't be read back
+    /// is never written. Only the OCCT tagger makes side roles, and its loops are never negative.
+    @Test func aNegativeLoopIsNotEncoded() {
+        #expect(throws: EncodingError.self) { try JSONEncoder().encode(TopoRole.side(loop: -1, segment: 2)) }
+    }
+
     @Test func anOldEdgePickDecodesWithOuterWalls() throws {
         let node = NodeID()
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "HoleConformanceTests|ClockwiseArcConformanceTests|TopoRoleLoopTests"`
Expected: FAIL only `aNegativeLoopIsNotEncoded` ("an error was expected but none was thrown and '37 bytes' was returned"). The three OCCT tests pass at once: they pin what OCCT does today (touching holes are rejected by the checker with the stray-hole sentence; a notched hole has six hole walls `side(loop: 1, segment: 0...5)`, the notch a cylinder of area `2 * 4 * pi`, no unnamed face).

- [ ] **Step 3: Implement**

Modify `Sources/CreatorKernel/TopoRole+Codable.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -31,4 +31,8 @@ extension TopoRole: Codable {
             try container.encode(Kind.endCap, forKey: .role)
         case .side(let loop, let segment):
+            guard loop >= 0 else {
+                throw EncodingError.invalidValue(loop, EncodingError.Context(
+                    codingPath: encoder.codingPath, debugDescription: "A side face's loop can't be negative."))
+            }
             try container.encode(Kind.side, forKey: .role)
             if loop != 0 {
```


- [ ] **Step 4: Run, full run, lint, commit**

Run the filter above: PASS. Full run: sum **2158** (master + 16). Lint clean.

```bash
git add Sources/CreatorKernel/TopoRole+Codable.swift Tests
git commit -m "test(kernel): pin touching holes and notched hole walls on OCCT; TopoRole refuses to encode a negative loop"
```

---

### Task 6: GK-4, kernel messages write numbers in Locale.messages

**Files:**
- Create: `Sources/CreatorKernel/Locale+Messages.swift`, `Sources/CreatorKernel/Double+Millimetres.swift`
- Delete: `Sources/CreatorNodes/Support/Locale+Messages.swift`
- Modify: `Sources/CreatorKernel/KernelError.swift`, `Sources/CreatorOCCT/KernelError+Blend.swift`
- Test: `Tests/CreatorKernelTests/KernelErrorMessageTests.swift` (new), `Tests/CreatorOCCTTests/UnbuildableBlendTests.swift`

**Interfaces:** `Locale.messages` (now `public`, in CreatorKernel; CreatorNodes' `.locale(.messages)` calls resolve to it through `import CreatorKernel`); `Double.millimetreText(locale: Locale = .messages)` (`package`; the one formatter behind every number in a kernel message, used by `KernelError` and `KernelError+Blend`); `KernelError.message(locale:)` (internal; `userMessage` is `message(locale: .messages)`); `KernelError.blendFailed/invalidBlend` gain a `locale: Locale = .messages` parameter (internal).

**Why:** node messages are pinned to en_US but `KernelError.userMessage` and the blend messages used the process locale, so on de_DE a fillet failure read "Radius 2,5 mm ... max ≈ 5,9 mm". `CreatorKernel` cannot import `CreatorNodes`, so the locale moves down. The formatter takes the locale as a parameter so the tests can pass a German one **explicitly**: they then fail on any machine (en_US included) if a number is written in another locale than the one given, and `userMessage` is pinned to `Locale.messages` by the second test.

- [ ] **Step 1: Write the tests**

Create `Tests/CreatorKernelTests/KernelErrorMessageTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorKernel

/// Kernel messages read the same on every machine: numbers use `Locale.messages` (en_US), as node messages do, so a
/// German host doesn't get "Radius 2,5 mm" beside a node's "2.5". The messages take their locale as a parameter, so a
/// German one can be passed in and the test fails on any machine if a number is written in another locale.
struct KernelErrorMessageTests {
    let tooLarge = KernelError.filletFailed(radius: 2.5, maxRadius: 5.9, reason: "")
    let unapplied = KernelError.filletFailed(radius: 2.5, maxRadius: nil, reason: "it can't.")
    let german = Locale(identifier: "de_DE")

    @Test func aFilletFailureWritesEachNumberInTheLocaleItIsGiven() {
        #expect(tooLarge.message(locale: german) == "Radius 2,5 mm is too large for the selected edges (max ≈ 5,9 mm).")
        #expect(unapplied.message(locale: german) == "Radius 2,5 mm could not be applied: it can't.")
    }

    @Test func userMessageWritesItsNumbersInLocaleMessages() {
        #expect(tooLarge.userMessage == tooLarge.message(locale: .messages))
        #expect(tooLarge.userMessage == "Radius 2.5 mm is too large for the selected edges (max ≈ 5.9 mm).")
        #expect(unapplied.userMessage == "Radius 2.5 mm could not be applied: it can't.")
    }

    @Test func aSizeIsWrittenInTheLocaleItIsGiven() {
        #expect(1234.5.millimetreText(locale: german) == "1.234,5")
        #expect(2.5.millimetreText() == "2.5", "Locale.messages unless told otherwise")
        #expect(2.456.millimetreText(locale: .messages) == "2.46")
    }
}
```

Modify `Tests/CreatorOCCTTests/UnbuildableBlendTests.swift` (a `+` line added; the file also gains `import Foundation` at the top):

```diff
@@ -1 +1,2 @@
+import Foundation
 import Testing
@@ -87,2 +88,12 @@ struct UnbuildableBlendTests {
     }
+
+    /// A chamfer's sizes are written into its reason where it is built, so they take the locale given there; a fillet's
+    /// are written by `KernelError.message(locale:)` (`KernelErrorMessageTests`).
+    @Test func aChamferMessageWritesItsSizesInTheLocaleItIsGiven() {
+        let german = Locale(identifier: "de_DE")
+        #expect(KernelError.blendFailed(size: 2.5, chamfer: true, largest: 9.9, locale: german).userMessage
+            == "Chamfer failed: the selected edges can't be chamfered by 2,5 mm (max ≈ 9,9 mm).")
+        #expect(KernelError.invalidBlend(size: 2.5, largest: nil, edgeCount: 2, chamfer: true, locale: german).userMessage
+            == "Chamfer failed: chamfering the 2 selected edges by 2,5 mm gives a broken solid, even by 0,1 mm.")
+    }
 }
```

- [ ] **Step 2: Run to see the Red**

Run: `swift test --filter "KernelErrorMessageTests|UnbuildableBlendTests"`
Expected: build FAIL, "value of type 'KernelError' has no member 'message'", "type 'Locale' has no member 'messages'", "extra argument 'locale' in call". After Step 3 these tests are behavioural on any host, which was checked by mutation: with `Double.millimetreText` changed to ignore its `locale` (`.locale(.messages)`), `aFilletFailureWritesEachNumberInTheLocaleItIsGiven`, `aSizeIsWrittenInTheLocaleItIsGiven` and `aChamferMessageWritesItsSizesInTheLocaleItIsGiven` fail on an en_US machine. What no test can show on an en_US host is that the process locale is no longer consulted by `userMessage`; that follows from `userMessage` being `message(locale: .messages)` and from the formatter being the only number formatter in the two files.

- [ ] **Step 3: Implement**

Create `Sources/CreatorKernel/Locale+Messages.swift`:

```swift
import Foundation

extension Locale {
    /// The locale for numbers and lists inside user-facing messages, the kernel's and the nodes'. Pinned so messages (and
    /// the tests that assert them) read "1,000" and "2.5" on every machine. Messages are English until the app has a
    /// string catalog; switch this to the user's locale then.
    public static let messages = Locale(identifier: "en_US")
}
```

Create `Sources/CreatorKernel/Double+Millimetres.swift`:

```swift
import Foundation

extension Double {
    /// A size in millimetres for a message: up to two decimals, written in `locale` ("2.5" in `Locale.messages`, "2,5"
    /// in a German one). The one formatter behind every number in a kernel message, so a call site can't forget the locale.
    package func millimetreText(locale: Locale = .messages) -> String {
        formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}
```

Delete `Sources/CreatorNodes/Support/Locale+Messages.swift`.

Modify `Sources/CreatorKernel/KernelError.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -10,3 +10,7 @@ public enum KernelError: Error, Equatable, Sendable {
 
-    public var userMessage: String {
+    /// The message, with its numbers in `Locale.messages`.
+    public var userMessage: String { message(locale: .messages) }
+
+    /// The message with its numbers written in `locale`. Only `userMessage` and the tests call it.
+    func message(locale: Locale) -> String {
         switch self {
@@ -17,6 +21,6 @@ public enum KernelError: Error, Equatable, Sendable {
         case .filletFailed(let radius, let maxRadius?, _):
-            "Radius \(radius.formatted(.number.precision(.fractionLength(0...2)))) mm is too large for the selected edges "
-                + "(max ≈ \(maxRadius.formatted(.number.precision(.fractionLength(0...2)))) mm)."
+            "Radius \(radius.millimetreText(locale: locale)) mm is too large for the selected edges "
+                + "(max ≈ \(maxRadius.millimetreText(locale: locale)) mm)."
         case .filletFailed(let radius, nil, let reason):
-            "Radius \(radius.formatted(.number.precision(.fractionLength(0...2)))) mm could not be applied: \(reason)"
+            "Radius \(radius.millimetreText(locale: locale)) mm could not be applied: \(reason)"
         case .unsupported(let operation):
```

Modify `Sources/CreatorOCCT/KernelError+Blend.swift` (the two functions gain `locale: Locale = .messages` and write every size with `millimetres(_, locale)`; the private helper now takes the locale and calls the shared formatter):

```diff
@@ -4,5 +4,5 @@ import Foundation
 extension KernelError {
-    static func blendFailed(size: Double, chamfer: Bool, largest: Double?) -> KernelError {
+    static func blendFailed(size: Double, chamfer: Bool, largest: Double?, locale: Locale = .messages) -> KernelError {
         if chamfer {
-            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? ""
+            let limit = largest.map { " (max ≈ \(millimetres($0, locale)) mm)" } ?? ""
             return .operationFailed(operation: "chamfer",
-                                    reason: "the selected edges can't be chamfered by \(millimetres(size)) mm\(limit).")
+                                    reason: "the selected edges can't be chamfered by \(millimetres(size, locale)) mm\(limit).")
@@ -16,17 +16,18 @@ extension KernelError {
-    static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool) -> KernelError {
+    static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool,
+                             locale: Locale = .messages) -> KernelError {
         let edges = edgeCount == 1 ? "the selected edge" : "the \(edgeCount) selected edges"
-        let noneFound = BlendGrid.triesSmallest(below: size) ? ", even by \(millimetres(BlendGrid.step)) mm" : ""
+        let noneFound = BlendGrid.triesSmallest(below: size) ? ", even by \(millimetres(BlendGrid.step, locale)) mm" : ""
         if chamfer {
-            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? noneFound
+            let limit = largest.map { " (max ≈ \(millimetres($0, locale)) mm)" } ?? noneFound
             return .operationFailed(operation: "chamfer",
-                                    reason: "chamfering \(edges) by \(millimetres(size)) mm gives a broken solid\(limit).")
+                                    reason: "chamfering \(edges) by \(millimetres(size, locale)) mm gives a broken solid\(limit).")
         }
@@ -34,3 +35,4 @@ extension KernelError {
-            : "rounding \(edges) by \(millimetres(size)) mm gives a broken solid."
+            : "rounding \(edges) by \(millimetres(size, locale)) mm gives a broken solid."
         return .filletFailed(radius: size, maxRadius: largest, reason: reason)
     }
 
-    private static func millimetres(_ value: Double) -> String {
-        value.formatted(.number.precision(.fractionLength(0...2)))
+    /// `Double.millimetreText`, the formatter `KernelError.userMessage` uses too.
+    private static func millimetres(_ value: Double, _ locale: Locale) -> String {
+        value.millimetreText(locale: locale)
     }
```


- [ ] **Step 4: Run, full run, lint, commit**

Run: `swift test --filter "KernelErrorMessageTests|UnbuildableBlendTests|InvalidBlendTests"`: PASS (21 tests, 4 of them new). Full run: sum **2162** (master + 20). Lint clean.

```bash
git add Sources Tests
git commit -m "fix(kernel): kernel messages write numbers in Locale.messages like node messages"
```

---

### Task 7: GK-5, GK-6, GK-7, a truthful missing-socket message and two catalog and acceptance assertions

**Files:**
- Modify: `Sources/CreatorGraph/Evaluator+Running.swift`
- Test: `Tests/CreatorGraphTests/OptionalOutputTests.swift`, `Tests/CreatorNodesTests/GraphParameterNodeTests.swift`, `Tests/CreatorNodesTests/CatalogTests.swift`, `Tests/CreatorNodesTests/BracketAcceptanceTests.swift`

**Why:** (GK-5) a link to a socket that vanished because of a `typeVersion` migration or a hand edit reads "which that node doesn't produce with its current settings", which blames settings. The behaviour (an error, not a silent `.blocked`) is right and is pinned. (GK-6) `inspectorControlsBindRealSocketsOfTheRightType` skips settings before the socket lookup, so an input socket named like a setting would share an `inputValues` key unnoticed. (GK-7) the bracket's reopen block checks only the chamfer keys.

- [ ] **Step 1: Update and add the tests**

The two existing tests that pin the old sentence move to the new one; one new test wires an output the node has no spec for at all.

Modify `Tests/CreatorGraphTests/OptionalOutputTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -26,5 +26,15 @@ struct OptionalOutputTests {
         let report = try await evaluator().evaluate(graph([node, add], [link(node, "sometimes", add, "a")]), demand: [add.id])
         #expect(report.results[add.id]?.state == .error("“a” is wired to “sometimes”, "
-                + "which that node doesn't produce with its current settings."))
+                + "which that node doesn't have, or doesn't produce with its current settings."))
+    }
+
+    /// A link to an output the node has no spec for at all (a socket renamed by a migration, or a hand-edited file) reads the
+    /// same way, and is an error, never a silent `.blocked`.
+    @Test func wiringAnOutputTheNodeDoesNotHaveIsAnError() async throws {
+        let node = makeNode(OptionalOutputNode.self, ["flag": .bool(true)])
+        let add = makeNode(AddNode.self)
+        let report = try await evaluator().evaluate(graph([node, add], [link(node, "renamed", add, "a")]), demand: [add.id])
+        #expect(report.results[add.id]?.state == .error("“a” is wired to “renamed”, "
+                + "which that node doesn't have, or doesn't produce with its current settings."))
     }
 }
```

Modify `Tests/CreatorNodesTests/GraphParameterNodeTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -38,5 +38,6 @@ struct GraphParameterNodeTests {
         h.wire(node, "integer", to: integer, "value")
         let report = try await h.run([integer])
-        #expect(report.error(integer) == "“value” is wired to “integer”, which that node doesn't produce with its current settings.")
+        #expect(report.error(integer)
+            == "“value” is wired to “integer”, which that node doesn't have, or doesn't produce with its current settings.")
     }
```

Modify `Tests/CreatorNodesTests/CatalogTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -47,4 +47,13 @@ struct CatalogTests {
     }
 
+    /// A setting and an input socket of one name would share one `inputValues` key; the control test above skips settings
+    /// before it looks sockets up, so this is what notices.
+    @Test func noInputSocketIsNamedLikeASetting() {
+        for definition in BuiltInNodes.all {
+            let clashes = definition.inputs.map(\.name).filter { NodeSetting.all.contains($0) }
+            #expect(clashes.isEmpty, "\(definition.typeID) has input sockets named like settings: \(clashes)")
+        }
+    }
+
     @Test func inspectorControlsBindRealSocketsOfTheRightType() {
         for definition in BuiltInNodes.all {
```

Modify `Tests/CreatorNodesTests/BracketAcceptanceTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -128,4 +128,14 @@ struct BracketAcceptanceTests {
     }
 
+    /// The fillet rule still names the same 4 edges by the same keys, and the chamfer rule the same 7.
+    func expectSelections(_ document: DocumentModel, _ bracket: Bracket, fillet: Set<EdgeKey>, chamfer: Set<EdgeKey>,
+                          sourceLocation: SourceLocation = #_sourceLocation) throws {
+        let filletSet = try edgeSet(document, bracket.filletEdges), chamferSet = try edgeSet(document, bracket.chamferEdges)
+        #expect(keys(filletSet) == fillet, sourceLocation: sourceLocation)
+        #expect(keys(chamferSet) == chamfer, sourceLocation: sourceLocation)
+        #expect(filletSet.edges.count == 4, sourceLocation: sourceLocation)
+        #expect(chamferSet.edges.count == 7, sourceLocation: sourceLocation)
+    }
+
     @Test func bracketKeepsItsEdgeSelectionsAcrossParameterChangesAndExports() async throws {
         let kernel = OCCTKernel()
@@ -154,8 +164,5 @@ struct BracketAcceptanceTests {
         await document.waitForEvaluation()
         expectAllOK(document, "Width 90, 6 holes")
-        #expect(keys(try edgeSet(document, bracket.filletEdges)) == filletKeys)
-        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == chamferKeys)
-        #expect(try edgeSet(document, bracket.filletEdges).edges.count == 4)
-        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)
+        try expectSelections(document, bracket, fillet: filletKeys, chamfer: chamferKeys)
         let cut = try #require(document.results[bracket.cut.id]?.outputs?["solid"]?.solids?.first)
         for item in 0..<6 {
@@ -171,5 +178,5 @@ struct BracketAcceptanceTests {
         await reopened.waitForEvaluation()
         expectAllOK(reopened, "reopened")
-        #expect(keys(try edgeSet(reopened, bracket.chamferEdges)) == chamferKeys)
+        try expectSelections(reopened, bracket, fillet: filletKeys, chamfer: chamferKeys)
 
         // Export STEP (re-read through OCCT) and STL (closed and manifold).
```


`expectSelections` replaces both four-line groups of fillet/chamfer assertions (the longer test body would exceed SwiftLint's 50-line function limit) and adds the fillet keys and the two edge counts (4 and 7) after the reopen.

- [ ] **Step 2: Run to see the Red**

Run: `swift test --filter "OptionalOutputTests|GraphParameterNodeTests"`
Expected: FAIL, three: `wiringAnAbsentOutputExplainsWhy`, `wiringAnOutputTheNodeDoesNotHaveIsAnError` and `wiringAnOutputTheParameterDoesNotFillIsExplained` (the sentence still has the old wording). `CatalogTests` and the bracket test pass at once (GK-6 and GK-7 are pinning tests: no catalog node clashes today, and the reopened bracket already keeps its fillet keys).

- [ ] **Step 3: Implement**

Modify `Sources/CreatorGraph/Evaluator+Running.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -40,5 +40,5 @@ extension Evaluator {
                 guard let value = outputs[link.from.socket] else {
                     return .failed("“\(spec.name)” is wired to “\(link.from.socket)”, "
-                        + "which that node doesn't produce with its current settings.")
+                        + "which that node doesn't have, or doesn't produce with its current settings.")
                 }
                 guard let converted = value.converted(to: spec.type) else {
```


- [ ] **Step 4: Run, full run, lint, commit**

Run: `swift test --filter "OptionalOutputTests|GraphParameterNodeTests|CatalogTests|BracketAcceptanceTests"`: PASS. Full run: sum **2164** (master + 22). Lint clean.

```bash
git add Sources/CreatorGraph/Evaluator+Running.swift Tests
git commit -m "fix(graph): the missing-socket message no longer blames settings; pin catalog socket names and the reopened bracket's selections"
```

---

### Task 8: GK-8, the ledger tests that pin node edges

**Files:**
- Create: `Tests/CreatorNodesTests/NodeEdgeCaseTests.swift`, `Tests/CreatorNodesTests/PieceCountTests.swift`, `Tests/CreatorKernelTests/EdgeOrderTests.swift`, `Tests/CreatorGraphTests/Support/BoolListNode.swift`
- Modify: `Tests/CreatorNodesTests/EdgeTagMatchTests.swift`, `Tests/CreatorGraphTests/OptionalOutputTests.swift`, `Sources/CreatorNodes/Selection/EdgesByDirectionNode.swift` (doc comment), `Sources/CreatorKernel/Topology+EdgePicks.swift` (doc comment)

**Why:** the M3 ledger listed tests nobody wrote. These pin behaviour that is already right, so they pass at once; each is a one-line statement of a limit or a refusal (14 in the new files and `EdgeTagMatchTests`, plus the broadcast one): a grid over 10,000 points whose counts are each within bounds; a negative corner radius; a zero rotation axis at angle 0 (refused); rotation about an off-origin axis followed by the move; a smooth (not ruled) loft through three circles; an Output of an empty list; a closed polyline's closing point dropped; Edge Set Op on equal but separate solids (the cache-eviction case in its doc comment); `midpointOrder` ties by ID; `pieceCount` joins only through edges with two faces; an ordinal past the matches; an optional output that one broadcast item leaves out (a list `[true, false]` into the optional-output test node), which `Evaluator+Running.swift` treats as absent for the whole result ("An optional output that any iteration left out is absent from the result"), so what is wired to it is an error. The two doc comments record the 90 degree limit of Edges by Direction (the slider stops at 45) and the comparator's tie rule (User decision 6).

- [ ] **Step 1: Add the tests and comments**

Create `Tests/CreatorNodesTests/NodeEdgeCaseTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Inputs the node tests didn't reach (final review, M3 ledger): limits, refusals and graph shapes at the edge of what a
/// node accepts, each pinned as the nodes behave now.
struct NodeEdgeCaseTests {
    @Test func aGridLargerThanTheLimitIsExplainedEvenWhenEachCountIsWithin() async throws {
        var h = Harness()
        // 200 × 100 = 20,000 points: each count is allowed, the product is not.
        let grid = h.add(GridPointsNode.self, ["countX": .integer(200), "countY": .integer(100)])
        let report = try await h.run([grid])
        #expect(report.error(grid) == "The grid can have at most 10,000 points.")
    }

    @Test func aNegativeCornerRadiusIsExplained() async throws {
        var h = Harness()
        let rounded = h.add(RoundedRectangleNode.self, ["cornerRadius": .number(-1)])
        let report = try await h.run([rounded])
        #expect(report.error(rounded) == "“cornerRadius” can't be negative.")
    }

    @Test func aZeroAxisIsRefusedEvenWhenTheAngleIsZero() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let transform = h.add(TransformNode.self, ["angle": .number(0), "axisDirection": .vector(.zero)])
        h.wire(box, "solid", to: transform, "solid")
        let report = try await h.run([transform])
        #expect(report.error(transform) == "The rotation axis direction can't be zero.")
    }

    /// A 10 × 10 × 10 box on XY (centre (0, 0, 5)), turned 90° about the vertical line through (10, 0), then moved (1, 2, 3):
    /// the centre goes (0, 0) → (10, −10) by the turn, then to (11, −8, 8).
    @Test func rotationAboutAnOffOriginAxisIsFollowedByTheMove() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let transform = h.add(TransformNode.self, [
            "move": .vector(Vector3(1, 2, 3)), "angle": .number(90),
            "axisOrigin": .vector(Vector3(10, 0, 0)), "axisDirection": .vector(.unitZ),
        ])
        h.wire(box, "solid", to: transform, "solid")
        let solid = try onlySolid(try await h.run([transform], kernel: OCCTKernel()), transform)
        #expect(isClose(solid.bounds.center, Vector3(11, -8, 8), tolerance: 1e-6))
        #expect(isClose(solid.bounds.size, Vector3(10, 10, 10), tolerance: 1e-6))
    }

    @Test func aSmoothLoftThroughThreeCirclesIsASolid() async throws {
        var h = Harness()
        let diameters = h.add(SeriesNode.self, ["start": .number(20), "step": .number(-6), "count": .integer(3)])
        let heights = h.add(SeriesNode.self, ["start": .number(0), "step": .number(10), "count": .integer(3)])
        let plane = h.add(PlaneNode.self)
        h.wire(heights, "values", to: plane, "offset")
        let circles = h.add(CircleNode.self)
        h.wire(diameters, "values", to: circles, "diameter")
        h.wire(plane, "plane", to: circles, "plane")
        let loft = h.add(LoftNode.self, ["ruled": .bool(false)])
        h.wire(circles, "profile", to: loft, "sections")
        let kernel = OCCTKernel()
        let solid = try onlySolid(try await h.run([loft], kernel: kernel), loft)
        let smooth = try await volume(solid, kernel)
        // Between the cylinder of the smallest section (r 4) and of the largest (r 10) over the same 20 mm.
        #expect(smooth > Double.pi * 16 * 20 && smooth < Double.pi * 100 * 20)
        #expect(isClose(solid.bounds.size.z, 20, relative: 1e-4))
    }

    @Test func anOutputOfAnEmptyListWarnsThereIsNothingToExport() async throws {
        var h = Harness()
        let none = h.add(GridPointsNode.self, ["countX": .integer(0), "countY": .integer(1), "total": .integer(0)])
        let box = h.box(10, 10, 10)
        let copies = h.add(TransformNode.self)
        h.wire(box, "solid", to: copies, "solid")
        h.wire(none, "points", to: copies, "move")
        let output = h.add(OutputNode.self, output: true)
        h.wire(copies, "solid", to: output, "solid")
        let report = try await h.run([output])
        #expect(report.warning(output) == "There is nothing to preview or export.")
    }

    // MARK: Called directly, with inputs no wire produces

    func context(_ definition: any NodeDefinition.Type) -> EvalContext {
        EvalContext(node: BuiltInNodes.registry.makeNode(definition.typeID), item: 0, parameters: [:])
    }

    @Test func aClosingPointEqualToTheFirstIsDroppedFromAClosedPolyline() async throws {
        let corners = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 0, 0)]
        let inputs = NodeInputs(item: 0, slots: [
            "points": .list(corners.map(Scalar.vector)), "closed": .item(.bool(true)), "plane": .item(.plane(.xy)),
        ])
        let outputs = try await PolylineNode.evaluate(inputs, kernel: FakeKernel(), context: context(PolylineNode.self))
        guard case .profile(let profile)? = outputs.values["profile"] else {
            Issue.record("no profile: \(outputs)")
            return
        }
        #expect(profile.outer.count == 3, "three corners, closed by the third segment, not four")
        #expect(profile.isClosed)
    }

    @Test func edgeSetsOfEqualButSeparateSolidsCombine() async throws {
        let kernel = FakeKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let profile = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let first = try await kernel.extrude(profile, distance: 5, mode: .oneSided, tag: tag)
        let second = try await kernel.extrude(profile, distance: 5, mode: .oneSided, tag: tag)
        #expect(first !== second, "two instances, as when the cache evicts one rule's solid and keeps the other")
        let edges = first.topology.edges.map(\.id)
        let inputs = NodeInputs(item: 0, slots: [
            "a": .item(.edgeSet(EdgeSet(solid: first, edges: Array(edges.prefix(2))))),
            "b": .item(.edgeSet(EdgeSet(solid: second, edges: Array(edges.dropFirst(1).prefix(2))))),
            "operation": .item(.integer(2)),
        ])
        let outputs = try await EdgeSetOpNode.evaluate(inputs, kernel: kernel, context: context(EdgeSetOpNode.self))
        guard case .edgeSet(let combined)? = outputs.values["edges"] else {
            Issue.record("no edge set: \(outputs)")
            return
        }
        #expect(combined.edges == [edges[1]], "the intersection of the two overlapping pairs")
    }
}
```

Create `Tests/CreatorNodesTests/PieceCountTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorNodes

/// `Topology.pieceCount` (a result of more than one piece is a multi-body compound, spec §11): faces count as joined by an
/// edge between two of them, and by nothing else.
struct PieceCountTests {
    func face(_ id: Int) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [])
    }

    func edge(_ id: Int, faces: [Int]) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: .unitX, length: 1, midpoint: .zero, convexity: .convex,
                 faces: faces.map(FaceID.init))
    }

    @Test func facesJoinedByAnEdgeAreOnePiece() {
        let joined = Topology(faces: [face(0), face(1), face(2)], edges: [edge(0, faces: [0, 1]), edge(1, faces: [1, 2])])
        #expect(joined.pieceCount == 1)
    }

    @Test func anEdgeWithOneFaceJoinsNothing() {
        // Face 2 has an edge of its own that lists a single face: it still stands apart.
        let apart = Topology(faces: [face(0), face(1), face(2)], edges: [edge(0, faces: [0, 1]), edge(1, faces: [2])])
        #expect(apart.pieceCount == 2)
    }

    @Test func aSeamJoinsAFaceToItself() {
        let cylinder = Topology(faces: [face(0), face(1)], edges: [edge(0, faces: [1, 1])])
        #expect(cylinder.pieceCount == 2)
    }
}
```

Create `Tests/CreatorKernelTests/EdgeOrderTests.swift`:

```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// `Topology.edges(matching:)` orders the edges of one key by midpoint, then by ID (spec §5.3, rule 5). Ordinals saved in a
/// pick index that order, so what counts as a tie is part of the file format.
struct EdgeOrderTests {
    let node = NodeID()
    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 0)) }

    func edge(_ id: Int, at midpoint: Vector3) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: .unitX, length: 1, midpoint: midpoint, convexity: .convex,
                 faces: [FaceID(0), FaceID(1)])
    }

    func order(_ edges: [EdgeInfo]) -> [Int] {
        let topology = Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [side]),
        ], edges: edges)
        return topology.edges(matching: EdgeKey([top], [side])).map(\.id.rawValue)
    }

    @Test func midpointsThatDifferByMoreThanAMicrometreOrderByPosition() {
        // The lower ID is the farther along x.
        #expect(order([edge(1, at: Vector3(5, 0, 0)), edge(2, at: Vector3(-5, 0, 0))]) == [2, 1])
        #expect(order([edge(1, at: Vector3(2e-6, 0, 0)), edge(2, at: .zero)]) == [2, 1], "2 µm apart is a real difference")
    }

    @Test func midpointsWithinAMicrometreTieAndOrderByID() {
        // x, y and z each within 1e-6 mm of each other, so the IDs decide, whichever order the topology lists them in.
        let near = [edge(7, at: .zero), edge(3, at: Vector3(5e-7, 0, 0)), edge(5, at: Vector3(0, 0, -5e-7))]
        #expect(order(near) == [3, 5, 7])
        #expect(order(near.reversed()) == [3, 5, 7])
    }
}
```

Modify `Tests/CreatorNodesTests/EdgeTagMatchTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -52,4 +52,10 @@ struct EdgeTagMatchTests {
     }
 
+    /// An ordinal past the key's matches (the file was edited, or the matches are fewer now) selects nothing, and says so.
+    @Test func anOrdinalPastTheMatchesSelectsNothingAndWarns() {
+        let pick = EdgePick(key: EdgeKey([top], [front]), matchCount: 2, ordinals: [5])
+        #expect(EdgeTagMatch.resolve([pick], in: topology()) == EdgeTagMatch(edges: [], warnings: ["Matched 0 edges, expected 2."]))
+    }
+
     /// A 1 → 2 drift and a 1 → 0 drift must not add up to "Matched 2 edges, expected 2.".
     @Test func oppositeDriftsDoNotCancelOut() {
```

Create `Tests/CreatorGraphTests/Support/BoolListNode.swift`. It is a file of its own and is **not** added to `testRegistry`: `GroupModelTests.everyRegistryMakesGroupNodesButThePaletteDoesNotListThem` asserts that registry has 18 nodes (the editor track's tests and Groups depend on it), so the test below builds its own registry from `testRegistry.all`.

```swift
import CreatorKernel
@testable import CreatorGraph

/// Emits the list true, false as one list-valued output, to broadcast a flag over two items. Not in `testRegistry`
/// (a test that counts that registry's nodes would change); a test that needs it builds its own registry.
enum BoolListNode: NodeDefinition {
    static let typeID = "test.boolList"
    static let displayName = "Bool List"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("flags", .bool)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["flags": [.bool(true), .bool(false)]])
    }
}
```

Append to `Tests/CreatorGraphTests/OptionalOutputTests.swift` (after Task 7's test, before the closing brace of the struct):

```swift
    /// Broadcast over [true, false]: the first item produces the optional output and the second leaves it out. An output
    /// any item left out is absent from the whole result (`Evaluator+Running`), so what is wired to it is an error, not
    /// the first item's value. The required output still has both items.
    @Test func anOptionalOutputOneBroadcastItemLeavesOutIsAbsentForAll() async throws {
        let registry = NodeRegistry(testRegistry.all + [BoolListNode.self])
        let flags = registry.makeNode(BoolListNode.typeID)
        let node = makeNode(OptionalOutputNode.self)
        let add = makeNode(AddNode.self)
        let report = try await Evaluator(registry: registry, kernel: FakeKernel()).evaluate(
            graph([flags, node, add], [link(flags, "flags", node, "flag"), link(node, "sometimes", add, "a")]), demand: [add.id])
        #expect(report.results[node.id]?.outputs?["always"]?.numbers == [1, 1])
        #expect(report.results[node.id]?.outputs?["sometimes"] == nil)
        #expect(report.results[add.id]?.state == .error("“a” is wired to “sometimes”, "
                + "which that node doesn't have, or doesn't produce with its current settings."))
    }
```

Modify `Sources/CreatorNodes/Selection/EdgesByDirectionNode.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -7,4 +7,5 @@ import Foundation
 /// Either sense counts (|cos| is compared), and only lines qualify: a circle edge's `direction`
 /// is its axis, so without the `kind == .line` check every hole rim would match "parallel to Z".
+/// The slider stops at 45° but the node accepts up to 90° (every line then matches), for a wired value.
 public enum EdgesByDirectionNode: NodeDefinition {
     public static let typeID = "creator.edgesByDirection"
```

Modify `Sources/CreatorKernel/Topology+EdgePicks.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -43,5 +43,7 @@ extension Topology {
     }
 
-    /// Deterministic order for edges sharing a key (spec §5.3, rule 5).
+    /// Deterministic order for edges sharing a key (spec §5.3, rule 5). Midpoints within 1e-6 mm tie and go by ID. That is
+    /// not a strict weak ordering when three midpoints chain within the tolerance, which no real part does; it is left as
+    /// it is because a saved pick's ordinals index this order.
     static func midpointOrder(_ a: EdgeInfo, _ b: EdgeInfo) -> Bool {
         let pairs = [(a.midpoint.x, b.midpoint.x), (a.midpoint.y, b.midpoint.y), (a.midpoint.z, b.midpoint.z)]
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "NodeEdgeCaseTests|PieceCountTests|EdgeOrderTests|EdgeTagMatchTests|OptionalOutputTests"`
Expected: PASS (these pin existing behaviour; there is no Red). To see that each can fail, change one expectation (for example the grid limit sentence) and re-run.

- [ ] **Step 3: Full run, lint, commit**

Full run: sum **2179** (master + 37). Lint clean (the dictionary literals in `NodeEdgeCaseTests` are written one entry per line with trailing commas for the trailing-comma rule).

```bash
git add Sources Tests
git commit -m "test(nodes): pin the M3 ledger's node edge cases, edge order ties and piece counts"
```

---

### Task 9: ED-14 (d), Project says every reason when nothing projects

**Files:**
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel+Project.swift`
- Test: `Tests/CreatorSketchEditorTests/ProjectToolTests.swift`

**Why:** a face pick can skip several edges for different reasons; when nothing projected only the first reason (`left.first`) reached the person, while the mixed case already joined them all.

- [ ] **Step 1: Write the failing test**

Modify `Tests/CreatorSketchEditorTests/ProjectToolTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -98,4 +98,15 @@ struct ProjectToolTests {
     }
 
+    /// A face pick can leave several edges out for different reasons, and with none projectable all of them are said, as they
+    /// are when some project.
+    @Test func everyReasonForLeavingEdgesOutIsSaidWhenNothingProjects() {
+        let circle = "Edge 2 can't be projected: it is a circle that doesn't face the sketch plane."
+        let perpendicular = "Edge 3 can't be projected: it is perpendicular to the sketch plane."
+        let (model, host) = makeModel(skipped: [circle, perpendicular])
+        model.project(.face(solid: 0, FaceID(1)))
+        #expect(host.commits.isEmpty)
+        #expect(model.refusal == "\(circle) \(perpendicular)")
+    }
+
     @Test func someEdgesProjectingAndSomeNotStoresTheOnesThatDoAndSaysWhatWasLeftOut() {
         let reason = "Edge 2 can't be projected: it is a circle that doesn't face the sketch plane."
```


- [ ] **Step 2: Run to see it fail**

Run: `swift test --filter ProjectToolTests`
Expected: FAIL, `everyReasonForLeavingEdgesOutIsSaidWhenNothingProjects` (`refusal` is only the circle sentence).

- [ ] **Step 3: Implement**

Modify `Sources/CreatorSketchEditor/SketchEditorModel+Project.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -26,5 +26,5 @@ extension SketchEditorModel {
         }
         guard !writes.isEmpty else {
-            refusal = left.first ?? "There is nothing there to project."
+            refusal = left.isEmpty ? "There is nothing there to project." : left.joined(separator: " ")
             return
         }
```


- [ ] **Step 4: Run, full run, lint, commit**

Run: `swift test --filter ProjectToolTests`: PASS (11). Full run: sum **2180** (master + 38). Lint clean.

```bash
git add Sources/CreatorSketchEditor Tests/CreatorSketchEditorTests/ProjectToolTests.swift
git commit -m "fix(sketch-editor): Project names every reason it left edges out when nothing projects"
```

---

### Task 10: GK-14 (c), pin the circle tangent inside a plate

**Files:**
- Test: `Tests/CreatorNodesTests/NodeEdgeCaseTests.swift`

**Why:** the triage feared OCCT could not build a face from the self-touching outer loop a tangent circle leaves. Probing showed it can (see Disposition); this pins the two analytic volumes so a future OCCT or region change is seen. It passes at once.

- [ ] **Step 1: Add the test**

Modify `Tests/CreatorNodesTests/NodeEdgeCaseTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -4,4 +4,5 @@ import CreatorKernel
 import CreatorNodes
 import CreatorOCCT
+import CreatorSketch
 import Testing
 
@@ -80,4 +81,21 @@ struct NodeEdgeCaseTests {
     }
 
+    /// A circle tangent to a plate's edge from inside gives the plate's region a self-touching outer loop (the circle runs
+    /// along it as a notch) and the circle its own region. OCCT builds both faces: the two solids have the analytic volumes.
+    @Test func aCircleTangentInsideAPlateExtrudesToTheAnalyticVolumes() async throws {
+        var plate = RectangleSketch(width: 20, height: 20)
+        plate.sketch.addCircle(center: Vector2(10, 5), radius: 5)
+        var h = Harness()
+        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(plate.sketch)])
+        let extrude = h.add(ExtrudeNode.self, ["distance": .number(3)])
+        h.wire(sketch, "profiles", to: extrude, "profile")
+        let kernel = OCCTKernel()
+        let report = try await h.run([extrude], kernel: kernel)
+        let solids = try #require(report.value(extrude, "solid")?.solids)
+        try #require(solids.count == 2)
+        #expect(isClose(try await volume(solids[0], kernel), 3 * (400 - 25 * Double.pi), relative: 1e-6))
+        #expect(isClose(try await volume(solids[1], kernel), 3 * 25 * Double.pi, relative: 1e-6))
+    }
+
     // MARK: Called directly, with inputs no wire produces
```


- [ ] **Step 2: Run, full run, lint, commit**

Run: `swift test --filter NodeEdgeCaseTests`: PASS (9). Full run: sum **2181** (master + 39). Lint clean.

```bash
git add Tests/CreatorNodesTests/NodeEdgeCaseTests.swift
git commit -m "test(sketch): pin the extrusion of a circle tangent inside a plate"
```

---

### Task 11: BUG-4, say which constraint is ignored (needs Task 1)

**Files:**
- Modify: `Sources/CreatorNodes/Sketch/SketchSolve.swift`
- Test: `Tests/CreatorNodesTests/SketchNodeTests.swift`

**Interfaces:**
- Consumes: `SketchSolution.suspended` (Task 1 fills it for kind changes), `Sketch.label(of: SketchConstraintRef)`.
- Produces: warning text "<label> is ignored: its projected edge is a different kind of curve now." for each such constraint or dimension; none for those on a suspended projection (`SketchProjections` already names the edge and says "Its constraints are ignored.").

**Why:** with Task 1 alone the sketch solves but a constraint silently stops applying and the projected edge does not turn red (only its pick is suspended). See User decision 1.

- [ ] **Step 1: Write the failing tests**

They call `SketchSolve.run` directly: through the node, `SketchProjections.resolve` rebuilds the curve from the pick, and a hand-made kind change cannot be fed in.

Modify `Tests/CreatorNodesTests/SketchNodeTests.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -50,4 +50,24 @@ struct SketchNodeTests {
     }
 
+    /// A projected edge is refreshed from the model on every evaluation, so a line a fillet turned into an arc arrives as an
+    /// arc: what was said about it as a line can't hold, and the person is told which constraint is left out.
+    @Test func aConstraintOnAProjectedEdgeThatChangedKindIsIgnoredAndSaid() throws {
+        var sketch = Sketch()
+        let source = ProjectionSource(reference: "e", curve: .arc(center: .zero, radius: 5, start: .degrees(0), end: .degrees(90)))
+        let arc = sketch.add(SketchEntity(.projected(source)))
+        sketch.add(.horizontal(arc))
+        let output = try SketchSolve.run(sketch, on: .xy)
+        #expect(output.warnings.contains("Horizontal on Projected edge 1 is ignored: its projected edge is a different kind of curve now."))
+    }
+
+    @Test func aSuspendedProjectionIsNotSaidTwice() throws {
+        var sketch = Sketch()
+        let source = ProjectionSource(reference: "e", curve: .arc(center: .zero, radius: 5, start: .degrees(0), end: .degrees(90)),
+                                      isSuspended: true)
+        sketch.add(.horizontal(sketch.add(SketchEntity(.projected(source)))))
+        let output = try SketchSolve.run(sketch, on: .xy)
+        #expect(!output.warnings.contains { $0.contains("different kind of curve") }, "SketchProjections already names it")
+    }
+
     @Test func anUnderConstrainedSketchWarnsAndStillOutputs() async throws {
         var sketch = Sketch()
```


- [ ] **Step 2: Run to see it fail**

Run: `swift test --filter SketchNodeTests`
Expected: FAIL, `aConstraintOnAProjectedEdgeThatChangedKindIsIgnoredAndSaid` (no such warning). `aSuspendedProjectionIsNotSaidTwice` passes (it guards the other direction).

- [ ] **Step 3: Implement**

Modify `Sources/CreatorNodes/Sketch/SketchSolve.swift` (a `-` line is removed, a `+` line added):

```diff
@@ -29,5 +29,5 @@ enum SketchSolve {
             break
         }
-        var warnings: [String] = []
+        var warnings = ignoredByKind(sketch, solution)
         let freedom = solution.degreesOfFreedom
         if freedom > 0 {
@@ -45,4 +45,20 @@ enum SketchSolve {
     }
 
+    /// The constraints and dimensions the solver left out because a projected edge they sit on is another kind of curve than
+    /// when they were made (a line that an edit upstream turned into an arc). A suspended projection is named by
+    /// `SketchProjections` already, with its constraints.
+    private static func ignoredByKind(_ sketch: Sketch, _ solution: SketchSolution) -> [String] {
+        solution.suspended.compactMap { ref in
+            let entities = switch ref {
+            case .constraint(let id): sketch.constraints[id]?.entities ?? []
+            case .dimension(let id): sketch.dimensions[id]?.kind.entities ?? []
+            }
+            let isNamedAlready = entities.contains { entity in
+                if case .projected(let source)? = sketch.entities[entity]?.kind { source.isSuspended } else { false }
+            }
+            return isNamedAlready ? nil : "\(sketch.label(of: ref)) is ignored: its projected edge is a different kind of curve now."
+        }
+    }
+
     /// Why a reference dimension isn't measured, for `unmeasured(_:because:)`.
     static let onSuspendedEdge = "its projected edge is suspended"
```


- [ ] **Step 4: Run, full run, lint, commit**

Run: `swift test --filter SketchNodeTests`: PASS (22). Full run: sum **2183** (master + 41). Lint clean.

```bash
git add Sources/CreatorNodes/Sketch/SketchSolve.swift Tests/CreatorNodesTests/SketchNodeTests.swift
git commit -m "feat(sketch): the Sketch node names a constraint ignored because its projected edge changed kind"
```

---

### Task 12: Errata lines (docs only)

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md`

Only the two fixes that change documented behaviour get an Errata line: edge runs (Task 2) and the suspension of wrong-kind projected edges (Tasks 1 and 11). No other spec or doc is touched; CLAUDE.md sentences are listed in the header for the app track.

- [ ] **Step 1: Add the two bullets**

Modify `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (a `-` line is removed, a `+` line added):

```diff
@@ -515,4 +515,11 @@ Plan `2026-10-09-naming-merged-faces.md`, roadmap row "Naming: picks on merged f
   edges become fewer runs (a split edge it recorded as 2 edges, now whole), and it no longer warns when a recorded
   edge is split into more pieces (master warned "Matched 2 edges, expected 1." there).
+- §5.3 rule 6's runs, refined (follow-ups, kernel): edges join into one run only where they continue each other, not
+  wherever they touch. Their ends must be within 1e-4 mm (OCCT edge ends sit up to the vertex tolerance from a shared
+  vertex after a blend, so the old 1e-6 mm counted a split edge as two runs and warned) and they must leave that point in
+  opposite directions to within 0.01 rad (`Topology.runCount`, `EdgeCurve.endDirections`), so two edges that meet at a
+  corner are two runs, not one. Which edges a pick selects, and the file format, do not change; only the warning can.
+  A pick saved before this whose recorded run count came from the old rule (a whole loop of straight edges that meet at
+  corners recorded 1 run; it is now 4) warns the first time its edge count changes, where it stayed silent before.
 - Errata (M6)'s polygon swap: the two picks on the plate sides the union had merged with the rectangle's now resolve
   to the plate's whole side edges, and Edges by Tag is `.ok` with five edges, so §8's chamfer promise holds for the
```

Modify `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (a `-` line is removed, a `+` line added):

```diff
@@ -311,4 +311,9 @@ All tests use Swift Testing.
 - §7's evaluate does not store the solve's warm start: it solves from the stored sketch every time, so results don't
   depend on evaluation history. S5's editor writes `Sketch.remember(_:)` into the setting after each edit.
+- §7's suspension also covers a constraint or dimension on a projected edge whose current curve is the wrong kind for it
+  (a line that an edit upstream turned into an arc, or the reverse): the solver skips it like one on a suspended edge, so
+  the rest of the sketch still solves instead of the whole sketch failing, and the Sketch node warns "<constraint> is
+  ignored: its projected edge is a different kind of curve now." The edge itself is not marked suspended, and the
+  constraint is kept (not deleted), so it applies again if the edge returns to its kind.
 
 ## Errata (S5a)
```


- [ ] **Step 2: Check and commit**

Run `git diff --stat`: only those two files, 12 added lines. Full run is unchanged (**2183**). Lint clean.

```bash
git add docs/superpowers/specs
git commit -m "docs: Errata for edge runs and for wrong-kind projected edges"
```

---

## Self-Review

**Spec coverage.** BUG-3: Task 2 (tests for the corner, the micrometre gap, tangent arcs, split arcs; the naming tests are the guard that saved picks resolve alike). BUG-4: Task 1 reproduces and fixes it; Task 11 adds the warning (a default, User decision 1). GK-1 to GK-8, GK-11: Tasks 3 to 8, GK-2 and GK-8 partly with the reasons in the Disposition. GK-9, GK-10, GK-12, GK-13, GK-14: dropped or the editor's, each with evidence. ED-14: only (d)'s second half is live (Task 9); the rest are fixed, unreachable or the app track's. Errata: Task 12. CLAUDE.md: listed, not edited.

**Placeholder scan.** No "TBD", "TODO" or "similar to Task N"; every code step is a diff or a whole file taken from the verified scratch copy. The scratch run is the source of every block here.

**Type consistency.** `EdgeCurve.endDirections` (Task 2) is the only new name used later (`runCount`, same task). `KernelError.loftWithHoles` (Task 3) is used by `FakeKernel`, `OCCTKernel` and `LoftNode` only. `Locale.messages` (Task 6) is `public` in CreatorKernel and is the default of `millimetreText(locale:)` and of the two blend builders, and is used by the unchanged CreatorNodes files. `SolveFailure.blamesProjection` (Task 1) is set by `TermBuilder.wrongKind(_:needs:blaming:)` and read by `TermBuilder+Terms.swift`; `Double.millimetreText(locale:)` (Task 6) is used by `KernelError` and `KernelError+Blend`. `SketchSolution.suspended` (existing) is read by Task 11.

**Review Focus.** Each of the five lines names its test and task above.

## Risks

- **Task 2's two constants are heuristics** (1e-4 mm, 0.01 rad) validated on the bracket and the unit cases, not on a corpus of blended parts. A blend whose edge ends are off by more than 1e-4 mm would still count as two runs (the old behaviour at a larger scale). The shim could return vertex tolerances later.
- **Task 2 changes warnings for old saved run counts** (User decision 3), never the picked edges. Scope: any saved pick of a whole straight-edged loop (`runCount` 1 under the old rule, 4 now) warns once its edge count changes; New picks are unaffected. Mitigation B in decision 3 (a retained legacy joiner in `hasDrifted`) is not in this plan.
- **Task 6's one untestable link on an en_US host** is that nobody calls `Double.formatted` with the process locale in a kernel message again: `millimetreText(locale:)` is the one formatter in `KernelError` and `KernelError+Blend`, and a new message that formats a number another way is not caught. Review for it.
- **Task 1 suspends only failures that blame a projected operand** (`SolveFailure.blamesProjection`, set in `line()`, `circle()` for a projected operand, and in the Equal and Tangent pair checks when a projected edge is in the pair). A pair check cannot tell which side changed, so `Equal(projected line, circle)` that was never valid is suspended too rather than failed, and Task 11 says "a different kind of curve now" for it; the editor cannot make such a constraint, so this needs a hand-edited file. A new `wrongKind` throw must pass `blaming:` if a projected edge can be its cause.
- **Task 4's FakeKernel check is approximate** (documented in its doc comment): it can still accept what OCCT refuses.

## Verification

**Re-verified for this revision** in a scratch copy of the worktree (session scratchpad, with a sibling `MetalUI` that is a symlink to `/Users/maxburger/Developer/MetalUI`, because an older MetalUI snapshot lacks `CloseRequestReply` and `CreatorApp` does not build against it): master `4dff87b` plus the code this revision changed, namely Task 1 (`SolveFailure.blamesProjection`, `wrongKind(blaming:)`, `TermBuilder+Terms.swift`, the three tests), Task 6 (`Double+Millimetres.swift`, `KernelError.message(locale:)`, the blend builders, the four tests), Task 7's sentence change with its two test updates, Task 8's broadcast pin with `BoolListNode`, and Task 11 (code and both tests). Results: `swift build --build-tests` clean; `swift test` exit 0, 11 "Test run with" lines, no "recorded an issue" or "failed after", **2151** tests = 2142 + 3 (Task 1) + 4 (Task 6) + 2 (`OptionalOutputTests`: the Task 7 renamed-socket test and the Task 8 broadcast pin); no compiler warning outside the one known; `swiftlint lint --strict` 0 violations in 1070 files. `SketchNodeTests` with Task 11 applied: 22 tests pass, lint clean. Mutation check for Task 6: with the locale parameter ignored, three of the new tests fail on an en_US host. A first attempt put `BoolListNode` into `testRegistry` and `GroupModelTests` (count 18) failed, hence the separate registry in the test.

**Earlier, not repeated** (those tasks' code is unchanged by this revision): each of the other tasks was applied in order in an earlier scratch copy, its Red step run (where it has one), then a full `swift test`, `swiftlint lint --strict` and a compiler-warning diff against the baseline. The table below is the earlier per-task sum plus this revision's added tests (Task 1 +1, Task 6 +2, Task 8 +1 over that run); the earlier cumulative sums were 2144, 2149, 2150, 2153, 2157, 2159, 2161, 2175, 2176, 2177, 2179. The full 12-task cumulative run on the revised plan has not been re-done: the first thing the implementer does after Task 11 is the full run against these counts.

| After | Tests | New warnings | Lint |
|---|---|---|---|
| Task 1 | 2145 (master + 3) | 0 | clean |
| Task 2 | 2150 (master + 8) | 0 | clean |
| Task 3 | 2151 (master + 9) | 0 | clean |
| Task 4 | 2154 (master + 12) | 0 | clean |
| Task 5 | 2158 (master + 16) | 0 | clean |
| Task 6 | 2162 (master + 20) | 0 | clean |
| Task 7 | 2164 (master + 22) | 0 | clean |
| Task 8 | 2179 (master + 37) | 0 | clean |
| Task 9 | 2180 (master + 38) | 0 | clean |
| Task 10 | 2181 (master + 39) | 0 | clean |
| Task 11 | 2183 (master + 41) | 0 | clean |
| Task 12 | 2183 | 0 | clean |

Each full run passes only if the exit code is 0, no line says "recorded an issue" or "failed after", and 11 "Test run with" lines appear.
