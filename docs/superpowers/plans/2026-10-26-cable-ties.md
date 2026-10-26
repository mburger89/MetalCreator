# Cable Ties Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The user selects wires on the graph canvas (a click, or an ⌥-box) and presses ⌘⇧T; a cable tie gathers them into a draggable bundle that the wires run through side by side, the wires go slack while things move and pull taut when they stop, and the file (format 9) reopens exactly as it was left (spec §1).

**Architecture:** `CableTie` (with `TieID`) lives in `Graph.ties` beside the comments, so a group definition's inside has its own. It is edited by two plain, non-evaluating commands, `setTie` and `removeTie`. `removeNode`, `disconnect` and a replacing `connect` take the wires they remove out of ties inside the same command, and their inverses put the ties back. The editor computes every wire's taut route through its ties' lanes as pure geometry (`WireRoute`, `TieLayout`, `WireRouting`), and drawing, hit testing, boxes, culling and ⌘⇧T all read that route. The slack is a closed-form damped spring per route piece (`WireSpring`, `WireMotion`): moves kick it, the canvas draws it inside `TimelineView(.animation)` only while it is non-zero, and Reduce Motion stops it from ever being kicked.

**Tech Stack:** Swift 6.4 strict concurrency, MetalUI (`TimelineView(.animation)`, `@Environment(\.accessibilityReduceMotion)`, `onChange(of:initial:)`), `@MainActor @Observable EditorModel`/`DocumentModel`, Swift Testing, SwiftLint `--strict`.

**Spec:** `docs/superpowers/specs/2026-10-26-cable-ties-design.md` (approved 2026-10-26; binding), under `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (§3 selection, §7 comments: the precedent this follows) and `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all their Errata. Task 13 appends the errata spec §7 asks for and records this plan's rulings in the cable ties spec.

**Worktree:** `/Users/maxburger/Developer/MetalCreator-cable-ties`, branch `cable-ties`, off master at the commit that adds this plan (`git -C /Users/maxburger/Developer/MetalCreator worktree add ../MetalCreator-cable-ties -b cable-ties master`). Run every command from the worktree root. Never edit `Package.swift`'s MetalUI path, never modify `../MetalUI`, never take screenshots. Before Task 1, run the full suite once and note its test count as the baseline (the pass rule is at the end of Task 13).

## Global Constraints

Copied from the spec and `CLAUDE.md`; every task's requirements include them.

- **Manual only:** ties are made by the user with **⌘⇧T** (`GraphKeyBindings` checks MetalUI's `.primary`, so it is **Ctrl+Shift+T** on Linux and Windows, and ⌥ is Alt there). No automatic bundling or routing, no sag at rest, no wire colours or labels, no reroute nodes, no ties in the viewport.
- **A wire is identified by its input endpoint (`Link.to`).** A tie is `CableTie { id: TieID, position: Vector2 (stored flow coordinates), wires: Set<Endpoint> }` in `Graph.ties: [TieID: CableTie]`.
- **Invariants:** (I1) every wire a tie holds is the `to` of an existing link; (I2) a tie holds **at least two** wires, and one that would hold fewer is removed. A wire may be in any number of ties. `Graph.apply` keeps both; decoding repairs both.
- **Commands** `setTie(CableTie)` (add or replace whole) and `removeTie(TieID)`: `touchedNodes` empty, `affectsResults` false, work under `.inDefinition` and `.at`. **Undo names: "Tie Wires", "Add to Tie", "Move Tie", "Remove Tie", "Untie Wire"** (constants in `UndoName`, never blank).
- `removeNode` (every wire into or out of the node), `disconnect` (that wire) and `connect` onto an occupied input (the replaced wire) **strip those wires from ties in the same command**, (I2) applies, and their **inverses restore the ties exactly**, one undo step per user action. **A new wire is never tied implicitly.**
- **File format 9.** `GraphFile.currentFormatVersion = 9`, the history note in `GraphFile.swift` says 9 added `ties`, the `ties` key is **written only when non-empty, sorted by id, each tie's wires sorted**, format 8 and older give no ties, decoding 9 drops wires breaking (I1) and then ties breaking (I2), and tolerates repeated ids the way stickies do (the first wins). An older app refuses format 9 through its newer-version check.
- **Selection** (`CanvasSelection`) gains `wires: Set<Endpoint>` and `ties: Set<TieID>`: view state, never saved, never undone.
- **Hit test:** a point **within 5 pt (display canvas points)** of a wire's **taut** route hits it; a point in a tie's band hits the tie. Priority: socket, tie, node, note, wire, frame, empty (see ruling R3 for the resize handle).
- **Click** on a wire or tie selects it, replacing; **⇧ adds, ⌘ toggles (⌘ wins)**; a click on empty canvas clears everything.
- **⌥-drag on empty canvas** box-selects **wires only** (taut route crosses or lies inside the box); the modifiers at the start fix the mode: **⌥ replaces the wire selection, ⌥⇧ adds, ⌥⌘ toggles**; nodes, comments and ties keep their selection; **Esc restores** the selection the drag began with. **A plain box** selects nodes and comments as now plus **ties whose band lies inside the box**, never wires.
- **⌘⇧T:** no tie selected and ≥2 wires: a new tie holding them ("Tie Wires") at the centre of where they were picked (the box's inside points, or the click points, remembered in memory only), and the selection becomes just the new tie. Exactly one tie and ≥1 wire selected: add them ("Add to Tie"). Anything else: the existing refusal. It runs **only while the panel is visible and no interaction is under way**.
- **Moving ties:** a drag moves a tie as one coalesced undo step ("Move Tie"); a selection of ties with nodes and comments moves together; ties nudge like nodes.
- **Editing:** Delete with ties selected removes them ("Remove Tie"); Delete with only wires does nothing; **⌥-click on a wire within a tie's band** unties that wire ("Untie Wire"), (I2) applies. Everything undoes.
- **Groups:** grouping moves a tie into the definition only if all of its wires move with them; otherwise the crossing wires leave it and (I2) applies; ungrouping moves the definition's ties back out, remapped.
- **Route:** source socket → tie₁ lane → … → target socket; ties in **stored `position.x` order, then by id**; each piece leaves and enters **along the flow** with the reach **`max(40, |along| × 0.5)`** (G1 at every lane; an untied route equals today's `WireGeometry`); lanes **4 pt apart**, centred on `position`, **across the flow**, ordered by the target socket's display position across the flow, then by endpoint; the **band** is a rounded rectangle **6 pt along the flow**, **3 pt beyond the outer lanes**, in the theme's **`glassStroke`** (`Palette.hairline`), drawn above the wires and below the nodes.
- **Draw order:** frames → wires → tie bands → notes → nodes → ghosts → dragged wire → box. Culling by each route's bounds; a tie by its band. Selected wires draw wider in the theme's selection colour; selected ties draw their band in it.
- **Motion:** pinned points (the socket ends and the lanes) are drawn exactly where they are at every frame; each piece's two control points carry a spring (offset and velocity); a move of the pinned ends by Δ grows the offset by −Δ × a slack factor below 1; **damping ratio about 0.8, settles within about 0.3 s, offset capped at 40% of the piece's length**; at rest the offset is **exactly zero** (a tolerance snaps residues) and the drawn route is the taut route bit for bit; **`TimelineView(.animation)` wraps the wire layer only while some spring is non-zero**; the step is pure, `(state, Δ, dt)` → state, with `dt` from an injected clock; **Reduce Motion: no spring state is ever created**; hit testing, culling and saving use the taut route only; motion is never saved.
- **Portability:** everything in `CreatorGraph` and `CreatorEditor` builds on Linux and Windows (Foundation only; no Apple-only import). Modifier checks on MetalUI events say `.primary`.
- `CLAUDE.md`: Swift 6 strict concurrency, Swift Testing only, `@MainActor @Observable` models, behaviour in models and thin views, one type per file in `Sources`, no force unwraps or force `try`, no GCD, no legacy formatters, `swiftlint lint --strict` with **0 violations** (multi-line collection literals need trailing commas). Stored coordinates are left-to-right flow; `CanvasFlow` converts for display. An `.equatable()` canvas view's `==` covers every stored property and its test uses `expectEqualityCovers`. MetalUI gaps go in `docs/metalui-gaps.md` (entry and summary-table row) and are never worked around.

## Review Focus

Input classes the spec implies and no task's happy path exercises, most likely to bite first. Each line has its test in the task that owns the code.

1. **The selection names a tie or wire that undo took away** (undo of Tie Wires, of a paste, a disconnect). Expected: Delete, ⌘⇧T, a drag, an arrow and ⌥-click skip it, with no trap, no refusal for Delete and no empty undo step. Test: `aGoneTieOrWireInTheSelectionIsSkipped` (Task 9).
2. **A file written by hand or by another build**: a tie naming a wire that isn't there, a tie left with one wire, a repeated tie id, and a format-8 file. Expected: it opens; the bad wire and then the small tie are dropped; the first of a repeated id wins; format 8 has no ties. Tests: `decodingDropsWiresThatAreNotThereAndThenSmallTies`, `aRepeatedTieIDKeepsTheFirst`, `aFormatEightFileHasNoTies` (Task 1).
3. **A tie dragged behind its wires' sources, or onto a socket.** Expected: the route loops back with every piece still leaving and entering along the flow (G1), stays finite, and a press on the socket still grabs the socket. Tests: `thePiecesJoinTangentContinuouslyAtEveryLaneEvenBehindTheSource` (Task 4), `aSocketBeatsATieAndATieBeatsANode` (Task 6).
4. **The left dock.** Expected: lanes spread across x, bands are the transpose, a click on a transposed wire hits it, ⌘⇧T stores the tie at the transpose of the picked centre, and a drag moves the tie in stored coordinates. Tests: `inTheVerticalFlowLanesSpreadAcrossXInEndpointOrder` (Task 4), `theLeftDockHitsTheTransposedRoute` (Task 6), `inTheLeftDockTheTieGoesToTheStoredCentre` (Task 8), `aTieDraggedInTheLeftDockMovesInStoredCoordinates` (Task 9).
5. **A long frame, or a clock that steps backwards** (the app wakes from sleep, a frame's date is a little older than the kick). Expected: one long step settles exactly as many short ones would and never overshoots the cap; an earlier date changes nothing. Tests: `oneLongFrameIsTheSameAsManyShortOnes`, `timeNeverRunsBackwards` (Task 11).

## Key decisions (made by this plan where the spec leaves a choice)

- **R1 (spec §3.2: snapshot or batch).** **The inverse is a batch.** `restoreNode` and `restoreLinks` are unchanged. When `removeNode`, `disconnect` or a replacing `connect` takes wires out of ties, its inverse becomes `.batch([<the inverse it returns today>] + ties.map(.setTie(old)))`, with the links restored first so each `setTie` passes (I1). When no tie is reached the inverse is exactly today's, so no existing test or caller sees a change. This needs no new associated values on any command, and it keeps one undo step per action because `DocumentModel` records the one inverse command. Redo replays the forward command, which strips again.
- **R2.** `TieID`'s field is `rawValue`, as `NodeID`, `CommentID` and `GroupID` have it (the spec's sketch writes `raw`). `ForEach` keys read `id.rawValue`.
- **R3 (contradiction).** The spec's priority list ends "…, wire, frame, resize, empty", which would let a note swallow its own resize handle. The handle stays where it is today: just before its own comment's body. The full order is socket, tie, node, note (a selected note's handle first), wire, frame (a selected frame's handle first), empty. `commentHit` splits into `noteHit` and `frameHit` so the wire can sit between them.
- **R4.** The 5 pt wire distance and the band are in display canvas points, as the spec says ("display"). They are not screen points, so they scale with zoom.
- **R5.** A drag that starts on a wire is a drag on empty canvas: a box, or an ⌥-box. Only a click selects a wire. Wires cross the canvas everywhere, so this keeps box selection working where a press lands on one.
- **R6.** ⌘A selects every node, comment and tie, and no wire. This matches the plain box, which never selects wires.
- **R7.** The clipboard copies a tie whenever every wire it holds is copied, whether or not the tie itself is selected, as the wires between copied nodes are copied. Paste and ⌥-drag select the copies. `NodeClipboard` is in `CreatorEditor`, so its tests are `CreatorEditorTests` (spec §6 lists them under CreatorGraph).
- **R8.** Undo names for mixed actions: a move of ties alone is "Move Tie"; ties moved with anything else make "Move". A delete of ties alone is "Remove Tie", by Delete or by ⌘X; ties deleted with anything else make "Delete" or "Cut". The ties are removed before the nodes in the batch.
- **R9.** ⌘⇧T with one tie and only wires already in it is refused, because there is nothing to add. After Add to Tie, the selection becomes the tie, as after Tie Wires. The refusal has no node to shake, so it is the canvas's refusal line: "Select two or more wires to tie, or one tie and the wires to add to it."
- **R10 (spec §4.2's position rule).** Each wire's pick point is either the stored click point, or, for an ⌥-box, the mean of the midpoints of its route's stretches inside the box. The tie goes at the mean of the selected wires' pick points. A selected wire with no pick point counts its route's middle sample. Pick points live in `EditorModel.wirePickPoints`, in memory only.
- **R11 (spec §4.5).** Ungroup handles the outer level's wires into and out of the group node the way Group handles crossing wires: they leave their ties. The automatic strip in `removeNode` does this. Make Unique copies a definition's ties onto the copy, remapped to the copy's nodes; the spec does not mention Make Unique.
- **R12 (spec §3.3).** The `ties` key is read whatever the file's version. A format-8 file never has one, so format 8 gives no ties.
- **R13 (spec §5.2).** Only moves kick the springs: a drag of the selection and an arrow nudge, of nodes, frames carrying nodes, or ties. Undo, paste and a dock change snap straight to the new taut routes. The spring is solved in closed form, so a step is exact for any `dt`. The `TimelineView` content reads the slack at the frame's date and writes nothing to the model. A settle task checks every 100 ms and ends the timeline once every spring has snapped to zero. Starting constants: natural frequency 20 rad/s, damping ratio 0.8, slack 0.6, cap 0.4, rest below 0.05 pt and 1 pt/s. They are tuned by eye in TIE-1.
- **R14.** The editor has no snapping, so spec §4.3's "snapped" adds nothing. Ties are nudged.
- **R15.** A selected wire is drawn 4 pt wide in `Palette.selection` instead of its socket colour.
- **R16.** Frames carry nodes only; a moved frame does not carry ties.
- **R17.** The wire layer is `if animating { TimelineView(.animation) { … } } else { static }`, as the spec words it. A paused schedule would leave a timeline in the tree at rest.

## File structure

New files (one type per file in `Sources`):

- `Sources/CreatorGraph/Ties/`: `TieID.swift` (identity), `CableTie.swift` (the value and its sorted Codable), `Endpoint+Order.swift` (a fixed endpoint order), `Graph+Ties.swift` (the two commands, `stripTies(holding:)`, `restoring(_:ties:)`, decode repair).
- `Sources/CreatorEditor/`:
  - Pure geometry: `WireRoute.swift`, `TieLayout.swift`, `WireRouting.swift`.
  - Pure motion: `SpringPoint.swift`, `PieceSpring.swift`, `WireSpring.swift`, `WireMotion.swift`.
  - Model extensions: `EditorModel+Wires.swift` (routing, hits, boxes), `EditorModel+Ties.swift` (⌘⇧T, untie), `EditorModel+Motion.swift`.
  - Views: `TieBandView.swift`, `WireLayer.swift`.
- Tests:
  - `Tests/CreatorGraphTests/Support/TieFixtures.swift`, and `Tests/CreatorGraphTests/Ties/{TieCommandTests,TieFileTests,TieStrippingTests,TieGroupTests}.swift`.
  - `Tests/CreatorEditorTests/Support/{TieScene,ManualClock}.swift`, and `Tests/CreatorEditorTests/{WireRouteTests,TieRenderTests,WireHitTests,WireSelectionTests,WireBoxSelectTests,TieKeyTests,TieEditingTests,TieClipboardTests,WireSpringTests,WireMotionTests,EditorWireMotionTests}.swift`.
  - `Tests/CreatorAppTests/WireMotionWindowTests.swift`.

## How to read the code blocks

New files are given whole. An edit to an existing file is given as **Replace** (the exact current text) and **with** (the new text); apply each with an exact string replacement, and if the old text is not found, a step was skipped. Verification commands run from the worktree root. `swift build --build-tests` must print no `error:` and no `warning:` other than the `ld: warning` lines about Homebrew's OCCT dylibs.

Every commit in this plan ends with these two lines:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS
```

## Tasks

### Task 1: The tie model, its two commands and file format 9

Spec §3.1, §3.2 (the commands and undo names), §3.3.

**Files:**
- Create: `Sources/CreatorGraph/Ties/TieID.swift`, `Sources/CreatorGraph/Ties/CableTie.swift`, `Sources/CreatorGraph/Ties/Endpoint+Order.swift`, `Sources/CreatorGraph/Ties/Graph+Ties.swift`
- Modify: `Sources/CreatorGraph/Graph.swift` (whole file), `Sources/CreatorGraph/GraphCommand.swift`, `Sources/CreatorGraph/Graph+Commands.swift:125-126`, `Sources/CreatorGraph/GraphFile.swift:5-18`, `Sources/CreatorGraph/UndoName.swift`
- Modify (format pins 8 → 9): `Tests/CreatorGraphTests/Comments/CommentFileTests.swift:64`, `Tests/CreatorGraphTests/Trees/TreeFileTests.swift:14,16,70-71`, `Tests/CreatorGraphTests/Images/ImageFileTests.swift:35,37,217-219`, `Tests/CreatorGraphTests/Groups/GroupFileTests.swift:38,40`, `Tests/CreatorGraphTests/ViewStateLibraryTests.swift:25`, `Tests/CreatorGraphTests/Implicit/ImplicitFileTests.swift:13-14`, `Tests/CreatorGraphTests/EdgePickFileTests.swift:31,33`
- Test: `Tests/CreatorGraphTests/Support/TieFixtures.swift`, `Tests/CreatorGraphTests/Ties/TieCommandTests.swift`, `Tests/CreatorGraphTests/Ties/TieFileTests.swift`

**Interfaces:**
- Consumes: `Graph`, `GraphCommand`, `Endpoint`, `Link`, `Vector2` (`isFinite`), `GraphError.invalidValue`, `GraphContent.apply`.
- Produces:
  - `public struct TieID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible { public let rawValue: UUID; init(rawValue: UUID = UUID()) }`.
  - `public struct CableTie: Hashable, Sendable, Identifiable, Codable { var id: TieID; var position: Vector2; var wires: Set<Endpoint>; init(id: TieID = TieID(), position:, wires:); static let minimumWires = 2 }`.
  - `extension Endpoint: Comparable`.
  - `Graph.ties: [TieID: CableTie]` and the `Graph.init(... frames:, ties: = [:])` parameter.
  - `GraphCommand.setTie(CableTie)` and `.removeTie(TieID)`.
  - `Graph.applyTie(_:)` (internal) and `Graph.repaired(_:links:)` (internal static).
  - `UndoName.tieWires/addToTie/moveTie/removeTie/untieWire`, and `GraphFile.currentFormatVersion == 9`.
  - Test fixtures `tieID(_:)`, `tie(_:_:at:)`, `tieNode(_:at:)` and `TieGraph`.

- [ ] **Step 1: Write the fixtures and the failing tests**

`Tests/CreatorGraphTests/Support/TieFixtures.swift`
```swift
// Test fixture file: cable tie fixtures shared by the tie tests.
import CreatorGeometry
import CreatorKernel
import Foundation
@testable import CreatorGraph

/// A tie ID whose sort order is `n`, so tests control the order ties are written in.
func tieID(_ n: Int) -> TieID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return TieID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID())
}

/// Tie `n` holding `wires` at `position` (stored coordinates).
func tie(_ n: Int, _ wires: [Endpoint], at position: Vector2 = Vector2(250, 150)) -> CableTie {
    CableTie(id: tieID(n), position: position, wires: Set(wires))
}

/// A test node of `definition` placed at `position`.
func tieNode(_ definition: any NodeDefinition.Type, at position: Vector2) -> Node {
    var node = makeNode(definition)
    node.position = position
    return node
}

/// Four constants feeding two adders, each wire into an adder's input: `s1a` (c1 → s1.a), `s1b` (c2 → s1.b), `s2a`
/// (c3 → s2.a) and `s2b` (c4 → s2.b). The nodes sit apart, so grouping any of c1, c2 and s1 puts the group's top-left at c1's
/// place, (100, 100).
struct TieGraph {
    let c1 = tieNode(ConstantNode.self, at: Vector2(100, 100))
    let c2 = tieNode(ConstantNode.self, at: Vector2(100, 200))
    let c3 = tieNode(ConstantNode.self, at: Vector2(100, 300))
    let c4 = tieNode(ConstantNode.self, at: Vector2(100, 400))
    let s1 = tieNode(AddNode.self, at: Vector2(400, 100))
    let s2 = tieNode(AddNode.self, at: Vector2(400, 300))

    var nodes: [Node] { [c1, c2, c3, c4, s1, s2] }
    var links: [Link] {
        [link(c1, "value", s1, "a"), link(c2, "value", s1, "b"), link(c3, "value", s2, "a"), link(c4, "value", s2, "b")]
    }
    var s1a: Endpoint { Endpoint(node: s1.id, socket: "a") }
    var s1b: Endpoint { Endpoint(node: s1.id, socket: "b") }
    var s2a: Endpoint { Endpoint(node: s2.id, socket: "a") }
    var s2b: Endpoint { Endpoint(node: s2.id, socket: "b") }

    /// The graph with `ties`, its links in canonical order (as commands and decoding keep them, so undo compares equal).
    func make(ties: [CableTie] = []) -> Graph {
        var made = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links,
                         ties: Dictionary(uniqueKeysWithValues: ties.map { ($0.id, $0) }))
        made.sortLinks()
        return made
    }

    @MainActor
    func document(ties: [CableTie] = []) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: make(ties: ties)), registry: testRegistry, kernel: FakeKernel())
    }
}
```

`Tests/CreatorGraphTests/Ties/TieCommandTests.swift`
```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// The two tie commands (cable ties spec 2026-10-26 §3.2): each is reversible, a refused one changes nothing, and neither
/// re-evaluates (ties are editor furniture).
@MainActor
struct TieCommandTests {
    let scene = TieGraph()

    @Test func settingAddsAndItsInverseRemoves() throws {
        var g = scene.make()
        let added = tie(1, [scene.s1a, scene.s1b])
        let inverse = try g.apply(.setTie(added), registry: testRegistry)
        #expect(g.ties == [added.id: added])
        #expect(inverse == .removeTie(added.id))
        try g.apply(inverse, registry: testRegistry)
        #expect(g == scene.make())
    }

    @Test func settingAgainReplacesWholeAndItsInverseRestoresTheOld() throws {
        let old = tie(1, [scene.s1a, scene.s1b])
        var g = scene.make(ties: [old])
        var changed = old
        changed.position = Vector2(260, 180)
        changed.wires.insert(scene.s2a)
        let inverse = try g.apply(.setTie(changed), registry: testRegistry)
        #expect(g.ties == [old.id: changed])
        #expect(inverse == .setTie(old))
        try g.apply(inverse, registry: testRegistry)
        #expect(g == scene.make(ties: [old]))
    }

    @Test func removingReturnsTheTieAndUndoPutsItBack() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b]), tie(2, [scene.s2a, scene.s2b])])
        var g = start
        let inverse = try g.apply(.removeTie(tieID(1)), registry: testRegistry)
        #expect(Set(g.ties.keys) == [tieID(2)])
        #expect(inverse == .setTie(tie(1, [scene.s1a, scene.s1b])))
        try g.apply(inverse, registry: testRegistry)
        #expect(g == start)
    }

    /// (I1) and (I2) are refused, not repaired: a command carries what the editor meant, and a wrong one is a bug to see.
    @Test func aBadTieIsRefusedAndChangesNothing() {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b])])
        let unwired = Endpoint(node: scene.c1.id, socket: "value")  // the constant's own input: no wire
        let refused: [GraphCommand] = [
            .setTie(tie(2, [scene.s1a])),
            .setTie(tie(2, [])),
            .setTie(tie(2, [scene.s1a, unwired])),
            .setTie(tie(2, [scene.s1a, scene.s1b], at: Vector2(.nan, 0))),
            .setTie(tie(2, [scene.s1a, scene.s1b], at: Vector2(0, .infinity))),
            .removeTie(tieID(9)),
            .batch([.setTie(tie(3, [scene.s2a, scene.s2b])), .removeTie(tieID(8))]),
        ]
        for command in refused {
            var g = start
            #expect(throws: GraphError.self) { try g.apply(command, registry: testRegistry) }
            #expect(g == start, "\(command)")
        }
    }

    @Test func tiesTouchNoNodeAndAffectNoResult() {
        let commands: [GraphCommand] = [.setTie(tie(1, [scene.s1a, scene.s1b])), .removeTie(tieID(1))]
        for command in commands {
            #expect(command.touchedNodes.isEmpty)
            #expect(!command.affectsResults)
        }
        #expect(!GraphCommand.batch(commands).affectsResults)
        #expect(GraphContent().affectsResults(.batch(commands)) == false)
    }

    @Test func aTieInsideADefinitionIsEditedThere() throws {
        let doubler = Doubler()
        let inside = tie(1, [Endpoint(node: doubler.add.id, socket: "a"), Endpoint(node: doubler.add.id, socket: "b")])
        var content = GraphContent(definitions: table([doubler.definition]))
        let inverse = try content.apply(GraphCommand.setTie(inside).at(.definition(doubler.id)), registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.ties == [inside.id: inside])
        #expect(content.graph.ties.isEmpty)
        #expect(inverse == .inDefinition(doubler.id, .removeTie(inside.id)))
        try content.apply(inverse, registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.ties.isEmpty == true)
    }

    @Test func theUndoNamesAreTheSpecs() {
        #expect([UndoName.tieWires, UndoName.addToTie, UndoName.moveTie, UndoName.removeTie, UndoName.untieWire]
                == ["Tie Wires", "Add to Tie", "Move Tie", "Remove Tie", "Untie Wire"])
    }

    @Test func endpointsAreOrderedByNodeThenSocket() {
        #expect([scene.s2b, scene.s1b, scene.s2a, scene.s1a].sorted()
                == [scene.s1a, scene.s1b, scene.s2a, scene.s2b].sorted { ($0.node, $0.socket) < ($1.node, $1.socket) })
        #expect(Endpoint(node: scene.s1.id, socket: "a") < Endpoint(node: scene.s1.id, socket: "b"))
    }
}
```

`Tests/CreatorGraphTests/Ties/TieFileTests.swift`
```swift
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// Ties are saved with their graph (cable ties spec 2026-10-26 §3.3): format 9, the key written only when there are some,
/// sorted by id with each tie's wires sorted, and decoding repairs (I1) and then (I2).
@MainActor
struct TieFileTests {
    let scene = TieGraph()

    func json(_ file: GraphFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try GraphFileIO.encode(file)) as? [String: Any])
    }

    func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    @Test func tiesRoundTripOnTheTopLevelAndInsideADefinition() throws {
        let doubler = Doubler()
        var definition = doubler.definition
        definition.graph.ties[tieID(5)] = tie(5, [Endpoint(node: doubler.add.id, socket: "a"),
                                                  Endpoint(node: doubler.add.id, socket: "b")])
        let top = scene.make(ties: [tie(1, [scene.s1a, scene.s1b]),
                                    tie(2, [scene.s1b, scene.s2a, scene.s2b], at: Vector2(-30.5, 1e6))])
        let file = GraphFile(graph: top, definitions: table([definition]))
        #expect(try reopened(file) == file)
    }

    @Test func tiesAreWrittenSortedByIDWithTheirWiresSorted() throws {
        let ids = [7, 3, 9, 1]
        let file = GraphFile(graph: scene.make(ties: ids.map { tie($0, [scene.s2b, scene.s1a, scene.s2a]) }))
        let graph = try #require(try json(file)["graph"] as? [String: Any])
        let written = try #require(graph["ties"] as? [[String: Any]])
        #expect(written.compactMap { $0["id"] as? String } == ids.sorted().map { tieID($0).rawValue.uuidString })
        let wires = try #require(written.first?["wires"] as? [[String: Any]])
        let sorted = [scene.s1a, scene.s2a, scene.s2b].sorted()
        #expect(wires.compactMap { $0["node"] as? String } == sorted.map(\.node.rawValue.uuidString))
        #expect(wires.compactMap { $0["socket"] as? String } == sorted.map(\.socket.rawValue))
        #expect(try GraphFileIO.encode(file) == GraphFileIO.encode(file), "deterministic")
    }

    @Test func aGraphWithoutTiesIsWrittenWithoutTheKey() throws {
        let graph = try #require(try json(GraphFile(graph: scene.make()))["graph"] as? [String: Any])
        #expect(graph["ties"] == nil)
    }

    /// (I1) first, then (I2): a wire that is no link's input goes, and a tie that is then left with one wire goes too.
    @Test func decodingDropsWiresThatAreNotThereAndThenSmallTies() throws {
        let gone = Endpoint(node: NodeID(), socket: "a")
        var written = scene.make()
        written.ties[tieID(1)] = tie(1, [scene.s1a, gone])
        written.ties[tieID(2)] = tie(2, [scene.s1a, scene.s1b, gone])
        written.ties[tieID(3)] = tie(3, [scene.s2a, scene.s2b])
        let decoded = try reopened(GraphFile(graph: written)).graph
        #expect(decoded.ties == [tieID(2): tie(2, [scene.s1a, scene.s1b]), tieID(3): tie(3, [scene.s2a, scene.s2b])])
    }

    @Test func aRepeatedTieIDKeepsTheFirst() throws {
        let first = tie(1, [scene.s1a, scene.s1b])
        var object = try json(GraphFile(graph: scene.make(ties: [first])))
        var graph = try #require(object["graph"] as? [String: Any])
        var written = try #require(graph["ties"] as? [[String: Any]])
        var copy = try #require(written.first)
        copy["position"] = ["x": 999, "y": 999]
        written.append(copy)
        graph["ties"] = written
        object["graph"] = graph
        let decoded = try GraphFileIO.decode(try JSONSerialization.data(withJSONObject: object), registry: testRegistry)
        #expect(decoded.graph.ties == [first.id: first])
    }

    @Test func aFormatEightFileHasNoTies() throws {
        let id = NodeID()
        let text = """
        {"formatVersion": 8, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"value": {"type": "number", "value": 2}}}]}}
        """
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.graph.ties.isEmpty)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(2))
    }

    @Test func filesAreWrittenAsFormatNineAndTenIsRefused() throws {
        #expect(GraphFile.currentFormatVersion == 9, "9: cable ties")
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 9"#))
        #expect(throws: GraphFileError.newerFormat(10)) {
            try GraphFileIO.decode(Data(#"{"formatVersion": 10, "graph": {"nodes": []}}"#.utf8), registry: testRegistry)
        }
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head`
Expected: errors such as "cannot find type 'CableTie' in scope" and "extra argument 'ties' in call".

- [ ] **Step 3: Write the model**

`Sources/CreatorGraph/Ties/TieID.swift`
```swift
import Foundation

/// Identity of a cable tie (cable ties spec 2026-10-26 §3.1), unique within its graph.
public struct TieID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: TieID, rhs: TieID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }

    public var description: String { String(rawValue.uuidString.prefix(8)) }
}
```

`Sources/CreatorGraph/Ties/CableTie.swift`
```swift
import CreatorGeometry

/// A cable tie (cable ties spec 2026-10-26 §3.1): a shared waypoint that the wires it holds run through side by side and
/// fan out after. Editor furniture: it never affects evaluation. `position` is in stored (left-to-right) canvas points, like a
/// node's; each wire is named by its input endpoint (`Link.to`), since an input takes at most one wire. `Graph.apply` keeps
/// every wire a link's input of the graph (I1) and every tie at `minimumWires` or more (I2); decoding repairs both
/// (`Graph.repaired`).
public struct CableTie: Hashable, Sendable, Identifiable {
    /// The fewest wires a tie holds (I2).
    public static let minimumWires = 2

    public var id: TieID
    public var position: Vector2
    public var wires: Set<Endpoint>

    public init(id: TieID = TieID(), position: Vector2, wires: Set<Endpoint>) {
        self.id = id
        self.position = position
        self.wires = wires
    }
}

/// Saved in `Graph.ties` (format 9) with its wires sorted, so the same tie is always the same bytes.
extension CableTie: Codable {
    private enum CodingKeys: String, CodingKey { case id, position, wires }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(TieID.self, forKey: .id),
                  position: try container.decode(Vector2.self, forKey: .position),
                  wires: Set(try container.decode([Endpoint].self, forKey: .wires)))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(position, forKey: .position)
        try container.encode(wires.sorted(), forKey: .wires)
    }
}
```

`Sources/CreatorGraph/Ties/Endpoint+Order.swift`
```swift
/// Endpoints in one fixed order, by node and then socket: how a tie's wires are written (cable ties spec §3.3) and how its
/// lanes are ordered when two targets are level (§5.1).
extension Endpoint: Comparable {
    public static func < (lhs: Endpoint, rhs: Endpoint) -> Bool { (lhs.node, lhs.socket) < (rhs.node, rhs.socket) }
}
```

`Sources/CreatorGraph/Ties/Graph+Ties.swift`
```swift
extension Graph {
    /// The two tie commands (cable ties spec 2026-10-26 §3.2), applied to this graph. Ties never affect evaluation
    /// (`GraphCommand.affectsResults`). `setTie` adds the tie or replaces it whole, so a move and an added wire are each one
    /// command carrying the tie's new value; its inverse carries the old. Refused, changing nothing: a position that isn't
    /// finite, fewer than two wires (I2), a wire that is no link's input here (I1), and removing a tie that isn't there.
    mutating func applyTie(_ command: GraphCommand) throws(GraphError) -> GraphCommand {
        switch command {
        case .setTie(let tie):
            try requireValid(tie)
            let old = ties.updateValue(tie, forKey: tie.id)
            return old.map { .setTie($0) } ?? .removeTie(tie.id)
        case .removeTie(let id):
            guard let old = ties.removeValue(forKey: id) else { throw .invalidValue("That tie is gone.") }
            return .setTie(old)
        default:
            throw .invalidValue("Not a tie edit.")  // `apply` routes only the two tie commands here.
        }
    }

    private func requireValid(_ tie: CableTie) throws(GraphError) {
        guard tie.position.isFinite else { throw .invalidValue("Enter a finite number.") }
        guard tie.wires.count >= CableTie.minimumWires else { throw .invalidValue("A tie holds at least two wires.") }
        guard tie.wires.isSubset(of: Set(links.map(\.to))) else { throw .invalidValue("A tie can only hold wires that are there.") }
    }

    /// The ties a file held, as a graph keeps them (cable ties spec §3.3): the first of a repeated ID, without the wires that
    /// are no input of `links` (I1), and then without the ties that left with fewer than two wires (I2).
    static func repaired(_ decoded: [CableTie], links: [Link]) -> [TieID: CableTie] {
        var ties: [TieID: CableTie] = [:]
        for tie in decoded where ties[tie.id] == nil {
            ties[tie.id] = tie
        }
        let wired = Set(links.map(\.to))
        return ties.compactMapValues { tie in
            var kept = tie
            kept.wires.formIntersection(wired)
            return kept.wires.count >= CableTie.minimumWires ? kept : nil
        }
    }
}
```

`Sources/CreatorGraph/Graph.swift` (whole file)
```swift
import CreatorKernel

/// The whole recipe: nodes, wires, document parameters, canvas comments and cable ties. Pure data.
public struct Graph: Sendable, Equatable {
    public var nodes: [NodeID: Node]
    public var links: [Link]
    public var parameters: [GraphParameter]
    /// Sticky notes and comment frames (canvas comments spec 2026-10-09 §7). Editor furniture: they never affect
    /// evaluation. A comment ID is in at most one of the two.
    public var stickies: [CommentID: StickyNote]
    public var frames: [CommentID: CommentFrame]
    /// Cable ties (cable ties spec 2026-10-26 §3). Editor furniture like the comments. Every wire a tie holds is a link's
    /// input here, and every tie holds two or more: `apply` keeps both, and decoding repairs both.
    public var ties: [TieID: CableTie]

    public init(nodes: [NodeID: Node] = [:], links: [Link] = [], parameters: [GraphParameter] = [],
                stickies: [CommentID: StickyNote] = [:], frames: [CommentID: CommentFrame] = [:],
                ties: [TieID: CableTie] = [:]) {
        self.nodes = nodes
        self.links = links
        self.parameters = parameters
        self.stickies = stickies
        self.frames = frames
        self.ties = ties
    }
}

extension Graph: Codable {
    private enum CodingKeys: String, CodingKey { case nodes, links, parameters, stickies, frames, ties }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode([Node].self, forKey: .nodes)
        nodes = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        links = try container.decodeIfPresent([Link].self, forKey: .links) ?? []
        parameters = try container.decodeIfPresent([GraphParameter].self, forKey: .parameters) ?? []
        // A hand-edited file may repeat an ID: the first one read wins, and a frame never takes a note's ID.
        var notes: [CommentID: StickyNote] = [:]
        for note in try container.decodeIfPresent([StickyNote].self, forKey: .stickies) ?? [] where notes[note.id] == nil {
            notes[note.id] = note
        }
        var boxes: [CommentID: CommentFrame] = [:]
        for box in try container.decodeIfPresent([CommentFrame].self, forKey: .frames) ?? []
        where boxes[box.id] == nil && notes[box.id] == nil {
            boxes[box.id] = box
        }
        stickies = notes
        frames = boxes
        // Format 9; absent before it. Repaired against the links just read (I1, then I2).
        ties = Self.repaired(try container.decodeIfPresent([CableTie].self, forKey: .ties) ?? [], links: links)
        sortLinks()  // Canonical order, so command + undo yields an equal graph.
    }

    /// Nodes are written as an array sorted by ID, so saved files diff cleanly.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes.values.sorted { $0.id < $1.id }, forKey: .nodes)
        try container.encode(links, forKey: .links)
        try container.encode(parameters, forKey: .parameters)
        // Comments are written, sorted by ID, only when there are some, so a graph without them is written as before.
        if !stickies.isEmpty { try container.encode(stickies.values.sorted { $0.id < $1.id }, forKey: .stickies) }
        if !frames.isEmpty { try container.encode(frames.values.sorted { $0.id < $1.id }, forKey: .frames) }
        // Ties likewise, each with its wires sorted (`CableTie.encode`), so the output is deterministic.
        if !ties.isEmpty { try container.encode(ties.values.sorted { $0.id < $1.id }, forKey: .ties) }
    }
}
```

`Sources/CreatorGraph/GraphCommand.swift`. Replace:
```swift
    case removeFrame(CommentID)
    /// Adds a group definition (the inverse of `removeDefinition`).
```
with:
```swift
    case removeFrame(CommentID)
    /// Adds a cable tie, or replaces the one with its ID whole (cable ties spec 2026-10-26 §3.2): a move and an added wire are
    /// each one of these carrying the tie's new value. Never affects evaluation.
    case setTie(CableTie)
    case removeTie(TieID)
    /// Adds a group definition (the inverse of `removeDefinition`).
```
Replace:
```swift
        case .setSticky, .removeSticky, .setFrame, .removeFrame: []
        case .inDefinition, .addDefinition, .removeDefinition, .setInterface: []
```
with:
```swift
        case .setSticky, .removeSticky, .setFrame, .removeFrame, .setTie, .removeTie: []
        case .inDefinition, .addDefinition, .removeDefinition, .setInterface: []
```
Replace:
```swift
        case .setSticky, .removeSticky, .setFrame, .removeFrame: false
        case .batch(let commands): commands.contains { $0.affectsResults }
```
with:
```swift
        case .setSticky, .removeSticky, .setFrame, .removeFrame, .setTie, .removeTie: false
        case .batch(let commands): commands.contains { $0.affectsResults }
```

`Sources/CreatorGraph/Graph+Commands.swift`. Replace:
```swift
        case .setSticky, .removeSticky, .setFrame, .removeFrame:
            return try applyComment(command)
```
with:
```swift
        case .setSticky, .removeSticky, .setFrame, .removeFrame:
            return try applyComment(command)

        case .setTie, .removeTie:
            return try applyTie(command)
```

`Sources/CreatorGraph/UndoName.swift`. Replace:
```swift
    // MARK: Groups (groups spec §5, §6)
```
with:
```swift
    // MARK: Cable ties (cable ties spec 2026-10-26 §3.2)
    public static let tieWires = "Tie Wires"
    public static let addToTie = "Add to Tie"
    public static let moveTie = "Move Tie"
    public static let removeTie = "Remove Tie"
    public static let untieWire = "Untie Wire"

    // MARK: Groups (groups spec §5, §6)
```

`Sources/CreatorGraph/GraphFile.swift`. Replace:
```swift
    /// computed, never saved. Version-1 to -7 files open unchanged and are written as 8.
    public static let currentFormatVersion = 8
```
with:
```swift
    /// computed, never saved. 9: cable ties (`Graph.ties`, cable ties spec 2026-10-26 §3.3), written only when a graph has some,
    /// sorted by ID with each tie's wires sorted; a version-8 reader would drop them when it saved, so it refuses the file
    /// instead. Version-1 to -8 files open unchanged and are written as 9.
    public static let currentFormatVersion = 9
```

Format pins (each is a test that names the current format; they move with it):
- `Tests/CreatorGraphTests/Comments/CommentFileTests.swift`: replace `#expect(GraphFile.currentFormatVersion == 8, "5: the comments' keys; 6: tree nodes' text settings; 7: images; 8: implicit sockets")` with `#expect(GraphFile.currentFormatVersion == 9, "5: the comments' keys; 6: tree nodes' text settings; 7: images; 8: implicit sockets; 9: cable ties")`.
- `Tests/CreatorGraphTests/Trees/TreeFileTests.swift`: in `savedFilesAreTheCurrentFormat`, `== 8` becomes `== 9` and `#""formatVersion" : 8"#` becomes `#""formatVersion" : 9"#`. In `aNewerFileIsStillRefusedWithItsVersion`, `newerFormat(9)` becomes `newerFormat(10)` and `{"formatVersion": 9, ` becomes `{"formatVersion": 10, `.
- `Tests/CreatorGraphTests/Images/ImageFileTests.swift`: `#expect(GraphFile.currentFormatVersion == 8)` becomes `== 9` and `#expect(object["formatVersion"] as? Int == 8)` becomes `== 9`. In `aNewerFormatIsRefusedWithTheExistingMessage`, `"\"formatVersion\" : 9"` becomes `"\"formatVersion\" : 10"`, both `newerFormat(9)` become `newerFormat(10)`, and `(file format 9).` becomes `(file format 10).`.
- `Tests/CreatorGraphTests/Groups/GroupFileTests.swift` and `Tests/CreatorGraphTests/EdgePickFileTests.swift`: `== 8` becomes `== 9` and `#""formatVersion" : 8"#` becomes `#""formatVersion" : 9"#`.
- `Tests/CreatorGraphTests/ViewStateLibraryTests.swift`: `#expect(GraphFile.currentFormatVersion == 8, "S4, groups, trees, images and implicit sockets bumped it; the library's key did not")` becomes `#expect(GraphFile.currentFormatVersion == 9, "S4, groups, trees, images, implicit sockets and cable ties bumped it; the library's key did not")`.
- `Tests/CreatorGraphTests/Implicit/ImplicitFileTests.swift`: `@Test func theFormatIsEight() {` / `#expect(GraphFile.currentFormatVersion == 8)` become `@Test func theFormatIsNine() {` / `#expect(GraphFile.currentFormatVersion == 9, "9: cable ties, after 8's implicit sockets")`.
- `Tests/CreatorGraphTests/MessageTests.swift` keeps `newerFormat(9)`: it pins the sentence, not the current format.

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter CreatorGraphTests 2>&1 | tail -3`
Expected: passes, including `TieCommandTests` and `TieFileTests`.
Run: `grep -rnE 'currentFormatVersion == 8|"formatVersion" : 8|newerFormat\(9\)' Tests | grep -v MessageTests`
Expected: no output.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: `Done linting! Found 0 violations, 0 serious in … files.`

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): cable ties in the graph, setTie and removeTie, file format 9" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

---

### Task 2: Wires leave their ties when they go

Spec §3.2, "Wires leaving ties automatically". Ruling R1.

**Files:**
- Modify: `Sources/CreatorGraph/Graph+Commands.swift:16-55` (removeNode, connect, disconnect), `Sources/CreatorGraph/Ties/Graph+Ties.swift`
- Test: `Tests/CreatorGraphTests/Ties/TieStrippingTests.swift`

**Interfaces:**
- Consumes: Task 1's `Graph.ties`, `CableTie.minimumWires`, `.setTie`.
- Produces:
  - `Graph.stripTies(holding: Set<Endpoint>) -> [GraphCommand]` (internal, mutating): the `setTie(old)` commands that restore the touched ties, in tie-ID order.
  - `Graph.restoring(_ inverse: GraphCommand, ties: [GraphCommand]) -> GraphCommand` (internal static).
  - The new inverse shapes: `removeNode` → `restoreNode` or `.batch([restoreNode] + setTies)`; `disconnect` → `restoreLinks` or `.batch([restoreLinks] + setTies)`; replacing `connect` → `.batch([.disconnect, .restoreLinks] + setTies)`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/Ties/TieStrippingTests.swift`
```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Removing a node, a disconnect and a connect that replaces a wire take the wires they remove out of every tie in the same
/// command, a tie left with fewer than two wires goes (I2), and undo puts every tie back exactly (cable ties spec §3.2).
@MainActor
struct TieStrippingTests {
    let scene = TieGraph()

    func applying(_ command: GraphCommand, to start: Graph) throws -> (graph: Graph, inverse: GraphCommand) {
        var g = start
        let inverse = try g.apply(command, registry: testRegistry)
        return (g, inverse)
    }

    func undone(_ applied: (graph: Graph, inverse: GraphCommand)) throws -> Graph {
        var g = applied.graph
        try g.apply(applied.inverse, registry: testRegistry)
        return g
    }

    @Test func removingANodeTakesTheWiresIntoItOutOfTheirTies() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a]), tie(2, [scene.s2a, scene.s2b])])
        let removed = try applying(.removeNode(scene.s1.id), to: start)
        #expect(removed.graph.ties[tieID(1)] == nil, "left with one wire, the tie goes")
        #expect(removed.graph.ties[tieID(2)] == start.ties[tieID(2)], "a tie the node never reached is untouched")
        #expect(try undone(removed) == start)
    }

    @Test func aWireOutOfARemovedNodeLeavesItsTiesToo() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a])])
        let removed = try applying(.removeNode(scene.c3.id), to: start)
        #expect(removed.graph.ties[tieID(1)]?.wires == [scene.s1a, scene.s1b])
        #expect(try undone(removed) == start)
    }

    @Test func withNoTieReachedTheInverseIsAsBefore() throws {
        let start = scene.make(ties: [tie(1, [scene.s2a, scene.s2b])])
        let removed = try applying(.removeNode(scene.s1.id), to: start)
        #expect(removed.inverse == .restoreNode(scene.s1, links: [link(scene.c1, "value", scene.s1, "a"),
                                                                link(scene.c2, "value", scene.s1, "b")]))
        let cut = try applying(.disconnect(link(scene.c1, "value", scene.s1, "a")), to: start)
        #expect(cut.inverse == .restoreLinks([link(scene.c1, "value", scene.s1, "a")]))
    }

    @Test func disconnectingAWireTakesItOutOfItsTies() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a])])
        let cut = try applying(.disconnect(link(scene.c1, "value", scene.s1, "a")), to: start)
        #expect(cut.graph.ties[tieID(1)]?.wires == [scene.s1b, scene.s2a])
        #expect(try undone(cut) == start)
    }

    /// The new wire lands on the same input the old one left, so it is the same endpoint: it is still never tied implicitly.
    @Test func aReplacingConnectUntiesTheOldWireAndNeverTiesTheNewOne() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b])])
        let replaced = try applying(.connect(link(scene.c3, "value", scene.s1, "a")), to: start)
        #expect(replaced.graph.incomingLink(to: scene.s1a)?.from.node == scene.c3.id)
        #expect(replaced.graph.ties.isEmpty, "the replaced wire left, and one wire is no tie")
        #expect(try undone(replaced) == start)
    }

    @Test func aNewConnectOnAFreeInputLeavesTiesAlone() throws {
        var start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b])])
        start.links.removeAll { $0.to == scene.s2b }
        let connected = try applying(.connect(link(scene.c4, "value", scene.s2, "b")), to: start)
        #expect(connected.graph.ties == start.ties)
        #expect(connected.inverse == .disconnect(link(scene.c4, "value", scene.s2, "b")))
    }

    @Test func undoAndRedoThroughTheDocumentRestoreTiesExactly() throws {
        let start = scene.make(ties: [tie(1, [scene.s1a, scene.s1b, scene.s2a])])
        let document = DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
        try document.perform(.batch([.removeNode(scene.c1.id), .removeNode(scene.s2.id)]), name: UndoName.delete)
        let after = document.graph
        #expect(after.ties.isEmpty, "c1 took s1a, s2 took s2a, and one wire is no tie")
        document.undo()
        #expect(document.graph == start)
        document.redo()
        #expect(document.graph == after)
        document.undo()
        #expect(document.graph == start)
    }

    @Test func insideADefinitionTheSameHolds() throws {
        let doubler = Doubler()
        var definition = doubler.definition
        definition.graph.ties[tieID(1)] = tie(1, [Endpoint(node: doubler.add.id, socket: "a"),
                                                  Endpoint(node: doubler.add.id, socket: "b")])
        var content = GraphContent(definitions: table([definition]))
        let before = content
        let unwire = GraphCommand.disconnect(link(doubler.input, "value", doubler.add, "a")).at(.definition(doubler.id))
        let inverse = try content.apply(unwire, registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.ties.isEmpty == true)
        try content.apply(inverse, registry: testRegistry)
        #expect(content == before)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter TieStrippingTests 2>&1 | grep -E "recorded an issue|passed|failed" | head`
Expected: failures, such as `removed.graph.ties[tieID(1)] == nil` recording an issue (the tie still holds the removed wires).

- [ ] **Step 3: Strip in the three commands**

Append to `Sources/CreatorGraph/Ties/Graph+Ties.swift`, inside the extension, after `repaired`:
```swift

    /// Takes `wires` out of every tie that holds one, removing a tie left with fewer than two (I2), and returns the
    /// commands that put each touched tie back as it was, in tie-ID order (cable ties spec §3.2). An inverse runs them after
    /// it has restored the wires, so each passes (I1).
    mutating func stripTies(holding wires: Set<Endpoint>) -> [GraphCommand] {
        guard !wires.isEmpty else { return [] }
        var restores: [GraphCommand] = []
        for id in ties.keys.sorted() {
            guard var tie = ties[id], !tie.wires.isDisjoint(with: wires) else { continue }
            restores.append(.setTie(tie))
            tie.wires.subtract(wires)
            ties[id] = tie.wires.count >= CableTie.minimumWires ? tie : nil
        }
        return restores
    }

    /// `inverse`, followed by the tie restores when wires left ties, as one command (one undo step). With none it is
    /// `inverse` itself, so a command that reached no tie undoes exactly as it always did.
    static func restoring(_ inverse: GraphCommand, ties restores: [GraphCommand]) -> GraphCommand {
        restores.isEmpty ? inverse : .batch([inverse] + restores)
    }
```

`Sources/CreatorGraph/Graph+Commands.swift`. Replace:
```swift
            let removed = links.filter { $0.from.node == id || $0.to.node == id }
            links.removeAll { $0.from.node == id || $0.to.node == id }
            nodes[id] = nil
            sortLinks()
            return .restoreNode(node, links: removed)
```
with:
```swift
            let removed = links.filter { $0.from.node == id || $0.to.node == id }
            links.removeAll { $0.from.node == id || $0.to.node == id }
            nodes[id] = nil
            // Every wire into or out of the node leaves its ties (cable ties spec §3.2).
            let ties = stripTies(holding: Set(removed.map(\.to)))
            sortLinks()
            return Self.restoring(.restoreNode(node, links: removed), ties: ties)
```
Replace:
```swift
            if let replaced {
                return .batch([.disconnect(link), .restoreLinks([replaced])])
            }
            return .disconnect(link)
```
with:
```swift
            if let replaced {
                // The replaced wire leaves its ties; the new one on the same input is never tied implicitly.
                let ties = stripTies(holding: [link.to])
                return .batch([.disconnect(link), .restoreLinks([replaced])] + ties)
            }
            return .disconnect(link)
```
Replace:
```swift
            guard links.contains(link) else { throw .linkNotFound }
            links.removeAll { $0 == link }
            sortLinks()
            return .restoreLinks([link])
```
with:
```swift
            guard links.contains(link) else { throw .linkNotFound }
            links.removeAll { $0 == link }
            let ties = stripTies(holding: [link.to])
            sortLinks()
            return Self.restoring(.restoreLinks([link]), ties: ties)
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter CreatorGraphTests 2>&1 | tail -3`
Expected: passes. Every older graph test passes unchanged: an inverse that reached no tie has its old shape.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(graph): removing a node or a wire takes it out of its ties, and undo puts them back`, with the two trailer lines)

---

### Task 3: Ties through Group, Ungroup and Make Unique

Spec §4.5. Ruling R11.

**Files:**
- Modify: `Sources/CreatorGraph/Groups/GroupBuilder.swift:34`, `Sources/CreatorGraph/Groups/GroupCommands+Ungroup.swift`, `Sources/CreatorGraph/Groups/GroupCommands+MakeUnique.swift:29-31`
- Test: `Tests/CreatorGraphTests/Ties/TieGroupTests.swift`

**Interfaces:**
- Consumes: Task 1's `Graph.ties`, `.setTie`; Task 2's strip in `removeNode`; `GroupSplice.endpoint(_:)`, `GroupSplice.links`.
- Produces: `GroupCommands.tiesSplicedOut(of:by:offset:) -> [GraphCommand]` (internal static).

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/Ties/TieGroupTests.swift`
```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Ties follow Group, Ungroup and Make Unique (cable ties spec 2026-10-26 §4.5): a tie goes inside a new group only when every
/// wire it holds does, a wire that crosses the boundary leaves its tie, Ungroup brings a definition's ties back out on the
/// spliced copies, and Make Unique gives the copy ties of its own.
@MainActor
struct TieGroupTests {
    let scene = TieGraph()

    func group(_ ids: Set<NodeID>, in document: DocumentModel) throws -> GroupEdit {
        let edit = try GroupCommands.group(ids, in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command, name: UndoName.group)
        return edit
    }

    @Test func groupingEveryWireOfATieMovesItInside() throws {
        let held = tie(1, [scene.s1a, scene.s1b], at: Vector2(250, 150))
        let document = scene.document(ties: [held])
        let before = document.content
        _ = try group([scene.c1.id, scene.c2.id, scene.s1.id], in: document)
        let definition = try #require(document.definitions.values.first)
        #expect(definition.graph.ties == [held.id: CableTie(id: held.id, position: Vector2(150, 50), wires: held.wires)],
                "moved like the nodes, relative to their top-left (100, 100)")
        #expect(document.graph.ties.isEmpty)
        document.undo()
        #expect(document.content == before, "one undo step")
    }

    @Test func aTieWithWiresOutsideKeepsThoseAndStaysOutside() throws {
        let held = tie(1, [scene.s1a, scene.s2a, scene.s2b])
        let document = scene.document(ties: [held])
        _ = try group([scene.c1.id, scene.c2.id, scene.s1.id], in: document)
        #expect(document.graph.ties[held.id]?.wires == [scene.s2a, scene.s2b])
        #expect(document.definitions.values.first?.graph.ties.isEmpty == true)
    }

    /// Grouping c1 and s1: `s1a` moves inside, `s1b` crosses in from c2 outside. Both leave, and one wire is no tie.
    @Test func aWireCrossingTheBoundaryLeavesItsTie() throws {
        let document = scene.document(ties: [tie(1, [scene.s1a, scene.s1b])])
        _ = try group([scene.c1.id, scene.s1.id], in: document)
        #expect(document.graph.ties.isEmpty)
        #expect(document.definitions.values.first?.graph.ties.isEmpty == true)
    }

    @Test func ungroupingBringsTheTiesBackOutOnTheCopies() throws {
        let held = tie(1, [scene.s1a, scene.s1b], at: Vector2(250, 150))
        let document = scene.document(ties: [held])
        let grouped = try group([scene.c1.id, scene.c2.id, scene.s1.id], in: document)
        let node = try #require(grouped.selection.first)
        let edit = try GroupCommands.ungroup(node, in: .root, of: document.content, registry: testRegistry)
        try document.perform(edit.command, name: UndoName.ungroup)
        let add = try #require(edit.selection.compactMap { document.graph.nodes[$0] }.first { $0.typeID == AddNode.typeID })
        #expect(document.graph.ties.count == 1)
        let back = try #require(document.graph.ties.values.first)
        #expect(back.wires == [Endpoint(node: add.id, socket: "a"), Endpoint(node: add.id, socket: "b")])
        #expect(back.position == Vector2(250, 150), "moved by the group node, which stood at the nodes' top-left")
        #expect(back.id != held.id, "a fresh ID, like the spliced nodes'")
        document.undo()
        #expect(document.definitions.values.first?.graph.ties.count == 1, "undo puts it back inside")
    }

    /// Doubler's Group Input feeds both of Add's inputs. Ungrouping an instance whose input is a typed value writes the
    /// value onto them, so no wire is left to tie; one fed by a wire keeps both inner wires, so the tie comes out.
    @Test func aWireThatBecomesAValueOnUngroupLeavesItsTie() throws {
        var doubler = Doubler()
        doubler.definition.graph.ties[tieID(1)] = tie(1, [Endpoint(node: doubler.add.id, socket: "a"),
                                                          Endpoint(node: doubler.add.id, socket: "b")])
        let unwired = instance(of: doubler.definition, ["value": .number(4)])
        let wired = instance(of: doubler.definition)
        let constant = tieNode(ConstantNode.self, at: Vector2(-300, 0))
        var start = graph([unwired, wired, constant], [link(constant, "value", wired, "value")])
        start.sortLinks()
        let document = DocumentModel(file: GraphFile(graph: start, definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        let fromValue = try GroupCommands.ungroup(unwired.id, in: .root, of: document.content, registry: testRegistry)
        try document.perform(fromValue.command, name: UndoName.ungroup)
        #expect(document.graph.ties.isEmpty, "Group Input fed nothing: the inner wires became values")
        let fromWire = try GroupCommands.ungroup(wired.id, in: .root, of: document.content, registry: testRegistry)
        try document.perform(fromWire.command, name: UndoName.ungroup)
        let add = try #require(fromWire.selection.first.flatMap { document.graph.nodes[$0] })
        #expect(document.graph.ties.values.map(\.wires)
                == [[Endpoint(node: add.id, socket: "a"), Endpoint(node: add.id, socket: "b")]])
    }

    @Test func makeUniqueGivesTheCopyItsOwnTies() throws {
        var doubler = Doubler()
        let inner = tie(1, [Endpoint(node: doubler.add.id, socket: "a"), Endpoint(node: doubler.add.id, socket: "b")])
        doubler.definition.graph.ties[inner.id] = inner
        let node = instance(of: doubler.definition)
        var content = GraphContent(graph: graph([node]), definitions: table([doubler.definition]))
        let edit = try GroupCommands.makeUnique(node.id, in: .root, of: content, registry: testRegistry)
        try content.apply(edit.command, registry: testRegistry)
        let copy = try #require(content.definitions.values.first { $0.id != doubler.id })
        let copiedAdd = try #require(copy.graph.nodes.values.first { $0.typeID == AddNode.typeID })
        #expect(copy.graph.ties[inner.id]?.wires == [Endpoint(node: copiedAdd.id, socket: "a"),
                                                     Endpoint(node: copiedAdd.id, socket: "b")])
        #expect(content.definitions[doubler.id]?.graph.ties == [inner.id: inner], "the original keeps its own")
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter TieGroupTests 2>&1 | grep -cE "recorded an issue"`
Expected: a non-zero count. The tie is lost by Group, and the copy's tie names the old nodes.

- [ ] **Step 3: Write the group rules**

`Sources/CreatorGraph/Groups/GroupBuilder.swift`. Replace:
```swift
        definition.graph.links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
        self.graph = graph
```
with:
```swift
        definition.graph.links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
        // A tie goes inside when every wire it holds does, moved like the nodes (cable ties spec §4.5). Removing the grouped
        // nodes takes their wires, inner and crossing, out of every other tie (`Graph.stripTies`).
        let inner = Set(definition.graph.links.map(\.to))
        for tie in graph.ties.values where tie.wires.isSubset(of: inner) {
            definition.graph.ties[tie.id] = CableTie(id: tie.id, position: tie.position - topLeft, wires: tie.wires)
        }
        self.graph = graph
```

`Sources/CreatorGraph/Groups/GroupCommands+Ungroup.swift`. Replace `import CreatorKernel` (line 1) with:
```swift
import CreatorGeometry
import CreatorKernel
```
Replace:
```swift
        let here: [GraphCommand] = [.removeNode(id)] + splice.nodes.values.sorted { $0.id < $1.id }.map { .addNode($0) }
            + (splice.links.isEmpty ? [] : [.restoreLinks(splice.links)]) + settings + comments
```
with:
```swift
        let here: [GraphCommand] = [.removeNode(id)] + splice.nodes.values.sorted { $0.id < $1.id }.map { .addNode($0) }
            + (splice.links.isEmpty ? [] : [.restoreLinks(splice.links)]) + settings + comments
            + tiesSplicedOut(of: definition, by: splice, offset: offset)
```
Add, inside the same extension, after `ungroup(_:in:of:registry:)`:
```swift

    /// The definition's ties as Ungroup brings them out (cable ties spec §4.5). Each wire is moved onto the spliced copy of
    /// its node, and kept only where the splice wires it: a wire Group Input fed from nothing outside became a value, so it
    /// leaves. Each tie is moved by the group node's position like the nodes and gets a fresh ID; a tie left with fewer than
    /// two wires stays behind. The outer level's wires into and out of the group node have already left their ties with it
    /// (`Graph.stripTies` in `removeNode`), as Group's crossing wires do.
    static func tiesSplicedOut(of definition: GroupDefinition, by splice: GroupSplice, offset: Vector2) -> [GraphCommand] {
        let wired = Set(splice.links.map(\.to))
        return definition.graph.ties.values.sorted { $0.id < $1.id }.compactMap { tie in
            let wires = Set(tie.wires.compactMap { splice.endpoint($0) }).intersection(wired)
            guard wires.count >= CableTie.minimumWires else { return nil }
            return .setTie(CableTie(position: tie.position + offset, wires: wires))
        }
    }
```

`Sources/CreatorGraph/Groups/GroupCommands+MakeUnique.swift`. Replace:
```swift
        copy.graph.stickies = definition.graph.stickies
        copy.graph.frames = definition.graph.frames
```
with:
```swift
        copy.graph.stickies = definition.graph.stickies
        copy.graph.frames = definition.graph.frames
        // Its ties too, each wire on the copy of its node (cable ties spec §4.5).
        copy.graph.ties = definition.graph.ties.mapValues { tie in
            CableTie(id: tie.id, position: tie.position, wires: Set(tie.wires.compactMap { wire in
                fresh[wire.node].map { Endpoint(node: $0, socket: wire.socket) }
            }))
        }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter CreatorGraphTests 2>&1 | tail -3`
Expected: passes (every group test too).
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(graph): ties follow Group, Ungroup and Make Unique`, with the two trailer lines)

---

### Task 4: The taut route, tie lanes and bands (pure geometry)

Spec §5.1 (route, tie order, lanes, band, culling bounds).

**Files:**
- Modify: `Sources/CreatorEditor/WireGeometry.swift` (whole file)
- Create: `Sources/CreatorEditor/WireRoute.swift`, `Sources/CreatorEditor/TieLayout.swift`, `Sources/CreatorEditor/WireRouting.swift`, `Sources/CreatorEditor/EditorModel+Wires.swift`
- Modify: `Tests/CreatorEditorTests/Support/EditorModelTestSupport.swift:8-17`
- Test: `Tests/CreatorEditorTests/Support/TieScene.swift`, `Tests/CreatorEditorTests/WireRouteTests.swift`

**Interfaces:**
- Consumes: `CableTie`, `TieID`, `Endpoint: Comparable` (Task 1); `CanvasFlow`, `CanvasRect`, `EditorModel.anchor(of:)`, `SocketRef(_:isInput:)`.
- Produces:
  - `WireGeometry` is now `Hashable`, with `init(start:control1:control2:end:)`, `point(at:) -> Vector2` and `static bounds(of: [WireGeometry], padding:) -> CanvasRect`.
  - `public struct WireRoute: Equatable, Sendable { var wire: Endpoint; var pieces: [WireGeometry]; init(wire:through:flow:); init(wire:pieces:); pinned: [Vector2]; samples: [Vector2]; middle: Vector2; bounds(padding:) -> CanvasRect; distance(to:) -> Double; pointsInside(_:) -> [Vector2]; intersects(_:) -> Bool; static samplesPerPiece = 24 }`.
  - `public struct TieLayout: Equatable, Sendable { id: TieID; lanes: [Endpoint: Vector2]; band: CanvasRect; static laneSpacing = 4, bandLength = 6, bandOverhang = 3; init(_ tie: CableTie, inputs: [Endpoint: Vector2], flow: CanvasFlow) }`.
  - `public struct WireRouting: Equatable, Sendable { routes: [Endpoint: WireRoute]; ties: [TieID: TieLayout]; init(links:ties:outputs:inputs:flow:) }`.
  - `EditorModel.wireRouting: WireRouting`.
  - Test support: `makeEditor(..., ties: [CableTie] = [], dock:, registry:)`, `TieScene`, `tieID(_:)`.

- [ ] **Step 1: Write the test support and the failing tests**

`Tests/CreatorEditorTests/Support/EditorModelTestSupport.swift`. Replace:
```swift
func makeEditor(_ nodes: [Node], _ links: [Link] = [], parameters: [GraphParameter] = [],
                stickies: [StickyNote] = [], frames: [CommentFrame] = [],
                dock: DockSide = .bottom, registry: NodeRegistry = editorTestRegistry) -> EditorModel {
    let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links, parameters: parameters,
                      stickies: Dictionary(uniqueKeysWithValues: stickies.map { ($0.id, $0) }),
                      frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) }))
```
with:
```swift
func makeEditor(_ nodes: [Node], _ links: [Link] = [], parameters: [GraphParameter] = [],
                stickies: [StickyNote] = [], frames: [CommentFrame] = [], ties: [CableTie] = [],
                dock: DockSide = .bottom, registry: NodeRegistry = editorTestRegistry) -> EditorModel {
    var graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links, parameters: parameters,
                      stickies: Dictionary(uniqueKeysWithValues: stickies.map { ($0.id, $0) }),
                      frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) }),
                      ties: Dictionary(uniqueKeysWithValues: ties.map { ($0.id, $0) }))
    graph.sortLinks()  // As a loaded file has them, so undo compares equal.
```

`Tests/CreatorEditorTests/Support/TieScene.swift`
```swift
// Test fixture file: three wires straight across the canvas, for the cable tie tests.
import CreatorGeometry
import CreatorGraph
import Foundation
@testable import CreatorEditor

/// Three Number nodes on the left wired across to three on the right, each pair level, so at zoom 1 with no pan each wire's
/// taut route is a straight horizontal line: `upper` from (168, 60) to (600, 60), `lower` from (168, 260) to (600, 260) and
/// `third` from (168, 460) to (600, 460). `upperMiddle`, `lowerMiddle` and `thirdMiddle` are halfway along them, clear of
/// every node. `tie()` holds `upper` and `lower` at (384, 160): its lanes are (384, 158) and (384, 162), and its band runs
/// from (381, 155) to (387, 165).
@MainActor
struct TieScene {
    let a1 = testNode(NumberTestNode.self, id: 1, at: Vector2(0, 0))
    let a2 = testNode(NumberTestNode.self, id: 2, at: Vector2(0, 200))
    let b1 = testNode(NumberTestNode.self, id: 3, at: Vector2(600, 20))
    let b2 = testNode(NumberTestNode.self, id: 4, at: Vector2(600, 220))
    let a3 = testNode(NumberTestNode.self, id: 5, at: Vector2(0, 400))
    let b3 = testNode(NumberTestNode.self, id: 6, at: Vector2(600, 420))
    let upperMiddle = Vector2(384, 60)
    let lowerMiddle = Vector2(384, 260)
    let thirdMiddle = Vector2(384, 460)

    var nodes: [Node] { [a1, a2, b1, b2, a3, b3] }
    var links: [Link] { [wire(a1, "value", b1, "value"), wire(a2, "value", b2, "value"), wire(a3, "value", b3, "value")] }
    var upper: Endpoint { Endpoint(node: b1.id, socket: "value") }
    var lower: Endpoint { Endpoint(node: b2.id, socket: "value") }
    var third: Endpoint { Endpoint(node: b3.id, socket: "value") }

    /// Tie `n` at `position` (stored coordinates), holding `wires` (`upper` and `lower` when not given).
    func tie(_ n: Int = 1, at position: Vector2 = Vector2(384, 160), holding wires: Set<Endpoint>? = nil) -> CableTie {
        CableTie(id: tieID(n), position: position, wires: wires ?? [upper, lower])
    }

    func editor(ties: [CableTie] = [], stickies: [StickyNote] = [], frames: [CommentFrame] = [],
                dock: DockSide = .bottom) -> EditorModel {
        makeEditor(nodes, links, stickies: stickies, frames: frames, ties: ties, dock: dock)
    }
}

/// A tie ID whose sort order is `n`, so tests control the draw order.
func tieID(_ n: Int) -> TieID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return TieID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID())
}
```

`Tests/CreatorEditorTests/WireRouteTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The taut route (cable ties spec 2026-10-26 §5.1): an untied wire is today's one cubic; a tied one is a chain of cubics
/// through each tie's lane, meeting ties in stored flow order and then by ID, joining tangent-continuously at every lane;
/// lanes are 4 points apart across the flow in target order; the band is 6 points along the flow and 3 beyond the outer
/// lanes.
@MainActor
struct WireRouteTests {
    let source1 = Endpoint(node: nodeID(1), socket: "value"), source2 = Endpoint(node: nodeID(2), socket: "value")
    let source3 = Endpoint(node: nodeID(5), socket: "value")
    let upper = Endpoint(node: nodeID(3), socket: "value"), lower = Endpoint(node: nodeID(4), socket: "value")
    let third = Endpoint(node: nodeID(6), socket: "value")

    var links: [Link] { [Link(from: source1, to: upper), Link(from: source2, to: lower), Link(from: source3, to: third)] }
    var outputs: [Endpoint: Vector2] { [source1: Vector2(168, 60), source2: Vector2(168, 260), source3: Vector2(168, 460)] }
    var inputs: [Endpoint: Vector2] { [upper: Vector2(600, 60), lower: Vector2(600, 260), third: Vector2(600, 460)] }

    func routing(_ ties: [CableTie], flow: CanvasFlow = .horizontal) -> WireRouting {
        WireRouting(links: links, ties: Dictionary(uniqueKeysWithValues: ties.map { ($0.id, $0) }), outputs: outputs,
                    inputs: inputs, flow: flow)
    }

    func tie(_ n: Int, at position: Vector2, _ wires: Set<Endpoint>) -> CableTie {
        CableTie(id: tieID(n), position: position, wires: wires)
    }

    @Test func anUntiedRouteIsTodaysOneCubic() throws {
        let route = try #require(routing([]).routes[upper])
        #expect(route.pieces == [WireGeometry(from: Vector2(168, 60), to: Vector2(600, 60), flow: .horizontal)])
        #expect(route.pinned == [Vector2(168, 60), Vector2(600, 60)])
    }

    @Test func aTiedRouteRunsThroughItsLane() throws {
        let routed = routing([tie(1, at: Vector2(384, 160), [upper, lower])])
        let route = try #require(routed.routes[upper])
        #expect(route.pinned == [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)])
        #expect(route.pieces == [WireGeometry(from: Vector2(168, 60), to: Vector2(384, 158), flow: .horizontal),
                                 WireGeometry(from: Vector2(384, 158), to: Vector2(600, 60), flow: .horizontal)])
        #expect(routed.routes[lower]?.pinned == [Vector2(168, 260), Vector2(384, 162), Vector2(600, 260)])
        #expect(routed.routes[third]?.pieces.count == 1, "a wire the tie doesn't hold is untouched")
    }

    @Test func theRouteMeetsItsTiesInStoredFlowOrderThenByID() throws {
        let ordered = routing([tie(1, at: Vector2(450, 100), [upper, lower]), tie(2, at: Vector2(300, 100), [upper, lower])])
        #expect(ordered.routes[upper]?.pinned
                == [Vector2(168, 60), Vector2(300, 98), Vector2(450, 98), Vector2(600, 60)], "by position.x, not by ID")
        let level = routing([tie(2, at: Vector2(384, 100), [upper, lower]), tie(1, at: Vector2(384, 300), [upper, lower])])
        #expect(level.routes[upper]?.pinned
                == [Vector2(168, 60), Vector2(384, 298), Vector2(384, 98), Vector2(600, 60)], "level ties go by ID")
    }

    /// Each piece enters its end and leaves its start along the flow, so at every lane the incoming and outgoing tangents
    /// point the same way along the flow (G1), whichever way the lane lies, behind the source included.
    @Test func thePiecesJoinTangentContinuouslyAtEveryLaneEvenBehindTheSource() throws {
        for flow in [CanvasFlow.horizontal, .vertical] {
            let ties = [tie(1, at: Vector2(384, 160), [upper, lower]), tie(2, at: Vector2(100, 900), [upper, lower])]
            let route = try #require(routing(ties, flow: flow).routes[upper])
            #expect(route.pieces.count == 3)
            for (piece, next) in zip(route.pieces, route.pieces.dropFirst()) {
                #expect(piece.end == next.start)
                let incoming = piece.end - piece.control2, outgoing = next.control1 - next.start
                if flow == .horizontal {
                    #expect(incoming.y == 0 && outgoing.y == 0 && incoming.x > 0 && outgoing.x > 0, "\(flow)")
                } else {
                    #expect(incoming.x == 0 && outgoing.x == 0 && incoming.y > 0 && outgoing.y > 0, "\(flow)")
                }
            }
            let bounds = route.bounds(padding: 0)
            #expect(bounds.origin.isFinite && bounds.size.isFinite)
        }
    }

    @Test func lanesAreFourPointsApartAcrossTheFlowInTargetOrder() throws {
        let layout = try #require(routing([tie(1, at: Vector2(384, 160), [third, upper, lower])]).ties[tieID(1)])
        #expect(layout.lanes == [upper: Vector2(384, 156), lower: Vector2(384, 160), third: Vector2(384, 164)])
    }

    /// In the vertical flow the tie is drawn at its transpose and its lanes spread across x. Here every target has the same
    /// x, so the endpoint order decides.
    @Test func inTheVerticalFlowLanesSpreadAcrossXInEndpointOrder() throws {
        let layout = try #require(routing([tie(1, at: Vector2(384, 160), [third, lower, upper])], flow: .vertical).ties[tieID(1)])
        #expect(layout.lanes == [upper: Vector2(156, 384), lower: Vector2(160, 384), third: Vector2(164, 384)])
        #expect(layout.band == CanvasRect(origin: Vector2(153, 381), size: Vector2(14, 6)))
    }

    @Test func theBandSpansTheLanesWithItsOverhang() throws {
        let two = try #require(routing([tie(1, at: Vector2(384, 160), [upper, lower])]).ties[tieID(1)])
        #expect(two.band == CanvasRect(origin: Vector2(381, 155), size: Vector2(6, 10)))
        let sources = (0..<20).map { Endpoint(node: nodeID(100 + $0), socket: "value") }
        let targets = (0..<20).map { Endpoint(node: nodeID(200 + $0), socket: "value") }
        let many = WireRouting(
            links: zip(sources, targets).map { Link(from: $0, to: $1) },
            ties: [tieID(1): CableTie(id: tieID(1), position: Vector2(384, 160), wires: Set(targets))],
            outputs: Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($1, Vector2(168, Double($0) * 30)) }),
            inputs: Dictionary(uniqueKeysWithValues: targets.enumerated().map { ($1, Vector2(600, Double($0) * 30)) }),
            flow: .horizontal)
        let band = try #require(many.ties[tieID(1)]?.band)
        #expect(band.size == Vector2(6, 19 * 4 + 6), "twenty lanes")
        #expect(Set(many.ties[tieID(1)]?.lanes.values.map(\.y) ?? []).count == 20, "each wire its own lane")
    }

    @Test func aRouteIsCulledByTheBoundsOfAllItsPieces() throws {
        let route = try #require(routing([tie(1, at: Vector2(384, 900), [upper, lower])]).routes[upper])
        let pieces = route.pieces.map { $0.bounds(padding: 4) }
        #expect(route.bounds(padding: 4) == pieces.dropFirst().reduce(pieces[0]) { $0.union($1) })
        #expect(route.bounds(padding: 4).contains(Vector2(384, 898)), "the lane far below")
    }

    @Test func distanceAndBoxesReadTheTautRoute() throws {
        let route = try #require(routing([]).routes[upper])
        #expect(abs(route.distance(to: Vector2(384, 64)) - 4) < 1e-9)
        #expect(route.intersects(CanvasRect(corner: Vector2(370, 40), Vector2(400, 80))))
        #expect(!route.intersects(CanvasRect(corner: Vector2(370, 100), Vector2(400, 120))))
        #expect(route.pointsInside(CanvasRect(corner: Vector2(370, 100), Vector2(400, 120))).isEmpty)
        #expect(route.intersects(CanvasRect(corner: Vector2(0, 0), Vector2(900, 900))), "lying wholly inside counts")
        #expect(route.pointsInside(CanvasRect(corner: Vector2(370, 40), Vector2(400, 80))).allSatisfy {
            abs($0.y - 60) < 1e-9 && (370...400).contains($0.x)
        })
        #expect(abs(route.middle.y - 60) < 1e-9, "the samples are the Bernstein sums, so within rounding")
    }

    @Test func theEditorRoutesTheLevelItShows() throws {
        let scene = TieScene()
        let editor = scene.editor(ties: [scene.tie()])
        #expect(editor.wireRouting.routes[scene.upper]?.pinned == [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)])
        #expect(editor.wireRouting.routes[scene.third]?.pinned == [Vector2(168, 460), Vector2(600, 460)])
        #expect(editor.wireRouting.ties[tieID(1)]?.band == CanvasRect(origin: Vector2(381, 155), size: Vector2(6, 10)))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -5`
Expected: "cannot find 'WireRouting' in scope" and similar.

- [ ] **Step 3: Write the geometry**

`Sources/CreatorEditor/WireGeometry.swift` (whole file)
```swift
import CreatorGeometry
import CreatorGraph

/// A wire's cubic bezier between two points (spec §6.2): the whole of an untied wire, or one piece of a tied wire's route
/// (cable ties spec 2026-10-26 §5.1). The control points leave each end along the flow (right/left in the horizontal flow,
/// down/up in the vertical), so a wire always leaves an output forwards and enters an input forwards.
public struct WireGeometry: Hashable, Sendable {
    public var start: Vector2
    public var control1: Vector2
    public var control2: Vector2
    public var end: Vector2

    /// `start` is the output end, `end` the input end, both in display canvas points.
    public init(from start: Vector2, to end: Vector2, flow: CanvasFlow) {
        let along = flow == .horizontal ? end.x - start.x : end.y - start.y
        let reach = max(40, abs(along) * 0.5)
        let step = flow == .horizontal ? Vector2(reach, 0) : Vector2(0, reach)
        self.start = start
        self.control1 = start + step
        self.control2 = end - step
        self.end = end
    }

    /// A piece with its four points given: a slack piece (`WireMotion.drawn`), or one moved into a view's frame.
    public init(start: Vector2, control1: Vector2, control2: Vector2, end: Vector2) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }

    /// The point at `t` along the curve: `start` at 0, `end` at 1.
    public func point(at t: Double) -> Vector2 {
        let u = 1 - t
        return start * (u * u * u) + control1 * (3 * u * u * t) + control2 * (3 * u * t * t) + end * (t * t * t)
    }

    /// A rectangle holding the whole curve (it lies inside its control points' hull), grown
    /// by `padding` for the stroke.
    public func bounds(padding: Double) -> CanvasRect {
        let points = [start, control1, control2, end]
        let low = Vector2(points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0)
        let high = Vector2(points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
        return CanvasRect(origin: low - Vector2(padding, padding), size: high - low + Vector2(2 * padding, 2 * padding))
    }

    /// A rectangle holding every piece, grown by `padding`; an empty rectangle at the origin for none.
    public static func bounds(of pieces: [WireGeometry], padding: Double) -> CanvasRect {
        let boxes = pieces.map { $0.bounds(padding: padding) }
        guard let first = boxes.first else { return CanvasRect(origin: .zero, size: .zero) }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }
}
```

`Sources/CreatorEditor/WireRoute.swift`
```swift
import CreatorGeometry
import CreatorGraph

/// A wire's taut route (cable ties spec 2026-10-26 §5.1) in display canvas points: one cubic from its output to its input, or
/// a chain of them through the lane of each tie that holds it. Each piece leaves and enters along the flow with
/// `WireGeometry`'s reach rule, so the pieces join tangent-continuously at every lane and an untied wire is exactly the cubic
/// it always was. Hit testing, box selection, culling and the place of a new tie read this route, never the slack one
/// (§5.2).
public struct WireRoute: Equatable, Sendable {
    /// How many segments each piece is sampled into for hit testing and boxes.
    public static let samplesPerPiece = 24

    /// The wire, named by its input endpoint.
    public var wire: Endpoint
    /// The pieces, the output end first.
    public var pieces: [WireGeometry]

    public init(wire: Endpoint, pieces: [WireGeometry]) {
        self.wire = wire
        self.pieces = pieces
    }

    /// The route through `points`: the output's anchor, each lane in order, the input's anchor.
    public init(wire: Endpoint, through points: [Vector2], flow: CanvasFlow) {
        self.init(wire: wire, pieces: zip(points, points.dropFirst()).map { WireGeometry(from: $0, to: $1, flow: flow) })
    }

    /// The points the route passes through exactly (§5.2's pinned points): its two ends and each lane.
    public var pinned: [Vector2] { (pieces.first.map { [$0.start] } ?? []) + pieces.map(\.end) }

    /// The route as a polyline, `samplesPerPiece` segments a piece, from the output end.
    public var samples: [Vector2] {
        var points = pieces.first.map { [$0.start] } ?? []
        for piece in pieces {
            for step in 1...Self.samplesPerPiece {
                points.append(piece.point(at: Double(step) / Double(Self.samplesPerPiece)))
            }
        }
        return points
    }

    /// The middle sample: where a wire with no pick point puts a new tie (cable ties plan ruling R10).
    public var middle: Vector2 {
        let points = samples
        return points.isEmpty ? .zero : points[points.count / 2]
    }

    /// A rectangle holding every piece, grown by `padding`.
    public func bounds(padding: Double) -> CanvasRect { WireGeometry.bounds(of: pieces, padding: padding) }

    /// How far `point` is from the route's polyline.
    public func distance(to point: Vector2) -> Double {
        let points = samples
        return zip(points, points.dropFirst()).map { Self.distance(from: point, toSegment: $0, $1) }.min() ?? .infinity
    }

    /// The middle of each stretch of the route inside `rect`; empty when it never enters it.
    public func pointsInside(_ rect: CanvasRect) -> [Vector2] {
        let points = samples
        return zip(points, points.dropFirst()).compactMap { Self.clip($0, $1, to: rect) }.map { ($0.0 + $0.1) * 0.5 }
    }

    /// Whether the route crosses or lies inside `rect`.
    public func intersects(_ rect: CanvasRect) -> Bool { !pointsInside(rect).isEmpty }

    static func distance(from p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return (p - a).length }
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared, 0), 1)
        return (a + ab * t - p).length
    }

    /// The part of segment `a`–`b` inside `rect` (Liang–Barsky), or `nil` when it misses.
    static func clip(_ a: Vector2, _ b: Vector2, to rect: CanvasRect) -> (Vector2, Vector2)? {
        let d = b - a
        var low = 0.0, high = 1.0
        let edges = [(-d.x, a.x - rect.origin.x), (d.x, rect.maxX - a.x), (-d.y, a.y - rect.origin.y), (d.y, rect.maxY - a.y)]
        for (p, q) in edges {
            if p == 0 {
                if q < 0 { return nil }
                continue
            }
            let r = q / p
            if p < 0 { low = max(low, r) } else { high = min(high, r) }
            if low > high { return nil }
        }
        return (a + d * low, a + d * high)
    }
}
```

`Sources/CreatorEditor/TieLayout.swift`
```swift
import CreatorGeometry
import CreatorGraph

/// Where a tie is drawn (cable ties spec 2026-10-26 §5.1), in display canvas points. It has a lane for each wire it holds:
/// the lanes sit `laneSpacing` apart across the flow, centred on the tie's position, and are ordered by where each wire's
/// input sits across the flow, then by endpoint, to cut down crossings after the fan-out. Its band is a rounded rectangle
/// `bandLength` along the flow, spanning every lane and reaching `bandOverhang` beyond the outer ones.
public struct TieLayout: Equatable, Sendable {
    public static let laneSpacing = 4.0
    public static let bandLength = 6.0
    public static let bandOverhang = 3.0

    public var id: TieID
    /// Each wire's lane point.
    public var lanes: [Endpoint: Vector2]
    public var band: CanvasRect

    /// `inputs` are the input anchors of the wires (display canvas points); a wire without one has no lane.
    public init(_ tie: CableTie, inputs: [Endpoint: Vector2], flow: CanvasFlow) {
        let across: (Vector2) -> Double = { flow == .horizontal ? $0.y : $0.x }
        let ordered = tie.wires.compactMap { wire in inputs[wire].map { (wire, across($0)) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
            .map(\.0)
        let centre = flow.display(tie.position)
        let unit = flow == .horizontal ? Vector2(0, 1) : Vector2(1, 0)
        let along = flow == .horizontal ? Vector2(1, 0) : Vector2(0, 1)
        let first = -Double(max(ordered.count - 1, 0)) * Self.laneSpacing / 2
        var lanes: [Endpoint: Vector2] = [:]
        for (index, wire) in ordered.enumerated() {
            lanes[wire] = centre + unit * (first + Double(index) * Self.laneSpacing)
        }
        let spread = Double(max(ordered.count - 1, 0)) * Self.laneSpacing + 2 * Self.bandOverhang
        id = tie.id
        self.lanes = lanes
        band = CanvasRect(origin: centre + unit * (first - Self.bandOverhang) - along * (Self.bandLength / 2),
                          size: along * Self.bandLength + unit * spread)
    }
}
```

`Sources/CreatorEditor/WireRouting.swift`
```swift
import CreatorGeometry
import CreatorGraph

/// The taut routes of a level's wires and the layouts of its ties (cable ties spec 2026-10-26 §5.1), from the socket anchors,
/// in display canvas points. Pure: `EditorModel.wireRouting` builds it from the level shown, and the tests build it from
/// anchors they choose.
public struct WireRouting: Equatable, Sendable {
    /// Each link's route, by its input endpoint.
    public var routes: [Endpoint: WireRoute]
    public var ties: [TieID: TieLayout]

    /// `outputs` and `inputs` are the anchors of the links' two ends; a link missing either is left out. A wire meets its
    /// ties in the order of their stored `position.x`, then by ID.
    public init(links: [Link], ties: [TieID: CableTie], outputs: [Endpoint: Vector2], inputs: [Endpoint: Vector2],
                flow: CanvasFlow) {
        let layouts = ties.mapValues { TieLayout($0, inputs: inputs, flow: flow) }
        var held: [Endpoint: [CableTie]] = [:]
        for tie in ties.values {
            for wire in tie.wires { held[wire, default: []].append(tie) }
        }
        var routes: [Endpoint: WireRoute] = [:]
        for link in links {
            guard let start = outputs[link.from], let end = inputs[link.to] else { continue }
            let lanes = (held[link.to] ?? []).sorted { ($0.position.x, $0.id) < ($1.position.x, $1.id) }
                .compactMap { layouts[$0.id]?.lanes[link.to] }
            routes[link.to] = WireRoute(wire: link.to, through: [start] + lanes + [end], flow: flow)
        }
        self.routes = routes
        self.ties = layouts
    }
}
```

`Sources/CreatorEditor/EditorModel+Wires.swift`
```swift
import CreatorGeometry
import CreatorGraph

/// Wires and cable ties on the canvas (cable ties spec 2026-10-26 §4, §5).
extension EditorModel {
    /// The level's wires and ties as drawn: every link's taut route and every tie's lanes and band, in display canvas
    /// points, from the socket anchors. Hit testing, boxes, culling and ⌘⇧T read it. It is computed each time it is read,
    /// never stored.
    public var wireRouting: WireRouting {
        var outputs: [Endpoint: Vector2] = [:]
        var inputs: [Endpoint: Vector2] = [:]
        for link in graph.links {
            outputs[link.from] = anchor(of: SocketRef(link.from, isInput: false))
            inputs[link.to] = anchor(of: SocketRef(link.to, isInput: true))
        }
        return WireRouting(links: graph.links, ties: graph.ties, outputs: outputs, inputs: inputs, flow: flow)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter 'WireRouteTests|WireGeometryTests|CanvasLayersTests|CanvasCullingTests' 2>&1 | tail -3`
Expected: passes.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(editor): taut wire routes through tie lanes, and tie bands`, with the two trailer lines)

---

### Task 5: Drawing routes and bands, the draw order, culling and selected highlights

Spec §4.1 (the highlights), §5.1 (band colour, draw order, culling). Rulings R15, R17.

**Files:**
- Modify: `Sources/CreatorEditor/CanvasSelection.swift` (whole file), `Sources/CreatorEditor/WireShape.swift` (whole file), `Sources/CreatorEditor/WireView.swift` (whole file), `Sources/CreatorEditor/CanvasLayers.swift:6-96`, `Sources/CreatorEditor/EditorModel+Culling.swift`, `Sources/CreatorEditor/EditorModel+Wires.swift`
- Create: `Sources/CreatorEditor/TieBandView.swift`, `Sources/CreatorEditor/WireLayer.swift`
- Modify (tests): `Tests/CreatorEditorTests/CanvasLayersTests.swift:15-16`, `Tests/CreatorEditorTests/CommentViewEqualityTests.swift:48-52`
- Test: `Tests/CreatorEditorTests/TieRenderTests.swift`

**Interfaces:**
- Consumes: Task 4's `WireRouting`, `WireRoute`, `TieLayout`, `WireGeometry.bounds(of:padding:)`, `TieScene`.
- Produces:
  - `CanvasSelection`: `wires: Set<Endpoint>`, `ties: Set<TieID>`, `init(nodes:comments:wires:ties:)`, and `applying(wires:mode:)`.
  - `WireView(pieces:color:lineWidth:)` and `WireView(geometry:color:lineWidth:)`; `WireView.defaultLineWidth = 2`.
  - `TieBandView(band:isSelected:palette:)`.
  - `WireLayer(model:routing:palette:animates:)`.
  - `CanvasLayers.Wire { id: String, route: WireRoute, color: HexColor, lineWidth: Double }`, `CanvasLayers.selectedLineWidth = 4`, and `CanvasLayers.wires(_:routing:palette:motion:)`. Its `motion:` parameter is `WireMotion?`, added in Task 11; this task writes the function without it.
  - `EditorModel.drawOrderTies(in:) -> [TieLayout]` and `EditorModel.drawnTies(in:) -> [TieLayout]`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/TieRenderTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// How wires and ties draw (cable ties spec 2026-10-26 §4.1, §5.1): a tied wire through its lane, a selected wire wider in the
/// selection colour, a band in the glass stroke above the wires and below notes and nodes (in the selection colour when
/// selected), selected ties last, and ties culled by their band.
@MainActor
struct TieRenderTests {
    let scene = TieScene()

    func canvasOrigin(_ editor: EditorModel) -> Vector2 {
        GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary).origin
    }

    /// The top-left of the rect painted last at `point` (display canvas points), in canvas points.
    func painted(at point: Vector2, in scene: Scene, _ editor: EditorModel) -> Vector2? {
        let origin = canvasOrigin(editor)
        return topRect(at: origin + point, in: scene).map { screenFrame(of: $0, in: scene).origin - origin }
    }

    func panel(_ editor: EditorModel) -> Scene {
        renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
    }

    func isColour(_ rect: MUIRect?, _ colour: HexColor) -> Bool {
        guard let rect else { return false }
        let want = colour.hsla
        return abs(rect.background.h - want.h) < 0.01 && abs(rect.background.s - want.s) < 0.01
            && abs(rect.background.l - want.l) < 0.01 && abs(rect.background.a - want.a) < 0.01
    }

    @Test func aTiedWireIsDrawnThroughItsLane() throws {
        let editor = scene.editor(ties: [scene.tie()])
        let wire = try #require(CanvasLayers.wires(editor).first { $0.route.wire == scene.upper })
        #expect(wire.id == "\(scene.b1.id.rawValue.uuidString).value")
        #expect(wire.route.pinned == [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)])
        #expect(wire.color == Palette.dracula.socket(.number) && wire.lineWidth == WireView.defaultLineWidth)
    }

    @Test func aSelectedWireIsWiderInTheSelectionColour() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(wires: [scene.upper])
        let wires = CanvasLayers.wires(editor)
        let upper = wires.first { $0.route.wire == scene.upper }, lower = wires.first { $0.route.wire == scene.lower }
        #expect(upper?.color == Palette.dracula.selection && upper?.lineWidth == CanvasLayers.selectedLineWidth)
        #expect(lower?.color == Palette.dracula.socket(.number) && lower?.lineWidth == WireView.defaultLineWidth)
        #expect(!editor.document.canUndo, "selection is view state")
    }

    @Test func bandsDrawAboveTheWiresAndBelowNotesAndNodes() {
        let band = Vector2(384, 160)
        let editor = scene.editor(ties: [scene.tie()])
        #expect(painted(at: band, in: panel(editor), editor) == Vector2(381, 155), "the band, where nothing is above it")
        let noted = scene.editor(ties: [scene.tie()], stickies: [note(1, at: Vector2(370, 150), size: Vector2(40, 40))])
        #expect(painted(at: band, in: panel(noted), noted) == Vector2(370, 150), "a note covers the band")
        let under = scene.editor(ties: [scene.tie(at: Vector2(84, 30))])
        #expect(painted(at: Vector2(84, 30), in: panel(under), under) == Vector2(0, 0), "a node covers the band")
    }

    @Test func aBandIsTheGlassStrokeAndASelectedOneTheSelectionColour() {
        let editor = scene.editor(ties: [scene.tie()])
        let point = canvasOrigin(editor) + Vector2(384, 160)
        #expect(isColour(topRect(at: point, in: panel(editor)), Palette.dracula.hairline))
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        #expect(isColour(topRect(at: point, in: panel(editor)), Palette.dracula.selection))
    }

    @Test func selectedTiesDrawLast() {
        let editor = scene.editor(ties: [scene.tie(1), scene.tie(2, at: Vector2(384, 161))])
        #expect(editor.drawOrderTies(in: editor.wireRouting).map(\.id) == [tieID(1), tieID(2)])
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        #expect(editor.drawOrderTies(in: editor.wireRouting).map(\.id) == [tieID(2), tieID(1)])
    }

    @Test func aTieWhollyOutsideTheCanvasIsNotBuilt() {
        let editor = scene.editor(ties: [scene.tie(), scene.tie(2, at: Vector2(9_000, 9_000))])
        #expect(editor.drawnTies(in: editor.wireRouting).map(\.id) == [tieID(1), tieID(2)], "unplaced, everything is drawn")
        editor.panelPlacement = PanelPlacement(window: Vector2(1000, 700),
                                               panel: CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300)))
        #expect(editor.drawnTies(in: editor.wireRouting).map(\.id) == [tieID(1)])
    }

    @Test func aBandIsEqualOnlyWhenEveryInputIs() {
        let band = CanvasRect(origin: Vector2(381, 155), size: Vector2(6, 10))
        expectEqualityCovers(TieBandView(band: band, isSelected: false, palette: .dracula),
                             equalTo: TieBandView(band: band, isSelected: false, palette: .dracula), [
            "band": TieBandView(band: band.moved(by: Vector2(1, 0)), isSelected: false, palette: .dracula),
            "isSelected": TieBandView(band: band, isSelected: true, palette: .dracula),
            "palette": TieBandView(band: band, isSelected: false, palette: Palette(.alucard)),
        ])
    }
}
```

`Tests/CreatorEditorTests/CanvasLayersTests.swift`. Replace:
```swift
        #expect(wires.first?.geometry.start == Vector2(168, 120))
        #expect(wires.first?.geometry.end == Vector2(300, 40))
```
with:
```swift
        #expect(wires.first?.route.pieces.first?.start == Vector2(168, 120))
        #expect(wires.first?.route.pieces.last?.end == Vector2(300, 40))
```

`Tests/CreatorEditorTests/CommentViewEqualityTests.swift`. Replace:
```swift
            "geometry": WireView(geometry: WireGeometry(from: Vector2(0, 0), to: Vector2(101, 40), flow: .horizontal), color: color),
```
with:
```swift
            "pieces": WireView(pieces: [geometry, WireGeometry(from: Vector2(100, 40), to: Vector2(200, 0), flow: .horizontal)],
                               color: color),
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -5`
Expected: "cannot find 'TieBandView' in scope", "extra argument 'wires' in call".

- [ ] **Step 3: Write the selection fields, the views and the layer order**

`Sources/CreatorEditor/CanvasSelection.swift` (whole file)
```swift
import CreatorGraph
import CreatorKernel

/// What is selected on the canvas (spec 2026-10-09 §3, §7; cable ties spec 2026-10-26 §4.1): nodes, canvas comments, wires
/// and cable ties. View state: never undone, never saved. Every gesture and key built on this type takes the new kinds in
/// unchanged.
public struct CanvasSelection: Equatable, Sendable {
    public var nodes: Set<NodeID>
    /// Sticky notes and comment frames alike.
    public var comments: Set<CommentID>
    /// Wires, each named by its input endpoint.
    public var wires: Set<Endpoint>
    public var ties: Set<TieID>

    public init(nodes: Set<NodeID> = [], comments: Set<CommentID> = [], wires: Set<Endpoint> = [], ties: Set<TieID> = []) {
        self.nodes = nodes
        self.comments = comments
        self.wires = wires
        self.ties = ties
    }

    public var isEmpty: Bool { nodes.isEmpty && comments.isEmpty && wires.isEmpty && ties.isEmpty }

    /// Whether every item of `other` is selected here.
    public func isSuperset(of other: CanvasSelection) -> Bool {
        nodes.isSuperset(of: other.nodes) && comments.isSuperset(of: other.comments) && wires.isSuperset(of: other.wires)
            && ties.isSuperset(of: other.ties)
    }

    /// This selection combined with `items` as `mode` says: replaced by them, with them added, or with each of
    /// them toggled in or out.
    public func applying(_ items: CanvasSelection, mode: SelectionMode) -> CanvasSelection {
        switch mode {
        case .replace: items
        case .add: CanvasSelection(nodes: nodes.union(items.nodes), comments: comments.union(items.comments),
                                   wires: wires.union(items.wires), ties: ties.union(items.ties))
        case .toggle: CanvasSelection(nodes: nodes.symmetricDifference(items.nodes),
                                      comments: comments.symmetricDifference(items.comments),
                                      wires: wires.symmetricDifference(items.wires),
                                      ties: ties.symmetricDifference(items.ties))
        }
    }

    /// This selection with only its wires combined with `boxed` as `mode` says: what an ⌥-box does (cable ties spec §4.1).
    /// Nodes, comments and ties stay as they are.
    public func applying(wires boxed: Set<Endpoint>, mode: SelectionMode) -> CanvasSelection {
        var result = self
        switch mode {
        case .replace: result.wires = boxed
        case .add: result.wires.formUnion(boxed)
        case .toggle: result.wires.formSymmetricDifference(boxed)
        }
        return result
    }
}
```

`Sources/CreatorEditor/WireShape.swift` (whole file)
```swift
import CreatorGeometry
import MetalUI

/// A wire drawn as a chain of bezier pieces in one `Path` (cable ties spec 2026-10-26 §5.1), in coordinates relative to its
/// own frame's origin. An untied wire is one piece.
struct WireShape: Shape, Hashable {
    var pieces: [WireGeometry]

    init(_ pieces: [WireGeometry], origin: Vector2) {
        self.pieces = pieces.map {
            WireGeometry(start: $0.start - origin, control1: $0.control1 - origin, control2: $0.control2 - origin,
                         end: $0.end - origin)
        }
    }

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            if let first = pieces.first { path.move(to: Self.point(first.start)) }
            for piece in pieces {
                path.addCurve(to: Self.point(piece.end), control1: Self.point(piece.control1), control2: Self.point(piece.control2))
            }
        }
    }

    static func point(_ v: Vector2) -> Point<Pixels> { Point(x: v.x.px, y: v.y.px) }
}
```

`Sources/CreatorEditor/WireView.swift` (whole file)
```swift
import CreatorGeometry
import CreatorStyle
import MetalUI

/// One wire: a stroked `WireShape` (its route's pieces) in a frame just big enough for them, offset to its place on the
/// canvas.
struct WireView: Component, Equatable {
    static let defaultLineWidth = 2.0

    let pieces: [WireGeometry]
    let color: HexColor
    let lineWidth: Double

    init(pieces: [WireGeometry], color: HexColor, lineWidth: Double = WireView.defaultLineWidth) {
        self.pieces = pieces
        self.color = color
        self.lineWidth = lineWidth
    }

    /// A wire of one piece: the wire being dragged, or an untied wire.
    init(geometry: WireGeometry, color: HexColor, lineWidth: Double = WireView.defaultLineWidth) {
        self.init(pieces: [geometry], color: color, lineWidth: lineWidth)
    }

    var content: some ElementGroup {
        let bounds = WireGeometry.bounds(of: pieces, padding: lineWidth * 2)
        return WireShape(pieces, origin: bounds.origin)
            .stroke(color.color, lineWidth: lineWidth.px)
            .frame(width: bounds.size.x.px, height: bounds.size.y.px)
            .offset(x: bounds.origin.x.px, y: bounds.origin.y.px)
    }
}
```

`Sources/CreatorEditor/TieBandView.swift`
```swift
import CreatorGraph
import CreatorStyle
import MetalUI

/// A tie's band (cable ties spec 2026-10-26 §5.1): a rounded rectangle across its lanes, in the theme's glass stroke, or in
/// its selection colour while the tie is selected. `band` is in display canvas points.
struct TieBandView: Component, Equatable {
    let band: CanvasRect
    let isSelected: Bool
    let palette: Palette

    var content: some ElementGroup {
        RoundedRectangle(cornerRadius: TieLayout.bandOverhang.px)
            .fill((isSelected ? palette.selection : palette.hairline).color)
            .frame(width: band.size.x.px, height: band.size.y.px)
            .offset(x: band.origin.x.px, y: band.origin.y.px)
    }
}
```

`Sources/CreatorEditor/WireLayer.swift`
```swift
import CreatorStyle
import MetalUI

/// The canvas's wires (cable ties spec 2026-10-26 §5): one `WireView` for each wire that can show, built from its route.
/// `animates` is false until Task 12 of the cable ties plan wraps the views in a `TimelineView` while some wire is slack.
struct WireLayer: Component {
    let model: EditorModel
    let routing: WireRouting
    let palette: Palette
    let animates: Bool

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ForEach(CanvasLayers.wires(model, routing: routing, palette: palette), id: \.id) { wire in
                WireView(pieces: wire.route.pieces, color: wire.color, lineWidth: wire.lineWidth).equatable()
            }
        }
    }
}
```

`Sources/CreatorEditor/CanvasLayers.swift`. Replace the doc comment's first sentence:
```swift
/// Everything drawn under the canvas transform, back to front: comment frames, wires, notes, nodes (the selected last
/// within each kind), ⌥-drag ghosts, the wire being dragged and the box selection. Positions are display canvas
```
with:
```swift
/// Everything drawn under the canvas transform, back to front: comment frames, wires, cable tie bands, notes, nodes (the
/// selected last within each kind), ⌥-drag ghosts, the wire being dragged and the box selection (cable ties spec 2026-10-26
/// §5.1). Positions are display canvas
```
Replace:
```swift
        let selectedComments = model.canvasSelection.comments
        let commentGhosts = Self.commentGhosts(model)
        return ZStack(alignment: .topLeading) {
```
with:
```swift
        let selectedComments = model.canvasSelection.comments
        let selectedTies = model.canvasSelection.ties
        let routing = model.wireRouting
        let commentGhosts = Self.commentGhosts(model)
        return ZStack(alignment: .topLeading) {
```
Replace:
```swift
            ForEach(Self.wires(model, palette: palette), id: \.id) { wire in
                WireView(geometry: wire.geometry, color: wire.color).equatable()
            }
```
with:
```swift
            WireLayer(model: model, routing: routing, palette: palette, animates: false)
            ForEach(model.drawnTies(in: routing), id: \.id.rawValue) { layout in
                TieBandView(band: layout.band, isSelected: selectedTies.contains(layout.id), palette: palette).equatable()
            }
```
Replace the `Wire` struct and `wires(_:palette:)`:
```swift
    struct Wire: Identifiable {
        var id: String
        var geometry: WireGeometry
        var color: HexColor
    }

    /// Every wire whose two sockets are on the canvas and some of whose curve can show (`drawnCanvasRect`), coloured
    /// by its source socket's type in `palette`.
    static func wires(_ model: EditorModel, palette: Palette = .dracula) -> [Wire] {
        let drawn = model.drawnCanvasRect
        return model.graph.links.compactMap { link in
            let from = SocketRef(link.from, isInput: false), to = SocketRef(link.to, isInput: true)
            guard let start = model.anchor(of: from), let end = model.anchor(of: to),
                  let source = model.graph.nodes[link.from.node] else { return nil }
            let geometry = WireGeometry(from: start, to: end, flow: model.flow)
            // WireView's frame: the curve's bounds padded by twice its 2-point stroke.
            if let drawn, !drawn.intersects(geometry.bounds(padding: 4)) { return nil }
            let type = model.shape(of: source).outputs.first { $0.name == link.from.socket }?.type
            return Wire(id: "\(link.to.node.rawValue.uuidString).\(link.to.socket.rawValue)",
                        geometry: geometry,
                        color: type.map(palette.socket) ?? palette.secondaryText)
        }
    }
```
with:
```swift
    struct Wire: Identifiable {
        var id: String
        var route: WireRoute
        var color: HexColor
        var lineWidth: Double
    }

    /// How wide a selected wire is drawn (cable ties spec §4.1).
    static let selectedLineWidth = 4.0

    /// Every wire whose two sockets are on the canvas and some of whose taut route can show (`drawnCanvasRect`), coloured
    /// by its source socket's type in `palette`, or wider in the selection colour when selected. `routing` is
    /// `model.wireRouting` when not given.
    static func wires(_ model: EditorModel, routing: WireRouting? = nil, palette: Palette = .dracula) -> [Wire] {
        let drawn = model.drawnCanvasRect
        let routing = routing ?? model.wireRouting
        let selected = model.canvasSelection.wires
        return model.graph.links.compactMap { link in
            guard let taut = routing.routes[link.to], let source = model.graph.nodes[link.from.node] else { return nil }
            let isSelected = selected.contains(link.to)
            let width = isSelected ? selectedLineWidth : WireView.defaultLineWidth
            // WireView's frame: the route's bounds padded by twice its stroke.
            if let drawn, !drawn.intersects(taut.bounds(padding: 2 * width)) { return nil }
            let type = model.shape(of: source).outputs.first { $0.name == link.from.socket }?.type
            return Wire(id: "\(link.to.node.rawValue.uuidString).\(link.to.socket.rawValue)",
                        route: taut,
                        color: isSelected ? palette.selection : type.map(palette.socket) ?? palette.secondaryText,
                        lineWidth: width)
        }
    }
```

Append to `Sources/CreatorEditor/EditorModel+Wires.swift`, inside the extension:
```swift

    /// Ties back to front: by ID, with the selected ones raised above the rest.
    public func drawOrderTies(in routing: WireRouting) -> [TieLayout] {
        routing.ties.values.sorted { a, b in
            let aSelected = canvasSelection.ties.contains(a.id), bSelected = canvasSelection.ties.contains(b.id)
            return aSelected != bSelected ? bSelected : a.id < b.id
        }
    }
```

Append to `Sources/CreatorEditor/EditorModel+Culling.swift`:
```swift

extension EditorModel {
    /// The ties the canvas builds, back to front: `drawOrderTies(in:)` without those whose band lies wholly outside
    /// `drawnCanvasRect` (cable ties spec §5.1). Hit testing and selection always see every tie.
    public func drawnTies(in routing: WireRouting) -> [TieLayout] {
        let order = drawOrderTies(in: routing)
        guard let drawn = drawnCanvasRect else { return order }
        return order.filter { drawn.intersects($0.band) }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter CreatorEditorTests 2>&1 | tail -3`
Expected: passes, `TieRenderTests` included.
Run: `swift test --filter 'CanvasContentSkipWindowTests|PanelContentSkipWindowTests' 2>&1 | tail -3`
Expected: passes. These graphs have no ties, so the counts are unchanged.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

If `topRect` finds no rect for the band, `RoundedRectangle().fill` is not drawn as a scene rect. Read how `StatusBadgeView`'s `Capsule` background appears in `Scene` and assert on that record instead. Do not change the band.

- [ ] **Step 5: Commit** (`feat(editor): draw wires through their ties, tie bands, and selected wires and ties`, with the two trailer lines)

---

### Task 6: Hit testing and click selection of wires and ties

Spec §4.1 (wire hit-test, priority, click). Rulings R3, R4, R5, R10 (click points).

**Files:**
- Modify: `Sources/CreatorEditor/CanvasHit.swift` (whole file), `Sources/CreatorEditor/EditorModel.swift:103` (a stored property) and `:191-211` (`hitTest`), `Sources/CreatorEditor/EditorModel+CommentGeometry.swift:42-57`, `Sources/CreatorEditor/EditorModel+Wires.swift`, `Sources/CreatorEditor/EditorModel+Selection.swift:32-40`, `Sources/CreatorEditor/EditorModel+Pointer.swift:38-40,102-123`, `Sources/CreatorEditor/EditorModel+DoubleClick.swift:43`
- Test: `Tests/CreatorEditorTests/WireHitTests.swift`, `Tests/CreatorEditorTests/WireSelectionTests.swift`

**Interfaces:**
- Consumes: Task 4's `wireRouting`, `WireRoute.distance(to:)`, `TieLayout.band`; Task 5's `CanvasSelection(wires:ties:)`, `drawOrderTies(in:)`.
- Produces:
  - `CanvasHit.tie(TieID)` and `.wire(Endpoint)`.
  - `EditorModel.wireHitDistance = 5.0`, `tieHit(at:in:) -> TieID?`, `wireHit(at:in:) -> Endpoint?`, `noteHit(at:) -> CanvasHit?`, `frameHit(at:) -> CanvasHit?` (`commentHit` is gone).
  - `EditorModel.wirePickPoints: [Endpoint: Vector2]` (internal, `@ObservationIgnored`, stored coordinates).
  - `EditorModel.click(_:at:modifiers:)` (private), the function Task 9 adds the ⌥-untie to.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/WireHitTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// What a press on a wire or a tie hits (cable ties spec 2026-10-26 §4.1): a wire within 5 points of its taut route, a tie
/// anywhere on its band; priority socket, tie, node, note, wire, frame, empty, with a selected comment's handle just before
/// its own comment (plan ruling R3).
@MainActor
struct WireHitTests {
    let scene = TieScene()

    @Test func aPointOnOrNearAWireHitsIt() {
        let editor = scene.editor()
        #expect(editor.hitTest(scene.upperMiddle) == .wire(scene.upper))
        #expect(editor.hitTest(scene.upperMiddle + Vector2(0, 4)) == .wire(scene.upper))
        #expect(editor.hitTest(scene.upperMiddle + Vector2(0, 7)) == .empty)
        #expect(editor.hitTest(scene.lowerMiddle) == .wire(scene.lower))
    }

    @Test func theDistanceIsInCanvasPointsUnderZoomAndPan() {
        let editor = scene.editor()
        editor.transform = CanvasTransform(offset: Vector2(-40, 30), zoom: 2)
        let point = editor.transform.toScreen(scene.upperMiddle + Vector2(0, 4))
        #expect(editor.hitTest(point) == .wire(scene.upper))
        #expect(editor.hitTest(editor.transform.toScreen(scene.upperMiddle + Vector2(0, 7))) == .empty)
    }

    @Test func aTiedWireHitsAlongItsTautRoute() throws {
        let editor = scene.editor(ties: [scene.tie()])
        let onRoute = try #require(editor.wireRouting.routes[scene.upper]?.pieces.first?.point(at: 0.5))
        #expect(editor.hitTest(onRoute) == .wire(scene.upper))
        #expect(editor.hitTest(scene.upperMiddle) == .empty, "the straight line it used to be is empty now")
    }

    @Test func aTieHitsAnywhereOnItsBand() {
        let editor = scene.editor(ties: [scene.tie()])
        #expect(editor.hitTest(Vector2(384, 160)) == .tie(tieID(1)))
        #expect(editor.hitTest(Vector2(381.5, 155.5)) == .tie(tieID(1)), "the band's corner")
        #expect(editor.hitTest(Vector2(384, 158)) == .tie(tieID(1)), "a lane is the tie's, not its wire's")
    }

    @Test func aSocketBeatsATieAndATieBeatsANode() {
        let onSocket = scene.editor(ties: [scene.tie(at: Vector2(600, 60))])
        #expect(onSocket.hitTest(Vector2(600, 60)) == .socket(SocketRef(scene.upper, isInput: true)))
        let onNode = scene.editor(ties: [scene.tie(at: Vector2(84, 30))])
        #expect(onNode.hitTest(Vector2(84, 30)) == .tie(tieID(1)), "a tie dropped on a node can still be grabbed")
        #expect(onNode.hitTest(Vector2(20, 40)) == .node(scene.a1.id), "the rest of the node is the node's")
    }

    @Test func aNoteBeatsAWireAndAWireBeatsAFrame() {
        let covered = scene.editor(stickies: [note(1, at: Vector2(334, 10), size: Vector2(100, 100))])
        #expect(covered.hitTest(scene.upperMiddle) == .note(commentID(1)))
        let frame = box(2, at: Vector2(300, 40), size: Vector2(200, 200))
        #expect(makeEditor(scene.nodes, [], frames: [frame]).hitTest(scene.upperMiddle) == .frame(frame.id),
                "set up: without the wire the point is the frame's title bar")
        #expect(scene.editor(frames: [frame]).hitTest(scene.upperMiddle) == .wire(scene.upper))
    }

    @Test func theLeftDockHitsTheTransposedRoute() throws {
        let editor = scene.editor(dock: .left)
        let onUpper = try #require(editor.wireRouting.routes[scene.upper]?.pieces.first?.point(at: 0.5))
        #expect(onUpper == Vector2(94, 338), "set up: the vertical flow's route")
        #expect(editor.hitTest(onUpper) == .wire(scene.upper))
    }

    /// Wires cross the canvas everywhere, so a drag that starts on one draws a box (plan ruling R5).
    @Test func aDragThatStartsOnAWireDrawsABox() {
        let editor = scene.editor()
        editor.drag(scene.upperMiddle, Vector2(900, 300))
        #expect(editor.selection == [scene.b1.id, scene.b2.id], "the box covered the two nodes on the right")
        #expect(editor.canvasSelection.wires.isEmpty && !editor.document.canUndo)
    }
}
```

`Tests/CreatorEditorTests/WireSelectionTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Clicking wires and ties (cable ties spec 2026-10-26 §4.1): a click selects, replacing the selection; ⇧ adds, ⌘ toggles,
/// ⌘ wins; a click on empty canvas clears everything. View state, never undone. A click on a wire remembers where it
/// landed, in stored coordinates, for ⌘⇧T.
@MainActor
struct WireSelectionTests {
    let scene = TieScene()

    @Test func aClickOnAWireSelectsItAlone() {
        let editor = scene.editor()
        editor.selection = [scene.a1.id]
        editor.click(scene.upperMiddle)
        #expect(editor.canvasSelection == CanvasSelection(wires: [scene.upper]))
        #expect(!editor.document.canUndo)
    }

    @Test func shiftAddsCommandTogglesAndCommandWins() {
        let editor = scene.editor()
        editor.click(scene.upperMiddle)
        editor.click(scene.lowerMiddle, modifiers: .shift)
        #expect(editor.canvasSelection.wires == [scene.upper, scene.lower])
        editor.click(scene.upperMiddle, modifiers: .command)
        #expect(editor.canvasSelection.wires == [scene.lower])
        editor.click(scene.lowerMiddle, modifiers: [.command, .shift])
        #expect(editor.canvasSelection.wires.isEmpty)
    }

    @Test func aClickOnATieSelectsItAndShiftAddsAWire() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.click(Vector2(384, 160))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        editor.click(scene.thirdMiddle, modifiers: .shift)
        #expect(editor.canvasSelection == CanvasSelection(wires: [scene.third], ties: [tieID(1)]))
    }

    @Test func aClickOnEmptyCanvasClearsWiresAndTiesToo() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], wires: [scene.upper], ties: [tieID(1)])
        editor.click(Vector2(384, 380))
        #expect(editor.canvasSelection.isEmpty)
    }

    @Test func aClickRemembersWhereItPickedTheWire() {
        let editor = scene.editor()
        editor.click(scene.upperMiddle + Vector2(10, 2))
        #expect(editor.wirePickPoints[scene.upper] == Vector2(394, 62))
        let left = scene.editor(dock: .left)
        left.click(Vector2(94, 338))
        #expect(left.wirePickPoints[scene.upper] == Vector2(338, 94), "stored, so the transpose of the drawn point")
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -5`
Expected: "type 'CanvasHit' has no member 'wire'".

- [ ] **Step 3: Write the hits and the clicks**

`Sources/CreatorEditor/CanvasHit.swift` (whole file)
```swift
import CreatorGraph
import CreatorKernel

/// What lies under a point on the canvas (cable ties spec 2026-10-26 §4.1). Topmost first: a socket, a tie's band, a node,
/// a note (a selected one's resize handle first), a wire, a frame's chrome (a selected one's handle first), then empty
/// canvas.
public enum CanvasHit: Equatable, Sendable {
    case socket(SocketRef)
    /// A cable tie, anywhere on its band.
    case tie(TieID)
    case node(NodeID)
    /// A sticky note, anywhere on its rectangle.
    case note(CommentID)
    /// A wire within `EditorModel.wireHitDistance` of its taut route, named by its input endpoint.
    case wire(Endpoint)
    /// A comment frame, on its title bar or its edge band only.
    case frame(CommentID)
    /// The bottom-right handle of a selected comment: a press drags its size.
    case resize(CommentID)
    case empty
}
```

`Sources/CreatorEditor/EditorModel.swift`. Replace:
```swift
    @ObservationIgnored var lastClick: ClickTarget?
```
with:
```swift
    @ObservationIgnored var lastClick: ClickTarget?
    /// Where each wire was last picked, by a click or an ⌥-box, in stored canvas points: where ⌘⇧T puts a new tie
    /// (`EditorModel+Ties`, cable ties spec §4.2). View state, in memory only.
    @ObservationIgnored var wirePickPoints: [Endpoint: Vector2] = [:]
```
Replace the whole `hitTest` (its doc comment through its closing brace):
```swift
    /// What is under `screen` (canvas-local screen points): the frontmost node's socket within
    /// `NodeLayout.socketHitRadius` screen points, else the frontmost node, else a comment (`commentHit(at:)`:
    /// notes, then frames), else empty canvas.
    public func hitTest(_ screen: Vector2) -> CanvasHit {
        let point = transform.toCanvas(screen)
        let radius = NodeLayout.socketHitRadius / transform.zoom
        for node in drawOrder.reversed() {
            let shape = shape(of: node)
            let origin = displayOrigin(of: node)
            for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
                for socket in sockets {
                    guard let offset = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                    if (origin + offset - point).length <= radius {
                        return .socket(SocketRef(Endpoint(node: node.id, socket: socket.name), isInput: isInput))
                    }
                }
            }
            if CanvasRect(origin: origin, size: NodeLayout.size(shape)).contains(point) { return .node(node.id) }
        }
        return commentHit(at: point) ?? .empty
    }
```
with:
```swift
    /// What is under `screen` (canvas-local screen points; cable ties spec 2026-10-26 §4.1): the frontmost node's socket
    /// within `NodeLayout.socketHitRadius` screen points, else a tie's band, else the frontmost node, else a note
    /// (`noteHit(at:)`), else a wire within `wireHitDistance` of its taut route, else a frame's chrome (`frameHit(at:)`),
    /// else empty canvas. A tie beats the node it lies over, so one dropped on a node can still be grabbed.
    public func hitTest(_ screen: Vector2) -> CanvasHit {
        let point = transform.toCanvas(screen)
        let radius = NodeLayout.socketHitRadius / transform.zoom
        let routing = wireRouting
        let tie = tieHit(at: point, in: routing)
        for node in drawOrder.reversed() {
            let shape = shape(of: node)
            let origin = displayOrigin(of: node)
            for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
                for socket in sockets {
                    guard let offset = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                    if (origin + offset - point).length <= radius {
                        return .socket(SocketRef(Endpoint(node: node.id, socket: socket.name), isInput: isInput))
                    }
                }
            }
            if CanvasRect(origin: origin, size: NodeLayout.size(shape)).contains(point) {
                return tie.map(CanvasHit.tie) ?? .node(node.id)
            }
        }
        if let tie { return .tie(tie) }
        if let note = noteHit(at: point) { return note }
        if let wire = wireHit(at: point, in: routing) { return .wire(wire) }
        return frameHit(at: point) ?? .empty
    }
```

`Sources/CreatorEditor/EditorModel+CommentGeometry.swift`. Replace `commentHit(at:)` (its doc comment through its closing brace):
```swift
    /// The comment under `point` (display canvas points), topmost first: a selected comment's resize handle, a note
    /// anywhere on its rectangle, then a frame on its title bar or edge band. Notes beat frames, and the selected
    /// raise within their kind, as they draw. `nil` when no comment is there; nodes are tested before this.
    func commentHit(at point: Vector2) -> CanvasHit? {
        for note in drawOrderNotes.reversed() {
            let rect = frame(of: note)
            if canvasSelection.comments.contains(note.id), CommentLayout.handle(of: rect).contains(point) { return .resize(note.id) }
            if rect.contains(point) { return .note(note.id) }
        }
        for box in drawOrderFrames.reversed() {
            let rect = frame(of: box)
            if canvasSelection.comments.contains(box.id), CommentLayout.handle(of: rect).contains(point) { return .resize(box.id) }
            if CommentLayout.chromeContains(rect, point) { return .frame(box.id) }
        }
        return nil
    }
```
with:
```swift
    /// The note under `point` (display canvas points), topmost first: a selected note's resize handle, else a note anywhere
    /// on its rectangle; the selected raise, as they draw. `nil` when no note is there. Nodes and ties are tested before
    /// this, wires after it (`hitTest`, cable ties spec §4.1).
    func noteHit(at point: Vector2) -> CanvasHit? {
        for note in drawOrderNotes.reversed() {
            let rect = frame(of: note)
            if canvasSelection.comments.contains(note.id), CommentLayout.handle(of: rect).contains(point) { return .resize(note.id) }
            if rect.contains(point) { return .note(note.id) }
        }
        return nil
    }

    /// The frame under `point`: a selected frame's resize handle, else a frame on its title bar or edge band; the selected
    /// raise. `nil` when no frame is there. Wires are tested before this.
    func frameHit(at point: Vector2) -> CanvasHit? {
        for box in drawOrderFrames.reversed() {
            let rect = frame(of: box)
            if canvasSelection.comments.contains(box.id), CommentLayout.handle(of: rect).contains(point) { return .resize(box.id) }
            if CommentLayout.chromeContains(rect, point) { return .frame(box.id) }
        }
        return nil
    }
```

Append to `Sources/CreatorEditor/EditorModel+Wires.swift`, inside the extension:
```swift

    /// How close to a wire's taut route a press still hits it, in display canvas points (cable ties spec §4.1).
    public static let wireHitDistance = 5.0

    /// The frontmost tie whose band holds `point` (display canvas points).
    func tieHit(at point: Vector2, in routing: WireRouting) -> TieID? {
        drawOrderTies(in: routing).last { $0.band.contains(point) }?.id
    }

    /// The wire whose taut route passes nearest `point`, within `wireHitDistance`; on a tie, the lower endpoint.
    func wireHit(at point: Vector2, in routing: WireRouting) -> Endpoint? {
        routing.routes.values
            .map { ($0.wire, $0.distance(to: point)) }
            .filter { $0.1 <= Self.wireHitDistance }
            .min { ($0.1, $0.0) < ($1.1, $1.0) }?.0
    }
```

`Sources/CreatorEditor/EditorModel+Selection.swift`. Replace:
```swift
        case .note(let id), .frame(let id), .resize(let id): CanvasSelection(comments: [id])
        case .empty: nil
```
with:
```swift
        case .note(let id), .frame(let id), .resize(let id): CanvasSelection(comments: [id])
        case .wire(let wire): CanvasSelection(wires: [wire])
        case .tie(let id): CanvasSelection(ties: [id])
        case .empty: nil
```
Also replace its doc line `/// What a press on `hit` selects: the node, or a socket's node, or the comment; `nil` for empty canvas.` with `/// What a press on `hit` selects: the node, or a socket's node, the comment, the wire or the tie; `nil` for empty canvas.`

`Sources/CreatorEditor/EditorModel+Pointer.swift`. Replace:
```swift
        case nil:
            click(press.hit, mode: SelectionMode(press.modifiers))
```
with:
```swift
        case nil:
            click(press.hit, at: press.point, modifiers: press.modifiers)
```
Replace `click(_:mode:)` (doc comment through closing brace):
```swift
    /// A press that didn't move selects what it landed on as `mode` says (spec 2026-10-09 §3). On an item already
    /// selected, a plain click collapses the selection to it, ⌘ toggles it out and ⇧ keeps it. On empty canvas a
    /// plain click clears the selection and a modified one keeps it.
    private func click(_ hit: CanvasHit, mode: SelectionMode) {
        guard let items = items(for: hit) else {
            if mode == .replace { clearSelection() }
            return
        }
        select(items, mode: mode)
    }
```
with:
```swift
    /// A press that didn't move selects what it landed on as the modifiers held at the press say (`SelectionMode`, spec
    /// 2026-10-09 §3). On an item already selected, a plain click collapses the selection to it, ⌘ toggles it out and ⇧
    /// keeps it. On empty canvas a plain click clears the selection and a modified one keeps it. A click on a wire also
    /// remembers where it landed, for ⌘⇧T's tie (cable ties spec §4.2).
    private func click(_ hit: CanvasHit, at screen: Vector2, modifiers: CanvasModifiers) {
        let mode = SelectionMode(modifiers)
        guard let items = items(for: hit) else {
            if mode == .replace { clearSelection() }
            return
        }
        if case .wire(let wire) = hit { wirePickPoints[wire] = flow.stored(transform.toCanvas(screen)) }
        select(items, mode: mode)
    }
```
Replace:
```swift
        if case .socket(let socket) = hit {
            return .connecting(WireDrag(from: socket, current: transform.toCanvas(screen)))
        }
```
with:
```swift
        if case .socket(let socket) = hit {
            return .connecting(WireDrag(from: socket, current: transform.toCanvas(screen)))
        }
        // A drag that starts on a wire is a drag on empty canvas: a wire is selected by a click or an ⌥-box (cable ties
        // spec §4.1), never moved.
        if case .wire = hit { return emptyCanvasDrag(at: screen, modifiers: modifiers) }
```

`Sources/CreatorEditor/EditorModel+DoubleClick.swift`. Replace `        case .socket, .resize, .empty:` with `        case .socket, .resize, .wire, .tie, .empty:`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter CreatorEditorTests 2>&1 | tail -3`
Expected: passes. In the older tests a click on empty canvas that now lands on a wire still leaves `selection` empty. If an older test asserts `canvasSelection.isEmpty` after clicking exactly on a wire, move its click off the wire and say so in the commit body.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(editor): hit test and click-select wires and ties`, with the two trailer lines)

---

### Task 7: The ⌥-box for wires, the plain box and ⌘A for ties

Spec §4.1 (⌥-drag, plain box). Ruling R6.

**Files:**
- Modify: `Sources/CreatorEditor/CanvasInteraction.swift`, `Sources/CreatorEditor/EditorModel+Pointer.swift` (release, cancel, empty drag, update, a new `applyWireBox`), `Sources/CreatorEditor/EditorModel+Wires.swift`, `Sources/CreatorEditor/EditorModel+Selection.swift:27-30,42-46`, `Sources/CreatorEditor/CanvasLayers.swift:68-70`
- Test: `Tests/CreatorEditorTests/WireBoxSelectTests.swift`

**Interfaces:**
- Consumes: Task 4's `WireRoute.pointsInside(_:)`, `TieLayout.band`; Task 5's `CanvasSelection.applying(wires:mode:)`; Task 6's `wirePickPoints`.
- Produces:
  - `CanvasInteraction.wireBoxSelecting(start:current:base:mode:)`.
  - `EditorModel.wires(intersecting:in:) -> [Endpoint: Vector2]` (display coordinates, the mean inside point of each wire).
  - `EditorModel.ties(inside:in:) -> Set<TieID>` and `EditorModel.selectionBox: CanvasRect?`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/WireBoxSelectTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Boxes and wires (cable ties spec 2026-10-26 §4.1): an ⌥-drag on empty canvas selects only wires, those whose taut route
/// crosses or lies inside the box, in the mode the modifiers at its start fix (⌥ replaces, ⌥⇧ adds, ⌥⌘ toggles), keeping the
/// rest of the selection, and Esc puts back what it began with. A plain box never selects wires, and picks up ties whose band
/// lies inside it. ⌘A selects ties but no wire.
@MainActor
struct WireBoxSelectTests {
    let scene = TieScene()
    let overUpper = (Vector2(370, 40), Vector2(400, 80))
    let overLower = (Vector2(370, 240), Vector2(400, 280))

    @Test func anOptionBoxSelectsTheWiresItCrossesAndKeepsTheRest() {
        let editor = scene.editor(ties: [scene.tie(at: Vector2(384, 600), holding: [scene.lower, scene.third])])
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], wires: [scene.third], ties: [tieID(1)])
        editor.drag(overUpper.0, overUpper.1, modifiers: .option)
        #expect(editor.canvasSelection == CanvasSelection(nodes: [scene.a1.id], wires: [scene.upper], ties: [tieID(1)]),
                "⌥ replaces the wires only")
        #expect(!editor.document.canUndo)
    }

    @Test func optionShiftAddsAndOptionCommandToggles() {
        let editor = scene.editor()
        editor.drag(overUpper.0, overUpper.1, modifiers: .option)
        editor.drag(overLower.0, overLower.1, modifiers: [.option, .shift])
        #expect(editor.canvasSelection.wires == [scene.upper, scene.lower])
        editor.drag(overUpper.0, overUpper.1, modifiers: [.option, .command])
        #expect(editor.canvasSelection.wires == [scene.lower])
        editor.drag(overLower.0, overLower.1, modifiers: [.option, .command, .shift])
        #expect(editor.canvasSelection.wires.isEmpty, "⌘ wins over ⇧")
    }

    @Test func aBoxTheWiresOnlyCrossSelectsThem() {
        let editor = scene.editor()
        editor.drag(Vector2(380, 0), Vector2(390, 300), modifiers: .option)
        #expect(editor.canvasSelection.wires == [scene.upper, scene.lower], "crossing counts, not only lying inside")
        editor.drag(Vector2(100, 500), Vector2(700, 520), modifiers: .option)
        #expect(editor.canvasSelection.wires.isEmpty, "a box over nothing replaces the wires with none")
    }

    @Test func theModeIsTheOneTheDragStartedWithAndEscPutsTheSelectionBack() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], wires: [scene.third])
        editor.pointerDragged(from: overUpper.0, to: overUpper.0, modifiers: .option)
        editor.pointerDragged(from: overUpper.0, to: overUpper.1, modifiers: .option)
        editor.pointerDragged(from: overUpper.0, to: overUpper.1 + Vector2(1, 0), modifiers: [])
        guard case .wireBoxSelecting(_, _, _, let mode)? = editor.interaction else {
            Issue.record("expected a wire box"); return
        }
        #expect(mode == .replace && editor.canvasSelection.wires == [scene.upper])
        #expect(editor.selectionBox == CanvasRect(corner: overUpper.0, overUpper.1 + Vector2(1, 0)))
        #expect(editor.perform(.cancel))
        #expect(editor.canvasSelection == CanvasSelection(nodes: [scene.a1.id], wires: [scene.third]))
        #expect(editor.interaction == nil && editor.selectionBox == nil)
        editor.pointerReleased(from: overUpper.0, at: overUpper.1, modifiers: .option)
        #expect(editor.canvasSelection == CanvasSelection(nodes: [scene.a1.id], wires: [scene.third]))
    }

    @Test func anOptionBoxRemembersWhereEachWireLayInsideIt() throws {
        let editor = scene.editor()
        editor.drag(Vector2(370, 40), Vector2(400, 280), modifiers: .option)
        let upper = try #require(editor.wirePickPoints[scene.upper]), lower = try #require(editor.wirePickPoints[scene.lower])
        #expect(abs(upper.y - 60) < 1e-9 && (370...400).contains(upper.x))
        #expect(abs(lower.y - 260) < 1e-9 && (370...400).contains(lower.x))
    }

    @Test func aPlainBoxNeverSelectsWires() {
        let editor = scene.editor()
        editor.drag(overUpper.0, overUpper.1)
        #expect(editor.canvasSelection.isEmpty)
    }

    @Test func aPlainBoxPicksUpTiesWhoseBandLiesInsideIt() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.drag(Vector2(370, 150), Vector2(400, 170))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        editor.drag(Vector2(383, 150), Vector2(400, 170))
        #expect(editor.canvasSelection.isEmpty, "a box over part of the band leaves it")
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        editor.drag(Vector2(370, 150), Vector2(400, 170), modifiers: .command)
        #expect(editor.canvasSelection.isEmpty, "⌘ toggles ties like nodes")
    }

    @Test func selectAllSelectsTiesButNoWire() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selectAll()
        #expect(editor.canvasSelection == CanvasSelection(nodes: Set(scene.nodes.map(\.id)), ties: [tieID(1)]))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -5`
Expected: "type 'CanvasInteraction' has no member 'wireBoxSelecting'".

- [ ] **Step 3: Write the boxes**

`Sources/CreatorEditor/CanvasInteraction.swift`. Replace:
```swift
    case boxSelecting(start: Vector2, current: Vector2, base: CanvasSelection, mode: SelectionMode)
    case connecting(WireDrag)
```
with:
```swift
    case boxSelecting(start: Vector2, current: Vector2, base: CanvasSelection, mode: SelectionMode)
    /// An ⌥-drag on empty canvas (cable ties spec 2026-10-26 §4.1): a box that selects wires only, those whose taut route
    /// crosses or lies inside it, combined with `base`'s wires as `mode` says (⌥ replaces, ⌥⇧ adds, ⌥⌘ toggles). Nodes,
    /// comments and ties keep `base`'s selection.
    case wireBoxSelecting(start: Vector2, current: Vector2, base: CanvasSelection, mode: SelectionMode)
    case connecting(WireDrag)
```

`Sources/CreatorEditor/EditorModel+Pointer.swift`. Replace:
```swift
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .panning: break
        }
        endPress()
```
with:
```swift
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .wireBoxSelecting(let start, _, let base, let mode):
            applyWireBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .panning: break
        }
        endPress()
```
Replace:
```swift
        case .boxSelecting(_, _, let base, _)?: canvasSelection = base
```
with:
```swift
        case .boxSelecting(_, _, let base, _)?, .wireBoxSelecting(_, _, let base, _)?: canvasSelection = base
```
Replace:
```swift
    private func emptyCanvasDrag(at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        let point = transform.toCanvas(screen)
        return .boxSelecting(start: point, current: point, base: canvasSelection, mode: SelectionMode(modifiers))
    }
```
with:
```swift
    private func emptyCanvasDrag(at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        let point = transform.toCanvas(screen)
        // ⌥ makes it a box of wires only (cable ties spec §4.1); ⇧ and ⌘ still say how it combines.
        if modifiers.contains(.option) {
            return .wireBoxSelecting(start: point, current: point, base: canvasSelection, mode: SelectionMode(modifiers))
        }
        return .boxSelecting(start: point, current: point, base: canvasSelection, mode: SelectionMode(modifiers))
    }
```
Replace:
```swift
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .connecting(var wire):
```
with:
```swift
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .wireBoxSelecting(let start, _, let base, let mode):
            applyWireBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .connecting(var wire):
```
Add after `applyBox(from:to:base:mode:)`:
```swift

    /// The ⌥-box from `start` to `current` (display canvas points): the wires its taut routes cross, combined with the wires
    /// the drag began with as `mode` says, the rest of the selection as it began. Each wire it finds remembers where it lay
    /// inside the box, for ⌘⇧T (cable ties spec §4.2).
    private func applyWireBox(from start: Vector2, to current: Vector2, base: CanvasSelection, mode: SelectionMode) {
        setInteraction(.wireBoxSelecting(start: start, current: current, base: base, mode: mode))
        let found = wires(intersecting: CanvasRect(corner: start, current), in: wireRouting)
        for (wire, point) in found { wirePickPoints[wire] = flow.stored(point) }
        canvasSelection = base.applying(wires: Set(found.keys), mode: mode)
    }
```

Append to `Sources/CreatorEditor/EditorModel+Wires.swift`, inside the extension:
```swift

    /// The wires whose taut route crosses or lies inside `rect` (display canvas points), each with the centre of the middles
    /// of its stretches inside it: what an ⌥-box finds (cable ties spec §4.1, §4.2).
    func wires(intersecting rect: CanvasRect, in routing: WireRouting) -> [Endpoint: Vector2] {
        routing.routes.values.reduce(into: [:]) { found, route in
            let inside = route.pointsInside(rect)
            guard !inside.isEmpty else { return }
            found[route.wire] = inside.reduce(Vector2.zero, +) * (1 / Double(inside.count))
        }
    }

    /// The ties whose band lies wholly inside `rect`: what a plain box picks up (cable ties spec §4.1).
    func ties(inside rect: CanvasRect, in routing: WireRouting) -> Set<TieID> {
        Set(routing.ties.values.filter { rect.contains($0.band.origin) && rect.contains(Vector2($0.band.maxX, $0.band.maxY)) }
            .map(\.id))
    }

    /// The box being dragged on empty canvas, plain or ⌥ (display canvas points); `nil` while there is none.
    public var selectionBox: CanvasRect? {
        switch interaction {
        case .boxSelecting(let start, let current, _, _)?, .wireBoxSelecting(let start, let current, _, _)?:
            CanvasRect(corner: start, current)
        default:
            nil
        }
    }
```

`Sources/CreatorEditor/EditorModel+Selection.swift`. Replace:
```swift
    /// Everything on the canvas: every node and every comment.
    public var allItems: CanvasSelection {
        CanvasSelection(nodes: Set(graph.nodes.keys), comments: graph.commentIDs)
    }
```
with:
```swift
    /// Everything on the canvas: every node, comment and tie. Never a wire, as a plain box never selects one (cable ties plan
    /// ruling R6).
    public var allItems: CanvasSelection {
        CanvasSelection(nodes: Set(graph.nodes.keys), comments: graph.commentIDs, ties: Set(graph.ties.keys))
    }
```
Replace:
```swift
    /// What a box covers: the nodes and notes whose drawn rectangle meets `rect` (display canvas points) and the
    /// frames whose chrome does.
    public func items(intersecting rect: CanvasRect) -> CanvasSelection {
        CanvasSelection(nodes: nodes(intersecting: rect), comments: comments(intersecting: rect))
    }
```
with:
```swift
    /// What a plain box covers: the nodes and notes whose drawn rectangle meets `rect` (display canvas points), the
    /// frames whose chrome does, and the ties whose band lies wholly inside it (cable ties spec §4.1). Never a wire.
    public func items(intersecting rect: CanvasRect) -> CanvasSelection {
        CanvasSelection(nodes: nodes(intersecting: rect), comments: comments(intersecting: rect),
                        ties: ties(inside: rect, in: wireRouting))
    }
```

`Sources/CreatorEditor/CanvasLayers.swift`. Replace:
```swift
            if case .boxSelecting(let start, let current, _, _)? = model.interaction {
                BoxSelectionView(rect: CanvasRect(corner: start, current)).equatable()
            }
```
with:
```swift
            if let box = model.selectionBox {
                BoxSelectionView(rect: box).equatable()
            }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter CreatorEditorTests 2>&1 | tail -3`
Expected: passes. `BoxSelectModeTests` and `PressModifierTests` are unchanged, and their boxes never hold ⌥.
Run: `swift test --filter 'ContinuingPressCancelWindowTests|CanvasCancelWindowTests' 2>&1 | tail -3`
Expected: passes.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(editor): the ⌥-box selects wires; a plain box and ⌘A pick up ties`, with the two trailer lines)

---

### Task 8: ⌘⇧T ties the selected wires

Spec §4.2. Rulings R9, R10.

**Files:**
- Modify: `Sources/CreatorEditor/GraphKeyCommand.swift`, `Sources/CreatorEditor/GraphKeyBindings.swift:52-66`, `Sources/CreatorEditor/EditorModel+Commands.swift:14,30-45`
- Create: `Sources/CreatorEditor/EditorModel+Ties.swift`
- Modify (test): `Tests/CreatorEditorTests/GraphKeyEventTests.swift`
- Test: `Tests/CreatorEditorTests/TieKeyTests.swift`

**Interfaces:**
- Consumes: Task 6's `wirePickPoints` and click points; Task 7's box points; Task 4's `WireRoute.middle`; Task 1's `UndoName.tieWires/addToTie`.
- Produces:
  - `GraphKeyCommand.tieWires`.
  - `EditorModel.tieSelectedWires()`, `EditorModel.tieRefusal: String` (static) and `EditorModel.tiePosition(of:) -> Vector2`.
  - `EditorModel.commit(_ tie: CableTie, named:)` (private).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/CreatorEditorTests/GraphKeyEventTests.swift`, inside the struct, after `theCommandChordsKeepTheirModifiers`:
```swift

    /// ⌘⇧T ties wires (cable ties spec 2026-10-26 §4.2). The check is `.primary`, so it is Ctrl+Shift+T off macOS.
    @Test func commandShiftTTiesWires() {
        #expect(command(KeyEquivalent("t"), "T", [.primary, .shift]) == .tieWires)
        #expect(command(KeyEquivalent("T"), "T", [.primary, .shift]) == .tieWires, "AppKit reports a shifted letter upper-case")
        #expect(command(KeyEquivalent("t"), nil, .primary) == nil, "⌘T alone is nothing")
        #expect(command(KeyEquivalent("t"), "T", [.option, .shift]) == nil)
    }
```

`Tests/CreatorEditorTests/TieKeyTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// ⌘⇧T (cable ties spec 2026-10-26 §4.2): with no tie selected and two or more wires, a tie holding them where they were
/// picked, selected alone ("Tie Wires"); with one tie and one or more new wires, the wires join it ("Add to Tie"); anything
/// else is refused. It acts only while the panel shows and no drag is under way.
@MainActor
struct TieKeyTests {
    let scene = TieScene()

    @Test func twoClickedWiresAreTiedAtTheCentreOfTheClicks() throws {
        let editor = scene.editor()
        editor.click(scene.upperMiddle)
        editor.click(scene.lowerMiddle, modifiers: .shift)
        #expect(editor.perform(.tieWires))
        let tie = try #require(editor.graph.ties.values.first)
        #expect(editor.graph.ties.count == 1)
        #expect(tie.wires == [scene.upper, scene.lower])
        #expect(tie.position == Vector2(384, 160))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tie.id]), "the selection becomes the new tie")
        #expect(editor.document.undoName == "Tie Wires")
        editor.perform(.undo)
        #expect(editor.graph.ties.isEmpty)
    }

    @Test func boxedWiresAreTiedAtTheCentreOfWhereTheyLayInTheBox() throws {
        let editor = scene.editor()
        editor.drag(Vector2(370, 40), Vector2(400, 280), modifiers: .option)
        editor.perform(.tieWires)
        let tie = try #require(editor.graph.ties.values.first)
        #expect(tie.wires == [scene.upper, scene.lower])
        #expect(abs(tie.position.y - 160) < 1e-9 && (370...400).contains(tie.position.x))
    }

    @Test func inTheLeftDockTheTieGoesToTheStoredCentre() throws {
        let editor = scene.editor(dock: .left)
        let upper = try #require(editor.wireRouting.routes[scene.upper]?.pieces.first?.point(at: 0.5))
        let lower = try #require(editor.wireRouting.routes[scene.lower]?.pieces.first?.point(at: 0.5))
        editor.click(upper)
        editor.click(lower, modifiers: .shift)
        editor.perform(.tieWires)
        let tie = try #require(editor.graph.ties.values.first)
        #expect(tie.position == editor.flow.stored((upper + lower) * 0.5))
        #expect(tie.position == Vector2(338, 194), "the transpose of the drawn centre (194, 338)")
    }

    @Test func aTieAndAnotherWireAddTheWireToTheTie() throws {
        let editor = scene.editor(ties: [scene.tie()])
        editor.click(Vector2(384, 160))
        editor.click(scene.thirdMiddle, modifiers: .shift)
        editor.perform(.tieWires)
        let tie = try #require(editor.graph.ties[tieID(1)])
        #expect(tie.wires == [scene.upper, scene.lower, scene.third])
        #expect(tie.position == Vector2(384, 160), "adding leaves the tie where it is")
        #expect(editor.graph.ties.count == 1)
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        #expect(editor.document.undoName == "Add to Tie")
    }

    @Test func anythingElseIsRefusedAndChangesNothing() {
        let selections = [
            CanvasSelection(),
            CanvasSelection(wires: [scene.upper]),
            CanvasSelection(nodes: [scene.a1.id, scene.b1.id]),
            CanvasSelection(ties: [tieID(1)]),
            CanvasSelection(wires: [scene.third], ties: [tieID(1), tieID(2)]),
            CanvasSelection(wires: [scene.upper], ties: [tieID(1)]),
        ]
        for selection in selections {
            let editor = scene.editor(ties: [scene.tie(1), scene.tie(2, at: Vector2(384, 360), holding: [scene.lower, scene.third])])
            let before = editor.graph
            editor.canvasSelection = selection
            #expect(editor.perform(.tieWires), "the key is claimed: \(selection)")
            #expect(editor.graph == before && !editor.document.canUndo, "\(selection)")
            #expect(editor.refusal?.message == EditorModel.tieRefusal, "\(selection)")
        }
    }

    @Test func itActsOnlyWhileThePanelShowsAndNothingIsDragged() {
        let hidden = scene.editor()
        hidden.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        hidden.setDock(.hidden)
        #expect(!hidden.perform(.tieWires))
        #expect(hidden.graph.ties.isEmpty)
        let dragging = scene.editor()
        dragging.pointerDragged(from: Vector2(384, 380), to: Vector2(384, 380))
        dragging.pointerDragged(from: Vector2(384, 380), to: Vector2(450, 420))
        dragging.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        #expect(dragging.perform(.tieWires), "claimed during a drag")
        #expect(dragging.graph.ties.isEmpty, "and does nothing")
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -5`
Expected: "type 'GraphKeyCommand' has no member 'tieWires'".

- [ ] **Step 3: Write the command**

`Sources/CreatorEditor/GraphKeyCommand.swift`. Replace:
```swift
    /// ⌘⇧C: frames the selection.
    case addFrame
```
with:
```swift
    /// ⌘⇧C: frames the selection.
    case addFrame
    /// ⌘⇧T: ties the selected wires, or adds them to the selected tie (cable ties spec 2026-10-26 §4.2).
    case tieWires
```

`Sources/CreatorEditor/GraphKeyBindings.swift`. Replace:
```swift
    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo, ⌘G into ungroup, ⌘C into Frame Selection
    /// and ⌘N into Add Note. ⌘↓ and ⌘↑ (the arrows' private-use characters) go into and out of a group.
    static func commandChord(for character: String, shifted: Bool) -> GraphKeyCommand? {
        switch character {
        case "c": shifted ? .addFrame : .copy
        case "n": shifted ? .addNote : nil
```
with:
```swift
    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo, ⌘G into ungroup, ⌘C into Frame Selection,
    /// ⌘N into Add Note and ⌘T into Tie Wires. ⌘↓ and ⌘↑ (the arrows' private-use characters) go into and out of a group.
    static func commandChord(for character: String, shifted: Bool) -> GraphKeyCommand? {
        switch character {
        case "c": shifted ? .addFrame : .copy
        case "n": shifted ? .addNote : nil
        case "t": shifted ? .tieWires : nil
```

`Sources/CreatorEditor/EditorModel+Commands.swift`. Replace `        case .selectAll, .nudge, .frameSelection, .cut, .addNote, .addFrame:` with `        case .selectAll, .nudge, .frameSelection, .cut, .addNote, .addFrame, .tieWires:`. Replace:
```swift
        case .addFrame: return addFrameAroundSelection()
        default: return false // `perform(_:)` routes every other command elsewhere.
```
with:
```swift
        case .addFrame: return addFrameAroundSelection()
        case .tieWires: tieSelectedWires()
        default: return false // `perform(_:)` routes every other command elsewhere.
```
Also change the function's doc line `/// The selection's keys (spec 2026-10-09 §3), and ⌘X.` to `/// The selection's keys (spec 2026-10-09 §3), ⌘X and ⌘⇧T.`.

`Sources/CreatorEditor/EditorModel+Ties.swift`
```swift
import CreatorGeometry
import CreatorGraph

/// Tying wires (cable ties spec 2026-10-26 §4.2, §4.4).
extension EditorModel {
    /// What ⌘⇧T says when there is nothing it can do (spec §4.2's "anything else"; no node to shake).
    static let tieRefusal = "Select two or more wires to tie, or one tie and the wires to add to it."

    /// ⌘⇧T. With no tie selected and two or more wires, it ties the wires where they were picked and selects the new tie
    /// alone ("Tie Wires"). With exactly one tie selected and one or more wires it doesn't hold yet, it adds them to the
    /// tie and selects the tie ("Add to Tie"). Anything else is refused. Selected wires and ties that are gone (undone)
    /// count for nothing.
    public func tieSelectedWires() {
        let wires = canvasSelection.wires.filter { graph.incomingLink(to: $0) != nil }
        let ties = canvasSelection.ties.compactMap { graph.ties[$0] }
        if ties.isEmpty, wires.count >= CableTie.minimumWires {
            commit(CableTie(position: tiePosition(of: wires), wires: wires), named: UndoName.tieWires)
        } else if ties.count == 1, var tie = ties.first, !wires.isEmpty, !wires.isSubset(of: tie.wires) {
            tie.wires.formUnion(wires)
            commit(tie, named: UndoName.addToTie)
        } else {
            refuse(Self.tieRefusal, node: nil)
        }
    }

    /// Where a new tie goes (cable ties plan ruling R10): the centre of the points its wires were picked at, by a click or an
    /// ⌥-box, in stored coordinates. A wire with no such point counts its route's middle.
    func tiePosition(of wires: Set<Endpoint>) -> Vector2 {
        let routing = wireRouting
        let points = wires.sorted().compactMap { wire in
            wirePickPoints[wire] ?? routing.routes[wire].map { flow.stored($0.middle) }
        }
        guard !points.isEmpty else { return .zero }
        return points.reduce(Vector2.zero, +) * (1 / Double(points.count))
    }

    /// Sets `tie` as one undo step called `name`, then selects it alone.
    private func commit(_ tie: CableTie, named name: String) {
        do {
            try edit(.setTie(tie), name: name)
            canvasSelection = CanvasSelection(ties: [tie.id])
        } catch {
            refuse(error.message, node: nil)
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter 'TieKeyTests|GraphKeyEventTests|KeyCommandTests|SelectionKeyTests' 2>&1 | tail -3`
Expected: passes.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(editor): ⌘⇧T ties the selected wires or adds them to the selected tie`, with the two trailer lines)

---

### Task 9: Moving, nudging, deleting and untying ties

Spec §4.3, §4.4. Rulings R8, R14, R16. Review Focus 1 and 4.

**Files:**
- Modify: `Sources/CreatorEditor/SelectionPositions.swift` (whole file), `Sources/CreatorEditor/EditorModel+Selection.swift:48-86`, `Sources/CreatorEditor/EditorModel+Pointer.swift:149-150` and `click`, `Sources/CreatorEditor/EditorModel+Nudge.swift:19`, `Sources/CreatorEditor/EditorModel+Editing.swift:31-50`, `Sources/CreatorEditor/EditorModel+Ties.swift`, `Sources/CreatorEditor/EditorModel+Wires.swift`
- Test: `Tests/CreatorEditorTests/TieEditingTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 2, 4, 6 and 8.
- Produces:
  - `SelectionPositions.ties: [TieID: Vector2]` and `init(nodes:comments:ties:)`.
  - `EditorModel.moveName(of: SelectionPositions) -> String`.
  - `EditorModel.untie(at screen: Vector2, from: TieID) -> Bool` (internal) and `EditorModel.laneWire(of:near:in:) -> Endpoint?`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/TieEditingTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Editing ties (cable ties spec 2026-10-26 §4.3, §4.4). A drag or an arrow moves a tie as one undo step ("Move Tie", "Move"
/// with other items). Delete removes selected ties ("Remove Tie") and does nothing with only wires selected. ⌥-click on a
/// wire's lane unties it ("Untie Wire"), (I2) applying. Deleting a node or a wire takes its wires out of their ties, and
/// everything undoes.
@MainActor
struct TieEditingTests {
    let scene = TieScene()

    @Test func draggingATieMovesItAsOneUndoStep() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.pointerDragged(from: Vector2(384, 160), to: Vector2(384, 160))
        editor.pointerDragged(from: Vector2(384, 160), to: Vector2(404, 180))
        editor.pointerDragged(from: Vector2(384, 160), to: Vector2(434, 200))
        editor.pointerReleased(from: Vector2(384, 160), at: Vector2(434, 200))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(434, 200))
        #expect(editor.canvasSelection == CanvasSelection(ties: [tieID(1)]))
        #expect(editor.document.undoName == "Move Tie")
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(384, 160), "one step")
    }

    @Test func aTieMovesTogetherWithSelectedNodes() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(nodes: [scene.a1.id], ties: [tieID(1)])
        editor.drag(Vector2(20, 40), Vector2(50, 50))
        #expect(editor.graph.nodes[scene.a1.id]?.position == Vector2(30, 10))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(414, 170))
        #expect(editor.document.undoName == "Move")
        editor.perform(.undo)
        #expect(editor.graph.nodes[scene.a1.id]?.position == .zero && editor.graph.ties[tieID(1)]?.position == Vector2(384, 160))
    }

    @Test func aTieDraggedInTheLeftDockMovesInStoredCoordinates() {
        let editor = scene.editor(ties: [scene.tie()], dock: .left)
        editor.drag(Vector2(160, 384), Vector2(160, 434))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(434, 160))
    }

    @Test func anArrowNudgesASelectedTie() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        #expect(editor.perform(.nudge(Vector2(10, 0), isRepeat: false)))
        #expect(editor.graph.ties[tieID(1)]?.position == Vector2(394, 160))
        #expect(editor.document.undoName == "Move Tie")
    }

    @Test func deleteRemovesSelectedTiesAndLeavesTheirWires() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.canvasSelection = CanvasSelection(ties: [tieID(1)])
        editor.perform(.deleteSelection)
        #expect(editor.graph.ties.isEmpty && editor.graph.links.count == 3)
        #expect(editor.canvasSelection.isEmpty)
        #expect(editor.document.undoName == "Remove Tie")
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)] == scene.tie())
    }

    @Test func deleteWithOnlyWiresSelectedDoesNothing() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        editor.perform(.deleteSelection)
        #expect(editor.graph.links.count == 3 && !editor.document.canUndo && editor.refusal == nil)
    }

    @Test func deletingANodeTakesItsWiresOutOfTheirTies() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = [scene.b1.id]
        editor.perform(.deleteSelection)
        #expect(editor.graph.ties.isEmpty, "upper left, and one wire is no tie")
        #expect(editor.document.undoName == "Delete")
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)] == scene.tie())
    }

    @Test func deletingANodeAndItsTieTogetherIsOneStep() {
        let editor = scene.editor(ties: [scene.tie()])
        let before = editor.graph
        editor.canvasSelection = CanvasSelection(nodes: [scene.b1.id], ties: [tieID(1)])
        editor.perform(.deleteSelection)
        #expect(editor.graph.ties.isEmpty && editor.graph.nodes[scene.b1.id] == nil && editor.refusal == nil)
        #expect(editor.document.undoName == "Delete")
        editor.perform(.undo)
        #expect(editor.graph == before)
    }

    @Test func draggingAWiredInputOffUntiesItsWire() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.drag(Vector2(600, 60), Vector2(900, 600))
        #expect(editor.graph.incomingLink(to: scene.upper) == nil)
        #expect(editor.graph.ties.isEmpty)
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)] == scene.tie())
    }

    /// Three wires at (384, 160): lanes `upper` 156, `lower` 160, `third` 164. Once `upper` leaves, two are left, on lanes
    /// 158 and 162.
    @Test func anOptionClickOnALaneUntiesThatWire() {
        let editor = scene.editor(ties: [scene.tie(holding: [scene.upper, scene.lower, scene.third])])
        editor.click(Vector2(384, 156), modifiers: .option)
        #expect(editor.graph.ties[tieID(1)]?.wires == [scene.lower, scene.third])
        #expect(editor.document.undoName == "Untie Wire")
        editor.click(Vector2(384, 158), modifiers: .option)
        #expect(editor.graph.ties.isEmpty, "untying one of two removes the tie (I2)")
        #expect(!editor.canvasSelection.ties.contains(tieID(1)))
        editor.perform(.undo)
        editor.perform(.undo)
        #expect(editor.graph.ties[tieID(1)]?.wires == [scene.upper, scene.lower, scene.third])
    }

    @Test func anOptionClickOnAPlainWireSelectsIt() {
        let editor = scene.editor(ties: [scene.tie(at: Vector2(384, 600))])
        editor.click(scene.thirdMiddle, modifiers: .option)
        #expect(editor.canvasSelection == CanvasSelection(wires: [scene.third]))
        #expect(!editor.document.canUndo)
    }

    @Test func aGoneTieOrWireInTheSelectionIsSkipped() {
        let editor = scene.editor()
        editor.canvasSelection = CanvasSelection(wires: [scene.upper, scene.lower])
        editor.perform(.tieWires)
        editor.perform(.undo)
        #expect(editor.graph.ties.isEmpty && editor.canvasSelection.ties.count == 1, "set up: the selection names a gone tie")
        editor.perform(.deleteSelection)
        #expect(!editor.document.canUndo && editor.refusal == nil, "Delete skips it without a step")
        #expect(!editor.perform(.nudge(Vector2(1, 0), isRepeat: false)), "nothing to nudge")
        editor.canvasSelection.wires = [scene.upper]
        editor.perform(.tieWires)
        #expect(editor.graph.ties.isEmpty && editor.refusal?.message == EditorModel.tieRefusal)
        editor.drag(Vector2(384, 160), Vector2(434, 200))
        #expect(!editor.document.canUndo, "the drag where the tie was is a box")
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter TieEditingTests 2>&1 | grep -cE "recorded an issue"`
Expected: a non-zero count. The tie doesn't move, Delete leaves it, and ⌥-click selects instead of untying.

- [ ] **Step 3: Write the editing**

`Sources/CreatorEditor/SelectionPositions.swift` (whole file)
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Where the selected items were when a drag began, in stored (left-to-right) canvas points: what a move offsets
/// and an ⌥-drag copies. A comment's position is its frame's origin; a tie's is its position (cable ties spec §4.3).
public struct SelectionPositions: Equatable, Sendable {
    public var nodes: [NodeID: Vector2]
    public var comments: [CommentID: Vector2]
    public var ties: [TieID: Vector2]

    public init(nodes: [NodeID: Vector2] = [:], comments: [CommentID: Vector2] = [:], ties: [TieID: Vector2] = [:]) {
        self.nodes = nodes
        self.comments = comments
        self.ties = ties
    }

    public var isEmpty: Bool { nodes.isEmpty && comments.isEmpty && ties.isEmpty }

    /// The items these positions are of.
    public var items: CanvasSelection {
        CanvasSelection(nodes: Set(nodes.keys), comments: Set(comments.keys), ties: Set(ties.keys))
    }
}
```

`Sources/CreatorEditor/EditorModel+Selection.swift`. Replace `positions(of:)`, `moveCommands(from:by:)` and `bounds(of:)` (from `    /// Where `items` are now` to the end of the extension):
```swift
    /// Where `items` are now (stored coordinates; a comment's is its frame's origin), skipping any no longer on the
    /// canvas.
    public func positions(of items: CanvasSelection) -> SelectionPositions {
        SelectionPositions(
            nodes: Dictionary(uniqueKeysWithValues: items.nodes.compactMap { id in
                graph.nodes[id].map { (id, $0.position) }
            }),
            comments: Dictionary(uniqueKeysWithValues: items.comments.compactMap { id in
                (graph.stickies[id]?.frame.origin ?? graph.frames[id]?.frame.origin).map { (id, $0) }
            }))
    }

    /// The commands that put every item of `start` at its position there plus `delta` (stored coordinates), in a
    /// stable order: the nodes by ID, then the comments by ID. A comment that is gone is skipped.
    public func moveCommands(from start: SelectionPositions, by delta: Vector2) -> [GraphCommand] {
        let nodeMoves = start.nodes.keys.sorted().compactMap { id in
            start.nodes[id].map { GraphCommand.move(id, to: $0 + delta) }
        }
        let commentMoves = start.comments.keys.sorted().compactMap { id -> GraphCommand? in
            guard let origin = start.comments[id] else { return nil }
            if var note = graph.stickies[id] {
                note.frame.origin = origin + delta
                return .setSticky(note)
            }
            guard var box = graph.frames[id] else { return nil }
            box.frame.origin = origin + delta
            return .setFrame(box)
        }
        return nodeMoves + commentMoves
    }

    /// The smallest rectangle (display canvas points) around the drawn rectangles of those `items` still on the
    /// canvas, comments included; `nil` when there are none.
    public func bounds(of items: CanvasSelection) -> CanvasRect? {
        let frames = items.nodes.compactMap { graph.nodes[$0] }.map { frame(of: $0) }
            + items.comments.sorted().compactMap { frame(ofComment: $0) }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }
```
with:
```swift
    /// Where `items` are now (stored coordinates; a comment's is its frame's origin, a tie's its position), skipping any no
    /// longer on the canvas.
    public func positions(of items: CanvasSelection) -> SelectionPositions {
        SelectionPositions(
            nodes: Dictionary(uniqueKeysWithValues: items.nodes.compactMap { id in
                graph.nodes[id].map { (id, $0.position) }
            }),
            comments: Dictionary(uniqueKeysWithValues: items.comments.compactMap { id in
                (graph.stickies[id]?.frame.origin ?? graph.frames[id]?.frame.origin).map { (id, $0) }
            }),
            ties: Dictionary(uniqueKeysWithValues: items.ties.compactMap { id in
                graph.ties[id].map { (id, $0.position) }
            }))
    }

    /// The commands that put every item of `start` at its position there plus `delta` (stored coordinates), in a
    /// stable order: the nodes by ID, then the comments, then the ties by ID. An item that is gone is skipped.
    public func moveCommands(from start: SelectionPositions, by delta: Vector2) -> [GraphCommand] {
        let nodeMoves = start.nodes.keys.sorted().compactMap { id in
            start.nodes[id].map { GraphCommand.move(id, to: $0 + delta) }
        }
        let commentMoves = start.comments.keys.sorted().compactMap { id -> GraphCommand? in
            guard let origin = start.comments[id] else { return nil }
            if var note = graph.stickies[id] {
                note.frame.origin = origin + delta
                return .setSticky(note)
            }
            guard var box = graph.frames[id] else { return nil }
            box.frame.origin = origin + delta
            return .setFrame(box)
        }
        let tieMoves = start.ties.keys.sorted().compactMap { id -> GraphCommand? in
            guard var tie = graph.ties[id], let position = start.ties[id] else { return nil }
            tie.position = position + delta
            return .setTie(tie)
        }
        return nodeMoves + commentMoves + tieMoves
    }

    /// The undo name of a move of `start`: "Move Tie" when only ties move (cable ties spec §4.3), else "Move".
    func moveName(of start: SelectionPositions) -> String {
        start.nodes.isEmpty && start.comments.isEmpty && !start.ties.isEmpty ? UndoName.moveTie : UndoName.move
    }

    /// The smallest rectangle (display canvas points) around the drawn rectangles of those `items` still on the
    /// canvas, comments and tie bands included; `nil` when there are none.
    public func bounds(of items: CanvasSelection) -> CanvasRect? {
        let routing = items.ties.isEmpty ? nil : wireRouting
        let frames = items.nodes.compactMap { graph.nodes[$0] }.map { frame(of: $0) }
            + items.comments.sorted().compactMap { frame(ofComment: $0) }
            + items.ties.sorted().compactMap { routing?.ties[$0]?.band }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }
```

`Sources/CreatorEditor/EditorModel+Pointer.swift`. Replace:
```swift
            try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key, name: UndoName.move)
```
with:
```swift
            try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key, name: moveName(of: start))
```
In `click(_:at:modifiers:)`, replace:
```swift
        let mode = SelectionMode(modifiers)
        guard let items = items(for: hit) else {
```
with:
```swift
        // ⌥-click on a tie's band unties the wire on the nearest lane (cable ties spec §4.4).
        if modifiers.contains(.option), case .tie(let id) = hit, untie(at: screen, from: id) { return }
        let mode = SelectionMode(modifiers)
        guard let items = items(for: hit) else {
```

`Sources/CreatorEditor/EditorModel+Nudge.swift`. Replace:
```swift
        try? edit(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey, name: UndoName.move)
```
with:
```swift
        try? edit(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey, name: moveName(of: start))
```

`Sources/CreatorEditor/EditorModel+Editing.swift`. Replace:
```swift
    private func delete(named name: String) -> Bool {
        let present = canvasSelection.nodes.filter { graph.nodes[$0] != nil }
        let commands = present.filter { !isBoundary($0) }.sorted().map { GraphCommand.removeNode($0) }
            + canvasSelection.comments.sorted().compactMap { id -> GraphCommand? in
```
with:
```swift
    private func delete(named name: String) -> Bool {
        let present = canvasSelection.nodes.filter { graph.nodes[$0] != nil }
        // Ties first: a selected tie whose last wires go with a deleted node would be gone by the time its own removal ran.
        let ties = canvasSelection.ties.sorted().filter { graph.ties[$0] != nil }.map { GraphCommand.removeTie($0) }
        let commands = ties + present.filter { !isBoundary($0) }.sorted().map { GraphCommand.removeNode($0) }
            + canvasSelection.comments.sorted().compactMap { id -> GraphCommand? in
```
Replace:
```swift
        do {
            try edit(.batch(commands), name: name)
            canvasSelection = CanvasSelection()
            return true
```
with:
```swift
        do {
            // Ties alone are "Remove Tie" (cable ties spec §4.4), by Delete or ⌘X alike.
            try edit(.batch(commands), name: commands.count == ties.count ? UndoName.removeTie : name)
            canvasSelection = CanvasSelection()
            return true
```
Replace the doc line `    /// Delete / ⌫: removes the selected nodes and their wires and the selected comments, as one undo step. A deleted` with `    /// Delete / ⌫: removes the selected nodes and their wires, the selected comments and the selected ties, as one undo step; wires alone stay (cable ties spec §4.4). A deleted`.

Append to `Sources/CreatorEditor/EditorModel+Ties.swift`, inside the extension:
```swift

    /// ⌥-click on tie `id`'s band at `screen` (cable ties spec §4.4): takes the wire on the nearest lane out of the tie, or
    /// removes the tie when it would hold fewer than two (I2), as one undo step ("Untie Wire"). Returns whether there was a
    /// wire to untie.
    func untie(at screen: Vector2, from id: TieID) -> Bool {
        guard var tie = graph.ties[id], let wire = laneWire(of: id, near: transform.toCanvas(screen), in: wireRouting) else {
            return false
        }
        tie.wires.remove(wire)
        let removes = tie.wires.count < CableTie.minimumWires
        do {
            try edit(removes ? .removeTie(id) : .setTie(tie), name: UndoName.untieWire)
            if removes { canvasSelection.ties.remove(id) }
        } catch {
            refuse(error.message, node: nil)
        }
        return true
    }
```

Append to `Sources/CreatorEditor/EditorModel+Wires.swift`, inside the extension:
```swift

    /// The wire whose lane in tie `id` lies nearest `point` (display canvas points): the one an ⌥-click on the band unties.
    func laneWire(of id: TieID, near point: Vector2, in routing: WireRouting) -> Endpoint? {
        routing.ties[id]?.lanes.min { (($0.value - point).length, $0.key) < (($1.value - point).length, $1.key) }?.key
    }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter CreatorEditorTests 2>&1 | tail -3`
Expected: passes. `CanvasSelectionTests` and `CommentSelectionTests` build their `SelectionPositions` without `ties:` and keep passing.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(editor): move, nudge, delete and untie cable ties`, with the two trailer lines)

---

### Task 10: Copy, paste and duplicate ties, and ties at a group's level

Spec §3.4, §4.5 from the editor. Ruling R7.

**Files:**
- Modify: `Sources/CreatorEditor/NodeClipboard.swift:13`, `Sources/CreatorEditor/EditorModel+Editing.swift:112-179`
- Test: `Tests/CreatorEditorTests/TieClipboardTests.swift`

**Interfaces:**
- Consumes: Task 1's `CableTie`; Task 5's `CanvasSelection.ties`; Task 8's `tieSelectedWires()`; `EditorModel.perform(.group)` and `.enterGroup`.
- Produces: `NodeClipboard.ties: [CableTie]` and `EditorModel.tieCopies(of:mapping:offset:) -> [CableTie]` (private).

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/TieClipboardTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Ties on the clipboard (cable ties spec 2026-10-26 §3.4): a tie is copied when every wire it holds is copied (both ends of
/// each in the selection), selected or not (plan ruling R7); a paste, ⌘D or ⌥-drag gives it a fresh ID, puts it on the
/// copies' wires, moves it like the nodes and selects it. Ties at a group's level (§4.5) from the editor.
@MainActor
struct TieClipboardTests {
    let scene = TieScene()

    @Test func copyingBothEndsOfEveryTiedWireCopiesTheTie() throws {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = Set(scene.nodes.map(\.id))
        editor.copySelection()
        editor.paste()
        #expect(editor.graph.ties.count == 2)
        let copy = try #require(editor.graph.ties.values.first { $0.id != tieID(1) })
        #expect(copy.position == Vector2(408, 184), "moved like the nodes")
        let pasted = editor.canvasSelection.nodes
        #expect(copy.wires.count == 2 && copy.wires.allSatisfy { pasted.contains($0.node) }, "on the copies' wires")
        #expect(editor.canvasSelection.ties == [copy.id], "and selected with them")
        editor.perform(.undo)
        #expect(editor.graph.ties.count == 1 && editor.graph.nodes.count == 6, "one step")
    }

    @Test func aTieWithAWireLeftBehindIsNotCopied() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = [scene.a1.id, scene.b1.id]
        editor.copySelection()
        editor.paste()
        #expect(editor.graph.ties.count == 1)
        #expect(editor.canvasSelection.ties.isEmpty)
    }

    @Test func duplicateAndOptionDragCopyTheTieToo() throws {
        let duplicated = scene.editor(ties: [scene.tie()])
        duplicated.selection = Set(scene.nodes.map(\.id))
        duplicated.duplicateSelection()
        #expect(duplicated.graph.ties.count == 2)
        let dragged = scene.editor(ties: [scene.tie()])
        dragged.selection = Set(scene.nodes.map(\.id))
        dragged.drag(Vector2(20, 40), Vector2(20, 640), modifiers: .option)
        let copy = try #require(dragged.graph.ties.values.first { $0.id != tieID(1) })
        #expect(copy.position == Vector2(384, 760))
    }

    @Test func cutThenPasteBringsTheTieBackOnTheCopies() {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = Set(scene.nodes.map(\.id))
        editor.cutSelection()
        #expect(editor.graph.ties.isEmpty, "the cut nodes took their wires out of the tie")
        editor.paste()
        #expect(editor.graph.ties.count == 1)
    }

    @Test func groupingFromTheEditorMovesTheTieInside() throws {
        let editor = scene.editor(ties: [scene.tie()])
        editor.selection = Set(scene.nodes.map(\.id))
        #expect(editor.perform(.group))
        #expect(editor.graph.ties.isEmpty)
        #expect(editor.perform(.enterGroup))
        #expect(editor.graph.ties.values.map(\.wires) == [[scene.upper, scene.lower]])
    }

    @Test func tyingInsideAGroupTiesInTheDefinition() throws {
        let editor = scene.editor()
        editor.selection = Set(scene.nodes.map(\.id))
        editor.perform(.group)
        editor.perform(.enterGroup)
        #expect(editor.isInsideGroup)
        editor.click(scene.upperMiddle)
        editor.click(scene.lowerMiddle, modifiers: .shift)
        editor.perform(.tieWires)
        #expect(editor.graph.ties.count == 1, "the level shown")
        #expect(editor.rootGraph.ties.isEmpty, "not the top level")
        #expect(editor.document.definitions.values.first?.graph.ties.count == 1)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter TieClipboardTests 2>&1 | grep -cE "recorded an issue"`
Expected: a non-zero count. The paste carries no tie.

- [ ] **Step 3: Carry ties on the clipboard**

`Sources/CreatorEditor/NodeClipboard.swift`. Replace:
```swift
    public var frames: [CommentFrame] = []
```
with:
```swift
    public var frames: [CommentFrame] = []
    /// The ties every wire of which was copied (cable ties spec 2026-10-26 §3.4).
    public var ties: [CableTie] = []
```

`Sources/CreatorEditor/EditorModel+Editing.swift`. In `clipboard(of:)`, replace:
```swift
        return NodeClipboard(nodes: nodes, links: links, definitions: definitions,
                             stickies: comments.compactMap { graph.stickies[$0] },
                             frames: comments.compactMap { graph.frames[$0] },
                             images: document.images.filter { hashes.contains($0.key) })
```
with:
```swift
        // A tie travels when every wire it holds does, selected or not, as the wires between copied nodes do.
        let copiedWires = Set(links.map(\.to))
        return NodeClipboard(nodes: nodes, links: links, definitions: definitions,
                             stickies: comments.compactMap { graph.stickies[$0] },
                             frames: comments.compactMap { graph.frames[$0] },
                             ties: graph.ties.values.filter { $0.wires.isSubset(of: copiedWires) }.sorted { $0.id < $1.id },
                             images: document.images.filter { hashes.contains($0.key) })
```
Replace its doc line `    /// nodes use and their comments. Group Input and Group Output are never copied.` with `    /// nodes use, their comments and the ties every wire of which they hold. Group Input and Group Output are never copied.`.

In `insert(_:offset:named:)`, replace:
```swift
        do {
            // The definitions are added to the document, the nodes and comments to the level shown.
```
with:
```swift
        let ties = tieCopies(of: clipboard.ties, mapping: mapping, offset: offset)
        commands += ties.map { .setTie($0) }
        do {
            // The definitions are added to the document, the nodes, comments and ties to the level shown.
```
Replace:
```swift
            return CanvasSelection(nodes: Set(mapping.values), comments: comments)
```
with:
```swift
            return CanvasSelection(nodes: Set(mapping.values), comments: comments, ties: Set(ties.map(\.id)))
```
Add after `insert(_:offset:named:)`, inside the extension:
```swift

    /// Fresh copies of `ties` on the copied wires (`mapping` takes each original node to its copy), moved by `offset`
    /// (stored coordinates). A tie whose wires don't all map is left out.
    private func tieCopies(of ties: [CableTie], mapping: [NodeID: NodeID], offset: Vector2) -> [CableTie] {
        ties.compactMap { original in
            let wires = Set(original.wires.compactMap { wire in mapping[wire.node].map { Endpoint(node: $0, socket: wire.socket) } })
            guard wires.count == original.wires.count else { return nil }
            return CableTie(position: original.position + offset, wires: wires)
        }
    }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter CreatorEditorTests 2>&1 | tail -3`
Expected: passes.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations. If `function_body_length` flags `insert`, move the comment-copy loops into a helper beside `tieCopies`. Never disable the rule.

- [ ] **Step 5: Commit** (`feat(editor): copy, paste and duplicate cable ties; ties at a group's level`, with the two trailer lines)

---

### Task 11: The spring (pure)

Spec §5.2 (pinned points, spring state, excitation, constants, rest, the pure step). Ruling R13. Review Focus 5.

**Files:**
- Create: `Sources/CreatorEditor/SpringPoint.swift`, `Sources/CreatorEditor/PieceSpring.swift`, `Sources/CreatorEditor/WireSpring.swift`, `Sources/CreatorEditor/WireMotion.swift`
- Test: `Tests/CreatorEditorTests/WireSpringTests.swift`, `Tests/CreatorEditorTests/WireMotionTests.swift`

**Interfaces:**
- Consumes: Task 4's `WireRoute` (`pinned`, `pieces`) and `WireGeometry.init(start:control1:control2:end:)`.
- Produces:
  - `public struct SpringPoint: Equatable, Sendable { var offset: Vector2; var velocity: Vector2 }`.
  - `public struct PieceSpring: Equatable, Sendable { var control1, control2: SpringPoint; var cap: Double; isAtRest }`.
  - `public enum WireSpring { naturalFrequency = 20, dampingRatio = 0.8, slack = 0.6, capFraction = 0.4, restOffset = 0.05, restSpeed = 1; step(_:startDelta:endDelta:length:dt:), kick(_:startDelta:endDelta:length:), evolve(_:dt:) }`.
  - `public struct WireMotion: Equatable, Sendable { springs: [Endpoint: [PieceSpring]]; time: Double; isAtRest; advanced(to:) -> WireMotion; mutating excite(from:to:at:); drawn(_: WireRoute) -> WireRoute }`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/WireSpringTests.swift`
```swift
import CreatorGeometry
import Testing
@testable import CreatorEditor

/// One piece's spring (cable ties spec 2026-10-26 §5.2). A moved end pulls its control point behind it by 60% of the move;
/// the offset never passes 40% of the piece's length; it settles, to the eye, within about 0.3 s, and then to exactly
/// zero; the solution is exact, so one long frame equals many short ones.
struct WireSpringTests {
    let frame = 1.0 / 60

    func run(_ state: PieceSpring, frames: Int) -> PieceSpring {
        (0..<frames).reduce(state) { spring, _ in
            WireSpring.step(spring, startDelta: .zero, endDelta: .zero, length: 100, dt: frame)
        }
    }

    @Test func aMovedEndPullsItsControlPointBehindIt() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: .zero, endDelta: Vector2(20, 0), length: 100)
        #expect(abs(kicked.control2.offset.x + 12) < 1e-12 && kicked.control2.offset.y == 0, "60% of the move, against it")
        #expect(kicked.control1 == SpringPoint(), "the end that did not move keeps its control point")
        #expect(!kicked.isAtRest)
    }

    @Test func theOffsetIsCappedAtFortyPercentOfThePiece() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: Vector2(0, 500), endDelta: .zero, length: 100)
        #expect(abs(kicked.control1.offset.length - 40) < 1e-9)
        #expect(kicked.control1.offset.x == 0 && kicked.control1.offset.y < 0)
        for frames in [1, 2, 5, 10, 20] {
            #expect(run(kicked, frames: frames).control1.offset.length <= 40 + 1e-9, "\(frames) frames")
        }
    }

    @Test func itSettlesWithinTheBudgetToExactlyZero() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: .zero, endDelta: Vector2(100, 0), length: 100)
        #expect(abs(kicked.control2.offset.x + 40) < 1e-9, "set up: at the cap")
        #expect(run(kicked, frames: 18).control2.offset.length < 1, "under 2.5% of the slack after 0.3 s")
        #expect(run(kicked, frames: 30) == PieceSpring(), "exactly zero after 0.5 s")
    }

    @Test func oneLongFrameIsTheSameAsManyShortOnes() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: .zero, endDelta: Vector2(100, 0), length: 100)
        let short = run(kicked, frames: 10)
        let once = WireSpring.evolve(kicked, dt: 10 * frame)
        #expect(abs(short.control2.offset.x - once.control2.offset.x) < 1e-9, "the solution is exact, not stepped")
        #expect(abs(short.control2.velocity.x - once.control2.velocity.x) < 1e-6)
        #expect(WireSpring.evolve(kicked, dt: 0.5) == PieceSpring(), "half a second at once settles too")
        #expect(WireSpring.evolve(kicked, dt: 30).isAtRest, "and a very long frame never overshoots")
    }

    @Test func nothingMovedAndNoTimeChangesNothing() {
        let kicked = WireSpring.kick(PieceSpring(), startDelta: Vector2(10, 10), endDelta: .zero, length: 100)
        #expect(WireSpring.step(kicked, startDelta: .zero, endDelta: .zero, length: 100, dt: 0).control1 == kicked.control1)
        #expect(WireSpring.evolve(kicked, dt: -1) == kicked)
        #expect(WireSpring.kick(PieceSpring(), startDelta: Vector2(0.01, 0), endDelta: .zero, length: 100) == PieceSpring(),
                "a move too small to see is no slack")
    }
}
```

`Tests/CreatorEditorTests/WireMotionTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Every wire's slack (cable ties spec 2026-10-26 §5.2): the pinned points (the ends and the lanes) are drawn exactly where
/// they are at every frame; only the wires whose pinned points moved go slack; a route that changed shape starts taut; at
/// rest nothing is held and the drawn route is the taut route bit for bit; time never runs backwards.
struct WireMotionTests {
    let upper = Endpoint(node: nodeID(3), socket: "value"), lower = Endpoint(node: nodeID(4), socket: "value")
    let before: [Endpoint: [Vector2]] = [
        Endpoint(node: nodeID(3), socket: "value"): [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)],
        Endpoint(node: nodeID(4), socket: "value"): [Vector2(168, 260), Vector2(600, 260)],
    ]
    let after: [Endpoint: [Vector2]] = [
        Endpoint(node: nodeID(3), socket: "value"): [Vector2(168, 60), Vector2(384, 198), Vector2(600, 60)],
        Endpoint(node: nodeID(4), socket: "value"): [Vector2(168, 260), Vector2(600, 260)],
    ]

    func moved() -> WireMotion {
        var motion = WireMotion()
        motion.excite(from: before, to: after, at: 10)
        return motion
    }

    @Test func aLaneThatMovesDownBowsBothItsPiecesUp() throws {
        let springs = try #require(moved().springs[upper])
        #expect(springs.count == 2)
        #expect(springs[0].control2.offset.y < 0 && springs[0].control1 == SpringPoint(), "the piece into the lane")
        #expect(springs[1].control1.offset.y < 0 && springs[1].control2 == SpringPoint(), "the piece out of it")
    }

    @Test func onlyTheWiresThatMovedGoSlack() {
        #expect(Set(moved().springs.keys) == [upper])
    }

    @Test func pinnedPointsAreExactOnEveryFrame() {
        let route = WireRoute(wire: upper, through: after[upper] ?? [], flow: .horizontal)
        let motion = moved()
        var bowed = false
        for frame in 0...40 {
            let drawn = motion.advanced(to: 10 + Double(frame) / 60).drawn(route)
            #expect(drawn.pinned == route.pinned, "frame \(frame)")
            if drawn != route { bowed = true }
        }
        #expect(bowed, "the pieces bowed in between")
        #expect(motion.advanced(to: 11).isAtRest)
        #expect(motion.advanced(to: 11).drawn(route) == route, "taut again, bit for bit")
    }

    @Test func aRouteThatChangedShapeStartsTaut() {
        var motion = moved()
        motion.excite(from: after, to: [upper: [Vector2(168, 60), Vector2(600, 60)], lower: after[lower] ?? []], at: 10.1)
        #expect(motion.springs[upper] == nil, "the tie went: two pieces became one")
    }

    @Test func timeNeverRunsBackwards() {
        let motion = moved()
        #expect(motion.advanced(to: 9) == motion)
        #expect(motion.advanced(to: 10) == motion)
    }

    @Test func atRestNothingIsDrawnDifferently() {
        let route = WireRoute(wire: lower, through: after[lower] ?? [], flow: .horizontal)
        #expect(WireMotion().drawn(route) == route)
        #expect(WireMotion().isAtRest)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: "cannot find 'WireSpring' in scope".

- [ ] **Step 3: Write the spring**

`Sources/CreatorEditor/SpringPoint.swift`
```swift
import CreatorGeometry

/// How far one control point of a slack piece is from its taut place, and how fast it moves (cable ties spec §5.2), in
/// display canvas points and points a second.
public struct SpringPoint: Equatable, Sendable {
    public var offset: Vector2
    public var velocity: Vector2

    public init(offset: Vector2 = .zero, velocity: Vector2 = .zero) {
        self.offset = offset
        self.velocity = velocity
    }
}
```

`Sources/CreatorEditor/PieceSpring.swift`
```swift
/// The slack of one piece of a wire's route (cable ties spec 2026-10-26 §5.2): a spring on each of its two control points,
/// and the most either offset may be (`cap`, 40% of the piece's length when it was last kicked). All zero at rest.
public struct PieceSpring: Equatable, Sendable {
    public var control1: SpringPoint
    public var control2: SpringPoint
    public var cap: Double

    public init(control1: SpringPoint = SpringPoint(), control2: SpringPoint = SpringPoint(), cap: Double = 0) {
        self.control1 = control1
        self.control2 = control2
        self.cap = cap
    }

    public var isAtRest: Bool { control1 == SpringPoint() && control2 == SpringPoint() }
}
```

`Sources/CreatorEditor/WireSpring.swift`
```swift
import CreatorGeometry
import Foundation

/// The spring that gives a moving wire its slack (cable ties spec 2026-10-26 §5.2), as pure functions of one piece's state.
/// `kick` handles the piece's pinned ends moving: the control points lag their taut places by `slack` of the move. `evolve`
/// lets the damped spring pull them back. It is solved in closed form, so it is exact for any `dt` and a long frame cannot
/// overshoot. The offset is capped at `capFraction` of the piece's length so the piece never folds over. A state too small
/// to see snaps to exactly zero, and the drawn piece is then the taut piece bit for bit. The constants are tuned by eye
/// (human check TIE-1).
public enum WireSpring {
    /// Radians a second. With the damping below, the slack is under 2.5% of itself after 0.3 s.
    public static let naturalFrequency = 20.0
    public static let dampingRatio = 0.8
    public static let slack = 0.6
    public static let capFraction = 0.4
    /// Below these (points, points a second), on both control points, the piece is at rest.
    public static let restOffset = 0.05
    public static let restSpeed = 1.0

    /// The pure step of spec §5.2: `state` kicked by its ends' moves, then `dt` seconds of spring.
    public static func step(_ state: PieceSpring, startDelta: Vector2, endDelta: Vector2, length: Double,
                            dt: Double) -> PieceSpring {
        evolve(kick(state, startDelta: startDelta, endDelta: endDelta, length: length), dt: dt)
    }

    /// `state` after its start moved by `startDelta` and its end by `endDelta`, the piece now `length` long.
    public static func kick(_ state: PieceSpring, startDelta: Vector2, endDelta: Vector2, length: Double) -> PieceSpring {
        var next = state
        next.cap = capFraction * max(length, 0)
        next.control1.offset = capped(state.control1.offset - startDelta * slack, to: next.cap)
        next.control2.offset = capped(state.control2.offset - endDelta * slack, to: next.cap)
        return settled(next)
    }

    /// `state` after `dt` seconds of the damped spring; unchanged for a `dt` that isn't positive.
    public static func evolve(_ state: PieceSpring, dt: Double) -> PieceSpring {
        guard !state.isAtRest, dt > 0 else { return state }
        var next = state
        next.control1 = evolve(state.control1, dt: dt, cap: state.cap)
        next.control2 = evolve(state.control2, dt: dt, cap: state.cap)
        return settled(next)
    }

    static func evolve(_ point: SpringPoint, dt: Double, cap: Double) -> SpringPoint {
        let (x, vx) = oscillate(point.offset.x, point.velocity.x, dt: dt)
        let (y, vy) = oscillate(point.offset.y, point.velocity.y, dt: dt)
        return SpringPoint(offset: capped(Vector2(x, y), to: cap), velocity: Vector2(vx, vy))
    }

    /// One axis of the under-damped spring after `dt`, exactly: offset `x` and velocity `v` in, the same out.
    static func oscillate(_ x: Double, _ v: Double, dt: Double) -> (Double, Double) {
        let sigma = dampingRatio * naturalFrequency
        let omega = naturalFrequency * (1 - dampingRatio * dampingRatio).squareRoot()
        let decay = exp(-sigma * dt), c = cos(omega * dt), s = sin(omega * dt)
        let a = (v + sigma * x) / omega
        let position = x * c + a * s
        return (decay * position, decay * (omega * (a * c - x * s) - sigma * position))
    }

    static func capped(_ offset: Vector2, to cap: Double) -> Vector2 {
        let length = offset.length
        return length > cap && length > 0 ? offset * (cap / length) : offset
    }

    /// `state`, or exactly zero once both control points are too close and too slow to see.
    static func settled(_ state: PieceSpring) -> PieceSpring {
        let quiet = [state.control1, state.control2].allSatisfy { $0.offset.length < restOffset && $0.velocity.length < restSpeed }
        return quiet ? PieceSpring() : state
    }
}
```

`Sources/CreatorEditor/WireMotion.swift`
```swift
import CreatorGeometry
import CreatorGraph

/// The slack of every wire in motion (cable ties spec 2026-10-26 §5.2): a `PieceSpring` for each piece of each wire whose
/// pinned points moved, as of `time` (seconds, the editor's motion clock). At rest it holds nothing. A drawn route keeps its
/// pinned points exactly and only its control points carry the slack. Pure: the canvas reads `advanced(to:)` at each frame's
/// date and never writes it back.
public struct WireMotion: Equatable, Sendable {
    public private(set) var springs: [Endpoint: [PieceSpring]] = [:]
    public private(set) var time = 0.0

    public init() {}

    public var isAtRest: Bool { springs.isEmpty }

    /// This motion at `time`; unchanged for a time not after its own, so a frame dated before the last kick changes nothing.
    public func advanced(to time: Double) -> WireMotion {
        guard time > self.time else { return self }
        var next = self
        next.time = time
        next.springs = springs.compactMapValues { pieces in
            let stepped = pieces.map { WireSpring.evolve($0, dt: time - self.time) }
            return stepped.allSatisfy(\.isAtRest) ? nil : stepped
        }
        return next
    }

    /// Advances to `time`, then kicks each wire's pieces by how its pinned points moved from `before` to `after` (display
    /// canvas points, by wire). A wire whose route changed shape (a tie added or removed) or appeared starts taut; one that
    /// is gone is dropped.
    public mutating func excite(from before: [Endpoint: [Vector2]], to after: [Endpoint: [Vector2]], at time: Double) {
        self = advanced(to: time)
        var kicked: [Endpoint: [PieceSpring]] = [:]
        for (wire, points) in after {
            guard let old = before[wire], old.count == points.count, points.count >= 2 else { continue }
            let current = springs[wire].flatMap { $0.count == points.count - 1 ? $0 : nil }
                ?? Array(repeating: PieceSpring(), count: points.count - 1)
            let pieces = current.indices.map { index in
                WireSpring.kick(current[index], startDelta: points[index] - old[index],
                                endDelta: points[index + 1] - old[index + 1],
                                length: (points[index + 1] - points[index]).length)
            }
            if !pieces.allSatisfy(\.isAtRest) { kicked[wire] = pieces }
        }
        springs = kicked
    }

    /// `route` as drawn now: its pinned points exactly where they are, its control points moved by their springs. A route
    /// with no spring, or a different number of pieces than its spring, is drawn taut.
    public func drawn(_ route: WireRoute) -> WireRoute {
        guard let pieces = springs[route.wire], pieces.count == route.pieces.count else { return route }
        return WireRoute(wire: route.wire, pieces: zip(route.pieces, pieces).map { piece, spring in
            WireGeometry(start: piece.start, control1: piece.control1 + spring.control1.offset,
                         control2: piece.control2 + spring.control2.offset, end: piece.end)
        })
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter 'WireSpringTests|WireMotionTests' 2>&1 | tail -3`
Expected: passes. If `itSettlesWithinTheBudgetToExactlyZero` fails, adjust only `naturalFrequency` (and with it the "under 2.5% after 0.3 s" comment) until both of its bounds hold. Never loosen the test. The numbers were checked in a scratch simulation: 0.49 at 0.3 s, zero by 0.45 s.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

- [ ] **Step 5: Commit** (`feat(editor): the wire spring and every wire's slack, pure`, with the two trailer lines)

---

### Task 12: Slack in the editor: moves kick it, a timeline draws it, Reduce Motion stops it

Spec §5.2 (the tick, Reduce Motion, taut-only reading). Rulings R13, R17.

**Files:**
- Modify: `Sources/CreatorEditor/EditorModel.swift:1-4` (imports) and `:103` (stored properties), `Sources/CreatorEditor/EditorModel+Pointer.swift:149-150`, `Sources/CreatorEditor/EditorModel+Nudge.swift:19`, `Sources/CreatorEditor/WireLayer.swift` (whole file), `Sources/CreatorEditor/CanvasLayers.swift`
- Create: `Sources/CreatorEditor/EditorModel+Motion.swift`
- Test: `Tests/CreatorEditorTests/Support/ManualClock.swift`, `Tests/CreatorEditorTests/EditorWireMotionTests.swift`, `Tests/CreatorAppTests/WireMotionWindowTests.swift`

**Interfaces:**
- Consumes: Task 11's `WireMotion`; Task 4's `wireRouting`; Task 5's `WireLayer` and `CanvasLayers.wires`.
- Produces:
  - Members of `EditorModel`: `isWireMotionActive: Bool` (tracked), `wireMotion: WireMotion` (internal, untracked), `motionClock: @MainActor () -> Double`, `reducesMotion: Bool`, `drawnMotion(at: Date) -> WireMotion`, `settleWireMotion()`, `stopWireMotion()` and `withWireSlack(_:)`.
  - `CanvasLayers.animatesWires(_:reducesMotion:) -> Bool`, and the `motion:` parameter of `CanvasLayers.wires`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/Support/ManualClock.swift`
```swift
// Test fixture file: a clock the motion tests set by hand.
/// Seconds that move only when a test moves them; `EditorModel.motionClock` reads `now`.
@MainActor
final class ManualClock {
    var now = 1_000.0
}
```

`Tests/CreatorEditorTests/EditorWireMotionTests.swift`
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// Slack in the editor (cable ties spec 2026-10-26 §5.2). Moving a node or a tie makes the wires it moves go slack, against the
/// motion; the canvas animates only while some wire is slack and stops once every wire is taut. Undo and a click make no
/// slack. With Reduce Motion on, no slack is ever made.
@MainActor
struct EditorWireMotionTests {
    let scene = TieScene()

    func editor(ties: [CableTie] = []) -> (EditorModel, ManualClock) {
        let clock = ManualClock()
        let editor = scene.editor(ties: ties)
        editor.motionClock = { clock.now }
        return (editor, clock)
    }

    @Test func draggingANodeMakesItsWiresSlackAgainstTheMotion() throws {
        let (editor, _) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.isWireMotionActive)
        let spring = try #require(editor.wireMotion.springs[scene.upper]?.first)
        #expect(spring.control2.offset.y < 0 && spring.control2.offset.x == 0, "b1 moved down: its end bows up")
        #expect(spring.control1 == SpringPoint())
        #expect(editor.wireMotion.springs[scene.lower] == nil, "a wire nothing moved stays taut")
    }

    @Test func draggingATieMakesBothSidesOfItsWiresSlack() {
        let (editor, _) = editor(ties: [scene.tie()])
        editor.drag(Vector2(384, 160), Vector2(384, 200))
        #expect(editor.wireMotion.springs[scene.upper]?.count == 2)
        #expect(editor.wireMotion.springs[scene.lower]?.count == 2)
    }

    @Test func theWiresSettleAndTheTimelineStops() {
        let (editor, clock) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(CanvasLayers.animatesWires(editor, reducesMotion: false))
        clock.now += 0.1
        editor.settleWireMotion()
        #expect(editor.isWireMotionActive, "still slack a tenth of a second on")
        clock.now += 1
        editor.settleWireMotion()
        #expect(!editor.isWireMotionActive && editor.wireMotion.isAtRest)
        #expect(!CanvasLayers.animatesWires(editor, reducesMotion: false), "at rest the wires draw without a timeline")
    }

    @Test func whileSlackTheDrawnWiresKeepTheirEndsAndBow() throws {
        let (editor, clock) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        let taut = try #require(editor.wireRouting.routes[scene.upper])
        let motion = editor.drawnMotion(at: Date(timeIntervalSinceReferenceDate: clock.now + 0.05))
        let drawn = try #require(CanvasLayers.wires(editor, motion: motion).first { $0.route.wire == scene.upper })
        #expect(drawn.route.pinned == taut.pinned, "the ends are exact")
        #expect(drawn.route != taut, "the control points carry the slack")
        let middle = try #require(taut.pieces.first?.point(at: 0.5))
        #expect(editor.hitTest(editor.transform.toScreen(middle)) == .wire(scene.upper), "hit testing reads the taut route")
    }

    @Test func undoAndAClickMakeNoSlack() {
        let (editor, clock) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        clock.now += 2
        editor.settleWireMotion()
        editor.perform(.undo)
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
        editor.click(Vector2(700, 50))
        #expect(editor.wireMotion.isAtRest)
    }

    @Test func anArrowNudgeMakesSlackToo() {
        let (editor, _) = editor()
        editor.selection = [scene.b1.id]
        editor.perform(.nudge(Vector2(0, 10), isRepeat: false))
        #expect(editor.wireMotion.springs[scene.upper] != nil)
    }

    @Test func withReduceMotionOnNoSlackIsEverMade() {
        let (editor, _) = editor()
        editor.reducesMotion = true
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
        #expect(!CanvasLayers.animatesWires(editor, reducesMotion: true))
    }

    @Test func turningReduceMotionOnMidMotionMakesTheWiresTaut() {
        let (editor, _) = editor()
        editor.drag(Vector2(700, 50), Vector2(700, 90))
        #expect(editor.isWireMotionActive)
        editor.reducesMotion = true
        #expect(editor.wireMotion.isAtRest && !editor.isWireMotionActive)
    }

    @Test func aCanvasInMotionStillDraws() {
        let (editor, _) = editor(ties: [scene.tie()])
        editor.drag(Vector2(384, 160), Vector2(384, 200))
        let frame = renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
        #expect(!frame.rects.isEmpty)
    }
}
```

`Tests/CreatorAppTests/WireMotionWindowTests.swift`
```swift
import CreatorEditor
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// Reduce Motion through a real headless window (cable ties spec 2026-10-26 §5.2): the canvas reads MetalUI's
/// `accessibilityReduceMotion` and passes it to the editor, which then never lets a wire go slack.
@MainActor
struct WireMotionWindowTests {
    @Test func theCanvasPassesReduceMotionToTheEditor() async throws {
        let app = try await AppWindow.open()
        #expect(!app.editor.reducesMotion)
        app.window.setReduceMotion(true)
        try await app.window.runUntilIdle()
        #expect(app.editor.reducesMotion)
        app.window.setReduceMotion(false)
        try await app.window.runUntilIdle()
        #expect(!app.editor.reducesMotion)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: "value of type 'EditorModel' has no member 'motionClock'".

- [ ] **Step 3: Write the motion**

`Sources/CreatorEditor/EditorModel.swift`. Replace:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Observation
```
with:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Observation
```
Replace:
```swift
    @ObservationIgnored var wirePickPoints: [Endpoint: Vector2] = [:]
```
with:
```swift
    @ObservationIgnored var wirePickPoints: [Endpoint: Vector2] = [:]
    /// The slack of the wires in motion (`EditorModel+Motion`, cable ties spec §5.2). View state, never saved. The canvas reads
    /// it inside its timeline every frame, so it is not tracked.
    @ObservationIgnored var wireMotion = WireMotion()
    /// Whether some wire is slack: what puts the wires inside a `TimelineView` (`WireLayer`). Tracked, so the canvas drops
    /// the timeline when the last wire settles.
    public internal(set) var isWireMotionActive = false
    /// The clock the springs run on, in seconds since the reference date, the same base as a timeline's dates. Tests set
    /// their own.
    @ObservationIgnored public var motionClock: @MainActor () -> Double = { Date().timeIntervalSinceReferenceDate }
    /// Reduce Motion, as the canvas read it (`CanvasLayers`). While it is on, no wire ever goes slack.
    @ObservationIgnored public var reducesMotion = false {
        didSet { if reducesMotion { stopWireMotion() } }
    }
    /// The task that ends the motion once every wire is taut (`EditorModel+Motion`).
    @ObservationIgnored var motionSettleTask: Task<Void, Never>?
```

`Sources/CreatorEditor/EditorModel+Motion.swift`
```swift
import CreatorGeometry
import CreatorGraph
import Foundation

/// Slack wires (cable ties spec 2026-10-26 §5.2). A move kicks the springs of the wires whose pinned points it moved
/// (`withWireSlack`); a move is a drag of the selection or an arrow key. While some wire is slack the canvas draws the wires
/// inside `TimelineView(.animation)` (`WireLayer`). Each frame reads the slack at its date (`drawnMotion(at:)`) and writes
/// nothing back. A settle task ends the motion once every wire is taut again (`settleWireMotion()`). With Reduce Motion on,
/// nothing is ever kicked. Hit testing, culling, boxes and the file only ever see the taut routes.
extension EditorModel {
    /// How often the settle task checks whether the wires are taut again.
    static let motionSettleInterval = Duration.milliseconds(100)

    /// Every wire's pinned points now (its ends and its lanes, display canvas points).
    func pinnedPoints() -> [Endpoint: [Vector2]] { wireRouting.routes.mapValues(\.pinned) }

    /// Runs `move`, then makes the wires whose pinned points it moved go slack, and starts the timeline if it isn't running.
    /// Just `move` while Reduce Motion is on.
    func withWireSlack(_ move: () -> Void) {
        guard !reducesMotion else {
            move()
            return
        }
        let before = pinnedPoints()
        move()
        wireMotion.excite(from: before, to: pinnedPoints(), at: motionClock())
        guard !wireMotion.isAtRest else { return }
        if !isWireMotionActive { isWireMotionActive = true }
        scheduleMotionSettle()
    }

    /// The slack at `date`, a timeline frame's: what the canvas draws. Pure: nothing is written.
    public func drawnMotion(at date: Date) -> WireMotion {
        wireMotion.advanced(to: date.timeIntervalSinceReferenceDate)
    }

    /// Advances the slack to the clock's time and, once every wire is taut, ends the motion (the timeline goes).
    public func settleWireMotion() {
        wireMotion = wireMotion.advanced(to: motionClock())
        if wireMotion.isAtRest { stopWireMotion() }
    }

    /// Every wire taut at once: Reduce Motion turned on, or the slack settled.
    func stopWireMotion() {
        wireMotion = WireMotion()
        motionSettleTask?.cancel()
        motionSettleTask = nil
        if isWireMotionActive { isWireMotionActive = false }
    }

    private func scheduleMotionSettle() {
        guard motionSettleTask == nil else { return }
        motionSettleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.motionSettleInterval)
                guard let self, !Task.isCancelled else { return }
                self.settleWireMotion()
                if !self.isWireMotionActive { return }
            }
        }
    }
}
```

`Sources/CreatorEditor/EditorModel+Pointer.swift`. Replace:
```swift
            try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key, name: moveName(of: start))
```
with:
```swift
            withWireSlack {
                _ = try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key, name: moveName(of: start))
            }
```

`Sources/CreatorEditor/EditorModel+Nudge.swift`. Replace:
```swift
        try? edit(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey, name: moveName(of: start))
```
with:
```swift
        withWireSlack {
            _ = try? edit(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey,
                          name: moveName(of: start))
        }
```

`Sources/CreatorEditor/WireLayer.swift` (whole file)
```swift
import CreatorStyle
import MetalUI

/// The canvas's wires (cable ties spec 2026-10-26 §5): one `WireView` for each wire that can show. At rest each is built from
/// its taut route, with no timeline, so a still canvas costs nothing per frame. While some wire is slack (`animates`), they
/// are built inside `TimelineView(.animation)` from the slack at the frame's date (`EditorModel.drawnMotion(at:)`, which
/// writes nothing).
struct WireLayer: Component {
    let model: EditorModel
    let routing: WireRouting
    let palette: Palette
    let animates: Bool

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            if animates {
                TimelineView(.animation) { context in
                    ZStack(alignment: .topLeading) {
                        ForEach(CanvasLayers.wires(model, routing: routing, palette: palette, motion: model.drawnMotion(at: context.date)),
                                id: \.id) { wire in
                            WireView(pieces: wire.route.pieces, color: wire.color, lineWidth: wire.lineWidth).equatable()
                        }
                    }
                }
            } else {
                ForEach(CanvasLayers.wires(model, routing: routing, palette: palette), id: \.id) { wire in
                    WireView(pieces: wire.route.pieces, color: wire.color, lineWidth: wire.lineWidth).equatable()
                }
            }
        }
    }
}
```

`Sources/CreatorEditor/CanvasLayers.swift`. Replace:
```swift
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
```
with:
```swift
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
    /// Reduce Motion (MetalUI's `accessibilityReduceMotion`). The canvas passes it to the model, which then never lets a wire
    /// go slack (cable ties spec §5.2).
    @Environment(\.accessibilityReduceMotion) var reducesMotion: Bool
```
Replace:
```swift
            WireLayer(model: model, routing: routing, palette: palette, animates: false)
```
with:
```swift
            WireLayer(model: model, routing: routing, palette: palette,
                      animates: Self.animatesWires(model, reducesMotion: reducesMotion))
```
Replace the end of `content` (the ZStack's closing brace and the getter's):
```swift
            if let box = model.selectionBox {
                BoxSelectionView(rect: box).equatable()
            }
        }
    }
```
with:
```swift
            if let box = model.selectionBox {
                BoxSelectionView(rect: box).equatable()
            }
        }
        .onChange(of: reducesMotion, initial: true) { _, reduces in model.reducesMotion = reduces }
    }

    /// Whether the wires are drawn inside a timeline: only while some wire is slack and Reduce Motion is off.
    static func animatesWires(_ model: EditorModel, reducesMotion: Bool) -> Bool {
        model.isWireMotionActive && !reducesMotion
    }
```
Replace the `wires` signature and its first lines:
```swift
    static func wires(_ model: EditorModel, routing: WireRouting? = nil, palette: Palette = .dracula) -> [Wire] {
```
with:
```swift
    static func wires(_ model: EditorModel, routing: WireRouting? = nil, palette: Palette = .dracula,
                      motion: WireMotion? = nil) -> [Wire] {
```
and in its `return Wire(...)`, replace `                        route: taut,` with `                        route: motion?.drawn(taut) ?? taut,`. Add to its doc comment: `With `motion`, each route is drawn with its slack; culling still reads the taut route.`

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"`
Expected: no output.
Run: `swift test --filter 'EditorWireMotionTests|WireMotionTests|WireSpringTests|TieRenderTests|CreatorEditorTests' 2>&1 | tail -3`
Expected: passes.
Run: `swift test --filter 'WireMotionWindowTests|CanvasContentSkipWindowTests|PanelContentSkipWindowTests|ContinuingPressCancelWindowTests|CanvasCancelWindowTests' 2>&1 | tail -3`
Expected: passes. A window test that drags a node with wires and counts content skips may now count more. That is because its frames carry a live timeline, which MetalUI rebuilds every frame (`timeVarying`), and the change is expected. Turn motion off in that test with `app.window.setReduceMotion(true)` before the drag, and add a comment naming the cable ties spec §5.2. Never change an expected count.
Run: `swiftlint lint --strict 2>&1 | tail -1`
Expected: 0 violations.

A compile error naming `TimelineView`'s content (a `ProposalElementGroup` requirement) or `onChange` on the canvas's `ZStack` is a MetalUI gap. Log it in `docs/metalui-gaps.md` (an entry and a summary-table row, prefix `TIE-`) and stop for the orchestrator. Never draw the slack another way.

- [ ] **Step 5: Commit** (`feat(editor): wires go slack while things move and pull taut; Reduce Motion keeps them taut`, with the two trailer lines)

---

### Task 13: Errata, notes, human checks, and the full verification

Spec §6 (the human checks), §7 (the errata), and the format history in `CLAUDE.md`.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (append), `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (append), `docs/superpowers/specs/2026-10-26-cable-ties-design.md` (append), `docs/verification/human-checks.md` (append), `CLAUDE.md` (three places)

**Interfaces:**
- Consumes: everything above.
- Produces: no code.

- [ ] **Step 1: The errata spec §7 asks for**

Append to `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`:
```markdown

## Errata (cable ties)

- §6.2's interactions gain wires and ties (`2026-10-26-cable-ties-design.md` §4): a click on a wire selects it (⇧ adds, ⌘
  toggles), ⌥-drag on empty canvas box-selects wires only, and ⌘⇧T (Ctrl+Shift+T on Linux and Windows) ties the selected
  wires. A tie is dragged like a node; ⌥-click on a wire in a tie's band unties it.
```

Append to `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`:
```markdown

## Errata (cable ties)

- §3: `CanvasSelection` gains `wires` (by input endpoint) and `ties`, view state like the rest. ⌘A selects every node, comment
  and tie, never a wire. A plain box also picks up the ties whose band lies wholly inside it and never a wire. An ⌥-drag on
  empty canvas is a box of wires only (⌥ replaces the wires, ⌥⇧ adds, ⌥⌘ toggles; Esc puts the selection back). A drag that
  starts on a wire is a drag on empty canvas (`2026-10-26-cable-ties-design.md` §4.1).
- §7: the draw order is frames → wires → tie bands → notes → nodes → ghosts → the wire being dragged → the box. The hit-test
  order is socket, tie, node, note (a selected note's handle first), wire, frame (a selected frame's handle first), empty.
```

Append to `docs/superpowers/specs/2026-10-26-cable-ties-design.md`:
```markdown

## Errata (plan, 2026-10-26)

Rulings of `docs/superpowers/plans/2026-10-26-cable-ties.md` where this spec left a choice or contradicted itself:

- §3.1: `TieID` holds `rawValue`, as `NodeID` and `CommentID` do, not `raw`.
- §3.2: an inverse that has to restore ties is `.batch([<the inverse it always returned>] + setTie(old)…)`; `restoreNode` and
  `restoreLinks` are unchanged, and an inverse that reached no tie keeps its old shape.
- §3.3: the `ties` key is read whatever the version; a format-8 file has none.
- §3.4: a tie is copied whenever every wire it holds is copied, whether or not it is selected. `NodeClipboard` is in
  `CreatorEditor`, so §6's clipboard tests are `CreatorEditorTests`.
- §4.1: a selected comment's resize handle stays just before its own comment's body (the list's "frame, resize" order would let a
  note hide its own handle). A drag that starts on a wire is a box. The 5-point distance and the band are display canvas points.
  ⌘A selects ties, not wires.
- §4.2: a wire's pick point is the click's, or the middle of where its route lies inside the ⌥-box; a wire with none counts its
  route's middle. ⌘⇧T with one tie and only wires it already holds is refused. After Add to Tie, the selection is the tie. The
  refusal has no node to shake: the canvas's refusal line says "Select two or more wires to tie, or one tie and the wires to add
  to it."
- §4.3: the editor has no snapping, so ties are nudged only. A move of ties alone is "Move Tie"; ties moved with other items make
  "Move". A frame carries nodes, not ties.
- §4.4: a delete of ties alone is "Remove Tie" (also by ⌘X); with other items it is "Delete" or "Cut".
- §4.5: Ungroup's outer wires on the group node leave their ties, as Group's crossing wires do. Make Unique copies a
  definition's ties onto the copy.
- §5.2: only moves (drags and arrow nudges) make slack; undo, paste and a dock change snap to the new taut routes. The spring is
  solved exactly (natural frequency 20 rad/s, damping ratio 0.8, slack 0.6, cap 0.4, rest below 0.05 pt and 1 pt/s), the
  timeline reads it without writing the model, and a settle task ends the timeline. A selected wire is drawn 4 points wide in
  the theme's selection colour.
```

- [ ] **Step 2: The human checks**

Append to `docs/verification/human-checks.md`:
```markdown

## Group TIE — cable ties (wire bundling)

**Status: PENDING.** Plan `2026-10-26-cable-ties.md`, spec `2026-10-26-cable-ties-design.md`. The tests pin the model, the
file, the geometry, the gestures and the spring; these check the look and the feel in a real window. Run
`swift run MetalCreatorApp` on a saved bracket with a busy graph, docked at the bottom; TIE-5 docks left.

- [ ] **TIE-1 Slack and settling.** Drag a node with several wires about, fast and slow: its wires bow behind the motion like
  cables, their ends stay on the sockets with no lag, and when you stop they pull taut, settled to the eye in about a third of a
  second, with no wobble at rest. Drag a tie: the wires on both sides bow. If it feels too floppy or too stiff, note which;
  `WireSpring`'s constants are the knobs. **Pinned:** `WireSpringTests`, `EditorWireMotionTests`. **Observed:**
- [ ] **TIE-2 The band's look.** Tie three wires: the band is a small rounded bar across the wires, visible but quiet, in Dracula
  and in Alucard (View ▸ Theme). Select it: it takes the selection colour. Select a wire: it draws wider in the selection
  colour. The band sits over the wires and under nodes and notes. **Pinned:** `TieRenderTests`. **Observed:**
- [ ] **TIE-3 ⌘⇧T end to end.** Click a wire, ⇧-click two more, press ⌘⇧T: a tie appears where you clicked (between the clicks)
  and is the only thing selected. The Edit menu says "Undo Tie Wires". ⌥-drag a box across two other wires and press ⌘⇧T: a tie
  where the box crossed them. Click a tie, ⇧-click a wire, ⌘⇧T: the wire joins ("Undo Add to Tie"). With one wire selected,
  ⌘⇧T says why nothing happened. Drag the tie ("Undo Move Tie"), press an arrow, Delete it ("Undo Remove Tie"), ⌘Z, and ⌥-click
  one wire on the band ("Undo Untie Wire"). Delete a node a tied wire comes from: the wire leaves the tie, and ⌘Z puts it back.
  **Pinned:** `TieKeyTests`, `TieEditingTests`. **Observed:**
- [ ] **TIE-4 Reduce Motion.** Turn on System Settings ▸ Accessibility ▸ Display ▸ Reduce motion and drag a node: the wires
  stay taut throughout. Turn it off again: they bow. **Pinned:** `EditorWireMotionTests.withReduceMotionOnNoSlackIsEverMade`,
  `WireMotionWindowTests`. **Observed:**
- [ ] **TIE-5 The vertical dock.** Dock the panel left: ties sit at the transpose, their bands run across the wires (now
  vertical), lanes are side by side left to right, and clicks, ⌥-boxes, ⌘⇧T and drags work as at the bottom. **Pinned:**
  `inTheVerticalFlowLanesSpreadAcrossXInEndpointOrder`, `theLeftDockHitsTheTransposedRoute`,
  `inTheLeftDockTheTieGoesToTheStoredCentre`. **Observed:**
- [ ] **TIE-6 A busy tie.** Tie about twenty wires into one bundle and drag it about quickly: the canvas stays smooth (no
  visible stutter), and once it stops the canvas is idle again (Activity Monitor shows the app's CPU dropping back).
  **Observed:**
- [ ] **TIE-7 Save and reopen.** Make two ties (one inside a group), save, close and reopen: every tie is where it was, holding
  the same wires. Group the nodes of a tie: it goes inside; Ungroup: it comes back out. **Pinned:** `TieFileTests`,
  `TieGroupTests`. **Observed:**
- [ ] **TIE-8 Linux and Windows.** On a Linux or Windows build, Ctrl+Shift+T ties and Alt-drag box-selects wires.
  **Observed:**
```

- [ ] **Step 3: `CLAUDE.md`**

In "Project state", after the paragraph that ends "…and its human checks (group CM) are pending.", add the line:
```markdown
Cable ties (wire bundling in the graph editor: spec `docs/superpowers/specs/2026-10-26-cable-ties-design.md`, plan
`docs/superpowers/plans/2026-10-26-cable-ties.md`) code is done; its human checks (group TIE) are pending.
```

In the `CreatorEditor` module notes, after the paragraph that ends "…Ungroup splices them into the level. ⌘A, arrows (one undo step per key-down run) and F act only while the panel shows; Esc closes the palette, then cancels a drag, then clears the selection.", add:
```markdown
  Cable ties (`CableTie`, `TieID`: `Sources/CreatorGraph/Ties`; spec 2026-10-26): per `Graph` (`ties`), saved sorted by ID with
  each tie's wires sorted and only when present (format 9), edited by `setTie` and `removeTie` (no evaluation). A wire is its input
  endpoint (`Link.to`); a tie holds two or more wires that are links (`Graph.apply` refuses otherwise; decoding repairs). `removeNode`,
  `disconnect` and a replacing `connect` strip their wires from ties in the same command (`Graph.stripTies`), and their inverse is
  `.batch([old inverse] + setTie(old)…)` only when a tie was reached. Group moves a tie inside when all its wires go, Ungroup brings a
  definition's ties out remapped, Make Unique copies them. The editor's geometry is `WireRouting` (pure: `WireRoute`, the taut chain of
  `WireGeometry` pieces through each tie's lane, ties met by stored `position.x` then ID; `TieLayout`, lanes 4 pt apart across the flow
  and the 6 pt band), read by drawing, hit testing (`CanvasHit.tie`/`.wire`: socket, tie, node, note, wire, frame), boxes (an ⌥-box
  selects wires only, `CanvasInteraction.wireBoxSelecting`; a plain box picks ties whose band is inside), culling and ⌘⇧T
  (`GraphKeyCommand.tieWires`, `EditorModel+Ties`, positioned at `wirePickPoints`). `CanvasSelection` holds `wires` and `ties`. The slack
  is `WireMotion` (a closed-form `WireSpring` per piece, kicked only by moves through `withWireSlack`), drawn by `WireLayer` inside
  `TimelineView(.animation)` only while `isWireMotionActive`; `reducesMotion` (from `@Environment(\.accessibilityReduceMotion)`,
  `CanvasLayers`) stops it. Draw order: frames, wires, tie bands, notes, nodes.
```

In "Rules", replace `File format is version 8 (2 added` with `File format is version 9 (2 added`, and replace `implicit solids and meshes are computed, never saved; files of format 1 to 7 open unchanged and are written as 8).` with `implicit solids and meshes are computed, never saved; 9 added cable ties, a graph's optional `ties` key (written only when present, sorted by ID, each tie's wires sorted; decoding drops wires that are no link's input, then ties left with fewer than two); files of format 1 to 8 open unchanged and are written as 9).`

- [ ] **Step 4: The full verification**

Run, one after another, from the worktree root:
```bash
swift build --build-tests 2>&1 | grep -E "error:|warning:" | grep -v "ld: warning"     # expect no output
swift test > .build/ct-test.log 2>&1; echo "exit=$?"                                    # expect exit=0
grep -c "Test run with" .build/ct-test.log                                              # expect 12
grep -cE "recorded an issue|failed after" .build/ct-test.log                            # expect 0
swiftlint lint --strict 2>&1 | tail -1                                                  # expect 0 violations
XP_TRACK=cable-ties scripts/linux-test.sh test > .build/ct-linux.log 2>&1; echo "exit=$?"   # expect exit=0
grep -c "Test run with" .build/ct-linux.log                                             # expect 12
grep -cE "recorded an issue|failed after" .build/ct-linux.log                           # expect 0
```
The test count is the baseline plus the new tests. Write both numbers in the commit body. Kill only processes you started: never `pkill`, `killall` or `xargs kill` swift processes, because MetalUI's work shares this Mac, and stop Docker only by this track's container name. Windows is CI's job, on the pushed branch.

- [ ] **Step 5: Commit** (`docs: cable ties errata, human checks TIE, CLAUDE.md and format 9`, with the test counts in the body and the two trailer lines)

---

## Self-review

- **Spec coverage:**
  - §3.1 is Task 1. §3.2: the commands and names are Task 1, the auto-strip and inverses are Task 2.
  - §3.3 (format 9, deterministic output, repair, the older-version refusal) is Task 1.
  - §3.4 (clipboard, paste, duplicate, ⌥-drag) is Task 10.
  - §4.1: the selection fields are Task 5, hit-test and click are Task 6, the ⌥-box, plain box and Esc are Task 7, and the highlights are Task 5.
  - §4.2 is Task 8. §4.3 is Task 9 (snapping, R14). §4.4 is Task 9 (Delete, ⌥-click; node and wire deletes through Task 2). §4.5 is Task 3, and Task 10 from the editor.
  - §5.1: the route, lanes, band and culling bounds are Task 4; the colour, draw order and culling are Task 5.
  - §5.2: the pure spring is Task 11; the tick, Reduce Motion and taut-only hit testing are Task 12.
  - §6's test list is spread as above, and the human checks are Task 13. §7 is Task 13.
- **Placeholders:** none. Every code step shows its code. Each "if this fails" branch names one action and forbids the workarounds.
- **Type consistency:**
  - `CanvasLayers.wires(_:routing:palette:motion:)` has no `motion:` in Task 5 and gains it in Task 12, whose tests use it.
  - `WireView(pieces:color:lineWidth:)` and `(geometry:…)`, `TieLayout.lanes/band`, `WireRouting.routes/ties`, `wirePickPoints`, `moveName(of:)`, `untie(at:from:)`, `laneWire(of:near:in:)`, `drawnMotion(at:)` and `settleWireMotion()` keep the same names and types wherever they appear.
- **Review Focus:** the five lines each have a named test in their owning task.

## Execution notes

- Tasks run in order. Each depends on the interfaces of the ones before it, and Tasks 5 to 12 all edit `EditorModel+Pointer.swift` or `CanvasLayers.swift`, so run them in sequence, not in parallel.
- No MetalUI gap is expected: `TimelineView(.animation)`, `accessibilityReduceMotion` and `onChange(of:initial:)` exist at the current pin. If one appears, Task 12 says what to do.
