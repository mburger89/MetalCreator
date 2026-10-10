# Naming: Face Picks on Merged Faces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Plane from Face pick on a face a union merged keeps its plane when the other operand stops merging (swapped for a polygon, or moved), and an Edges by Tag pick on the rim of a hole through such a face keeps naming that rim (roadmap row "Naming: face picks on merged faces").

**Architecture:** Two pure-Swift fallbacks in `CreatorKernel`, each used only when the strict tag-subset match finds nothing, so every pick that resolves today resolves identically. (1) **Face picks:** a `FacePick` also records the flat face's outward normal and centroid (optional keys, no format bump); a pick that matches no face is retried with each operand's tags alone (`Set<TopoTag>.partsByOrigin`), keeps the candidates that face the picked way, and takes the one lying in the picked face's plane (within a micrometre), nearest its centroid first (`Topology.resolution(of:)`); it is silent only when the pick recorded its position and exactly one candidate lies in that plane (the plane then stays where it was in space, on whichever part is left), otherwise Plane from Face places the plane and warns. (2) **Edge picks:** after `EdgeKey.narrowed` finds nothing, a side with tags from several node calls and none in common with the other side (the hole wall shares no node call with the plate or the flange) is split by operand (`EdgeKey.operandKeys`, `Topology.resolution(of:expecting:)`); several operands' keys naming edges are settled by the recorded edge count, else the nearest count, and Edges by Tag (and a Sketch projection) warns that it guessed. Nothing changes in `COCCT`/`CreatorOCCT` and nothing in the file format.

**Tech Stack:** Swift 6.4 (strict concurrency, Swift 6 language mode), Swift Testing, OpenCascade 7.9 through `CreatorOCCT` (tests only here), SwiftLint.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§5.3 topological naming, §8 naming stability, Errata (M6), Errata (naming: merged faces), whose last bullet this plan closes) with all its Errata. Task 4 adds Errata (naming: face picks). Earlier plan: `docs/superpowers/plans/2026-10-09-naming-merged-faces.md` (`EdgeKey.narrowed`, `EdgePick.runCount`).

**Verified against master `4e4be6e` (1643 tests) and MetalUI as checked out at `../MetalUI`.** Every code block below was applied task by task, in order, to a scratch copy of the worktree (with a sibling `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI`). In the first draft, after each task the package built with no new warnings (only the expected OCCT "built for newer macOS" linker notes and M4's existing `ContextMenuTests` capture warning), `swift test` exited 0 with no line saying "recorded an issue" or "failed after" and with 11 "Test run with" lines, and `swiftlint lint --strict` reported zero violations. Cumulative test counts (each new `@Test` function is one test, however many arguments it has): Task 1 → 1658 (master + 15), Task 2 → 1663 (master + 20), Task 3 → 1682 (master + 39), Task 4 → 1682 (master + 39; it adds docs only). This revision (the plate-alone test, the 1-micrometre tolerance, the ordinal and summed-count guards) re-ran the final state of Tasks 1 to 3 (Task 4 adds docs only) in full by the rule above (1682 tests, exit 0, 11 "Test run with" lines, `swiftlint lint --strict` clean); the earlier totals add up from each task's new test functions, and each task's filtered runs pass. The new OCCT tests of Tasks 2 and 3 were also run before their implementation and failed there, for the reason named in the step.

**Shared with other tracks (merge with care).** I could not read the other worktrees (the work rule forbids leaving this one), so what each file's other editors do is inferred from the track names:
- `CLAUDE.md` (Task 4 edits two sentences of the naming paragraph) and `docs/superpowers/roadmap.md` (Task 4 replaces one row) — every track edits them. Keep both sides' edits; the roadmap row text is this track's.
- `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (Task 4 inserts a section before "Errata (Themes)" and rewrites the last bullet of Errata (naming: merged faces)) — any track adding errata edits it. Keep every section; append, never reorder.
- `Tests/CreatorKernelTests/FacePickTests.swift` (Task 1 changes `aFacesPickIsItsWholeTagSet` to compare `.tags` only) — any track that touches face picks may edit this file. The side that merges second keeps comparing `.tags` only, and never compares `facePick(for:)` against a `FacePick(tags:)` built without a position (they are unequal now).
- `Sources/CreatorKernel/FacePick.swift`, `FacePick+Codable.swift`, `Topology+FacePicks.swift` (Task 1) — sketcher-s5c ("Project writes face/edge references") creates and reads `FacePick`s and `EdgePick`s. Whoever merges second must keep `FacePick.init(tags:normal:centroid:)` with both optionals defaulting to `nil`, the optional `normal`/`centroid` coding keys (written only when set), and `facePick(for:)` recording them; code that builds a pick with `FacePick(tags:)` keeps compiling and just gets the "can't tell which part" warning if its face ever comes apart.
- `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift` (Task 2) — the groups-comments and groups-editor tracks may touch group renaming. The side that merges second must keep copying the whole pick (`var renamed = pick; renamed.tags = …`) and never rebuild a `FacePick` from its tags alone, or the recorded position is lost.
- `Sources/CreatorNodes/Values/PlaneFromFaceNode.swift` (Task 2) — S5 "new sketch on face" wires this node. Keep `Topology.resolution(of:)` as the way it finds its face and the `mergedPick` warning.
- `Sources/CreatorKernel/Topology+EdgePicks.swift` (Task 3: `edges(resolving:)` now delegates), `Sources/CreatorNodes/Selection/EdgeTagMatch.swift` (Task 3: `choose` returns a fourth element, `isAmbiguous`; `resolve` warns with `ambiguousPick`) and `Sources/CreatorNodes/Sketch/SketchProjections.swift` (Task 3: `locate` passes `comparesRecordedCount: references.count == 1` and adds the ambiguity note to its drift text; about seven lines) — sketcher-s5c edits the projection code. A new caller of `EdgeTagMatch.choose` must read or ignore `isAmbiguous`, and pass `comparesRecordedCount: false` whenever it sums matches over several solids; the side that merges second keeps the fourth tuple element, the parameter and the seven lines in `locate`.
- `Sources/CreatorNodes/Selection/EdgesByTagNode.swift` (Task 3: a doc comment only) — any track editing Edges by Tag. Keep both sides' text; this track's sentence is the one naming `Topology.resolution(of:expecting:)`.
- `docs/verification/human-checks.md` (Task 4 appends Group NF at the end) — every track appends a group. Keep every group; append, never reorder.
- `Tests/CreatorNodesTests/BracketAcceptanceTests+FacePicks.swift` declares `isOK(_:_:)` and `Tests/CreatorNodesTests/BracketAcceptanceTests+HoleThroughMergedSide.swift` uses it; both extend `BracketAcceptanceTests`. If another track adds a helper of that name to the same type, keep one.
- No `Package.swift`, no MetalUI, no `GraphFile.swift`, no UI target, no `CreatorOCCT`/`COCCT`. `CreatorKernel`, `CreatorGraph` and `CreatorNodes` are the only sources touched.

**Prerequisites:**
- The worktree `/Users/maxburger/Developer/MetalCreator-facepick` on branch `naming-face-picks` at `4e4be6e` or later, clean (`git status --short` prints nothing). Run every command from it; never `cd` to another worktree.
- OpenCascade from Homebrew (as for M2 on). SwiftLint installed.

## What was observed (real OCCT, the §7.2 bracket)

Run with the tests in this plan, on master plus the plan's code, plus the same tests before their code:

1. **The face is merged, with both operands' tags.** The union's face on the plate's left side (normal −X) has tags of the plate and of the flange; Task 2's `mergedLeftSide` finds it by exactly that, and the pick `topology.facePick(for:)` writes names both.
2. **Today the plane is lost.** With the flange made 40 or 70 mm wide, or swapped for the hexagon, the pick matches nothing and Plane from Face is in error ("The picked face isn't on this solid any more. Pick it again."): Task 2's tests fail at the first check after the change, and pass before it.
3. **Today the hole rim is lost.** The same three changes make the hole rim pick match nothing: Edges by Tag warns "Matched 0 edges, expected 1." and selects nothing (Task 3's tests fail at that check; by the drift rule the text is "Matched 0 edges, expected 1.").
4. **After this plan:** the plane is on the plate's side (x = −30, facing −X, z ≤ 6) with no warning in all three cases, and the rim is the circle in that side. The hexagon keeps the flange's side tags on faces of its own (earlier plan, probe 4), so a rule that took "any part with the flange's tag" or "any part with the same normal" could land on them; the plane rule takes the part in the picked face's plane (Task 1's `aPartOutsideThePlaneIsAGuess` pins the geometry on a hand-built topology).
5. **A flange wider than the plate moves the rim.** At 70 mm the flange sticks out 5 mm past the plate, so the hole now starts in the flange's own face at x = −35; the rim is `{flange.side} | {hole.wall}` there, and that is where the pick goes (the plate has no face at that depth to hold it). That is the plan's behaviour, not a loss: the pick follows the hole, silently, because only one operand's key names an edge (user decision 3).
6. **Only the plate changes.** With the plate widened to 80 mm and the flange left at 60, the plate's side moves to x = -40 and the flange's side stays at x = -30, so the only part left in the picked plane is the flange's own face. Plane from Face stays in place in space, on that face (x = -30, z above the plate), silently (Task 2's `aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves`). That is the plan's behaviour, and the user is asked about it (user decision 1, option (e)).
7. **Saved files.** A reopened document resolves both picks identically (both acceptance files reopen), and a reader that only knows `tags` decodes a `FacePick` written with the new keys (Task 1's `anEarlierReaderIgnoresTheOptionalKeys`).

## Decisions made in this plan

1. **Retry per operand, only as a fallback.** `Topology.resolution(of: FacePick)` returns the strict tag-subset matches when there are any, and retries only when there are none; `faces(matching:)` keeps its meaning. A pick that resolves on master resolves identically (the whole suite is the regression check).
2. **The retry unit is a node call**, as in `EdgeKey.narrowed`: tags are grouped by `TopoTag.origin` (node and broadcast item). Broadcast items are separate operands. Groups are ordered by sort key so nothing depends on hashing.
3. **Rank by plane, then centroid; the plane decides confidence.** A candidate must be flat and face the way the picked face did (dot ≥ 1 − 1e-6). Candidates are ordered by distance from the picked face's plane (in micrometres; a candidate within 1 micrometre counts as in the plane and ties at 0), then by distance from its centroid, then by face ID. The answer is silent iff the pick recorded both normal and centroid and exactly one candidate lies in that plane. Silent means the plane stays where it was in space, on whichever part is still there: if the plate moves and the flange stays, the plane is on the flange's face (user decision 1, option (e)). Why not area: a merged face is bigger than any one operand's share, so area never matches an operand; the plane is what a merged face's parts share.
4. **Record the position on the pick, as optional keys.** `FacePick.normal` and `FacePick.centroid` (written by `Topology.facePick(for:)`, only for flat faces' normals). `Codable` writes them only when set and reads them with `decodeIfPresent`; older readers ignore them; `GraphFile.currentFormatVersion` stays 5 and `GraphFile.swift` is untouched. Equality of `FacePick` now includes them, which is right: two picks of the same tags at different positions differ.
5. **Edges: split a side only where `narrowed` can't help.** `EdgeKey.operandKeys` splits a side that has tags from at least two node calls and none from a node call the other side has. A side that shares a node call with the other (the plate's top against a plate-and-flange side) is `narrowed`'s case and is never split, so the edge where two operands meet keeps its full name; a key that matches or narrows is never split.
6. **Edge ambiguity is settled by the recorded count.** `Topology.resolution(of:expecting:)` takes the edge count the pick recorded. If exactly one operand's key names that many edges it wins silently; else the nearest count wins, ties by key sort order, and `EdgeResolution.isAmbiguous` is true. Two cases where the count means nothing are guesses too. (a) The count is a sum over several reference solids (a Sketch projection with more than one reference): `EdgeTagMatch.choose(_:in:comparesRecordedCount:)` is told not to compare it, and `locate` passes `references.count == 1`. (b) The pick has ordinals, which index the whole key's matches, and the key was resolved through one operand's share (`EdgeResolution.isSplit`): the answer is flagged ambiguous even when one operand is left. `EdgeTagMatch.resolve` then adds `EdgeTagMatch.ambiguousPick` to the warnings; a Sketch projection adds the same sentence to its drift text.
7. **`Topology.edges(resolving:)` stays** as a thin wrapper (`resolution(of:).edges`) for callers that only want the edges.
8. **No new `Kernel`, shim or `OCCTTagger` change.** Faces already carry both operands' tags (observation 1).
9. **No `SketchProjections` redesign.** Only `locate`'s drift text gains the ambiguity sentence.

## User decisions (the spec leaves them open)

**Decided 2026-10-09: the user approved every recommended default below (1 to 6).**

1. **What a face pick does when its merged face has come apart.** Recommended (this plan): retry per operand, take the part in the picked face's plane, silent only if it is the only one there; otherwise place the plane and warn. Alternatives: (b) never guess, keep today's error "isn't on this solid any more" for every merged pick that comes apart (simplest, loses the plane in exactly the cases of the roadmap row); (c) always warn when narrowed, even with one part in the plane (noisier, never silent); (d) rank by the area share (rejected: a merged face's area matches no operand); (e) follow the operand that moved. The pick's tags name both operands and not which one the person clicked, so "the plane stays put in space on the part that stayed" is the recommended and tested answer: if the plate widens and the flange stays, the plane stays at x = -30 on the flange's face, silently (Task 2's `aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves`). Option (e) would warn, or follow the side that moved, whenever the part in the plane is not the one the person picked on; that needs `FacePick` to record which operand it was picked on (one more optional key, written from the viewport pick, so an app-shell change) and costs a warning on edits that are plainly fine. Recommended: keep the silent answer; revisit if it surprises someone.
2. **Whether `FacePick` records its normal and centroid.** Recommended: yes, as optional keys (no format bump, older readers ignore them). Alternatives: bump to format 6 for the new keys (older builds then refuse the file, for no benefit); record nothing (every merged pick that comes apart is a guess and warns).
3. **A hole rim that can be found on only one operand after the change** (flange 70 mm wide: the rim is now on the flange's own face). Recommended: follow it silently; it is the only edge the key can name and the count matches. Alternatives: warn whenever an operand key (not the narrowed key) was needed; refuse (today's "Matched 0 edges").
4. **Two operands both fit an edge pick** (the hole's rim exists on both). Recommended: use the nearest count, then the first key in sort order, and warn (`ambiguousPick`). Alternatives: select none and warn "Matched 0"; select both operands' edges and warn.
5. **A Sketch projection that guessed.** Recommended: use the edge and report the guess in the node's warnings, like drift. Alternative: suspend the projection (its constraints ignored) until the pick is made again.
6. **Picks made before positions were recorded** (no normal/centroid; Plane from Face has existed only since S4/S5). With no position the plan can't tell the parts apart: it takes the first part in `partsByOrigin` order, which sorts on node ID strings, so the choice is arbitrary (the same every time within a document; Task 1's `theGuessWithoutAPositionIsTheFirstPartAndStable`). Recommended: warn whenever such a pick has to be retried. Alternatives: trust that arbitrary first part silently (wrong about as often as right); choose by the most of the pick's own tags or the largest area (no better a signal, because a merged face's tags split by operand, not by share).

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency; no `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- One type per Swift file, named after the type; extensions in `Type+Purpose.swift`.
- No force unwraps or force `try`. No GCD. No third-party packages. Numbers shown to people go through `FormatStyle` / `Locale.messages` (no new user-facing number text here).
- `@MainActor @Observable` models, behaviour in models and thin views (no model or view changes here).
- Module boundaries (CLAUDE.md): only `CreatorOCCT` touches OCCT, and all OCCT work runs under `OCCTKernel.serialized`; `CreatorKernel` imports only `CreatorGeometry` and Foundation. Never iterate a dictionary where order reaches output (`partsByOrigin` sorts what it groups).
- Create nodes only with `NodeRegistry.makeNode`; every graph edit goes through `DocumentModel.perform(_:)`.
- Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion` (now 5). This plan bumps nothing: its keys are optional and ignored by older readers.
- Must not regress the naming-stability or conformance tests (`swift test --filter CreatorOCCTTests`, `BracketAcceptanceTests`).
- A `swift test` run passes only if it exits 0, no line says "recorded an issue" or "failed after" (Swift Testing uses glyphs, not ✘), and 11 "Test run with" lines appear.
- **SwiftLint gates every commit:** `swiftlint lint --strict` reports zero violations.
- MetalUI gaps would go in `docs/metalui-gaps.md` (entry and summary-table row), never worked around. None arise: there is no UI work.

## Review Focus

1. **A pick made before positions were recorded** (tags only) must still find its plane, and say it guessed. Pinned: Task 1 `aPickWithoutAPositionIsAGuess`; Task 2 `aPlanePickWithoutAPositionWarnsOnceTheFaceHasComeApart`.
2. **A part with the same normal and tag but elsewhere** (the hexagon's side) must not win over the part in the picked plane. Pinned: Task 1 `aPickOnAMergedFaceFindsThePartInItsPlane`, `aPartOutsideThePlaneIsAGuess`; Task 2 `aPlanePickedOnAMergedSideSurvivesTheFlangeBecomingAPolygon`.
3. **Two parts in the same plane** (a flange face level with the plate's side that a cut separated): the nearest wins and the node warns. Pinned: Task 1 `twoPartsInThePlaneAreAmbiguousAndTheNearestWins`.
4. **The hole's rim when the flange sticks out past the plate** follows the hole to the flange's face. Pinned: Task 3 `aHoleRimPickedOnAMergedSideSurvivesTheFlangeChangingWidth` at 70 mm.
5. **An edge where two operands meet, and a key that already matches, are never split.** Pinned: Task 3 `aSideSharingANodeCallWithTheOtherSideIsNotSplit`, `aKeyThatMatchesIsResolvedAsBefore`; Task 1 `aPickThatMatchesIsNotNarrowed`.
6. **A group renames a pick's tags and keeps its position.** Pinned: Task 2 `renamingATagKeepsTheRecordedNormalAndCentroid`.
7. **Only the plate changes.** The plane stays in space on the flange's face, silently; this is the design, and user decision 1 asks about it. Pinned: Task 2 `aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves`.
8. **The in-plane tolerance is 1 micrometre.** A part 0.3 or 0.9 micrometres off is in the plane; 5 micrometres off is a guess. Pinned: Task 1 `aPartWithinAMicrometreOfThePlaneIsInIt`, `aPartFiveMicrometresOffThePlaneIsAGuess`.
9. **A summed count, and an ordinal pick resolved through one operand, are not trusted.** Pinned: Task 3 `aCountSummedOverReferencesIsNotComparedWithOneSolid`, `anOrdinalPickResolvedByOperandIsAGuess`.
10. **The two new warnings fit the badge and the inspector.** Visual only: human check NF-1 (Task 4).

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/CreatorKernel/TopoTag+Parts.swift` (new) | 1 | `Set<TopoTag>.partsByOrigin`: one set per node call |
| `Sources/CreatorKernel/FacePick.swift` | 1 | `normal`, `centroid` (optional) |
| `Sources/CreatorKernel/FacePick+Codable.swift` | 1 | optional coding keys |
| `Sources/CreatorKernel/FaceResolution.swift` (new) | 1 | the result of resolving a face pick |
| `Sources/CreatorKernel/Topology+FacePicks.swift` | 1 | `facePick(for:)` records the position; `resolution(of:)` |
| `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift` | 2 | keeps the recorded position when renaming |
| `Sources/CreatorNodes/Values/PlaneFromFaceNode.swift` | 2 | resolves through `resolution(of:)`; `mergedPick` warning |
| `Sources/CreatorKernel/EdgeKey+Operands.swift` (new) | 3 | `EdgeKey.operandKeys` |
| `Sources/CreatorKernel/EdgeResolution.swift` (new) | 3 | the result of resolving an edge key (`isAmbiguous`, `isSplit`) |
| `Sources/CreatorKernel/Topology+EdgeResolution.swift` (new) | 3 | `resolution(of:expecting:)` |
| `Sources/CreatorKernel/Topology+EdgePicks.swift` | 3 | `edges(resolving:)` delegates |
| `Sources/CreatorNodes/Selection/EdgeTagMatch.swift` | 3 | `choose` returns `isAmbiguous`; `ambiguousPick` warning |
| `Sources/CreatorNodes/Selection/EdgesByTagNode.swift` | 3 | doc comment only (shared) |
| `Sources/CreatorNodes/Sketch/SketchProjections.swift` | 3 | `locate` reports a guess (shared with sketcher-s5c) |
| `Tests/CreatorKernelTests/FaceResolutionTests.swift` (new), `FacePickTests.swift` (shared) | 1 | parts, resolution, tolerance, optional keys |
| `Tests/CreatorNodesTests/BracketAcceptanceTests+FacePicks.swift` (new) | 2 | the plane survives the flange changing, on OCCT |
| `Tests/CreatorGraphTests/Groups/FacePickRenamingTests.swift` (new) | 2 | renaming keeps the position |
| `Tests/CreatorKernelTests/EdgeOperandKeyTests.swift` (new) | 3 | operand keys and edge resolution |
| `Tests/CreatorNodesTests/EdgeTagMatchOperandTests.swift`, `SketchProjectionOperandTests.swift` (new) | 3 | Edges by Tag and projections on hand-built topologies |
| `Tests/CreatorNodesTests/BracketAcceptanceTests+HoleThroughMergedSide.swift` (new) | 3 | the hole rim survives the flange changing, on OCCT |
| spec, roadmap, CLAUDE.md, `docs/verification/human-checks.md` | 4 | Errata (naming: face picks), the row, the naming rule, Group NF |

---

### Task 1: Face picks that find their part (`partsByOrigin`, `FacePick` position, `Topology.resolution(of:)`)

**Files:**
- Create: `Sources/CreatorKernel/TopoTag+Parts.swift`
- Create: `Sources/CreatorKernel/FaceResolution.swift`
- Modify: `Sources/CreatorKernel/FacePick.swift`, `Sources/CreatorKernel/FacePick+Codable.swift`, `Sources/CreatorKernel/Topology+FacePicks.swift`
- Test: `Tests/CreatorKernelTests/FaceResolutionTests.swift` (new), `Tests/CreatorKernelTests/FacePickTests.swift`

**Interfaces:**
- Consumes: `TopoTag.origin: NodeTag` (exists), `FaceInfo` (`kind`, `normal`, `centroid`, `tags`), `Topology.faces(matching:)`, `Vector3.dot/normalized/length`.
- Produces: `extension Set where Element == TopoTag { public var partsByOrigin: [Set<TopoTag>] }` (empty unless two or more node calls); `FacePick.init(tags: Set<TopoTag>, normal: Vector3? = nil, centroid: Vector3? = nil)` with `normal`/`centroid` properties; `Topology.facePick(for:)` that records them (normal only for flat faces); `public struct FaceResolution { faces: [FaceInfo]; isNarrowed: Bool; isAmbiguous: Bool }`; `Topology.resolution(of: FacePick) -> FaceResolution`. Task 2 calls `resolution(of:)`; Task 3 calls `partsByOrigin`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorKernelTests/FaceResolutionTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Face picks on faces a union merged (roadmap "Naming: face picks on merged faces"): `Set<TopoTag>.partsByOrigin`,
/// `Topology.resolution(of:)` and the optional keys a `FacePick` records.
struct FaceResolutionTests {
    let plate = NodeID()
    let flange = NodeID()
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }

    func face(_ id: Int, _ normal: Vector3, _ centroid: Vector3, _ tags: Set<TopoTag>) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .plane, normal: normal, area: 1, centroid: centroid, tags: tags)
    }

    /// The plate's left side with the flange flush: one face with both operands' tags (face 1).
    var merged: Topology {
        Topology(faces: [face(0, .unitZ, Vector3(0, 0, 6), [top]), face(1, -.unitX, Vector3(-30, 6, 8), [side, flangeSide])],
                 edges: [])
    }

    /// The flange gone elsewhere: the plate's side stands alone (face 1), and a flange face with the same tag
    /// faces the same way but stands 17 mm inboard (face 2, like a hexagon's side).
    var apart: Topology {
        Topology(faces: [
            face(0, .unitZ, Vector3(0, 0, 6), [top]), face(1, -.unitX, Vector3(-30, 0, 3), [side]),
            face(2, -.unitX, Vector3(-13, 16, 15), [flangeSide]),
        ], edges: [])
    }

    var pick: FacePick { FacePick(tags: [side, flangeSide], normal: -.unitX, centroid: Vector3(-30, 6, 8)) }

    @Test func tagsSplitByTheNodeCallThatMadeThem() {
        let parts: [Set<TopoTag>] = Set([side, flangeSide, top]).partsByOrigin
        #expect(parts.count == 2)
        #expect(Set(parts) == [[side, top], [flangeSide]])
        #expect(parts == Set([side, flangeSide, top]).partsByOrigin, "the order is stable")
    }

    @Test func tagsOfOneNodeCallDoNotSplit() {
        #expect(Set([side, top]).partsByOrigin.isEmpty)
        #expect(Set<TopoTag>().partsByOrigin.isEmpty)
        let second = TopoTag(node: plate, item: 1, role: .endCap)
        #expect(Set([top, second]).partsByOrigin.count == 2, "broadcast items are separate node calls")
    }

    @Test func aPickThatMatchesIsNotNarrowed() {
        let resolved = merged.resolution(of: pick)
        #expect(resolved == FaceResolution(faces: [merged.faces[1]]))
        #expect(!resolved.isNarrowed)
    }

    @Test func aPickOnAMergedFaceFindsThePartInItsPlane() {
        let resolved = apart.resolution(of: pick)
        #expect(resolved.faces.map(\.id) == [FaceID(1)])
        #expect(resolved.isNarrowed)
        #expect(!resolved.isAmbiguous, "the plate's side is the only part in the plane the face was in")
    }

    /// Without the normal and centroid (a pick made before they were recorded) the parts can't be told apart.
    @Test func aPickWithoutAPositionIsAGuess() {
        let resolved = apart.resolution(of: FacePick(tags: [side, flangeSide]))
        #expect(resolved.isNarrowed)
        #expect(resolved.isAmbiguous)
        #expect(resolved.faces.count == 1)
    }

    /// With no position the part is the first in `partsByOrigin` order: arbitrary (it sorts on node IDs) but the
    /// same every time, and it is the warning, not the choice, that tells the person.
    @Test func theGuessWithoutAPositionIsTheFirstPartAndStable() throws {
        let unplaced = FacePick(tags: [side, flangeSide])
        let first = try #require(unplaced.tags.partsByOrigin.first)
        let expected = apart.faces(matching: FacePick(tags: first)).map(\.id)
        #expect(apart.resolution(of: unplaced).faces.map(\.id) == expected)
        #expect(apart.resolution(of: unplaced) == apart.resolution(of: unplaced))
    }

    @Test func twoPartsInThePlaneAreAmbiguousAndTheNearestWins() {
        let coplanar = Topology(faces: [
            face(1, -.unitX, Vector3(-30, 0, 3), [side]), face(2, -.unitX, Vector3(-30, 18, 20), [flangeSide]),
        ], edges: [])
        let resolved = coplanar.resolution(of: pick)
        #expect(resolved.faces.map(\.id) == [FaceID(1)])
        #expect(resolved.isAmbiguous)
    }

    /// The plane is the same to within a micrometre: a model OCCT rebuilt can land that close without moving.
    @Test func aPartWithinAMicrometreOfThePlaneIsInIt() {
        for offset in [0.0003, -0.0009] {
            let nudged = Topology(faces: [face(1, -.unitX, Vector3(-30 + offset, 0, 3), [side])], edges: [])
            let resolved = nudged.resolution(of: pick)
            #expect(resolved.faces.map(\.id) == [FaceID(1)])
            #expect(resolved.isNarrowed && !resolved.isAmbiguous, "\(offset) mm off the plane")
        }
    }

    @Test func aPartFiveMicrometresOffThePlaneIsAGuess() {
        let moved = Topology(faces: [face(1, -.unitX, Vector3(-30.005, 0, 3), [side])], edges: [])
        #expect(moved.resolution(of: pick).isAmbiguous)
    }

    @Test func aPartOutsideThePlaneIsAGuess() {
        let moved = Topology(faces: [face(2, -.unitX, Vector3(-13, 16, 15), [flangeSide])], edges: [])
        let resolved = moved.resolution(of: pick)
        #expect(resolved.faces.map(\.id) == [FaceID(2)])
        #expect(resolved.isAmbiguous)
    }

    @Test func aPartFacingAnotherWayIsNotThePickedFace() {
        let flipped = Topology(faces: [face(2, .unitX, Vector3(-30, 16, 15), [flangeSide])], edges: [])
        #expect(flipped.resolution(of: pick) == FaceResolution(faces: []))
    }

    @Test func aPickOfOneNodeCallThatMatchesNothingStaysUnmatched() {
        let gone = FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .endCap)])
        #expect(apart.resolution(of: gone) == FaceResolution(faces: []))
        #expect(apart.resolution(of: FacePick(tags: [])) == FaceResolution(faces: []))
    }

    @Test func aFacesPickRecordsItsNormalAndCentroidWhenFlat() {
        #expect(merged.facePick(for: FaceID(1)) == pick)
        let cylinder = Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .cylinder, normal: .unitZ, area: 1, centroid: Vector3(1, 2, 3), tags: [side]),
        ], edges: [])
        #expect(cylinder.facePick(for: FaceID(0)) == FacePick(tags: [side], centroid: Vector3(1, 2, 3)))
    }

    @Test func theOptionalKeysRoundTripAndAreOmittedWhenAbsent() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try JSONDecoder().decode(FacePick.self, from: try encoder.encode(pick)) == pick)
        let plain = FacePick(tags: [side])
        let text = try #require(String(bytes: try encoder.encode(plain), encoding: .utf8))
        #expect(!text.contains("normal") && !text.contains("centroid"))
        #expect(try JSONDecoder().decode(FacePick.self, from: try encoder.encode(plain)) == plain)
    }

    /// A `FacePick` as builds before the position was recorded decode it (unknown keys ignored).
    struct EarlierFacePick: Decodable {
        var tags: [TopoTag]
    }

    @Test func anEarlierReaderIgnoresTheOptionalKeys() throws {
        let earlier = try JSONDecoder().decode(EarlierFacePick.self, from: try JSONEncoder().encode(pick))
        #expect(Set(earlier.tags) == pick.tags)
    }
}
```

In `Tests/CreatorKernelTests/FacePickTests.swift`, a face's pick now records its position, so the whole-tag-set test compares the tags:

```diff
--- a/Tests/CreatorKernelTests/FacePickTests.swift
+++ b/Tests/CreatorKernelTests/FacePickTests.swift
@@ -33,7 +33,7 @@
     }
 
     @Test func aFacesPickIsItsWholeTagSet() {
-        #expect(sample().facePick(for: FaceID(1)) == FacePick(tags: [top, flangeTop]))
+        #expect(sample().facePick(for: FaceID(1))?.tags == [top, flangeTop])
         #expect(sample().facePick(for: FaceID(9)) == nil)
     }
 
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -5`
Expected: errors such as "extra arguments at positions #2, #3 in call" / "value of type 'Set<TopoTag>' has no member 'partsByOrigin'" / "value of type 'Topology' has no member 'resolution'".

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorKernel/TopoTag+Parts.swift`:

```swift
extension Set where Element == TopoTag {
    /// These tags split by the node call that made them (`TopoTag.origin`), one set per operand, ordered by
    /// sort key so the order never depends on hashing. Empty unless the tags come from at least two node calls:
    /// only a face that a union merged has tags to split.
    public var partsByOrigin: [Set<TopoTag>] {
        let groups = Dictionary(grouping: self, by: \.origin)
        guard groups.count > 1 else { return [] }
        return groups.values.map { Set($0) }.sorted { Self.sortKey($0) < Self.sortKey($1) }
    }

    private static func sortKey(_ tags: Set<TopoTag>) -> String {
        tags.map(\.sortKey).sorted().joined(separator: "+")
    }
}
```

Replace `Sources/CreatorKernel/FacePick.swift`:

```swift
import CreatorGeometry

/// A remembered face pick (sketcher spec §7, Plane from Face): the picked face's tags. It names every
/// face whose tags include all of them, so a face a union merged with a coplanar one still matches.
/// A face that a union had merged names both operands' tags and matches nothing once they stop merging;
/// then the pick is retried per operand (`Topology.resolution(of:)`), ranked by where the face was.
public struct FacePick: Hashable, Sendable {
    public var tags: Set<TopoTag>
    /// The face's outward normal when it was picked, if it was flat. Optional key in the file: it is what
    /// tells the parts of a face that has since come apart from each other. `nil` for picks made without it.
    public var normal: Vector3?
    /// The face's centroid when it was picked. Optional, like `normal`.
    public var centroid: Vector3?

    public init(tags: Set<TopoTag>, normal: Vector3? = nil, centroid: Vector3? = nil) {
        self.tags = tags
        self.normal = normal
        self.centroid = centroid
    }

    /// True when a tag is the `.unnamed` fallback (directly or inside a blend's source edge), which is
    /// unstable across rebuilds, like `EdgePick.touchesUnnamedFace`.
    public var touchesUnnamedFace: Bool { tags.contains { $0.role.isUnstable } }
}
```

Replace `Sources/CreatorKernel/FacePick+Codable.swift`:

```swift
import CreatorGeometry

extension FacePick: Codable {
    private enum CodingKeys: String, CodingKey { case tags, normal, centroid }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tags: Set(try container.decode([TopoTag].self, forKey: .tags)),
                  normal: try container.decodeIfPresent(Vector3.self, forKey: .normal),
                  centroid: try container.decodeIfPresent(Vector3.self, forKey: .centroid))
    }

    /// Tags are written sorted by `sortKey`, so encoding is deterministic (`EdgeKey` does the same). `normal`
    /// and `centroid` are written only when recorded, so a pick without them is encoded as it always was and
    /// older readers, which ignore the keys, still read the tags: the file format version is unchanged.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tags.sorted { $0.sortKey < $1.sortKey }, forKey: .tags)
        try container.encodeIfPresent(normal, forKey: .normal)
        try container.encodeIfPresent(centroid, forKey: .centroid)
    }
}
```

Create `Sources/CreatorKernel/FaceResolution.swift`:

```swift
/// What a `FacePick` names in a topology now (`Topology.resolution(of:)`).
public struct FaceResolution: Equatable, Sendable {
    /// The faces the pick names, in ID order; after narrowing, only the part chosen.
    public var faces: [FaceInfo]
    /// True when no face had all the pick's tags and `faces` is a part of the face the pick was made on, one
    /// operand's share of it.
    public var isNarrowed: Bool
    /// True when narrowed and the part is a guess: the pick recorded no position, or no single part lies in the
    /// plane the face was in. A caller says so, never silently (spec §5.3, rule 6).
    public var isAmbiguous: Bool

    public init(faces: [FaceInfo], isNarrowed: Bool = false, isAmbiguous: Bool = false) {
        self.faces = faces
        self.isNarrowed = isNarrowed
        self.isAmbiguous = isAmbiguous
    }
}
```

Replace `Sources/CreatorKernel/Topology+FacePicks.swift`:

```swift
import CreatorGeometry

extension Topology {
    /// How far (micrometres) a part may lie from the picked face's plane and still count as in it: a model rebuilt
    /// by OCCT lands within a tiny fraction of this, and a real move is far more.
    static let planeTolerance = 1.0

    /// Every face whose tags include all of `pick`'s, in ID order. An empty pick matches nothing.
    public func faces(matching pick: FacePick) -> [FaceInfo] {
        guard !pick.tags.isEmpty else { return [] }
        return faces.filter { pick.tags.isSubset(of: $0.tags) }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The pick that names face `id`: its whole tag set, and, for a flat face, its normal and centroid. `nil`
    /// for a face that isn't in the table.
    public func facePick(for id: FaceID) -> FacePick? {
        guard let face = face(id) else { return nil }
        return FacePick(tags: face.tags, normal: face.kind == .plane ? face.normal : nil, centroid: face.centroid)
    }

    /// The faces a remembered pick names now: its matches (`faces(matching:)`) or, only when it has none, the
    /// part of its face that is left. A pick on a face a union merged names both operands' tags; when one
    /// operand changes and the faces no longer merge, the pick matches nothing, so it is retried with each
    /// operand's tags alone (`partsByOrigin`). A candidate must face the way the picked face did; the one in the
    /// picked face's plane wins, nearest its centroid first. The answer is unambiguous only when the pick
    /// recorded its position and exactly one candidate lies in that plane. A pick that matches anything is never
    /// narrowed, so a pick that resolves today resolves the same way.
    public func resolution(of pick: FacePick) -> FaceResolution {
        let matches = faces(matching: pick)
        guard matches.isEmpty else { return FaceResolution(faces: matches) }
        var candidates: [FaceInfo] = []
        var seen: Set<FaceID> = []
        for part in pick.tags.partsByOrigin {
            for face in faces(matching: FacePick(tags: part)) where seen.insert(face.id).inserted {
                candidates.append(face)
            }
        }
        if let normal = pick.normal?.normalized {
            candidates = candidates.filter { face in
                face.kind == .plane && (face.normal?.normalized.map { $0.dot(normal) > 1 - 1e-6 } ?? false)
            }
        }
        guard !candidates.isEmpty else { return FaceResolution(faces: []) }
        guard let normal = pick.normal?.normalized, let centroid = pick.centroid else {
            return FaceResolution(faces: [candidates[0]], isNarrowed: true, isAmbiguous: true)
        }
        // Distance from the picked face's plane in micrometres (the model is in millimetres); within
        // `planeTolerance` counts as in the plane, so parts in it tie at 0.
        func offset(_ face: FaceInfo) -> Double {
            let micrometres = abs(normal.dot(face.centroid - centroid)) * 1e3
            return micrometres <= Self.planeTolerance ? 0 : micrometres
        }
        let ranked = candidates.sorted { a, b in
            if offset(a) != offset(b) { return offset(a) < offset(b) }
            let (da, db) = ((a.centroid - centroid).length, (b.centroid - centroid).length)
            return da != db ? da < db : a.id.rawValue < b.id.rawValue
        }
        let inPlane = ranked.filter { offset($0) == 0 }.count
        return FaceResolution(faces: [ranked[0]], isNarrowed: true, isAmbiguous: inPlane != 1)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "FaceResolutionTests|FacePickTests"`
Expected: PASS, "Test run with 20 tests in 2 suites passed".

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/t1.log | grep -cE 'recorded an issue|failed after'; grep -c 'Test run with' /tmp/t1.log; swiftlint lint --strict | tail -1`
Expected: `0`, `11`, "Found 0 violations" (use your scratchpad instead of `/tmp`). The run's total is master + 15 = 1658.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorKernel Tests/CreatorKernelTests
git commit -m "feat(kernel): face picks record their position and find their part when a merged face comes apart"
```

---

### Task 2: Plane from Face survives the flange changing

**Files:**
- Modify: `Sources/CreatorNodes/Values/PlaneFromFaceNode.swift`, `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift`
- Test: `Tests/CreatorNodesTests/BracketAcceptanceTests+FacePicks.swift` (new), `Tests/CreatorGraphTests/Groups/FacePickRenamingTests.swift` (new)

**Interfaces:**
- Consumes: `Topology.resolution(of:) -> FaceResolution` and `FacePick(tags:normal:centroid:)` (Task 1); `BracketAcceptanceTests.makeBracket()`, `swapTheFlangeForAHexagon(in:_:)`, `DocumentModel.previewNode`, `GraphCommand` (existing).
- Produces: `PlaneFromFaceNode.mergedPick` (internal `static let`, the warning text); `BracketAcceptanceTests.isOK(_:_:) -> Bool`, `planeOutput(_:_:)`, `openBracketWithPlane(_:)`, `mergedLeftSide(_:_:)` helpers (Task 3 reuses `isOK`).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/BracketAcceptanceTests+FacePicks.swift` (the fourth test, `aPlanePickWithoutAPositionWarnsOnceTheFaceHasComeApart`, needs `mergedPick`, so it is added in Step 5):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Roadmap "Naming: face picks on merged faces", the Plane from Face half. A plane is picked on the plate's
    /// left side, which the union merged with the flange's coplanar side (it names both operands' tags), while
    /// the flange is as wide as the plate. Then the flange alone changes width, narrower (40) or wider (70)
    /// than the plate, so the faces no longer merge and the pick matches nothing. The plane stays on the plate's
    /// side, with no warning, it survives a save and reopen, and it is back on the merged face once the flange
    /// is flush again.
    @Test(arguments: [40.0, 70.0])
    func aPlanePickedOnAMergedSideSurvivesTheFlangeChangingWidth(flangeWidth: Double) async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        let flush = try planeOutput(document, plane)
        #expect(isClose(flush.origin.x, -30) && flush.normal.dot(-.unitX) > 0.999)

        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(flangeWidth))]))
        await document.waitForEvaluation()
        try expectPlaneOnThePlateSide(document, plane, bracket, "flange \(flangeWidth) wide")

        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: kernel)
        reopened.previewNode = plane.id
        await reopened.waitForEvaluation()
        try expectPlaneOnThePlateSide(reopened, plane, bracket, "reopened at \(flangeWidth)")

        try document.perform(.batch([.setInput(bracket.flangeProfile.id, "width", nil), .connect(widthWire)]))
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "flush again")
        let again = try planeOutput(document, plane)
        #expect(isClose(again.origin.x, -30) && isClose(again.origin.y, flush.origin.y) && isClose(again.origin.z, flush.origin.z))
    }

    /// The same pick with the flange's Rectangle swapped for the hexagon of Errata (M6): the hexagon's vertical
    /// sides carry the flange's side tags and face the same way, 17 mm inboard of the plate's side, and the
    /// plane stays on the plate's side. The Fillet after the union refuses the hexagon bracket at R3 (spec
    /// Errata (Kernel: invalid blends)), which is not the plane's business: it sits on the union.
    @Test func aPlanePickedOnAMergedSideSurvivesTheFlangeBecomingAPolygon() async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        try swapTheFlangeForAHexagon(in: document, bracket)
        await document.waitForEvaluation()
        try expectPlaneOnThePlateSide(document, plane, bracket, "hexagon flange")

        document.undo()
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "undone")
    }

    /// The other way round: the plate alone is widened to 80 (its sides move to x = -40) while the flange stays 60
    /// wide, so the only part left in the plane the pick was in (x = -30) is the flange's own side, up the flange.
    /// The plane stays where it was in space, on that part, and the node says nothing: it doesn't follow the plate's
    /// side that moved (user decision 1, option (e)).
    @Test func aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves() async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(60))]))
        try document.perform(.setParameter(bracket.width.id, .number(80)))
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "silent: \(String(describing: document.results[plane.id]?.state))")
        let result = try planeOutput(document, plane)
        #expect(isClose(result.origin.x, -30), "still in the plane x = -30, not the plate's new side at -40")
        #expect(result.normal.dot(-.unitX) > 0.999)
        #expect(result.origin.z > 6, "on the flange's side, up the flange")
    }

    /// The bracket with a Plane from Face on the union's merged left side, shown in the preview and evaluated.
    func openBracketWithPlane(_ kernel: OCCTKernel) async throws -> (DocumentModel, Bracket, Node) {
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let union = try #require(document.results[bracket.union.id]?.outputs?["solid"]?.solids?.first)
        let plane = BuiltInNodes.registry.makeNode(PlaneFromFaceNode.typeID)
        let solidWire = Link(from: Endpoint(node: bracket.union.id, socket: "solid"), to: Endpoint(node: plane.id, socket: "solid"))
        let pick = try #require(union.topology.facePick(for: mergedLeftSide(union, bracket)))
        try document.perform(.batch([.addNode(plane), .connect(solidWire), .setInput(plane.id, NodeSetting.face, .facePick(pick))]))
        document.previewNode = plane.id
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "flush flange")
        return (document, bracket, plane)
    }

    /// The union's face on the plate's left side that carries both the plate's and the flange's tags.
    func mergedLeftSide(_ union: Solid, _ bracket: Bracket) throws -> FaceID {
        try #require(union.topology.faces.first { face in
            face.kind == .plane && (face.normal?.dot(-.unitX) ?? 0) > 0.999
                && face.tags.contains { $0.node == bracket.plate.id } && face.tags.contains { $0.node == bracket.flange.id }
        }).id
    }

    /// True for `.ok`: the node succeeded with no warning.
    func isOK(_ document: DocumentModel, _ node: Node) -> Bool {
        if case .ok? = document.results[node.id]?.state { true } else { false }
    }

    func planeOutput(_ document: DocumentModel, _ plane: Node) throws -> Plane {
        try #require(document.results[plane.id]?.outputs?["plane"]?.planes?.first)
    }

    /// The plane is on the plate's left side (x = -30, facing -X), and the node says nothing about it.
    func expectPlaneOnThePlateSide(_ document: DocumentModel, _ plane: Node, _ bracket: Bracket, _ when: String,
                                   sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(isOK(document, plane), "\(when)", sourceLocation: sourceLocation)
        let result = try planeOutput(document, plane)
        #expect(isClose(result.origin.x, -30), "\(when): at the plate's side", sourceLocation: sourceLocation)
        #expect(result.normal.dot(-.unitX) > 0.999, "\(when): facing out", sourceLocation: sourceLocation)
        #expect(result.origin.z <= 6, "\(when): on the plate, not up the flange", sourceLocation: sourceLocation)
    }
}
```

Create `Tests/CreatorGraphTests/Groups/FacePickRenamingTests.swift`:

```swift
import CreatorGeometry
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// A face pick renamed for a group keeps the position it recorded (roadmap "Naming: face picks on merged faces").
struct FacePickRenamingTests {
    @Test func renamingATagKeepsTheRecordedNormalAndCentroid() {
        let a = NodeID(), b = NodeID()
        let pick = FacePick(tags: [TopoTag(node: a, item: 0, role: .endCap)], normal: .unitZ, centroid: Vector3(1, 2, 3))
        let renamed = ConstantValue.facePick(pick).renamingTags([a: b])
        #expect(renamed == .facePick(FacePick(tags: [TopoTag(node: b, item: 0, role: .endCap)],
                                              normal: .unitZ, centroid: Vector3(1, 2, 3))))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "aPlanePicked|FacePickRenaming"`
Expected: FAIL. `aPlanePickedOnAMergedSideSurvivesTheFlangeChangingWidth` (both arguments), `…BecomingAPolygon` and `aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves` record "Expectation failed: isOK(document, plane)" at the first check after the change (Plane from Face is in error "The picked face isn't on this solid any more. Pick it again."), then "…planes.first" is nil; `renamingATagKeepsTheRecordedNormalAndCentroid` fails because the renamed pick lost its position. The checks before the change pass.

- [ ] **Step 3: Write the implementation**

```diff
--- a/Sources/CreatorNodes/Values/PlaneFromFaceNode.swift
+++ b/Sources/CreatorNodes/Values/PlaneFromFaceNode.swift
@@ -4,7 +4,9 @@
 
 /// A plane on a flat face of a solid (sketcher spec §7): origin at the face centroid, normal along the
 /// face's outward normal, x axis from `FacePlane`. The face is the remembered `FacePick` in the `face`
-/// setting, so the plane follows the face when the model changes. "New sketch on face" (S5) wires this
+/// setting, so the plane follows the face when the model changes, and, when the face was one a union merged
+/// with another operand's and the faces have since come apart, it stays on the part that is left
+/// (`Topology.resolution(of:)`). "New sketch on face" (S5) wires this
 /// node into a Sketch.
 public enum PlaneFromFaceNode: NodeDefinition {
     public static let typeID = "creator.planeFromFace"
@@ -19,6 +21,8 @@
     static let notFlat = "The picked face isn't flat, so it has no plane."
     static let unnamedPick = "The picked face has no stable name, so the plane may move to a different face "
         + "when the model changes. Pick it again after the change."
+    static let mergedPick = "The picked face was merged with a face from another part of the model that has since changed, "
+        + "so it isn't clear which part was picked. The plane sits on the closest one; pick the face again to settle it."
 
     public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
         let solid = try inputs.solid("solid")
@@ -28,11 +32,14 @@
         case .facePick(let stored)?: pick = stored
         case .some: throw NodeError.invalidValue(unreadablePick)
         }
-        let matches = solid.topology.faces(matching: pick)
+        let resolution = solid.topology.resolution(of: pick)
+        let matches = resolution.faces
         guard let face = matches.first else { throw NodeError.invalidValue(noMatch) }
         guard face.kind == .plane, let normal = face.normal?.normalized else { throw NodeError.invalidValue(notFlat) }
         var warnings: [String] = []
-        if matches.count > 1 {
+        if resolution.isAmbiguous {
+            warnings.append(mergedPick)
+        } else if matches.count > 1 {
             warnings.append("The pick matches \(matches.count.display) faces; the plane is on the first.")
         }
         if pick.touchesUnnamedFace { warnings.append(unnamedPick) }
```

```diff
--- a/Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift
+++ b/Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift
@@ -15,7 +15,9 @@
                 return renamed
             })
         case .facePick(let pick):
-            return .facePick(FacePick(tags: Self.renaming(pick.tags, names)))
+            var renamed = pick
+            renamed.tags = Self.renaming(pick.tags, names)
+            return .facePick(renamed)
         default:
             return self
         }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "aPlanePicked|FacePickRenaming|PlaneFromFaceNodeTests"`
Expected: PASS.

- [ ] **Step 5: Add the old-pick warning test**

In `Tests/CreatorNodesTests/BracketAcceptanceTests+FacePicks.swift`, insert this test before the comment `/// The bracket with a Plane from Face on the union's merged left side`:

```swift
    /// A pick made before faces recorded their position can't tell the parts apart: the plane is still found, on
    /// the first part, and it says so.
    @Test func aPlanePickWithoutAPositionWarnsOnceTheFaceHasComeApart() async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        let union = try #require(document.results[bracket.union.id]?.outputs?["solid"]?.solids?.first)
        let tags = try #require(union.topology.facePick(for: mergedLeftSide(union, bracket))?.tags)
        try document.perform(.setInput(plane.id, NodeSetting.face, .facePick(FacePick(tags: tags))))
        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(40))]))
        await document.waitForEvaluation()
        #expect(document.results[plane.id]?.state == .warning(PlaneFromFaceNode.mergedPick))
        #expect(document.results[plane.id]?.outputs?["plane"]?.planes?.count == 1)
    }
```

Run: `swift test --filter "BracketAcceptanceTests"`
Expected: PASS ("Test run with 9 tests"): the new four, plus the five that were there.

- [ ] **Step 6: Full suite and lint**

Run the full suite and lint as in Task 1 Step 5. Expected: exit 0, no "recorded an issue"/"failed after", 11 "Test run with" lines, 0 violations; the total is master + 20 = 1663.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorNodes/Values/PlaneFromFaceNode.swift Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift Tests/CreatorNodesTests/BracketAcceptanceTests+FacePicks.swift Tests/CreatorGraphTests/Groups/FacePickRenamingTests.swift
git commit -m "feat(nodes): Plane from Face stays on its part when the merged face comes apart"
```

---

### Task 3: A hole rim through a merged side survives the flange changing

**Files:**
- Create: `Sources/CreatorKernel/EdgeKey+Operands.swift`, `Sources/CreatorKernel/EdgeResolution.swift`, `Sources/CreatorKernel/Topology+EdgeResolution.swift`
- Modify: `Sources/CreatorKernel/Topology+EdgePicks.swift`, `Sources/CreatorNodes/Selection/EdgeTagMatch.swift`, `Sources/CreatorNodes/Selection/EdgesByTagNode.swift`, `Sources/CreatorNodes/Sketch/SketchProjections.swift`
- Test: `Tests/CreatorNodesTests/BracketAcceptanceTests+HoleThroughMergedSide.swift` (new), `Tests/CreatorKernelTests/EdgeOperandKeyTests.swift` (new), `Tests/CreatorNodesTests/EdgeTagMatchOperandTests.swift` (new), `Tests/CreatorNodesTests/SketchProjectionOperandTests.swift` (new)

**Interfaces:**
- Consumes: `Set<TopoTag>.partsByOrigin` (Task 1); `EdgeKey.narrowed`, `Topology.edges(matching:)` (exist); `BracketAcceptanceTests.isOK(_:_:)` (Task 2).
- Produces: `EdgeKey.operandKeys: [EdgeKey]`; `public struct EdgeResolution { edges: [EdgeInfo]; isAmbiguous: Bool; isSplit: Bool }`; `Topology.resolution(of: EdgeKey, expecting: Int? = nil) -> EdgeResolution`; `EdgeTagMatch.choose(_:in:comparesRecordedCount:)` returning `(chosen, matchCount, runCount, isAmbiguous)`; `EdgeTagMatch.ambiguousPick` (internal `static let`).

- [ ] **Step 1: Write the failing acceptance test**

Create `Tests/CreatorNodesTests/BracketAcceptanceTests+HoleThroughMergedSide.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Roadmap "Naming: face picks on merged faces", the edge half: a 5 mm hole drilled along X at y = 16, z = 3
    /// through the bracket's union, so its rim on the left side is an edge between a face the union merged (the
    /// plate's side and the flange's, `{plate.side, flange.side}`) and the hole's wall, which shares no node call
    /// with either. The rim is picked with the flange flush; then the flange alone changes width (40 or 70), or is
    /// swapped for the hexagon of Errata (M6), so the faces no longer merge and the key matches nothing. Edges by
    /// Tag still finds the rim on the plate's side, with no warning, after a save and reopen too, and the pick holds
    /// once the flange is flush again (the width cases).
    @Test(arguments: [(40.0, -30.0), (70.0, -35.0)])
    func aHoleRimPickedOnAMergedSideSurvivesTheFlangeChangingWidth(flangeWidth: Double, rimX: Double) async throws {
        try await checkTheRimSurvives("flange \(flangeWidth) wide", rimX: rimX) { document, bracket in
            let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
            try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(flangeWidth))]))
            return .batch([.setInput(bracket.flangeProfile.id, "width", nil), .connect(widthWire)])
        }
    }

    @Test func aHoleRimPickedOnAMergedSideSurvivesTheFlangeBecomingAPolygon() async throws {
        try await checkTheRimSurvives("hexagon flange", rimX: -30) { document, bracket in
            try swapTheFlangeForAHexagon(in: document, bracket)
            return nil
        }
    }

    /// Picks the hole's rim with the flange flush, applies `change` (which returns the command that restores the
    /// flange, if it has one), and checks the rule before, after, reopened and restored.
    func checkTheRimSurvives(_ when: String, rimX: Double, change: (DocumentModel, Bracket) throws -> GraphCommand?) async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let rule = try await addHole(to: document, bracket)
        let drilled = try edgeSetOutput(document, rule)
        let leftRim = try #require(drilled.solid.topology.edges.first { edge in
            !edge.isSeam && edge.kind == .circle && edge.midpoint.x < -29
        })
        let picks = drilled.solid.topology.picks(for: [leftRim.id])
        let flushKey = try #require(picks.first?.key)
        #expect(picks.count == 1 && flushKey.first.union(flushKey.second).contains { $0.node == bracket.flange.id },
                "the rim is named by the merged side's tags, the flange's among them")
        try document.perform(.setInput(rule.id, NodeSetting.picks, .edgePicks(picks)))
        await document.waitForEvaluation()
        #expect(isOK(document, rule), "flush flange")

        let restore = try change(document, bracket)
        await document.waitForEvaluation()
        try expectTheRim(document, rule, at: rimX, notNamed: flushKey, when)

        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: kernel)
        reopened.previewNode = rule.id
        await reopened.waitForEvaluation()
        try expectTheRim(reopened, rule, at: rimX, notNamed: flushKey, "reopened, \(when)")

        if let restore {
            try document.perform(restore)
            await document.waitForEvaluation()
            #expect(isOK(document, rule), "flush again")
            #expect(keys(try edgeSetOutput(document, rule)) == [flushKey])
        }
    }

    /// Drills the hole (a Circle on a YZ plane through (0, 16, 3), a symmetric Extrude, a subtracting Boolean on the
    /// union) and adds an Edges by Tag on the result, shown in the preview and evaluated.
    func addHole(to document: DocumentModel, _ bracket: Bracket) async throws -> Node {
        let registry = BuiltInNodes.registry
        var circle = registry.makeNode(CircleNode.typeID)
        let plane = Plane(origin: Vector3(0, 16, 3), normal: .unitX, xAxis: .unitY)
        circle.inputValues.merge(["diameter": .number(5), "plane": .plane(plane)]) { _, new in new }
        var bore = registry.makeNode(ExtrudeNode.typeID)
        bore.inputValues.merge(["distance": .number(100), "mode": .integer(1)]) { _, new in new }
        var drill = registry.makeNode(BooleanNode.typeID)
        drill.inputValues["operation"] = .integer(1)
        let rule = registry.makeNode(EdgesByTagNode.typeID)
        func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> GraphCommand {
            .connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input)))
        }
        try document.perform(.batch([
            .addNode(circle), .addNode(bore), .addNode(drill), .addNode(rule),
            link(circle, "profile", bore, "profile"), link(bracket.union, "solid", drill, "target"),
            link(bore, "solid", drill, "tools"), link(drill, "solid", rule, "solid"),
        ]))
        document.previewNode = rule.id
        await document.waitForEvaluation()
        #expect(document.results[rule.id]?.state == .warning("Pick edges in view to fill this rule."), "drilled, nothing picked yet")
        return rule
    }

    func edgeSetOutput(_ document: DocumentModel, _ rule: Node) throws -> EdgeSet {
        try #require(document.results[rule.id]?.outputs?["edges"]?.edgeSets?.first)
    }

    /// The rule picks exactly one edge, the hole's rim in the bracket's left side at x = `x`, under another name
    /// than the merged side's (the plate's side at -30, or the flange's own at -35 once it sticks out), and says
    /// nothing about it.
    func expectTheRim(_ document: DocumentModel, _ rule: Node, at x: Double, notNamed flushKey: EdgeKey, _ when: String,
                      sourceLocation: SourceLocation = #_sourceLocation) throws {
        let state = String(describing: document.results[rule.id]?.state)
        #expect(isOK(document, rule), "\(when): \(state)", sourceLocation: sourceLocation)
        let set = try edgeSetOutput(document, rule)
        #expect(set.edges.count == 1, "\(when): the rim", sourceLocation: sourceLocation)
        let rim = try #require(set.edges.first.flatMap { set.solid.topology.edge($0) }, sourceLocation: sourceLocation)
        #expect(rim.kind == .circle && isClose(rim.midpoint.x, x), "\(when): at x = \(x)", sourceLocation: sourceLocation)
        #expect(set.solid.topology.key(of: rim) != flushKey, "\(when): named by the operand that has it", sourceLocation: sourceLocation)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter "aHoleRimPicked"`
Expected: FAIL in all three cases (40, 70, hexagon). Everything up to the change passes (the rim is picked, "flush flange" is `.ok`); after the change `isOK(document, rule)` fails (Edges by Tag warns "Matched 0 edges, expected 1."), and `set.edges.count == 1` fails.

- [ ] **Step 3: Write the unit tests**

Create `Tests/CreatorKernelTests/EdgeOperandKeyTests.swift`:

```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Edge picks between a merged face and a third operand's face (roadmap "Naming: face picks on merged faces"):
/// `EdgeKey.operandKeys` and `Topology.resolution(of:expecting:)`.
struct EdgeOperandKeyTests {
    let plate = NodeID()
    let flange = NodeID()
    let hole = NodeID()
    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var flangeFront: TopoTag { TopoTag(node: flange, item: 0, role: .endCap) }
    var wall: TopoTag { TopoTag(node: hole, item: 0, role: .side(segment: 0)) }

    @Test func aMergedSideSharingNothingWithTheOtherSideIsSplitByOperand() {
        let keys = EdgeKey([side, flangeSide], [wall]).operandKeys
        #expect(Set(keys) == [EdgeKey([side], [wall]), EdgeKey([flangeSide], [wall])])
        #expect(keys == EdgeKey([wall], [flangeSide, side]).operandKeys, "the order is stable")
    }

    @Test func twoMergedSidesAreSplitOnBothSides() {
        let otherWall = TopoTag(node: NodeID(), item: 0, role: .side(segment: 1))
        #expect(Set(EdgeKey([side, flangeSide], [wall, otherWall]).operandKeys).count == 4, "each operand against each")
    }

    /// A side that has a node call in common with the other side is `narrowed`'s case, not this one's.
    @Test func aSideSharingANodeCallWithTheOtherSideIsNotSplit() {
        #expect(EdgeKey([top], [side, flangeSide]).operandKeys.isEmpty)
        #expect(EdgeKey([top, flangeFront], [side, flangeSide]).operandKeys.isEmpty)
    }

    @Test func aKeyOfSingleOperandSidesHasNoOperandKeys() {
        #expect(EdgeKey([side], [wall]).operandKeys.isEmpty)
    }

    /// Face 0: the plate's side, with or without the flange's tag (`merged`). Face 1: a flange face of its own.
    /// Face 2: the hole's wall. Edge 0 is the hole's rim on the plate part (face 0 | wall); `flangeRims` more
    /// edges (IDs 1...) are rims on the flange part (face 1 | wall).
    func topology(merged: Bool, flangeRims: Int = 0) -> Topology {
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: merged ? [side, flangeSide] : [side]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            FaceInfo(id: FaceID(2), kind: .cylinder, normal: .unitX, area: 1, centroid: .zero, tags: [wall]),
        ]
        func rim(_ id: Int, _ face: Int, at z: Double) -> EdgeInfo {
            EdgeInfo(id: EdgeID(id), kind: .circle, direction: .unitX, length: 15, midpoint: Vector3(-30, 16, z),
                     convexity: .concave, faces: [FaceID(face), FaceID(2)])
        }
        let flange = (0..<flangeRims).map { rim($0 + 1, 1, at: 12 + 8 * Double($0)) }
        return Topology(faces: faces, edges: [rim(0, 0, at: 3)] + flange)
    }

    @Test func aKeyThatMatchesIsResolvedAsBefore() {
        let key = EdgeKey([side, flangeSide], [wall])
        let merged = topology(merged: true)
        #expect(merged.resolution(of: key) == EdgeResolution(edges: [merged.edges[0]]))
    }

    @Test func aRimOnAMergedSideIsFoundOnTheOperandThatStillHasIt() {
        let key = EdgeKey([side, flangeSide], [wall])
        let apart = topology(merged: false)
        #expect(apart.edges(matching: key).isEmpty)
        #expect(apart.resolution(of: key, expecting: 1) == EdgeResolution(edges: [apart.edges[0]], isSplit: true))
        #expect(apart.edges(resolving: key).map(\.id) == [EdgeID(0)])
    }

    @Test func twoOperandsWithARimAreAmbiguousUnlessTheCountTellsThemApart() {
        let key = EdgeKey([side, flangeSide], [wall])
        let both = topology(merged: false, flangeRims: 1)
        let guess = both.resolution(of: key, expecting: 1)
        #expect(guess.isAmbiguous && guess.isSplit)
        #expect(guess.edges.count == 1, "one operand's rim, never both")
        #expect(both.resolution(of: key).isAmbiguous)
        #expect(both.resolution(of: key, expecting: 5).isAmbiguous, "no operand has five")
    }

    @Test func theCountPicksTheOperandWhoseRimsMatchIt() {
        // The flange's face has two rims; the plate's has one. A pick of two edges was the flange's.
        let two = topology(merged: false, flangeRims: 2).resolution(of: EdgeKey([side, flangeSide], [wall]), expecting: 2)
        #expect(!two.isAmbiguous && two.isSplit)
        #expect(two.edges.map(\.id) == [EdgeID(1), EdgeID(2)])
    }

    @Test func aKeyOfGoneTagsStillMatchesNothing() {
        let gone = TopoTag(node: NodeID(), item: 0, role: .endCap)
        let key = EdgeKey([side, gone], [TopoTag(node: NodeID(), item: 0, role: .endCap)])
        #expect(topology(merged: false).resolution(of: key) == EdgeResolution(edges: []))
    }
}
```

Create `Tests/CreatorNodesTests/EdgeTagMatchOperandTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
@testable import CreatorNodes
import Testing

/// Edges by Tag on a hole's rim through a face a union merged (roadmap "Naming: face picks on merged faces"), on
/// hand-built topologies: the plate's side (face 0), merged with the flange's coplanar side while the flange
/// stands flush, a flange face of its own (face 1) and the hole's wall (face 2).
struct EdgeTagMatchOperandTests {
    let plate = NodeID()
    let flange = NodeID()
    let hole = NodeID()
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var wall: TopoTag { TopoTag(node: hole, item: 0, role: .side(segment: 0)) }

    func rim(_ id: Int, _ face: Int, at z: Double) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .circle, direction: .unitX, length: 15, midpoint: Vector3(-30, 16, z),
                 convexity: .concave, faces: [FaceID(face), FaceID(2)])
    }

    func topology(flush: Bool, flangeRim: Bool = false) -> Topology {
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: flush ? [side, flangeSide] : [side]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            FaceInfo(id: FaceID(2), kind: .cylinder, normal: .unitX, area: 1, centroid: .zero, tags: [wall]),
        ]
        return Topology(faces: faces, edges: flangeRim ? [rim(0, 0, at: 3), rim(1, 1, at: 12)] : [rim(0, 0, at: 3)])
    }

    @Test func aRimPickedOnTheMergedSideSurvivesTheFlangeLeaving() {
        let picks = topology(flush: true).picks(for: [EdgeID(0)])
        #expect(picks == [EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 1)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: false)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aRimPickedApartResolvesWhenTheFlangeIsFlushAgain() {
        let picks = topology(flush: false).picks(for: [EdgeID(0)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aGuessBetweenOperandsIsReportedNotSilent() {
        let picks = topology(flush: true).picks(for: [EdgeID(0)])
        let match = EdgeTagMatch.resolve(picks, in: topology(flush: false, flangeRim: true))
        #expect(match.edges.count == 1)
        #expect(match.warnings == [EdgeTagMatch.ambiguousPick])
    }

    /// The recorded count is one solid's; a sum over several references is nobody's, so `choose` can be told not
    /// to compare it. The flange's face has two rims and the plate's one, and the pick recorded two.
    @Test func aCountSummedOverReferencesIsNotComparedWithOneSolid() {
        let flangeRims = Topology(faces: topology(flush: false).faces,
                                  edges: [rim(0, 0, at: 3), rim(1, 1, at: 12), rim(2, 1, at: 20)])
        let pick = EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 2)
        let compared = EdgeTagMatch.choose(pick, in: flangeRims)
        #expect(!compared.isAmbiguous && compared.chosen.map(\.id) == [EdgeID(1), EdgeID(2)])
        #expect(EdgeTagMatch.choose(pick, in: flangeRims, comparesRecordedCount: false).isAmbiguous)
    }

    /// Ordinals index the edges the whole key matched; once the key has been split by operand they index another
    /// list, so the pick says it guessed, even with one operand left. A key that still matches isn't split.
    @Test func anOrdinalPickResolvedByOperandIsAGuess() {
        let pick = EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 1, ordinals: [0])
        let apart = EdgeTagMatch.resolve([pick], in: topology(flush: false))
        #expect(apart.edges == [EdgeID(0)])
        #expect(apart.warnings == [EdgeTagMatch.ambiguousPick])
        #expect(EdgeTagMatch.resolve([pick], in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aRimThatIsGoneWarnsAsBefore() {
        let picks = topology(flush: true).picks(for: [EdgeID(0)])
        let bare = Topology(faces: topology(flush: false).faces, edges: [])
        #expect(EdgeTagMatch.resolve(picks, in: bare).warnings == ["Matched 0 edges, expected 1."])
    }
}
```

Create `Tests/CreatorNodesTests/SketchProjectionOperandTests.swift`:

```swift
import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorNodes
import Testing

/// A Sketch projection of a hole's rim through a face a union merged (roadmap "Naming: face picks on merged
/// faces"): `SketchProjections.locate` finds the rim by operand and says when it had to guess between two.
struct SketchProjectionOperandTests {
    let plate = NodeID()
    let flange = NodeID()
    let hole = NodeID()
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var wall: TopoTag { TopoTag(node: hole, item: 0, role: .side(segment: 0)) }

    /// The plate's side (face 0) with its rim (edge 0); with `flangeRim`, a flange face (face 1) has one too (edge 1).
    func reference(flangeRim: Bool) -> Solid {
        func rim(_ id: Int, _ face: Int, at z: Double) -> EdgeInfo {
            EdgeInfo(id: EdgeID(id), kind: .line, direction: .unitY, length: 5, midpoint: Vector3(-30, 16, z),
                     convexity: .concave, faces: [FaceID(face), FaceID(2)],
                     curve: .line(start: Vector3(-30, 14, z), end: Vector3(-30, 18, z)))
        }
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [side]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            FaceInfo(id: FaceID(2), kind: .cylinder, normal: .unitX, area: 1, centroid: .zero, tags: [wall]),
        ]
        let topology = Topology(faces: faces, edges: flangeRim ? [rim(0, 0, at: 3), rim(1, 1, at: 12)] : [rim(0, 0, at: 3)])
        return Solid(topology: topology, bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: FakeStorage())
    }

    var pick: EdgePick { EdgePick(key: EdgeKey([side, flangeSide], [wall]), matchCount: 1) }

    @Test func aRimOnTheOperandThatIsLeftIsFoundWithoutDrift() throws {
        guard case .found(let edge, let drift) = SketchProjections.locate(.edgePicks([pick]), in: [reference(flangeRim: false)]) else {
            Issue.record("the rim wasn't found")
            return
        }
        #expect(edge.id == EdgeID(0))
        #expect(drift == nil)
    }

    @Test func aGuessBetweenTwoOperandsIsSaid() throws {
        guard case .found(_, let drift) = SketchProjections.locate(.edgePicks([pick]), in: [reference(flangeRim: true)]) else {
            Issue.record("a rim wasn't found")
            return
        }
        #expect(drift == EdgeTagMatch.ambiguousPick)
    }
}
```

- [ ] **Step 4: Write the implementation**

Create `Sources/CreatorKernel/EdgeKey+Operands.swift`:

```swift
extension EdgeKey {
    /// The keys that name this key's edge by one operand at a time, for a side that `narrowed` can't cut down.
    ///
    /// A side that a union merged from several operands (`Set<TopoTag>.partsByOrigin`) has tags from node calls
    /// the other side knows nothing about when the edge runs between that side and a third operand's face: the rim
    /// of a hole drilled through a plate side that a flange side was merged into is `{plate.side, flange.side} |
    /// {hole.wall}`, and the hole wall shares no node call with either. Each such side is replaced by each
    /// operand's tags in turn, and the keys are returned in sort-key order, so the order never depends on hashing.
    /// A side with a node call in common with the other side is left alone (that is `narrowed`'s case), so an edge
    /// where two operands meet is never turned into an edge of one of them. Empty when no side can be split.
    public var operandKeys: [EdgeKey] {
        let firsts = Self.parts(first, toward: second), seconds = Self.parts(second, toward: first)
        guard firsts.count > 1 || seconds.count > 1 else { return [] }
        var seen: Set<EdgeKey> = [self]
        var keys: [EdgeKey] = []
        for a in firsts {
            for b in seconds {
                let key = EdgeKey(a, b)
                if seen.insert(key).inserted { keys.append(key) }
            }
        }
        return keys.sorted { $0.sortKey < $1.sortKey }
    }

    private static func parts(_ side: Set<TopoTag>, toward other: Set<TopoTag>) -> [Set<TopoTag>] {
        let origins = Set(other.map(\.origin))
        if side.contains(where: { origins.contains($0.origin) }) { return [side] }
        let parts = side.partsByOrigin
        return parts.isEmpty ? [side] : parts
    }
}
```

Create `Sources/CreatorKernel/EdgeResolution.swift`:

```swift
/// What an `EdgeKey` names in a topology now (`Topology.resolution(of:expecting:)`).
public struct EdgeResolution: Equatable, Sendable {
    /// The edges the key names, ordered by midpoint (x, then y, then z), then by ID.
    public var edges: [EdgeInfo]
    /// True when no edge had the key's tags and several operands' parts of it each name edges, so the choice
    /// between them is a guess. A caller says so, never silently (spec §5.3, rule 6).
    public var isAmbiguous: Bool
    /// True when `edges` are one operand's share of the key (`EdgeKey.operandKeys`), however many operands fit. A
    /// pick's edge ordinals were recorded against the whole key's matches, so they mean nothing among these.
    public var isSplit: Bool

    public init(edges: [EdgeInfo], isAmbiguous: Bool = false, isSplit: Bool = false) {
        self.edges = edges
        self.isAmbiguous = isAmbiguous
        self.isSplit = isSplit
    }
}
```

Create `Sources/CreatorKernel/Topology+EdgeResolution.swift`:

```swift
extension Topology {
    /// The edges a remembered key names now: its matches, or, only when it has none, the matches of its narrowed
    /// key (`EdgeKey.narrowed`), or, only when that has none either, the matches of the keys that name it by one
    /// operand at a time (`EdgeKey.operandKeys`: an edge between a merged face and a third operand's face).
    /// When several of those name edges, the one whose edge count is `count` wins if exactly one has it;
    /// otherwise the nearest count wins, then the first key in sort-key order, and the result is ambiguous.
    /// `count` is the edge count of one reference solid: leave it `nil` when the pick's count was summed across
    /// several (the sum names no operand's count). A key that matches anything is never narrowed, so a pick that resolves today resolves the same way.
    public func resolution(of key: EdgeKey, expecting count: Int? = nil) -> EdgeResolution {
        let matches = edges(matching: key)
        if !matches.isEmpty { return EdgeResolution(edges: matches) }
        if let narrowed = key.narrowed {
            let narrowedMatches = edges(matching: narrowed)
            if !narrowedMatches.isEmpty { return EdgeResolution(edges: narrowedMatches) }
        }
        let found = key.operandKeys.map { edges(matching: $0) }.filter { !$0.isEmpty }
        guard let first = found.first else { return EdgeResolution(edges: []) }
        guard found.count > 1 else { return EdgeResolution(edges: first, isSplit: true) }
        guard let count else { return EdgeResolution(edges: first, isAmbiguous: true, isSplit: true) }
        let exact = found.filter { $0.count == count }
        if exact.count == 1 { return EdgeResolution(edges: exact[0], isSplit: true) }
        let nearest = (exact.isEmpty ? found : exact).min { abs($0.count - count) < abs($1.count - count) }
        return EdgeResolution(edges: nearest ?? first, isAmbiguous: true, isSplit: true)
    }
}
```

`edges(resolving:)` now delegates:

```diff
--- a/Sources/CreatorKernel/Topology+EdgePicks.swift
+++ b/Sources/CreatorKernel/Topology+EdgePicks.swift
@@ -14,14 +14,10 @@
         edges.filter { edge($0, matches: key) }.sorted(by: Self.midpointOrder)
     }
 
-    /// The edges a remembered key names now: its matches, or, only when it has none, the matches of its
-    /// narrowed key (`EdgeKey.narrowed`). A pick on a face a union merged names both operands' tags; when
-    /// the other operand changes and the faces no longer merge, the narrowed key still finds the edge. A
-    /// key that matches anything is never narrowed, so a pick that resolves today resolves the same way.
+    /// The edges a remembered key names now (`resolution(of:expecting:)` without a count): its matches, else
+    /// those of its narrowed key, else those of its operand keys.
     public func edges(resolving key: EdgeKey) -> [EdgeInfo] {
-        let matches = edges(matching: key)
-        guard matches.isEmpty, let narrowed = key.narrowed else { return matches }
-        return edges(matching: narrowed)
+        resolution(of: key).edges
     }
 
     /// The picks that select exactly `ids`: one per distinct key, in first-picked order. A key that
```

Edges by Tag reports a guess, and the projections say it too:

```diff
--- a/Sources/CreatorNodes/Selection/EdgeTagMatch.swift
+++ b/Sources/CreatorNodes/Selection/EdgeTagMatch.swift
@@ -9,6 +9,8 @@
     static let nothingPicked = "Pick edges in view to fill this rule."
     static let unnamedPick = "A picked edge borders a face with no stable name, so the pick may move to a different edge "
         + "when the model changes. Pick it again after the change."
+    static let ambiguousPick = "A picked edge was on a face that a union had merged from several parts, and more than one of "
+        + "them now has an edge that fits. The pick uses the closest match; pick it again to settle it."
 
     /// Drift is reported per drifted pick, so two picks drifting in opposite directions
     /// (1 → 2 and 1 → 0) never cancel out into "Matched 2 edges, expected 2.". A pick drifts by
@@ -18,8 +20,10 @@
         var selected: [EdgeID] = []
         var seen: Set<EdgeID> = []
         var drifts: [(found: Int, expected: Int)] = []
+        var isAmbiguous = false
         for pick in picks {
             let choice = choose(pick, in: topology)
+            isAmbiguous = isAmbiguous || choice.isAmbiguous
             if pick.hasDrifted(matching: choice.matchCount, inRuns: choice.runCount) {
                 drifts.append((choice.matchCount, pick.matchCount))
             }
@@ -33,19 +37,31 @@
         } else if selected.isEmpty {
             warnings.append("Matched 0 edges, expected \(picks.reduce(0) { $0 + $1.matchCount }).")
         }
+        if isAmbiguous {
+            warnings.append(ambiguousPick)
+        }
         if picks.contains(where: \.touchesUnnamedFace) {
             warnings.append(unnamedPick)
         }
         return EdgeTagMatch(edges: selected, warnings: warnings)
     }
 
-    /// The edges one pick chooses in `topology` (what its key resolves to, `Topology.edges(resolving:)`:
-    /// its tag-subset matches, else its narrowed key's; then narrowed by its ordinals), how many edges the
-    /// key matched and how many runs they form. The Sketch node's projections use it too.
-    static func choose(_ pick: EdgePick, in topology: Topology) -> (chosen: [EdgeInfo], matchCount: Int, runCount: Int) {
-        let matches = topology.edges(resolving: pick.key)
+    /// The edges one pick chooses in `topology` (what its key resolves to, `Topology.resolution(of:expecting:)`:
+    /// its tag-subset matches, else its narrowed key's, else one operand's share of it; then narrowed by its
+    /// ordinals), how many edges the key matched, how many runs they form and whether the choice between operands
+    /// was a guess. The Sketch node's projections use it too.
+    ///
+    /// `comparesRecordedCount` says the pick's recorded count is for this topology alone; a caller that sums
+    /// matches over several solids (`SketchProjections.locate`) passes `false`, since the sum is no operand's
+    /// count. A pick with ordinals that resolved through one operand's share of its key is a guess too: its
+    /// ordinals index the whole key's edges.
+    static func choose(_ pick: EdgePick, in topology: Topology, comparesRecordedCount: Bool = true)
+        -> (chosen: [EdgeInfo], matchCount: Int, runCount: Int, isAmbiguous: Bool) {
+        let resolution = topology.resolution(of: pick.key, expecting: comparesRecordedCount ? pick.matchCount : nil)
+        let matches = resolution.edges
         let chosen = pick.ordinals.map { ordinals in ordinals.filter(matches.indices.contains).map { matches[$0] } } ?? matches
-        return (chosen, matches.count, Topology.runCount(matches))
+        let isAmbiguous = resolution.isAmbiguous || (pick.ordinals != nil && resolution.isSplit)
+        return (chosen, matches.count, Topology.runCount(matches), isAmbiguous)
     }
 
     /// "Matched 1 edge, expected 2." (several drifts joined by "; ").
```

```diff
--- a/Sources/CreatorNodes/Selection/EdgesByTagNode.swift
+++ b/Sources/CreatorNodes/Selection/EdgesByTagNode.swift
@@ -5,7 +5,8 @@
 /// stored in the `picks` setting as `.edgePicks(solid.topology.picks(for: edgeIDs))`; the M6 app
 /// shell writes it from viewport picks. A key matches by tag subsets on each side, so unions that
 /// merge faces keep the pick, and a key that matches nothing is narrowed to the operand its edge runs
-/// along (`Topology.edges(resolving:)`), so a pick on a merged face survives the other operand changing.
+/// along (`Topology.resolution(of:expecting:)`), so a pick on a merged face survives the other operand
+/// changing, including an edge between a merged face and a third operand's face (a hole through it).
 /// A changed match count is a warning, never silent (rule 6), unless only the number of pieces a picked
 /// edge is split into changed (`EdgePick.hasDrifted(matching:inRuns:)`).
 public enum EdgesByTagNode: NodeDefinition {
```

```diff
--- a/Sources/CreatorNodes/Sketch/SketchProjections.swift
+++ b/Sources/CreatorNodes/Sketch/SketchProjections.swift
@@ -55,17 +55,22 @@
         var found: [EdgeInfo] = []
         var matched = 0
         var runs = 0
+        var isAmbiguous = false
         for solid in references {
-            let choice = EdgeTagMatch.choose(pick, in: solid.topology)
+            let choice = EdgeTagMatch.choose(pick, in: solid.topology, comparesRecordedCount: references.count == 1)
             matched += choice.matchCount
             runs += choice.runCount
+            isAmbiguous = isAmbiguous || choice.isAmbiguous
             found += choice.chosen
         }
         switch found.count {
         case 0: return .problem("matches no edge of the references.")
         case 1:
             let drifted = pick.hasDrifted(matching: matched, inRuns: runs)
-            return .found(found[0], drift: drifted ? EdgeTagMatch.drift([(matched, pick.matchCount)]) : nil)
+            let drift = drifted ? EdgeTagMatch.drift([(matched, pick.matchCount)]) : nil
+            let guess = isAmbiguous ? EdgeTagMatch.ambiguousPick : nil
+            let notes = [drift, guess].compactMap { $0 }
+            return .found(found[0], drift: notes.isEmpty ? nil : notes.joined(separator: " "))
         default: return .problem("matches \(found.count.display) edges of the references.")
         }
     }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "aHoleRimPicked|EdgeOperandKeyTests|EdgeTagMatch|SketchProjection|EdgeKeyNarrowing"`
Expected: PASS.

- [ ] **Step 6: Full suite and lint**

Run the full suite and lint as in Task 1 Step 5. Expected: exit 0, no "recorded an issue"/"failed after", 11 "Test run with" lines, 0 violations; the total is master + 39 = 1682.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat(kernel): an edge pick between a merged face and a third operand's face is found by operand"
```

---

### Task 4: Docs: roadmap, Errata, the naming rule and the human check

**Files:**
- Modify: `docs/superpowers/roadmap.md`, `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `CLAUDE.md`, `docs/verification/human-checks.md`

**Interfaces:**
- Consumes: the names from Tasks 1 to 3.
- Produces: nothing for later tasks.

- [ ] **Step 1: Update the roadmap row**

Replace the whole row that starts `| — | Naming: face picks on merged faces` in `docs/superpowers/roadmap.md`:

```diff
--- a/docs/superpowers/roadmap.md
+++ b/docs/superpowers/roadmap.md
@@ -36,7 +36,7 @@
 | — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ✅ code done (plan `2026-10-09-naming-merged-faces.md`, Errata (naming: merged faces)): a key matching nothing is retried narrowed (`EdgeKey.narrowed`), drift counts runs as well as edges (`EdgePick.runCount`, no format bump) | `BracketAcceptanceTests+PolygonSwap` (flipped: Edges by Tag resolves with no warning; the Chamfer's failure was the invalid-blends row, now done), `BracketAcceptanceTests+MergedFaces` |
 | — | Kernel: blends that return an invalid solid — OCCT's fillet of the polygon-swap hexagon's vertical edges reports done but returns a solid `BRepCheck_Analyzer` rejects, so every later fillet or chamfer along the plate top's tangent chain fails (Errata (naming: merged faces)) | ✅ code done (plan `2026-10-09-kernel-invalid-blends.md`, Errata (Kernel: invalid blends)): every fillet and chamfer result is checked (`OCCTShape.isValid`); one OCCT's checker rejects is refused, naming the largest size that works ("Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."); repair was probed (ShapeFix, UnifySameDomain, tolerances, fillet shapes and parameters, edge order) and can't make it valid | `BracketAcceptanceTests+PolygonSwap` (flipped: the Fillet names 2.5 mm; at 2.5 mm the Chamfer and the Output have their part), `InvalidBlendTests`, `ShapeValidityTests` |
 | — | Kernel: largest size for blends OCCT can't build — a fillet or chamfer OCCT reports not done still says "can't be rounded this much" without a maximum (spec §3, risks table: "the maximum radius where possible"); `OCCTKernel.largestValidBlend` could name one there too, at the cost of up to ~20 failing tries | ⏳ | `FeatureConformanceTests.impossibleFilletFailsCleanlyAndKernelRecovers` (its `maxRadius` would become 9.9) |
-| — | Naming: face picks on merged faces — a `FacePick` (Plane from Face) on a face a union merged names both operands' tags and matches nothing once they stop merging; narrow it like `EdgeKey.narrowed` (it has no other side, so it needs its own rule). Also not narrowed yet: an edge pick between a merged face and a third operand's face (a hole through a merged plate+flange side), since the hole wall's tags share no origin with the merged side | 💬 | Errata (naming: merged faces) |
+| — | Naming: face picks on merged faces — a `FacePick` (Plane from Face) on a face a union merged names both operands' tags and matches nothing once they stop merging; an edge pick between a merged face and a third operand's face (a hole through a merged plate+flange side) shares no node call with the hole wall's tags | ✅ code done (plan `2026-10-09-naming-face-picks.md`, Errata (naming: face picks)); the rule is the plan's proposal, 💬 awaiting the user's sign-off: a face pick that matches nothing is retried per operand (`Topology.resolution(of:)`), ranked by the normal and centroid it now records (optional keys, no format bump), and warns when only one guess is left; an edge key that is still unmatched is split by operand (`EdgeKey.operandKeys`) and warns when two operands both fit | `BracketAcceptanceTests+FacePicks`, `BracketAcceptanceTests+HoleThroughMergedSide` |
 | — | Viewport: a selected rule's edges over the Final part — in Final preview, show the edges of a selected rule whose solid isn't shown (spec §6.3, Errata (M6)) | ⏳ after M6 | `SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid` |
 | — | Adopt MetalUI C10 (merged as MetalUI 2155f1e): `Slider` `onEditingChanged` for the inspector's coalescing (M5-a), materials and blur for the glass panels (M5-c), the window gradient (M5-d), the refused wire's keyframe shake (M5-i), `ProgressView` for the evaluating badge (M5-j); `ColorPicker` (M6-f) is already adopted (Themes Task 11) | ⏳ | docs/metalui-gaps.md summary table |
 | — | Viewport: frame in the model area — first framing, F and Look At centre the part in `ViewportModel.modelArea`, not the whole view (spec §6.3) | ✅ merged 2026-10-09 (human checks VC pending; the arrows, cube and pointer-less key zoom keep it there) | carry-over From M6 |
```

- [ ] **Step 2: Add Errata (naming: face picks) and close the old bullet**

```diff
--- a/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
+++ b/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
@@ -524,8 +524,41 @@
   `BracketAcceptanceTests.swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered` pins it, and
   `BracketAcceptanceTests.aChamferPickedOnMergedSidesSurvivesTheFlangeChangingWidth` pins the case end to end with no
   warning or error (the flange alone made 40 or 70 mm wide, so no plate side stays merged).
-- Face picks (`FacePick`, Plane from Face) are not narrowed: one made on a merged face still names both operands'
-  tags (roadmap row "Naming: face picks on merged faces").
+- Face picks (`FacePick`, Plane from Face) were not narrowed by this plan; see Errata (naming: face picks).
+
+## Errata (naming: face picks)
+
+Plan `2026-10-09-naming-face-picks.md`, roadmap row "Naming: face picks on merged faces". The rule is the plan's
+proposal; the user's sign-off is pending.
+
+- §5.3 rule 5: a face pick (`FacePick`, Plane from Face) also records the picked flat face's outward normal and
+  centroid (`FacePick.normal`, `FacePick.centroid`, optional keys that older readers ignore, so §4.5's format version
+  is unchanged; renaming a pick for a group keeps them).
+- §5.3 rules 3 and 5: a face pick that matches no face is retried with each operand's tags alone (the tags of one node
+  call, `TopoTag.origin`; `Set<TopoTag>.partsByOrigin`). A candidate must face the way the picked face did; the one
+  lying in the plane the picked face was in wins, nearest its centroid first (`Topology.resolution(of:)`). A pick that
+  matches anything is never retried, so every pick that resolved before resolves the same way.
+- §5.3 rule 6: the retry is silent only when the pick recorded its position and exactly one candidate lies in the
+  picked face's plane (within a micrometre); the plane then stays where it was in space, on whichever part is left, so
+  if the plate moves and the flange stays it sits on the flange's face (the pick doesn't record which operand it was
+  picked on; the user's sign-off is pending on this). Otherwise Plane from Face still places the plane, on the best candidate, and warns that it
+  isn't clear which part was picked (`PlaneFromFaceNode.mergedPick`), as it does for a pick made before positions were
+  recorded. A pick no candidate of which faces the picked way is still "isn't on this solid any more".
+- §5.3 rule 3: an edge key that matches nothing, whose narrowed key (Errata (naming: merged faces)) matches nothing
+  either, is retried by operand for each side that has tags from several node calls and none in common with the other
+  side (`EdgeKey.operandKeys`): the rim of a hole through a face a union merged is `{plate.side, flange.side} |
+  {hole.wall}` and the wall shares no node call with either. When several operands' keys name edges, the one with the
+  recorded edge count wins if exactly one has it; otherwise the nearest count wins and Edges by Tag warns
+  (`EdgeTagMatch.ambiguousPick`), as does a Sketch projection (`SketchProjections.locate`). A count summed over several reference solids is never
+  compared with one operand's, and a pick with edge ordinals that resolved through one operand's share of its key is a
+  guess too (the ordinals were recorded against the whole key's edges). An edge where two operands meet keeps its full
+  name, and a key that matches anything or narrows is never split.
+- The case with the flange wider than the plate: the hole's rim at the bracket's left side is then the flange's own
+  face (x = -35), so the pick follows the hole to that face rather than staying on the plate.
+  `BracketAcceptanceTests.aPlanePickedOnAMergedSideSurvivesTheFlangeChangingWidth`, `...BecomingAPolygon` and
+  `BracketAcceptanceTests.aHoleRimPickedOnAMergedSideSurvivesTheFlangeChangingWidth`, `...BecomingAPolygon` pin all of
+  it, and `BracketAcceptanceTests.aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves` pins the plane staying put
+  when the plate alone changes.
 
 ## Errata (Themes)
 
```

- [ ] **Step 3: Update CLAUDE.md's naming rule**

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -140,11 +140,11 @@
 never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
 Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.
 All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids and meshing mutates it; never call the shim outside it (tests included).
-Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a pick without one counts each recorded edge as a run) and warns only when both changed; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 5 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
+Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a pick without one counts each recorded edge as a run) and warns only when both changed; a key that still matches nothing is split by operand (`EdgeKey.operandKeys`, for an edge between a merged face and a third operand's face) and warns when two operands both fit; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 5 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
 4 added the `.sketch` and `.facePick` settings; 5 added `definitions`, group definitions, optional on decode).
 A `Segment2D.arc` with `end < start` runs clockwise (a sketch region's notch); the shim builds it reversed and
 `length` is positive. Edges carry `EdgeInfo.curve` (`EdgeCurve`, lines and circles) for sketch projection; a
-`FacePick` names faces by tag subset like `EdgePick`. The Sketch node solves on every evaluation from the stored
+`FacePick` names faces by tag subset like `EdgePick`; one that matches nothing is retried per operand and ranked by the normal and centroid it recorded (optional keys, no format bump; `Topology.resolution(of:)`), and warns when it can only guess. The Sketch node solves on every evaluation from the stored
 sketch's warm start; the editor writes `Sketch.remember` back into the setting with every commit (S5a). Node readers
 of sockets use `inputs(for: node)` (canvas shape and rows, inspector, handles), never the static `inputs`.
 `Profile2D` is `outer` + `holes` (loop 0 = outer, n = hole n); `segments` is the outer loop only, so code that
```

- [ ] **Step 4: Add the human check**

Append to the end of `docs/verification/human-checks.md` (the only edit to that file):

```markdown

## Group NF — naming: face picks on merged faces

**Status: NOT RUN.** Plan `2026-10-09-naming-face-picks.md`. The tests pin the behaviour; this checks that the two new
warnings read well where they appear.

- [ ] **NF-1 The two warnings.** Trigger both in `swift run MetalCreatorApp` and read each in the node's status badge
  and in the inspector: they wrap, aren't cut off, and say what to do. (1) Plane from Face's merged-pick warning:
  a Plane from Face on a face a union merged (S5c's New sketch on face, once it lands; before that, a document saved
  by a test, since the app can't pick a face yet), then unmerge it so the choice is a guess (a pick made before
  positions were recorded). (2) Edges by Tag's ambiguous-pick warning: a hole rim picked on a merged side, then a
  change after which two parts each have a rim. Record which of the two you could reach. Pinned:
  `aPlanePickWithoutAPositionWarnsOnceTheFaceHasComeApart`, `aGuessBetweenOperandsIsReportedNotSilent`.
  **Observed:**
```

- [ ] **Step 5: Check and commit**

Run the full suite and lint as in Task 1 Step 5 (docs only: the total stays master + 39 = 1682).

```bash
git add docs CLAUDE.md
git commit -m "docs: Errata (naming: face picks), the roadmap row, CLAUDE.md's naming rule and human check NF-1"
```

---

## Self-review

- **Spec coverage.** §5.3 rule 2 (merged faces carry both operands' tags): already true, observation 1. Rule 3/5 for faces: Tasks 1 and 2 (the retry, the position, Plane from Face). Rule 3/5 for edges between a merged face and a third operand's face: Task 3. Rule 6 (no silent drift): the plane warns in `mergedPick` cases, Edges by Tag and projections in `ambiguousPick` cases, and an operand-key match whose count differs from the recorded count still drifts through `hasDrifted`. §8's naming-stability promise for the swap and the width change: the two acceptance files. §4.5 (file format): optional keys, version stays 5, pinned by Task 1's optional-key test. The roadmap row's two parts are Tasks 2 and 3; the Errata, row, CLAUDE.md and the human check are Task 4.
- **Placeholder scan.** Every code block is the file as applied in the scratch copy (diffs and files are generated from it). No "TBD", no "similar to Task N". The commit steps assume the executor commits per task; the author of this plan did not commit.
- **Type consistency.** `partsByOrigin` (Task 1) is used by `resolution(of: FacePick)` and `EdgeKey.operandKeys` (Task 3). `FaceResolution(faces:isNarrowed:isAmbiguous:)` and `EdgeResolution(edges:isAmbiguous:)` have the same shape. `EdgeTagMatch.choose` returns the labelled four-tuple; `resolve` and `SketchProjections.locate` are its only callers. `PlaneFromFaceNode.mergedPick` and `EdgeTagMatch.ambiguousPick` are internal and reached by tests through `@testable`. `isOK(_:_:)` is declared once (Task 2) and used by Task 3.
- **Review Focus.** Each of the ten lines has a named test above, or (the tenth) a human check.

## Risks

- **A silent plane on the part that stayed.** The face retry is silent when exactly one candidate lies in the picked plane, and the plane then stays where it was in space. That is not only the rare coincidence of a different part happening to sit there: it is the ordinary case of the plate changing alone (widened while the flange stays), where the flange's face is the only candidate in the old plane, so the plane stays on the flange's face with no warning. The pick doesn't record which operand it was picked on, so the node can't tell that the plane arguably should have followed the plate. Task 2's `aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves` pins it; user decision 1, option (e), is the alternative.
- **Tolerance.** "In the plane" is within 1 micrometre (0.001 mm) absolute, measured along the picked normal. If the whole model moves in the same edit that unmerges the faces, no candidate lies in the plane, and the node warns instead of staying silent: a false alarm, never a wrong silent answer. A model OCCT rebuilds lands far inside the tolerance (tested at 0.3 and 0.9 micrometres off); 5 micrometres off is a guess.
- **A pick with no position guesses arbitrarily.** The first part in `partsByOrigin` order sorts on node IDs; the node warns, and the choice is stable within a document but unrelated to the geometry (user decision 6).
- **A single operand key can name the wrong edge.** If the intended operand is gone and the other operand coincidentally has an edge with the hole's wall, the pick follows it silently when its count matches; a different count still drifts. User decision 3.
- **One reference solid is assumed for the count tiebreak.** A Sketch projection with several references sums matches across them, so `locate` stops comparing the recorded count with one operand's (it then calls any two-operand fit a guess). With one reference the recorded count is compared as in an Edges by Tag rule.
- **Other tracks.** `choose`'s fourth tuple element and new `comparesRecordedCount` parameter, and `FacePick`'s new initialiser parameters, are source-compatible for existing callers, but a track that destructures `choose`'s result positionally, or compares `FacePick`s built with and without a position, needs a look when it merges.
- **Equality.** A `FacePick` with a position is no longer equal to the same tags without one; nothing in the code base compares picks that way today (Task 1 changed the one test that did).
- **The face warning can't be reached from the app yet.** Plane from Face has no pick control until S5c, so human check NF-1 may be able to read only the edge warning.
