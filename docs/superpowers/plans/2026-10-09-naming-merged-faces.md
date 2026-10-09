# Naming: Picks on Merged Faces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Edges by Tag pick on a face a union merged keeps naming the same edge when one operand changes, without a drift warning when an edge is only split into fewer or more pieces (roadmap row "Naming: picks on merged faces"; spec §8's polygon swap, Errata (M6)).

**Architecture:** Two pure-Swift rules in `CreatorKernel`, used by the one resolver every edge pick goes through (`EdgeTagMatch.choose` in `CreatorNodes`, shared by Edges by Tag and the Sketch node's projections). (1) **Narrowing:** a stored key that matches nothing is retried with each side cut to the tags of the node calls the other side also has (`EdgeKey.narrowed`, `Topology.edges(resolving:)`), so `{plate.endCap} | {plate.side(6), flange.side(3)}` becomes `{plate.endCap} | {plate.side(6)}` once the flange no longer merges with the plate side. (2) **Runs:** a pick of every match also records how many end-to-end chains its edges form (`EdgePick.runCount`, written only when it differs from the edge count), and drifts only when edge count *and* run count both changed (`EdgePick.hasDrifted(matching:inRuns:)`). Faces already carry every operand's tags through OCCT history (`OCCTTagger`, `SimplifyResult`), so nothing changes in `COCCT`/`CreatorOCCT` and nothing changes in the file format.

**Tech Stack:** Swift 6.4 (strict concurrency, Swift 6 language mode), Swift Testing, OpenCascade 7.9 through `COCCT`/`CreatorOCCT` (tests only here), SwiftLint.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§5.3 topological naming, §8 naming stability, Errata (M3) and (M6) on the polygon swap). Task 4 adds Errata (naming: merged faces).

**Verified against master `d9fedec` (1085 tests) and MetalUI master `67a579e`.** Every code block below was extracted from this file into a fresh copy of the worktree (with a sibling `MetalUI` link to the real `../MetalUI` checkout) and applied task by task, in order. After each task the package built with no new warnings (only the expected OCCT "built for newer macOS" linker notes and M4's existing `ContextMenuTests` capture warning), `swift test` exited 0 with no line saying "recorded an issue" or "failed after", and `swiftlint lint --strict` reported zero violations. Cumulative test counts: Task 1 → 1094 (master + 9), Task 2 → 1110 (master + 25), Task 3 → 1117 (master + 32), Task 4 → 1118 (master + 33; its parameterised test has 2 cases).

**Shared with other tracks (merge with care):**
- `CLAUDE.md` (Task 4 edits one sentence in the naming paragraph) — every track edits it.
- `docs/superpowers/roadmap.md` (Task 4 replaces row "Naming: picks on merged faces" and adds two rows under it) — every track edits it.
- `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (Task 4 appends a section at the end) — any track adding errata appends there too; keep both sections.
- `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` (Task 4 replaces one "From M6" bullet).
- `Sources/CreatorNodes/Sketch/SketchProjections.swift` (Task 3 changes `locate`'s drift test, ten lines) — sketcher-s5 (2D sketch editor) may edit this file; the change is local to `locate`.
- No other shared file: no `Package.swift`, no MetalUI, no `GraphFile.swift`, no UI target.

**Prerequisites:**
- The worktree `/Users/maxburger/Developer/MetalCreator-naming` on branch `naming-merged-faces` at `d9fedec` or later, clean (`git status --short` prints nothing). Run every command from it; never `cd` to another worktree.
- OpenCascade from Homebrew (as for M2 on). SwiftLint installed.

## Probe evidence (real OCCT, the §7.2 bracket)

Run on master with a throw-away test (not part of the plan) that dumped the filleted bracket's topology before and after Errata (M6)'s swap. Tag names: `plate`, `flange` are the two Extrude nodes; `fillet` is the Fillet.

1. **Merged faces already carry both operands' tags.** The union (`BRepAlgoAPI_Fuse` + `SimplifyResult`) merges the plate's left side with the full-width flange's coplanar side: face `{flange[0].side(3)+plate[0].side(6)}` (and `side(1)+side(2)` on the right, `startCap+side(4)` at the back). So "carry all generating/modified tags" is done; the defect is in matching.
2. **The recorded picks.** `topCapOutline` on the rectangle bracket picks 7 edges as 5 picks: `{plate.endCap} | {flange.side(3)+plate.side(6)}` matching **2** edges, the same on the right, and three plate-only picks (front edge, two front corner arcs) matching 1 each.
3. **Why 2 edges.** The flange's fillet (R3 on its vertical corner at x = −30, y = 12) cuts the plate's top cap back into the corner, so the top edge along the merged side is two collinear pieces meeting end to end: e23 `(-30,12,6)→(-30,-16,6)`, 28 mm, and e21 `(-30,12,6)→(-30,15,6)`, 3 mm.
4. **After the swap** (hexagon r 15, turned 30°, lifted 15 mm): the plate side stands alone, `{plate[0].side(6)}`, with one whole top edge e37 `(-30,16,6)→(-30,-16,6)`, 32 mm. The stored key matches nothing (the face lacks `flange.side(3)`), hence today's "Matched 0 edges, expected 2". **The flange keeps its node, so `flange[0].side(3)` still exists** — on a hexagon face that meets the plate's top (edge e34, `{plate.endCap} | {flange[0].side(3)}`). A rule "match any shared tag" would pick e34; narrowing to the tags of node calls the other side shares (`plate`) picks e37 alone.
5. **Counts.** Narrowed, each merged-side pick matches 1 edge where 2 were recorded: an edge count can't tell "one edge split in two" from "two edges". The two pieces of item 3 form **one run**; e37 is one run. Recording runs makes the swap drift-free and keeps "a second hole rim appeared" (two runs) a drift.
6. **The prototype of this plan** (Tasks 1–3) on the swap: Edges by Tag is `.ok` with 5 edges `[e37, e42, e38, e41, e39]` (both 32 mm sides, both front arcs, the front edge). Full `swift test` stayed green apart from the pinned swap test, whose naming expectations flip.
7. **The Chamfer still fails after the swap, and naming isn't why.** On the filleted hexagon bracket, every `chamfer` and `fillet` of any top-outline edge fails — `[e39]` alone, the 5 resolved edges, the 9-edge tangent chain, the closed loop with the hexagon's base edges, at 0.5, 0.2 and 0.05 mm. A hole rim on the same solid chamfers fine. `BRepFilletAPI_MakeChamfer` propagates `[e39]` to 9 edges (the tangent chain round the back corners). `BRepCheck_Analyzer(...).IsValid()` is **0 for the filleted hexagon bracket** and 1 for its union and for the rectangle bracket's fillet. The 5 resolved edges chamfer at 0.5 mm on the union (before the fillet). So OCCT's fillet of the hexagon's vertical edges returns an invalid solid without failing. It depends on the radius (checked again in review): re-filleting the hexagon union's 4 fillet edges at R 0.5, 1 and 2 gives valid solids, on each of which the 5 resolved edges chamfer at 0.5 mm; only the bracket's R3 is invalid. Through the whole graph (the swap, then the Fillet's radius set), the Chamfer succeeds and the Output has its part at R 0.5, 1, 2 and 2.5, and fails at R3. That is a kernel defect outside this row; Task 4 records it as roadmap row "Kernel: blends that return an invalid solid" and the swap test pins it.
8. **One operand changing, end to end.** With the flange alone made 40 or 70 mm wide (no plate side stays merged), the prototype resolves the 5 picks to the plate's edges with no warning anywhere, and the Output has its part (59 mm also resolves cleanly, but OCCT can't chamfer the 0.5 mm sliver it leaves, so the test uses 40 and 70).

## Decisions made in this plan

1. **Fix matching, not tagging.** Faces already hold all generating/modified tags (probe 1). No shim, history or `OCCTTagger` change, and no per-face "tag set" type: `FaceInfo.tags` already is one.
2. **Narrow only as a fallback.** `Topology.edges(resolving:)` returns the strict tag-subset matches when there are any, and narrows only when there are none, so every pick that resolves on master resolves identically (the whole suite is the regression check). `Topology.edge(_:matches:)` and `edges(matching:)` keep their meaning.
3. **Narrowing rule = shared node calls.** A side keeps the tags whose `TopoTag.origin` (node + broadcast item, a `NodeTag`) the other side also has; a side with none keeps everything. An edge between one operand's face and a merged face runs along that operand's part of it (probe 4). Intersection edges between operands (plate top vs flange front) and keys whose both sides are merged from the same operands are never narrowed. Broadcast items are separate operands.
4. **Runs, not "minimal subset".** A run is a chain of matched edges meeting end to end within 1e-6 mm (`EdgeCurve.ends`: lines and arcs; a full circle or an edge without a curve is its own run). `EdgePick.runCount` is recorded by `Topology.picks(for:)` only for a pick of every match whose runs are fewer than its edges; `nil` means one run per edge.
5. **Drift rule.** `hasDrifted(matching:inRuns:)`: no drift if the edge count is unchanged; otherwise drift unless it's a pick of every match whose run count is unchanged (`runCount ?? matchCount`). Ordinal picks count edges only (ordinals index edges). The warning text is unchanged ("Matched 1 edge, expected 2."). Picks saved before this change have no `runCount`, so each recorded edge counts as its own run: such a pick still warns when its edges become fewer runs (a split edge it recorded as 2 edges, now whole: "Matched 1 edge, expected 2.", as on master), and it no longer warns when a recorded edge is split into more pieces (recorded as 1 edge, now 2 pieces in 1 run: master warned "Matched 2 edges, expected 1.", this plan doesn't). That is a deliberate change for older files, the same one new picks get; exact compatibility with master would need `nil` to mean "count edges only" and `runCount` written on every pick of all matches, which changes how every new pick is encoded for no gain.
6. **No format bump.** `runCount` is an optional key with synthesized `Codable`: `nil` isn't written (unsplit picks encode byte for byte as before) and older readers ignore it (Task 2 decodes a new pick with an M6-era decoder). An older build reading a new file just counts edges, as it always has; it never selects different edges. `GraphFile.currentFormatVersion` stays 4 and `GraphFile.swift` is untouched.
7. **The Sketch node's projections get both rules for free** through `EdgeTagMatch.choose`; `SketchProjections.locate` switches to `hasDrifted` so a projection and Edges by Tag never disagree about drift.
8. **The polygon-swap test flips its naming half only** (probe 7). Edges by Tag: `.ok`, 5 edges, keys = the recorded keys narrowed, both sides whole (32 mm), nothing at the plate's back. Chamfer: still `.error("Chamfer failed…")`, Output without a result, and the test proves the picks aren't the cause by chamfering the same resolved edges on the union. Renamed `swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered`. Rejecting invalid blend results (which would move the error to the Fillet) is a behaviour change for its own row, not slipped in here.
9. **A second acceptance test that comes out whole:** `aChamferPickedOnMergedSidesSurvivesTheFlangeChangingWidth` (40 and 70 mm), including save/reopen and a re-pick that holds when the flange is flush again.
10. **Face picks stay as they are** (`FacePick` has no "other side" to narrow toward); Task 4 adds a 💬 roadmap row.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency; no `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- One type per Swift file, named after the type; extensions in `Type+Purpose.swift`.
- No force unwraps or force `try`. No GCD. No third-party packages. Numbers shown to people go through `FormatStyle` / `Locale.messages` (no new user-facing number text here).
- Module boundaries (CLAUDE.md): only `CreatorOCCT` touches OCCT, and all OCCT work runs under `OCCTKernel.serialized`; `CreatorKernel` imports only `CreatorGeometry` and Foundation. Never iterate a dictionary where order reaches output.
- Create nodes only with `NodeRegistry.makeNode`; every graph edit goes through `DocumentModel.perform(_:)`.
- Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion` (now 4). This plan bumps nothing.
- Must not regress the naming-stability or conformance tests (`swift test --filter CreatorOCCTTests`, `BracketAcceptanceTests`).
- A `swift test` run passes only if it exits 0 and no line says "recorded an issue" or "failed after".
- **SwiftLint gates every commit:** `swiftlint lint --strict` reports zero violations.
- No UI work. MetalUI gaps would go in `docs/metalui-gaps.md` (none arise).

## Review Focus

1. **A file saved before this change** (picks without `runCount`): each recorded edge counts as its own run. No new warning while nothing changes; it still warns when its edges become fewer runs (a split edge recorded as 2, now whole), and it no longer warns when a recorded edge is split into more pieces (master warned there). Pinned: Task 2 `aPickWithoutARunCountCountsEachEdgeAsARun`, `aSplitOrRejoinedEdgeIsNotDrift`; Task 3 `aPickSavedBeforeRunsStillWarnsWhenItsEdgesBecomeFewerRuns`, `aPickSavedBeforeRunsNoLongerWarnsWhenItsEdgeIsSplit`.
2. **The changed operand still carries the picked tag elsewhere** (the hexagon's `flange.side(3)` meets the plate's top): that edge must not be selected. Pinned: Task 1 `theOtherOperandsTagAloneDoesNotMatch`.
3. **An edge where two operands meet** (the plate's top against the flange's front) must keep its full name and never be narrowed onto plate-only edges. Pinned: Task 1 `anEdgeWhereTwoOperandsMeetIsNotNarrowed`, `aKeyWhoseSidesAreBothMergedFromTheSameOperandsIsNotNarrowed`.
4. **Re-picked after the change, then the operand comes back flush** (the edge is split again): no warning. Pinned: Task 3 `aPickMadeApartResolvesWhenThePartnerIsFlushAgain`, Task 4's last block.
5. **Broadcast items of one node** (two items' faces merged): the other item is another operand. Pinned: Task 1 `anotherBroadcastItemOfTheSameNodeIsAnotherOperand`.

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/CreatorKernel/TopoTag+Origin.swift` (new) | 1 | `TopoTag.origin: NodeTag` — the node call that made a face |
| `Sources/CreatorKernel/EdgeKey+Narrowing.swift` (new) | 1 | `EdgeKey.narrowed: EdgeKey?` |
| `Sources/CreatorKernel/Topology+EdgePicks.swift` | 1, 2 | `edges(resolving:)` (1); `picks(for:)` records `runCount` (2) |
| `Sources/CreatorKernel/EdgeCurve+Ends.swift` (new) | 2 | `EdgeCurve.ends: [Vector3]` |
| `Sources/CreatorKernel/Topology+EdgeRuns.swift` (new) | 2 | `Topology.runCount(_:) -> Int` |
| `Sources/CreatorKernel/EdgePick.swift` | 2 | `runCount: Int?`, `hasDrifted(matching:inRuns:)` |
| `Sources/CreatorNodes/Selection/EdgeTagMatch.swift` | 3 | resolve through `edges(resolving:)`, drift through `hasDrifted` |
| `Sources/CreatorNodes/Selection/EdgesByTagNode.swift` | 3 | doc comment only |
| `Sources/CreatorNodes/Sketch/SketchProjections.swift` | 3 | `locate` drifts like Edges by Tag (shared with sketcher-s5) |
| `Tests/CreatorKernelTests/EdgeKeyNarrowingTests.swift` (new) | 1 | narrowing and `edges(resolving:)` |
| `Tests/CreatorKernelTests/EdgeRunTests.swift` (new) | 2 | ends, runs, `runCount`, drift rule, JSON |
| `Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift` (new) | 2 | format 4 kept, older readers decode |
| `Tests/CreatorNodesTests/EdgeTagMatchMergedFaceTests.swift` (new) | 3 | Edges by Tag on merged / split topologies |
| `Tests/CreatorNodesTests/SketchProjectionRunTests.swift` (new) | 3 | `SketchProjections.locate` drifts by runs |
| `Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift` | 3 | the flipped §8 swap |
| `Tests/CreatorNodesTests/BracketAcceptanceTests+MergedFaces.swift` (new) | 4 | the flange changing width, end to end on OCCT |
| spec, roadmap, CLAUDE.md, carry-over note | 4 | Errata (naming: merged faces), rows, the naming rule |

---

### Task 1: Narrowed keys (`EdgeKey.narrowed`, `Topology.edges(resolving:)`)

**Files:**
- Create: `Sources/CreatorKernel/TopoTag+Origin.swift`
- Create: `Sources/CreatorKernel/EdgeKey+Narrowing.swift`
- Modify: `Sources/CreatorKernel/Topology+EdgePicks.swift` (add `edges(resolving:)` after `edges(matching:)`)
- Test: `Tests/CreatorKernelTests/EdgeKeyNarrowingTests.swift`

**Interfaces:**
- Consumes: `TopoTag` (`node`, `item`), `NodeTag(node:item:)` (Hashable), `EdgeKey(_:_:)` (canonical, Hashable), `Topology.edges(matching:)`.
- Produces: `extension TopoTag { public var origin: NodeTag }`; `extension EdgeKey { public var narrowed: EdgeKey? }`; `extension Topology { public func edges(resolving key: EdgeKey) -> [EdgeInfo] }` (strict matches, else the narrowed key's matches, midpoint-ordered). Task 3 calls `edges(resolving:)`; Task 3's swap test calls `narrowed` and `edges(resolving:)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CreatorKernelTests/EdgeKeyNarrowingTests.swift`:

```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Picks on faces a union merged (roadmap "Naming: picks on merged faces"): `EdgeKey.narrowed` and
/// `Topology.edges(resolving:)`.
struct EdgeKeyNarrowingTests {
    let plate = NodeID()
    let flange = NodeID()

    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }
    var flangeFront: TopoTag { TopoTag(node: flange, item: 0, role: .endCap) }

    @Test func aMergedSideNarrowsToTheOperandTheOtherSideCameFrom() {
        #expect(EdgeKey([top], [side, flangeSide]).narrowed == EdgeKey([top], [side]))
        #expect(EdgeKey([side, flangeSide], [top]).narrowed == EdgeKey([top], [side]))
    }

    @Test func aKeyOfOneOperandIsNotNarrowed() {
        #expect(EdgeKey([top], [side]).narrowed == nil)
    }

    /// The plate's top against the flange's front face: the edge where two operands meet keeps its name.
    @Test func anEdgeWhereTwoOperandsMeetIsNotNarrowed() {
        #expect(EdgeKey([top], [flangeFront]).narrowed == nil)
    }

    @Test func aKeyWhoseSidesAreBothMergedFromTheSameOperandsIsNotNarrowed() {
        let flangeTop = TopoTag(node: flange, item: 0, role: .side(segment: 2))
        #expect(EdgeKey([top, flangeTop], [side, flangeSide]).narrowed == nil)
    }

    /// Broadcast items are separate node calls: the faces of item 1 are not item 0's.
    @Test func anotherBroadcastItemOfTheSameNodeIsAnotherOperand() {
        let secondSide = TopoTag(node: plate, item: 1, role: .side(segment: 6))
        #expect(EdgeKey([top], [side, secondSide]).narrowed == EdgeKey([top], [side]))
    }

    /// Face 0: top. Face 1: the plate's side, merged with the flange's (`merged`) or on its own. Face 2: a
    /// face carrying the flange tag the pick also names (the hexagon's side 3 standing on the plate after the
    /// swap). Edge 0 is top | face 1; edge 1 is top | face 2.
    func topology(merged: Bool) -> Topology {
        Topology(
            faces: [
                FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
                FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero,
                         tags: merged ? [side, flangeSide] : [side]),
                FaceInfo(id: FaceID(2), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [flangeSide]),
            ],
            edges: [
                EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitY, length: 32, midpoint: Vector3(-30, 0, 6),
                         convexity: .convex, faces: [FaceID(0), FaceID(1)]),
                EdgeInfo(id: EdgeID(1), kind: .line, direction: .unitY, length: 8, midpoint: Vector3(-10, 16, 6),
                         convexity: .concave, faces: [FaceID(0), FaceID(2)]),
            ]
        )
    }

    @Test func aKeyThatMatchesResolvesToItsMatches() {
        let key = EdgeKey([top], [side, flangeSide])
        #expect(topology(merged: true).edges(resolving: key).map(\.id) == [EdgeID(0)])
        // The narrowed key would match edge 0 too; a key that matches is never narrowed, so nothing changes.
        #expect(topology(merged: true).edges(resolving: EdgeKey([top], [side])).map(\.id) == [EdgeID(0)])
    }

    @Test func aPickOnAMergedFaceFindsItsEdgeWhenThePartnerLeaves() {
        let key = EdgeKey([top], [side, flangeSide])
        #expect(topology(merged: false).edges(matching: key).isEmpty)
        #expect(topology(merged: false).edges(resolving: key).map(\.id) == [EdgeID(0)])
    }

    /// The flange's tag alone is not enough: the edge between the top and a flange-only face is not the one
    /// that was picked.
    @Test func theOtherOperandsTagAloneDoesNotMatch() {
        let resolved = topology(merged: false).edges(resolving: EdgeKey([top], [side, flangeSide]))
        #expect(!resolved.contains { $0.id == EdgeID(1) })
    }

    @Test func aKeyThatCantBeNarrowedStillMatchesNothing() {
        let gone = TopoTag(node: NodeID(), item: 0, role: .startCap)
        #expect(topology(merged: false).edges(resolving: EdgeKey([top], [gone])).isEmpty)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter EdgeKeyNarrowingTests`
Expected: the build fails: `EdgeKey.narrowed` and `Topology.edges(resolving:)` don't exist yet (errors at their first uses in `EdgeKeyNarrowingTests.swift`).

- [ ] **Step 3: Implement**

Create `Sources/CreatorKernel/TopoTag+Origin.swift`:

```swift
extension TopoTag {
    /// The node call that made the tagged face: the node and its broadcast item.
    public var origin: NodeTag { NodeTag(node: node, item: item) }
}
```

Create `Sources/CreatorKernel/EdgeKey+Narrowing.swift`:

```swift
extension EdgeKey {
    /// This key with each side cut down to the tags whose node call (`TopoTag.origin`) the other side also
    /// has tags from, or `nil` when that changes nothing.
    ///
    /// A face a union merged carries every operand's tags (spec §5.3, rule 2), but an edge between it and a
    /// face of one operand runs along that operand's part of it: the plate's top edge on a side that a
    /// flange's coplanar side was merged into is `{plate.endCap} | {plate.side}` whatever the flange does.
    /// A side with no tag from the other side's node calls is kept whole, so an edge where two operands meet
    /// (the plate's top against the flange's face) keeps its full name and is never narrowed.
    public var narrowed: EdgeKey? {
        let key = EdgeKey(Self.narrow(first, toward: second), Self.narrow(second, toward: first))
        return key == self ? nil : key
    }

    private static func narrow(_ side: Set<TopoTag>, toward other: Set<TopoTag>) -> Set<TopoTag> {
        let origins = Set(other.map(\.origin))
        let kept = side.filter { origins.contains($0.origin) }
        return kept.isEmpty ? side : kept
    }
}
```

Replace the whole of `Sources/CreatorKernel/Topology+EdgePicks.swift` with:

```swift
extension Topology {
    /// Whether `key` names `edge`. Each side of the key must be a subset of the tags of one of the
    /// edge's two faces (a union merges coplanar faces and their tag sets, so a merged face still
    /// matches). Seams never match.
    public func edge(_ edge: EdgeInfo, matches key: EdgeKey) -> Bool {
        guard !edge.isSeam, edge.faces.count == 2,
              let a = face(edge.faces[0])?.tags, let b = face(edge.faces[1])?.tags else { return false }
        return (key.first.isSubset(of: a) && key.second.isSubset(of: b))
            || (key.first.isSubset(of: b) && key.second.isSubset(of: a))
    }

    /// Every edge `key` names, ordered by midpoint (x, then y, then z, to 1e-6 mm), then by ID.
    public func edges(matching key: EdgeKey) -> [EdgeInfo] {
        edges.filter { edge($0, matches: key) }.sorted(by: Self.midpointOrder)
    }

    /// The edges a remembered key names now: its matches, or, only when it has none, the matches of its
    /// narrowed key (`EdgeKey.narrowed`). A pick on a face a union merged names both operands' tags; when
    /// the other operand changes and the faces no longer merge, the narrowed key still finds the edge. A
    /// key that matches anything is never narrowed, so a pick that resolves today resolves the same way.
    public func edges(resolving key: EdgeKey) -> [EdgeInfo] {
        let matches = edges(matching: key)
        guard matches.isEmpty, let narrowed = key.narrowed else { return matches }
        return edges(matching: narrowed)
    }

    /// The picks that select exactly `ids`: one per distinct key, in first-picked order. A key that
    /// names more edges than were picked records the picked edges' ordinals. Unknown IDs and seams
    /// are skipped.
    public func picks(for ids: [EdgeID]) -> [EdgePick] {
        let picked = Set(ids)
        var seenKeys: Set<EdgeKey> = []
        var result: [EdgePick] = []
        for id in ids {
            guard let edge = edge(id), !edge.isSeam, let key = key(of: edge), seenKeys.insert(key).inserted else { continue }
            let matches = edges(matching: key)
            let ordinals = matches.indices.filter { picked.contains(matches[$0].id) }
            result.append(EdgePick(key: key, matchCount: matches.count,
                                   ordinals: ordinals.count == matches.count ? nil : ordinals))
        }
        return result
    }

    /// Deterministic order for edges sharing a key (spec §5.3, rule 5).
    static func midpointOrder(_ a: EdgeInfo, _ b: EdgeInfo) -> Bool {
        let pairs = [(a.midpoint.x, b.midpoint.x), (a.midpoint.y, b.midpoint.y), (a.midpoint.z, b.midpoint.z)]
        for (p, q) in pairs where abs(p - q) > 1e-6 {
            return p < q
        }
        return a.id.rawValue < b.id.rawValue
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter EdgeKeyNarrowingTests` — Expected: 9 tests pass.
Run: `swift build --build-tests 2>&1 | grep -E "warning: |error: " | grep -v "ld: warning"` — Expected: only M4's `ContextMenuTests.swift:96` capture warning.
Run: `swift test` — Expected: exit 0, no "recorded an issue" / "failed after" line, 1094 tests (master + 9).
Run: `swiftlint lint --strict` — Expected: 0 violations.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorKernel/TopoTag+Origin.swift Sources/CreatorKernel/EdgeKey+Narrowing.swift Sources/CreatorKernel/Topology+EdgePicks.swift Tests/CreatorKernelTests/EdgeKeyNarrowingTests.swift
git commit -m "feat(kernel): narrow an edge key that matches nothing to the operand its edge runs along"
```

---

### Task 2: Runs (`EdgeCurve.ends`, `Topology.runCount`, `EdgePick.runCount`, `hasDrifted`)

**Files:**
- Create: `Sources/CreatorKernel/EdgeCurve+Ends.swift`
- Create: `Sources/CreatorKernel/Topology+EdgeRuns.swift`
- Modify: `Sources/CreatorKernel/EdgePick.swift` (whole file)
- Modify: `Sources/CreatorKernel/Topology+EdgePicks.swift` (`picks(for:)`)
- Test: `Tests/CreatorKernelTests/EdgeRunTests.swift`, `Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift`

**Interfaces:**
- Consumes: `EdgeCurve` (`.line(start:end:)`, `.circle(center:axis:radius:start:sweep:)`), `EdgeInfo.curve`, `Vector3` (`-`, `+`, `*`, `cross`, `dot`, `length`, `normalized`), Task 1's `Topology+EdgePicks.swift`.
- Produces: `extension EdgeCurve { public var ends: [Vector3] }`; `extension Topology { public static func runCount(_ edges: [EdgeInfo]) -> Int }`; `EdgePick.runCount: Int?`, `EdgePick.init(key:matchCount:ordinals:runCount:)` (both new parameters default `nil`); `EdgePick.hasDrifted(matching edges: Int, inRuns runs: Int) -> Bool`. Task 3 uses `runCount(_:)` and `hasDrifted`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorKernelTests/EdgeRunTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Split edges (roadmap "Naming: picks on merged faces"): `EdgeCurve.ends`, `Topology.runCount`,
/// `EdgePick.runCount` and the drift rule `EdgePick.hasDrifted(matching:inRuns:)`.
struct EdgeRunTests {
    let node = NodeID()
    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 6)) }

    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

    func line(_ id: Int, _ start: Vector3, _ end: Vector3, faces: [FaceID] = [FaceID(0), FaceID(1)]) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: (end - start).normalized, length: (end - start).length,
                 midpoint: (start + end) * 0.5, convexity: .convex, faces: faces, curve: .line(start: start, end: end))
    }

    @Test func aLineEndsAtItsTwoPoints() {
        #expect(EdgeCurve.line(start: .zero, end: Vector3(1, 2, 3)).ends == [.zero, Vector3(1, 2, 3)])
    }

    @Test func anArcEndsWhereItsSweepTakesItsStart() throws {
        let quarter = EdgeCurve.circle(center: Vector3(1, 1, 0), axis: .unitZ, radius: 2, start: Vector3(3, 1, 0), sweep: .pi / 2)
        let ends = quarter.ends
        try #require(ends.count == 2)
        #expect(near(ends[0], Vector3(3, 1, 0)))
        #expect(near(ends[1], Vector3(1, 3, 0)))
        // About −Z the same start sweeps the other way round.
        let reversed = EdgeCurve.circle(center: Vector3(1, 1, 0), axis: -.unitZ, radius: 2, start: Vector3(3, 1, 0), sweep: .pi / 2)
        #expect(near(reversed.ends[1], Vector3(1, -1, 0)))
    }

    @Test func aFullCircleHasNoEnds() {
        #expect(EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: 2 * .pi).ends.isEmpty)
    }

    @Test func edgesMeetingEndToEndAreOneRun() {
        // The bracket's plate-top edge on the merged side, split where the flange began: y −16…12 and 12…15.
        let long = line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6))
        let short = line(1, Vector3(-30, 12, 6), Vector3(-30, 15, 6))
        #expect(Topology.runCount([long, short]) == 1)
        #expect(Topology.runCount([long]) == 1)
    }

    @Test func runsAreTransitiveAndApartEdgesAreSeparateRuns() {
        let a = line(0, .zero, Vector3(1, 0, 0)), b = line(1, Vector3(1, 0, 0), Vector3(2, 0, 0))
        let c = line(2, Vector3(2, 0, 0), Vector3(3, 0, 0)), apart = line(3, Vector3(5, 0, 0), Vector3(6, 0, 0))
        #expect(Topology.runCount([a, c, b]) == 1)
        #expect(Topology.runCount([a, b, c, apart]) == 2)
        #expect(Topology.runCount([]) == 0)
    }

    @Test func anEdgeWithoutKnownEndsIsARunOfItsOwn() {
        var a = line(0, .zero, Vector3(1, 0, 0)), b = line(1, Vector3(1, 0, 0), Vector3(2, 0, 0))
        b.curve = nil
        #expect(Topology.runCount([a, b]) == 2)
        a.curve = .circle(center: .zero, axis: .unitZ, radius: 1, start: Vector3(1, 0, 0), sweep: 2 * .pi)
        #expect(Topology.runCount([a, line(1, Vector3(1, 0, 0), Vector3(2, 0, 0))]) == 2)
    }

    /// Face 0: top. Face 1: the side. `split` cuts the top-side edge in two at y = 12.
    func topology(split: Bool) -> Topology {
        let edges = split
            ? [line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6)), line(1, Vector3(-30, 12, 6), Vector3(-30, 15, 6))]
            : [line(0, Vector3(-30, 15, 6), Vector3(-30, -16, 6))]
        return Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [side]),
        ], edges: edges)
    }

    @Test func pickingASplitEdgeRecordsItsRunCount() {
        #expect(topology(split: true).picks(for: [EdgeID(0), EdgeID(1)])
            == [EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)])
    }

    @Test func aWholeEdgeRecordsNoRunCount() {
        #expect(topology(split: false).picks(for: [EdgeID(0)]) == [EdgePick(key: EdgeKey([top], [side]), matchCount: 1)])
    }

    /// Ordinals count edges, so a pick of one piece records no runs.
    @Test func pickingOnePieceRecordsItsOrdinalNotItsRuns() {
        #expect(topology(split: true).picks(for: [EdgeID(1)])
            == [EdgePick(key: EdgeKey([top], [side]), matchCount: 2, ordinals: [1])])
    }

    @Test func aSplitOrRejoinedEdgeIsNotDrift() {
        let split = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
        #expect(!split.hasDrifted(matching: 2, inRuns: 1))
        #expect(!split.hasDrifted(matching: 1, inRuns: 1), "the edge is whole again")
        let whole = EdgePick(key: EdgeKey([top], [side]), matchCount: 1)
        #expect(!whole.hasDrifted(matching: 2, inRuns: 1), "the edge is split now")
    }

    @Test func moreOrFewerRunsAreDrift() {
        let split = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
        #expect(split.hasDrifted(matching: 3, inRuns: 2))
        #expect(split.hasDrifted(matching: 0, inRuns: 0))
        let whole = EdgePick(key: EdgeKey([top], [side]), matchCount: 1)
        #expect(whole.hasDrifted(matching: 2, inRuns: 2), "a second edge, apart from the first")
    }

    /// A pick saved before runs were recorded has no `runCount`: each recorded edge counts as its own run. It
    /// drifts when its edges become fewer runs, and not when a recorded edge is split into more pieces.
    @Test func aPickWithoutARunCountCountsEachEdgeAsARun() {
        let saved = EdgePick(key: EdgeKey([top], [side]), matchCount: 2)
        #expect(!saved.hasDrifted(matching: 2, inRuns: 1))
        #expect(saved.hasDrifted(matching: 1, inRuns: 1), "2 recorded runs, now 1")
        #expect(!saved.hasDrifted(matching: 3, inRuns: 2), "one of the 2 recorded edges split in two")
    }

    @Test func aPickOfSomeMatchesComparesEdgesOnly() {
        let some = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, ordinals: [1])
        #expect(some.hasDrifted(matching: 1, inRuns: 1))
        #expect(!some.hasDrifted(matching: 2, inRuns: 1))
    }

    @Test func aRunCountRoundTripsAndIsWrittenOnlyWhenRecorded() throws {
        let split = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
        let whole = EdgePick(key: EdgeKey([top], [side]), matchCount: 1)
        #expect(try JSONDecoder().decode([EdgePick].self, from: try JSONEncoder().encode([split, whole])) == [split, whole])
        let text = try #require(String(bytes: try JSONEncoder().encode(whole), encoding: .utf8))
        #expect(!text.contains("runCount"))
    }
}
```

Create `Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// `EdgePick.runCount` (roadmap "Naming: picks on merged faces") is an optional key: files keep format
/// version 4, picks without it are written exactly as before, and a reader that doesn't know it still decodes.
struct EdgePickRunCountFileTests {
    let plate = NodeID()

    /// An `EdgePick` as builds before runCount decode it (synthesized `Codable`, unknown keys ignored).
    struct EarlierEdgePick: Decodable, Equatable {
        var key: EdgeKey
        var matchCount: Int
        var ordinals: [Int]?
    }

    var split: EdgePick {
        let top = TopoTag(node: plate, item: 0, role: .endCap)
        let side = TopoTag(node: plate, item: 0, role: .side(segment: 6))
        return EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
    }

    @Test func aRunCountRoundTripsThroughAVersionFourFile() throws {
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks([split])])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([rule])))
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains(#""runCount" : 1"#))
        #expect(text.contains(#""formatVersion" : 4"#))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded.graph.nodes[rule.id]?.inputValues["picks"] == .edgePicks([split]))
    }

    @Test func anEarlierReaderDecodesAPickWithARunCount() throws {
        let earlier = try JSONDecoder().decode(EarlierEdgePick.self, from: try JSONEncoder().encode(split))
        #expect(earlier == EarlierEdgePick(key: split.key, matchCount: 2, ordinals: nil))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "EdgeRunTests|EdgePickRunCountFileTests"`
Expected: the build fails: `EdgeCurve.ends`, `Topology.runCount(_:)`, `EdgePick.runCount` and `hasDrifted(matching:inRuns:)` don't exist yet.

- [ ] **Step 3: Implement**

Create `Sources/CreatorKernel/EdgeCurve+Ends.swift`:

```swift
import CreatorGeometry
import Foundation

extension EdgeCurve {
    /// The edge's two end points; none for a full circle, which is closed.
    public var ends: [Vector3] {
        switch self {
        case .line(let start, let end):
            return [start, end]
        case .circle(let center, let axis, _, let start, let sweep):
            guard abs(sweep) < 2 * .pi - 1e-9, let k = axis.normalized else { return [] }
            // Rodrigues' rotation of the radius vector about the axis by the sweep.
            let v = start - center
            let rotated = v * cos(sweep) + k.cross(v) * sin(sweep) + k * (k.dot(v) * (1 - cos(sweep)))
            return [start, center + rotated]
        }
    }
}
```

Create `Sources/CreatorKernel/Topology+EdgeRuns.swift`:

```swift
import CreatorGeometry

extension Topology {
    /// How many runs `edges` form: chains of edges that meet end to end (to 1e-6 mm). An edge an operation
    /// split in two is still one run, so a run is what a person picking sees as one edge. An edge whose ends
    /// aren't known (no `curve`, or a full circle) is a run of its own.
    public static func runCount(_ edges: [EdgeInfo]) -> Int {
        var parent = Array(edges.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        let ends = edges.map { $0.curve?.ends ?? [] }
        for i in edges.indices {
            for j in edges.indices where j > i {
                let meet = ends[i].contains { p in ends[j].contains { q in (p - q).length <= 1e-6 } }
                if meet { parent[root(j)] = root(i) }
            }
        }
        return Set(edges.indices.map(root)).count
    }
}
```

Replace the whole of `Sources/CreatorKernel/EdgePick.swift` with:

```swift
/// One remembered edge pick (spec §5.3, rule 5): the picked edge's key, how many edges that key
/// named when the pick was made, and, when only some of them were picked, which ones.
public struct EdgePick: Hashable, Sendable, Codable {
    public var key: EdgeKey
    /// How many edges `key` named when the pick was made. A different count later is drift (§5.3, rule 6).
    public var matchCount: Int
    /// Positions of the picked edges among the key's matches, ordered by midpoint (x, then y, then z).
    /// `nil` when every match was picked.
    public var ordinals: [Int]?
    /// How many runs (`Topology.runCount`) the key's matches formed, recorded only when every match was
    /// picked and the runs were fewer than the edges: an operation had split a picked edge. `nil` means
    /// one run per edge, and is what every pick made before runs were recorded has: such a pick still drifts
    /// when its edges become fewer runs, and no longer when a recorded edge is split into more pieces. An
    /// optional key, which older readers ignore (they then count edges, as they always did), so the file
    /// format stays 4.
    public var runCount: Int?

    public init(key: EdgeKey, matchCount: Int, ordinals: [Int]? = nil, runCount: Int? = nil) {
        self.key = key
        self.matchCount = matchCount
        self.ordinals = ordinals
        self.runCount = runCount
    }

    /// Whether `edges` matches forming `runs` runs are drift (spec §5.3, rule 6). A pick of every match
    /// drifts only when the edge count and the run count both differ from the recorded ones, so an edge
    /// that an operation splits in two, or stops splitting, is still the edge that was picked. A pick of
    /// some matches compares edges only, because its ordinals count edges.
    public func hasDrifted(matching edges: Int, inRuns runs: Int) -> Bool {
        guard edges != matchCount else { return false }
        return ordinals != nil || runs != (runCount ?? matchCount)
    }

    /// True when the key names a face by the `.unnamed` fallback, which is unstable across
    /// rebuilds. Blend faces are checked recursively: a fillet face whose source edge bordered an
    /// unnamed face is just as unstable.
    public var touchesUnnamedFace: Bool { key.first.union(key.second).contains { $0.role.isUnstable } }
}
```

In `Sources/CreatorKernel/Topology+EdgePicks.swift`, replace:

```swift
    /// The picks that select exactly `ids`: one per distinct key, in first-picked order. A key that
    /// names more edges than were picked records the picked edges' ordinals. Unknown IDs and seams
    /// are skipped.
    public func picks(for ids: [EdgeID]) -> [EdgePick] {
        let picked = Set(ids)
        var seenKeys: Set<EdgeKey> = []
        var result: [EdgePick] = []
        for id in ids {
            guard let edge = edge(id), !edge.isSeam, let key = key(of: edge), seenKeys.insert(key).inserted else { continue }
            let matches = edges(matching: key)
            let ordinals = matches.indices.filter { picked.contains(matches[$0].id) }
            result.append(EdgePick(key: key, matchCount: matches.count,
                                   ordinals: ordinals.count == matches.count ? nil : ordinals))
        }
        return result
    }
```

with:

```swift
    /// The picks that select exactly `ids`: one per distinct key, in first-picked order. A key that
    /// names more edges than were picked records the picked edges' ordinals; a key whose every match was
    /// picked records its run count when its matches form fewer runs than edges (`EdgePick.runCount`).
    /// Unknown IDs and seams are skipped.
    public func picks(for ids: [EdgeID]) -> [EdgePick] {
        let picked = Set(ids)
        var seenKeys: Set<EdgeKey> = []
        var result: [EdgePick] = []
        for id in ids {
            guard let edge = edge(id), !edge.isSeam, let key = key(of: edge), seenKeys.insert(key).inserted else { continue }
            let matches = edges(matching: key)
            let ordinals = matches.indices.filter { picked.contains(matches[$0].id) }
            guard ordinals.count == matches.count else {
                result.append(EdgePick(key: key, matchCount: matches.count, ordinals: ordinals))
                continue
            }
            let runs = Self.runCount(matches)
            result.append(EdgePick(key: key, matchCount: matches.count, runCount: runs == matches.count ? nil : runs))
        }
        return result
    }
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter "EdgeRunTests|EdgePickRunCountFileTests|EdgePickTests|EdgePickFileTests"` — Expected: all pass (14 + 2 new; the existing `EdgePickTests.pickingEveryMatchStoresNoOrdinals` still holds, because its edges carry no curves and so form one run each).
Run: `swift build --build-tests 2>&1 | grep -E "warning: |error: " | grep -v "ld: warning"` — Expected: only the `ContextMenuTests.swift:96` warning.
Run: `swift test` — Expected: exit 0, no failure line, 1110 tests (master + 25).
Run: `swiftlint lint --strict` — Expected: 0 violations.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorKernel/EdgeCurve+Ends.swift Sources/CreatorKernel/Topology+EdgeRuns.swift Sources/CreatorKernel/EdgePick.swift Sources/CreatorKernel/Topology+EdgePicks.swift Tests/CreatorKernelTests/EdgeRunTests.swift Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift
git commit -m "feat(kernel): record a split pick's run count and only call it drift when edges and runs both change"
```

---

### Task 3: Edges by Tag and projections resolve through both rules; flip the §8 polygon swap

**Files:**
- Modify: `Sources/CreatorNodes/Selection/EdgeTagMatch.swift` (whole file)
- Modify: `Sources/CreatorNodes/Selection/EdgesByTagNode.swift` (doc comment)
- Modify: `Sources/CreatorNodes/Sketch/SketchProjections.swift` (`locate`; shared with sketcher-s5)
- Test: `Tests/CreatorNodesTests/EdgeTagMatchMergedFaceTests.swift` (new), `Tests/CreatorNodesTests/SketchProjectionRunTests.swift` (new; its own file, so sketcher-s5's `SketchProjectionTests.swift` is untouched), `Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift` (whole file)

**Interfaces:**
- Consumes: Task 1's `Topology.edges(resolving:)`, `EdgeKey.narrowed`; Task 2's `Topology.runCount(_:)`, `EdgePick.runCount`, `EdgePick.hasDrifted(matching:inRuns:)`; `BracketAcceptanceTests`' `makeBracket()`, `topCapOutline(_:plate:)`, `edgeSet(_:_:)`, `keys(_:)`, `expectAllOK(_:_:)`.
- Produces: `EdgeTagMatch.choose(_:in:) -> (chosen: [EdgeInfo], matchCount: Int, runCount: Int)` (gains `runCount`); `BracketAcceptanceTests.swapTheFlangeForAHexagon(in: DocumentModel, _ bracket: Bracket) throws` (one undo step).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/EdgeTagMatchMergedFaceTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
@testable import CreatorNodes
import Testing

/// Edges by Tag on faces a union merged (roadmap "Naming: picks on merged faces"), on hand-built
/// topologies shaped like the bracket's left plate side: the plate's top (face 0), its side (face 1),
/// merged with the flange's coplanar side while the flange stands flush, and a flange-only face (face 2)
/// that meets the top.
struct EdgeTagMatchMergedFaceTests {
    let plate = NodeID()
    let flange = NodeID()
    var top: TopoTag { TopoTag(node: plate, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: plate, item: 0, role: .side(segment: 6)) }
    var flangeSide: TopoTag { TopoTag(node: flange, item: 0, role: .side(segment: 3)) }

    func line(_ id: Int, _ start: Vector3, _ end: Vector3, _ faces: [Int]) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: (end - start).normalized, length: (end - start).length,
                 midpoint: (start + end) * 0.5, convexity: .convex, faces: faces.map(FaceID.init),
                 curve: .line(start: start, end: end))
    }

    /// Flush (the rectangle flange): the side is merged, and the flange's fillet split its top edge at y = 12
    /// (edges 0 and 1). Apart (the hexagon): the side stands alone with one whole top edge (edge 0), and
    /// a flange face meets the top elsewhere (edge 1).
    func topology(flush: Bool) -> Topology {
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero,
                     tags: flush ? [side, flangeSide] : [side]),
            FaceInfo(id: FaceID(2), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [flangeSide]),
        ]
        let edges = flush
            ? [line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6), [1, 0]), line(1, Vector3(-30, 12, 6), Vector3(-30, 15, 6), [1, 0])]
            : [line(0, Vector3(-30, 16, 6), Vector3(-30, -16, 6), [0, 1]), line(1, Vector3(-10, 12, 6), Vector3(-10, 20, 6), [0, 2])]
        return Topology(faces: faces, edges: edges)
    }

    @Test func aPickOnAMergedFaceSurvivesThePartnerLeaving() {
        let picks = topology(flush: true).picks(for: [EdgeID(0), EdgeID(1)])
        #expect(picks == [EdgePick(key: EdgeKey([top], [side, flangeSide]), matchCount: 2, runCount: 1)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: false)) == EdgeTagMatch(edges: [EdgeID(0)], warnings: []))
    }

    @Test func aPickMadeApartResolvesWhenThePartnerIsFlushAgain() {
        let picks = topology(flush: false).picks(for: [EdgeID(0)])
        #expect(picks == [EdgePick(key: EdgeKey([top], [side]), matchCount: 1)])
        #expect(EdgeTagMatch.resolve(picks, in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0), EdgeID(1)], warnings: []))
    }

    /// A pick saved before runs were recorded (no `runCount`) counts each recorded edge as its own run: it
    /// resolves flush without a warning, and warns as on master once the partner leaves, because its 2 recorded
    /// edges (one split edge) are now 1 run.
    @Test func aPickSavedBeforeRunsStillWarnsWhenItsEdgesBecomeFewerRuns() {
        let saved = [EdgePick(key: EdgeKey([top], [side, flangeSide]), matchCount: 2)]
        #expect(EdgeTagMatch.resolve(saved, in: topology(flush: true)).warnings == [])
        let apart = EdgeTagMatch.resolve(saved, in: topology(flush: false))
        #expect(apart.edges == [EdgeID(0)])
        #expect(apart.warnings == ["Matched 1 edge, expected 2."])
    }

    /// The other half of the rule, and a change from master (which warned "Matched 2 edges, expected 1."): a pick
    /// saved before runs were recorded, on an edge that was whole then (`matchCount` 1, no `runCount`, exactly what
    /// an older file decodes to), resolves to both pieces with no warning once the edge is split into 2 in 1 run.
    @Test func aPickSavedBeforeRunsNoLongerWarnsWhenItsEdgeIsSplit() {
        let saved = [EdgePick(key: EdgeKey([top], [side]), matchCount: 1)]
        #expect(EdgeTagMatch.resolve(saved, in: topology(flush: true)) == EdgeTagMatch(edges: [EdgeID(0), EdgeID(1)], warnings: []))
    }

    @Test func picksOfOnePieceStillCountEdges() {
        let picks = topology(flush: true).picks(for: [EdgeID(1)])
        #expect(picks.first?.ordinals == [1])
        let apart = EdgeTagMatch.resolve(picks, in: topology(flush: false))
        #expect(apart.warnings == ["Matched 1 edge, expected 2."])
    }
}
```

Create `Tests/CreatorNodesTests/SketchProjectionRunTests.swift` (it pins `locate`'s switch to `hasDrifted`, so a merge in the shared `SketchProjections.swift` can't undo it silently):

```swift
import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorNodes
import Testing

/// A Sketch projection's pick drifts as an Edges by Tag pick does (roadmap "Naming: picks on merged faces"):
/// `SketchProjections.locate` adds up edges and runs across the references and asks `EdgePick.hasDrifted`.
struct SketchProjectionRunTests {
    let box = NodeID()
    var top: TopoTag { TopoTag(node: box, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: box, item: 0, role: .side(segment: 0)) }

    /// A reference whose only edge between `top` and `side` is one whole line, 32 mm long.
    var reference: Solid {
        let start = Vector3(-30, 16, 6)
        let end = Vector3(-30, -16, 6)
        let edge = EdgeInfo(id: EdgeID(0), kind: .line, direction: (end - start).normalized, length: 32,
                            midpoint: (start + end) * 0.5, convexity: .convex, faces: [FaceID(0), FaceID(1)],
                            curve: .line(start: start, end: end))
        let topology = Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [side]),
        ], edges: [edge])
        return Solid(topology: topology, bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: FakeStorage())
    }

    func located(_ pick: EdgePick) -> (edge: EdgeID, drift: String?)? {
        guard case .found(let edge, let drift) = SketchProjections.locate(.edgePicks([pick]), in: [reference]) else {
            return nil
        }
        return (edge.id, drift)
    }

    /// Picked while an operation split the edge in two (2 edges in 1 run), projected now that it is whole.
    @Test func aSplitEdgeThatIsWholeAgainIsFoundWithoutDrift() throws {
        let found = try #require(located(EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)))
        #expect(found.edge == EdgeID(0))
        #expect(found.drift == nil)
    }

    /// Picked as 2 edges in 2 runs, 1 now: drift, in Edges by Tag's words.
    @Test func fewerRunsThanRecordedIsDrift() throws {
        let found = try #require(located(EdgePick(key: EdgeKey([top], [side]), matchCount: 2)))
        #expect(found.edge == EdgeID(0))
        #expect(found.drift == "Matched 1 edge, expected 2.")
    }
}
```

Replace the whole of `Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift` with (the test it replaces, `swappingTheFlangeRectangleForAPolygonRederivesTheFilletAndFlagsTheChamferDrift`, pinned the drift this task removes):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Spec §8's third naming-stability case (spec Errata (M3), (M6), (naming: merged faces)): the L-flange's
    /// Rectangle swapped for a Regular Polygon on the same plane, a hexagon of radius 15 turned 30° so two of
    /// its sides stand parallel to Z, lifted 15 mm by a Transform so it stands on the plate. What holds, pinned
    /// here:
    /// - the fillet's rule re-derives its edges: 4 again, now the hexagon's vertical side edges on its two caps;
    /// - every chamfer pick resolves, with no warning: the three that name only plate faces to the same edges,
    ///   and the two on the plate sides the union had merged with the rectangle's coplanar sides, recorded with
    ///   the rectangle's side tags, to the plate's whole side edges by their narrowed keys (`EdgeKey.narrowed`);
    ///   the rectangle's fillet had split each of those edges in two, the hexagon doesn't, and that is not drift
    ///   (`EdgePick.runCount`);
    /// - OCCT still can't chamfer them: its fillet of the hexagon's vertical edges returns a solid that
    ///   OCCT's own checker rejects (`BRepCheck_Analyzer`, probe in the naming-merged-faces plan), and every
    ///   blend along the top outline's tangent chain fails on it, so the Chamfer is in error and the Output has
    ///   no result. The same resolved edges chamfer on the union before the fillet. Owner: roadmap row
    ///   "Kernel: blends that return an invalid solid";
    /// - one undo brings the rectangle flange, both edge sets and the part back.
    @Test func swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered() async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        let picks = filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate))
        #expect(picks.count == 5)
        #expect(picks.filter { $0.matchCount == 2 && $0.runCount == 1 }.count == 2, "the two split plate-side edges")
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks, .edgePicks(picks)))
        await document.waitForEvaluation()
        expectAllOK(document, "rectangle flange")
        let chamferKeys = keys(try edgeSet(document, bracket.chamferEdges))
        let filletKeys = keys(try edgeSet(document, bracket.filletEdges))

        try swapTheFlangeForAHexagon(in: document, bracket)
        await document.waitForEvaluation()

        #expect(document.results[bracket.fillet.id]?.state.isSuccess == true)
        let fillet = try edgeSet(document, bracket.filletEdges)
        #expect(fillet.edges.count == 4)
        #expect(keys(fillet) != filletKeys, "the fillet's flange keys are re-derived from the polygon")
        let sideX = 15 * 3.0.squareRoot() / 2   // r cos 30°
        #expect(fillet.edges.allSatisfy { id in
            fillet.solid.topology.edge(id).map { isClose(abs($0.midpoint.x), sideX, relative: 1e-6) } ?? false
        }, "every fillet edge is on one of the hexagon's vertical sides")

        let chamfer = try edgeSet(document, bracket.chamferEdges)
        guard case .ok? = document.results[bracket.chamferEdges.id]?.state else {
            Issue.record("Edges by Tag: \(String(describing: document.results[bracket.chamferEdges.id]?.state))"); return
        }
        #expect(chamfer.edges.count == 5)
        #expect(keys(chamfer) == Set(chamferKeys.map { $0.narrowed ?? $0 }), "the merged-side picks resolve narrowed")
        let outline = chamfer.edges.compactMap { chamfer.solid.topology.edge($0) }
        #expect(outline.allSatisfy { isClose($0.midpoint.z, 6, relative: 1e-9) && $0.midpoint.y <= 1e-6 },
                "the front edge, its corners and the two sides of the plate's top; not its back")
        #expect(outline.filter { isClose($0.length, 32, relative: 1e-9) }.count == 2, "each side edge is whole")

        let chamferNode = try #require(document.graph.nodes.values.first { $0.typeID == ChamferNode.typeID })
        guard case .error(let reason)? = document.results[chamferNode.id]?.state else {
            Issue.record("OCCT is expected to refuse the chamfer on the filleted hexagon"); return
        }
        #expect(reason.hasPrefix("Chamfer failed"))
        #expect(document.results[bracket.output.id]?.outputs == nil, "the Output has no part to show or export")
        // The picks are not what fails: the same resolved edges chamfer on the union, before the fillet.
        let union = try #require(document.results[bracket.union.id]?.outputs?["solid"]?.solids?.first)
        let resolved = picks.flatMap { union.topology.edges(resolving: $0.key) }.map(\.id)
        #expect(resolved.count == 5)
        _ = try await kernel.chamfer(union, edges: resolved, distance: 0.5, tag: NodeTag(node: NodeID(), item: 0))

        document.undo()
        await document.waitForEvaluation()
        expectAllOK(document, "undone")
        #expect(document.results[bracket.output.id]?.outputs?["solid"]?.solids?.count == 1)
        #expect(keys(try edgeSet(document, bracket.filletEdges)) == filletKeys)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == chamferKeys)
    }

    /// Replaces the flange's Rectangle with a hexagon (r 15, turned 30°) lifted 15 mm, as one undo step:
    /// removing the Rectangle drops its three wires, and the lifted flange replaces the old one in the union's
    /// tools.
    func swapTheFlangeForAHexagon(in document: DocumentModel, _ bracket: Bracket) throws {
        var polygon = BuiltInNodes.registry.makeNode(RegularPolygonNode.typeID)
        polygon.inputValues.merge(["sides": .integer(6), "radius": .number(15), "rotation": .number(30)]) { _, new in new }
        var lift = BuiltInNodes.registry.makeNode(TransformNode.typeID)
        lift.inputValues["move"] = .vector(Vector3(0, 0, 15))
        func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> GraphCommand {
            .connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input)))
        }
        try document.perform(.batch([
            .addNode(polygon), .addNode(lift), .removeNode(bracket.flangeProfile.id),
            link(bracket.flangePlane, "plane", polygon, "plane"), link(polygon, "profile", bracket.flange, "profile"),
            link(bracket.flange, "solid", lift, "solid"), link(lift, "solid", bracket.union, "tools"),
        ]))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "EdgeTagMatchMergedFaceTests|SketchProjectionRunTests|swappingTheFlange"`
Expected: `aSplitEdgeThatIsWholeAgainIsFoundWithoutDrift` fails (master's `locate` reports "Matched 1 edge, expected 2."), `aPickSavedBeforeRunsNoLongerWarnsWhenItsEdgeIsSplit` fails (master warns "Matched 2 edges, expected 1."), the other 4 `EdgeTagMatchMergedFaceTests` fail (the merged pick matches nothing, or warns "Matched 2 edges, expected 1."), `fewerRunsThanRecordedIsDrift` passes (master drifts there too), and the swap test records "Edges by Tag: Optional(… warning(\"Matched 0 edges, expected 2; 0 edges, expected 2.\"))".

- [ ] **Step 3: Implement**

Replace the whole of `Sources/CreatorNodes/Selection/EdgeTagMatch.swift` with:

```swift
import CreatorKernel

/// Resolves remembered picks against a solid's topology (spec §5.3, rules 5–6). Pure, so the
/// drift and warning rules are testable without a kernel.
struct EdgeTagMatch: Equatable {
    var edges: [EdgeID]
    var warnings: [String]

    static let nothingPicked = "Pick edges in view to fill this rule."
    static let unnamedPick = "A picked edge borders a face with no stable name, so the pick may move to a different edge "
        + "when the model changes. Pick it again after the change."

    /// Drift is reported per drifted pick, so two picks drifting in opposite directions
    /// (1 → 2 and 1 → 0) never cancel out into "Matched 2 edges, expected 2.". A pick drifts by
    /// `EdgePick.hasDrifted(matching:inRuns:)`: a picked edge that is split, or no longer split, is not drift.
    static func resolve(_ picks: [EdgePick], in topology: Topology) -> EdgeTagMatch {
        guard !picks.isEmpty else { return EdgeTagMatch(edges: [], warnings: [nothingPicked]) }
        var selected: [EdgeID] = []
        var seen: Set<EdgeID> = []
        var drifts: [(found: Int, expected: Int)] = []
        for pick in picks {
            let choice = choose(pick, in: topology)
            if pick.hasDrifted(matching: choice.matchCount, inRuns: choice.runCount) {
                drifts.append((choice.matchCount, pick.matchCount))
            }
            for edge in choice.chosen where seen.insert(edge.id).inserted {
                selected.append(edge.id)
            }
        }
        var warnings: [String] = []
        if !drifts.isEmpty {
            warnings.append(drift(drifts))
        } else if selected.isEmpty {
            warnings.append("Matched 0 edges, expected \(picks.reduce(0) { $0 + $1.matchCount }).")
        }
        if picks.contains(where: \.touchesUnnamedFace) {
            warnings.append(unnamedPick)
        }
        return EdgeTagMatch(edges: selected, warnings: warnings)
    }

    /// The edges one pick chooses in `topology` (what its key resolves to, `Topology.edges(resolving:)`:
    /// its tag-subset matches, else its narrowed key's; then narrowed by its ordinals), how many edges the
    /// key matched and how many runs they form. The Sketch node's projections use it too.
    static func choose(_ pick: EdgePick, in topology: Topology) -> (chosen: [EdgeInfo], matchCount: Int, runCount: Int) {
        let matches = topology.edges(resolving: pick.key)
        let chosen = pick.ordinals.map { ordinals in ordinals.filter(matches.indices.contains).map { matches[$0] } } ?? matches
        return (chosen, matches.count, Topology.runCount(matches))
    }

    /// "Matched 1 edge, expected 2." (several drifts joined by "; ").
    static func drift(_ drifts: [(found: Int, expected: Int)]) -> String {
        let counts = drifts.map { "\($0.found) \($0.found == 1 ? "edge" : "edges"), expected \($0.expected)" }
        return "Matched \(counts.joined(separator: "; "))."
    }
}
```

In `Sources/CreatorNodes/Selection/EdgesByTagNode.swift`, replace:

```swift
/// shell writes it from viewport picks. A key matches by tag subsets on each side, so unions that
/// merge faces keep the pick. A changed match count is a warning, never silent (rule 6).
```

with:

```swift
/// shell writes it from viewport picks. A key matches by tag subsets on each side, so unions that
/// merge faces keep the pick, and a key that matches nothing is narrowed to the operand its edge runs
/// along (`Topology.edges(resolving:)`), so a pick on a merged face survives the other operand changing.
/// A changed match count is a warning, never silent (rule 6), unless only the number of pieces a picked
/// edge is split into changed (`EdgePick.hasDrifted(matching:inRuns:)`).
```

In `Sources/CreatorNodes/Sketch/SketchProjections.swift`, replace:

```swift
    /// matched by `EdgeTagMatch.choose` (tag subsets, then ordinals), the same as Edges by Tag (parent
    /// spec §5.3), and a changed match count is reported in Edges by Tag's words, never silently.
    static func locate(_ setting: ConstantValue?, in references: [Solid]) -> Located {
        guard case .edgePicks(let picks)? = setting, picks.count == 1, let pick = picks.first else {
            return .problem("has no picked edge.")
        }
        guard !references.isEmpty else {
            return .problem("has no reference solid: wire the solid it was picked on into “references”.")
        }
        var found: [EdgeInfo] = []
        var matched = 0
        for solid in references {
            let choice = EdgeTagMatch.choose(pick, in: solid.topology)
            matched += choice.matchCount
            found += choice.chosen
        }
        switch found.count {
        case 0: return .problem("matches no edge of the references.")
        case 1:
            let drift = matched == pick.matchCount ? nil : EdgeTagMatch.drift([(matched, pick.matchCount)])
            return .found(found[0], drift: drift)
```

with:

```swift
    /// matched by `EdgeTagMatch.choose` (tag subsets, then ordinals), the same as Edges by Tag (parent
    /// spec §5.3, narrowing a key that matches nothing), and a changed match count is reported in Edges by
    /// Tag's words, never silently (`EdgePick.hasDrifted(matching:inRuns:)`, as Edges by Tag).
    static func locate(_ setting: ConstantValue?, in references: [Solid]) -> Located {
        guard case .edgePicks(let picks)? = setting, picks.count == 1, let pick = picks.first else {
            return .problem("has no picked edge.")
        }
        guard !references.isEmpty else {
            return .problem("has no reference solid: wire the solid it was picked on into “references”.")
        }
        var found: [EdgeInfo] = []
        var matched = 0
        var runs = 0
        for solid in references {
            let choice = EdgeTagMatch.choose(pick, in: solid.topology)
            matched += choice.matchCount
            runs += choice.runCount
            found += choice.chosen
        }
        switch found.count {
        case 0: return .problem("matches no edge of the references.")
        case 1:
            let drifted = pick.hasDrifted(matching: matched, inRuns: runs)
            return .found(found[0], drift: drifted ? EdgeTagMatch.drift([(matched, pick.matchCount)]) : nil)
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter "EdgeTagMatch|EdgesByTag|SketchProjection|SketchIntegration|BracketAcceptanceTests"` — Expected: all pass; `aPickWhoseMatchCountDriftedSaysSo` still warns (its pick has no `runCount`, so 1 edge in 1 run against 2 recorded is drift).
Run: `swift test --filter CreatorOCCTTests` — Expected: the conformance and naming-stability suites pass unchanged.
Run: `swift build --build-tests 2>&1 | grep -E "warning: |error: " | grep -v "ld: warning"` — Expected: only the `ContextMenuTests.swift:96` warning.
Run: `swift test` — Expected: exit 0, no failure line, 1117 tests (master + 32; the swap test is renamed, not added).
Run: `swiftlint lint --strict` — Expected: 0 violations (the swap test's body stays under 50 lines because the swap itself is `swapTheFlangeForAHexagon`).

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorNodes/Selection/EdgeTagMatch.swift Sources/CreatorNodes/Selection/EdgesByTagNode.swift Sources/CreatorNodes/Sketch/SketchProjections.swift Tests/CreatorNodesTests/EdgeTagMatchMergedFaceTests.swift Tests/CreatorNodesTests/SketchProjectionRunTests.swift Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift
git commit -m "feat(nodes): Edges by Tag keeps picks on merged faces through the polygon swap (§8)"
```

---

### Task 4: One operand changing, end to end on OCCT; record the rules

**Files:**
- Test: `Tests/CreatorNodesTests/BracketAcceptanceTests+MergedFaces.swift` (new)
- Modify: `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (append), `docs/superpowers/roadmap.md` (one row → three), `CLAUDE.md` (one sentence), `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` (one bullet) — all shared with other tracks.

**Interfaces:**
- Consumes: everything from Tasks 1–3; `GraphCommand.disconnect`, `.connect`, `.setInput(_, _, nil)`, `.batch`; `DocumentModel.fileData()`, `DocumentModel(data:registry:kernel:)`.
- Produces: nothing new for code; Errata (naming: merged faces) and roadmap rows "Kernel: blends that return an invalid solid" and "Naming: face picks on merged faces".

- [ ] **Step 1: Write the acceptance test**

Create `Tests/CreatorNodesTests/BracketAcceptanceTests+MergedFaces.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Roadmap "Naming: picks on merged faces", the case that comes out whole: the chamfer is picked on the
    /// plate's top outline while the flange is as wide as the plate (so the union merged each plate side with a
    /// flange side, and the flange's fillet split each side's top edge in two). Then the flange alone changes
    /// width, narrower (40) or wider (70) than the plate, so no side is merged any more. Every pick resolves to
    /// the same plate edges by its narrowed key, with no warning anywhere, and the part is still there; it
    /// survives a save and reopen, and a pick made now still holds once the flange is flush again.
    @Test(arguments: [40.0, 70.0])
    func aChamferPickedOnMergedSidesSurvivesTheFlangeChangingWidth(flangeWidth: Double) async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate)))))
        await document.waitForEvaluation()
        expectAllOK(document, "flush flange")
        let flushKeys = keys(try edgeSet(document, bracket.chamferEdges))
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)

        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(flangeWidth))]))
        await document.waitForEvaluation()
        expectAllOK(document, "flange \(flangeWidth) wide")
        let chamfer = try edgeSet(document, bracket.chamferEdges)
        #expect(chamfer.edges.count == 5, "the front edge, its two corners and the two plate sides")
        #expect(keys(chamfer) == Set(flushKeys.map { $0.narrowed ?? $0 }))
        #expect(document.results[bracket.output.id]?.outputs?["solid"]?.solids?.count == 1)

        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: kernel)
        await reopened.waitForEvaluation()
        expectAllOK(reopened, "reopened at \(flangeWidth)")
        #expect(keys(try edgeSet(reopened, bracket.chamferEdges)) == keys(chamfer))

        // Picked again now, the five edges name the plate alone, and they stay picked once the flange is flush.
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(chamfer.solid.topology.picks(for: chamfer.edges))))
        try document.perform(.batch([.setInput(bracket.flangeProfile.id, "width", nil), .connect(widthWire)]))
        await document.waitForEvaluation()
        expectAllOK(document, "re-picked, flush again")
        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == flushKeys)
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter aChamferPickedOnMergedSidesSurvivesTheFlangeChangingWidth`
Expected: PASS, "with 2 test cases passed". It is an acceptance test of Tasks 1–3, so it passes on arrival; during verification it was also run with Task 3's two resolver files reverted, where it failed with 12 issues (Edges by Tag warns "Matched 0 edges, expected 2; …", the Chamfer and Output have no result).

- [ ] **Step 3: Record the rules**

Append to `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (after the last line, Errata (Packaging)'s last bullet):

```markdown

## Errata (naming: merged faces)

Plan `2026-10-09-naming-merged-faces.md`, roadmap row "Naming: picks on merged faces".

- §5.3 rules 3 and 5: a remembered edge key that matches no edge is retried **narrowed**: each side keeps only the
  tags whose node call (node and broadcast item) the other side also has tags from, and a side with no such tag keeps
  all of its tags (`EdgeKey.narrowed`, `Topology.edges(resolving:)`). A pick on a face a union merged names both
  operands' tags; narrowed, it names the edge by the operand the edge runs along (the plate's top edge on a plate side
  is `{plate.endCap} | {plate.side}` whatever the flange does), so it survives the other operand changing or leaving.
  An edge where two operands meet keeps its full name, and a key that matches anything is never narrowed, so every
  pick that resolved before resolves the same way.
- §5.3 rule 6: a pick of every edge its key names also counts **runs**, edges that meet end to end, and drifts only
  when the edge count and the run count both differ from the recorded ones (`EdgePick.hasDrifted(matching:inRuns:)`):
  an edge that an operation splits in two, or stops splitting, is still the picked edge. `EdgePick.runCount` is
  recorded only when the runs were fewer than the edges. It is an optional key that older readers ignore (they count
  edges, as before), so §4.5's format version stays 4. A pick of some of a key's edges (ordinals) still counts edges.
  A pick saved before this has no run count, so each recorded edge counts as its own run: it still warns when its
  edges become fewer runs (a split edge it recorded as 2 edges, now whole), and it no longer warns when a recorded
  edge is split into more pieces (master warned "Matched 2 edges, expected 1." there).
- Errata (M6)'s polygon swap: the two picks on the plate sides the union had merged with the rectangle's now resolve
  to the plate's whole side edges, and Edges by Tag is `.ok` with five edges, so §8's chamfer promise holds for the
  names. The part is still lost, for a reason the M6 probe didn't see: OCCT's fillet of the hexagon's vertical edges
  reports success but returns a solid that `BRepCheck_Analyzer` rejects, and on it every fillet or chamfer along the
  plate top's tangent chain fails (at 0.5, 0.2 and 0.05 mm alike), while the same resolved edges chamfer on the union
  before the fillet. It depends on the fillet radius: valid at R ≤ 2 (and the chamfer then succeeds; it succeeds at
  R 2.5 too), invalid at the bracket's R3. So the Chamfer stays in error and the Output has no result, until the kernel rejects or repairs
  invalid blend results (roadmap row "Kernel: blends that return an invalid solid").
  `BracketAcceptanceTests.swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered` pins it, and
  `BracketAcceptanceTests.aChamferPickedOnMergedSidesSurvivesTheFlangeChangingWidth` pins the case end to end with no
  warning or error (the flange alone made 40 or 70 mm wide, so no plate side stays merged).
- Face picks (`FacePick`, Plane from Face) are not narrowed: one made on a merged face still names both operands'
  tags (roadmap row "Naming: face picks on merged faces").
```

In `docs/superpowers/roadmap.md`, replace the row:

```markdown
| — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ⏳ after M6 | `BracketAcceptanceTests+PolygonSwap` (flip its expectations when fixed) |
```

with:

```markdown
| — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ✅ code done (plan `2026-10-09-naming-merged-faces.md`, Errata (naming: merged faces)): a key matching nothing is retried narrowed (`EdgeKey.narrowed`), drift counts runs as well as edges (`EdgePick.runCount`, no format bump) | `BracketAcceptanceTests+PolygonSwap` (flipped: Edges by Tag resolves with no warning; the Chamfer still fails, row below), `BracketAcceptanceTests+MergedFaces` |
| — | Kernel: blends that return an invalid solid — OCCT's fillet of the polygon-swap hexagon's vertical edges reports done but returns a solid `BRepCheck_Analyzer` rejects, so every later fillet or chamfer along the plate top's tangent chain fails (Errata (naming: merged faces)); valid at R ≤ 2 (and the chamfer then succeeds; it succeeds at R 2.5 too), invalid at the bracket's R3; reject such a result with a plain message, or repair it | ⏳ | `BracketAcceptanceTests+PolygonSwap` (its Chamfer error and missing Output flip when fixed) |
| — | Naming: face picks on merged faces — a `FacePick` (Plane from Face) on a face a union merged names both operands' tags and matches nothing once they stop merging; narrow it like `EdgeKey.narrowed` (it has no other side, so it needs its own rule) | 💬 | Errata (naming: merged faces) |
```

In `CLAUDE.md`, replace:

```markdown
Edge picks (`EdgePick`) match by tag subsets per side and warn on count drift;
```

with:

```markdown
Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a pick without one counts each recorded edge as a run) and warns only when both changed;
```

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

```markdown
- Regular Polygon is `typeVersion` 2 (`rotation`). The §8 polygon swap keeps the fillet (re-derived) but not the
  chamfer: picks on faces a union merged name both operands' tags and drift when one operand changes, the Chamfer
  then fails and the Output has no result (spec Errata (M6)). A minimal-tag-subset pick isn't enough (the edge counts
  change too). Owner: roadmap row "Naming: picks on merged faces".
```

with:

```markdown
- Regular Polygon is `typeVersion` 2 (`rotation`). ✅ (naming-merged-faces plan) The §8 polygon swap's picks on faces
  a union merged now resolve with no warning: a key that matches nothing is retried `EdgeKey.narrowed`, and drift
  counts runs as well as edges (`EdgePick.runCount`). The Chamfer still fails there, because OCCT's fillet of the
  hexagon returns an invalid solid (spec Errata (naming: merged faces)). Owner of that: roadmap row "Kernel: blends
  that return an invalid solid"; face picks on merged faces: roadmap row "Naming: face picks on merged faces".
```

- [ ] **Step 4: Run everything**

Run: `swift build --build-tests 2>&1 | grep -E "warning: |error: " | grep -v "ld: warning"` — Expected: only the `ContextMenuTests.swift:96` warning.
Run: `swift test` — Expected: exit 0, no "recorded an issue" / "failed after" line, 1118 tests (master + 33).
Run: `swiftlint lint --strict` — Expected: 0 violations.
Run: `git diff --stat` — Expected: only the files this plan names.

- [ ] **Step 5: Commit**

```bash
git add Tests/CreatorNodesTests/BracketAcceptanceTests+MergedFaces.swift docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md docs/superpowers/roadmap.md CLAUDE.md docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
git commit -m "test(nodes): chamfer picks on merged sides survive the flange changing width; record Errata (naming: merged faces)"
```

---

## Self-review

- **Roadmap row coverage.** "Must survive one operand changing": Tasks 1 and 3 (narrowing), proven on OCCT by Task 3's swap (Edges by Tag `.ok`) and Task 4 (40 and 70 mm, no warning, part present, save/reopen). "Needs the split-edge count handled too, not only a minimal tag subset": Task 2 (runs) and Task 3 (drift through `hasDrifted`). "Flip its expectations when fixed": Task 3 flips the naming expectations; the Chamfer's error stays pinned with its real cause (probe 7) and a new owner row (Task 4).
- **Spec §5.3 rule 6 (no silent drift)** still holds: a changed number of runs is drift; only the number of pieces of the same runs is tolerated; ordinal picks count edges; zero matches still warns.
- **Spec §8 / naming stability:** Width 60→90 and Hole count 4→6 (`bracketKeepsItsEdgeSelectionsAcrossParameterChangesAndExports`) and `CreatorOCCTTests` run unchanged in every task's full `swift test`.
- **File format:** `runCount` optional, `nil` not written, older decoder checked (Task 2); version stays 4 (Task 2 asserts `"formatVersion" : 4`).
- **Placeholders:** none; every step has its code or exact text, extracted and replayed.
- **Type consistency:** `edges(resolving:)`, `narrowed`, `origin`, `runCount(_:)`, `runCount`, `hasDrifted(matching:inRuns:)`, `choose(...).runCount`, `swapTheFlangeForAHexagon(in:_:)` are spelled the same in every task.
- **Review Focus:** all five lines have their tests in Tasks 1–4.
- **Older files (Decision 5):** a pick saved before this change no longer warns when a recorded edge is split into more pieces (master did); it still warns when its edges become fewer runs. Pinned both ways in Tasks 2 and 3.
- **Risks left:** runs join edges that share an end point without checking tangency (two edges of one key meeting at a corner count as one run; none occur in the probes); narrowing can't help a key whose both sides are merged from the same operands; face picks aren't narrowed (row added).
