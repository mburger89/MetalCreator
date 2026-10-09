# MetalCreator S4: Sketch Node, Plane from Face and Projection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sketches reach the graph. `ConstantValue.sketch(Sketch)` stores a sketch as a node setting (file format 3 → 4). The **Sketch** node solves it and outputs its closed regions as a list of profiles, with one number input per exposed dimension and reference dimensions on `measurements`. **Plane from Face** puts a plane on a picked flat face. Projected model edges resolve against the Sketch node's `references` on every evaluation. A notched region (a clockwise arc in a counter-clockwise loop) now extrudes. No 2D editor UI: that is S5.

**Architecture:**
- **Graph.** `NodeDefinition` gains `static func inputs(for node: Node) -> [SocketSpec]`, defaulting to the static `inputs`. The `Evaluator` (gather and broadcast) and `Graph.connectionProblem` read it, so the Sketch node's exposed-dimension sockets are wired, gathered, broadcast and cached exactly like declared sockets. `CreatorGraph` now depends on `CreatorSketch` for `ConstantValue.sketch`; `CreatorSketch` still imports only `CreatorGeometry`.
- **Settings.** `ConstantValue` gains `.sketch(Sketch)` and `.facePick(FacePick)`, both settings with no runtime `Scalar`. `NodeSetting` gains `sketch`, `face` and `projection(_ reference:)` (`"projection.<reference>"`, holding `.edgePicks([pick])` for one projected edge). `GraphFile.currentFormatVersion` goes 3 → 4.
- **Kernel data.** `EdgeInfo.curve: EdgeCurve?` (an exact line or circle, from new `occt_edge_info` fields, and from `FakeKernel`) is what projection reads. `FacePick` (a face's tag set, matched as a subset) and `Topology.faces(matching:)`/`facePick(for:)` are what Plane from Face reads.
- **Nodes.** `SketchNode` (thin) reads the setting, resolves the plane, re-resolves projections (`SketchProjections` + `EdgeProjection`), applies wired dimension values (`SketchSockets`), and hands over to `SketchSolve`, which solves, maps the solver status to node states, finds regions and reads measurements. `PlaneFromFaceNode` uses `FacePlane` for its deterministic x axis.
- **Shim.** `build_edge` builds an arc with `end < start` as the counter-clockwise arc from `end` to `start`, reversed. `describe_edge` reports each edge's ends, and a circle's centre, radius and sweep.

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, OpenCascade 7.9 (Homebrew) behind `COCCT`/`CreatorOCCT`.

**Spec:** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (§2 architecture rows for `CreatorGraph` and `CreatorNodes`, §3 model, §6 "Graph" and the deferred clockwise-arc case, §7 Nodes, §9 row S4, §10 Integration), under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata (§4 graph engine, §4.5 files, §5.3 naming). Also read `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` (its "S4 (Sketch node)" items are what Tasks 6 and 7 implement).

**Branch and base:** `sketcher-s4`, a worktree off master `d48d757`, beside `../MetalUI` at master `c62d6ba`. Run every command from the worktree root. Never edit `Package.swift`'s MetalUI path.

**Files shared with other tracks** (editor-polish, viewport-input and packaging run in parallel worktrees):
- `Package.swift`: Task 4 adds `"CreatorSketch"` to the dependencies of `CreatorGraph`, `CreatorNodes`, `CreatorGraphTests` and `CreatorNodesTests` (four list edits, nothing else). The packaging track may also edit this file.
- `CLAUDE.md`: Task 7 edits three passages (project state, the `CreatorGraph`/`CreatorNodes` module bullets, the file-format sentence). Every track may edit it; merge by passage.
- `Sources/CreatorGraph/GraphFile.swift` and `Tests/CreatorGraphTests/EdgePickFileTests.swift`: the format version (Task 4). The editor-polish branch may also bump it (ruling below).
- `Sources/CreatorNodes/BuiltInNodes.swift` and `Tests/CreatorNodesTests/OutputNodeTests.swift`: two new entries and the count (Tasks 5, 6). editor-polish's palette and node library read `BuiltInNodes.registry` and need no change.
- `Sources/CreatorKernel/FakeKernel.swift` (Task 3): the fake's edges gain curves; no numbering changes.
- **Outside this track's modules, in `CreatorGeometry`** (Task 1): `Sources/CreatorGeometry/Segment2D.swift` (`length` takes `abs` of the sweep, a one-line change the S1–S2 handoff asks for, plus the `.arc` doc comment) and `Sources/CreatorGeometry/Profile2D.swift` (doc comment only). Task 1 also creates `Tests/CreatorGeometryTests/ClockwiseArcTests.swift`. Any track touching `Segment2D` or `Profile2D` merges by line.
- `docs/verification/human-checks.md` (Task 7): appends one new section, "Group S4", at the end. Other tracks append their own groups; merge by section.
- Nothing in `CreatorEditor`, `CreatorApp`, `CreatorViewport` or `MetalCreatorApp` changes.

**Format-version ruling (parallel tracks):** this plan bumps `GraphFile.currentFormatVersion` 3 → 4. The editor-polish branch may bump it too. **Whichever branch merges second takes the next number**: the constant in `GraphFile.swift` and its doc comment, the two literals in `EdgePickFileTests.savedFilesCarryTheCurrentFormatVersion`, the CLAUDE.md file-format sentence, and the sketcher spec's Errata (S4) line. Older files keep loading either way, because `GraphFileIO.decode` refuses only versions above the current one.

**Verification status:** every code block below was applied task by task, in order, to a scratch copy of master `d48d757` (with a sibling symlink to `../MetalUI` at `c62d6ba`), using OCCT 7.9.3. After each task, `swift build --build-tests` gave no new warnings (only the expected "built for newer macOS version" linker notes and master's existing `ContextMenuTests.swift:70` warning, with its caret continuation line), the full `swift test` passed, and `swiftlint lint --strict` reported no violations. Test counts (master has 901):

| After task | Tests | Master + |
|---|---|---|
| 1 Clockwise arcs | 908 | 7 |
| 2 Per-node inputs | 915 | 14 |
| 3 Edge curves | 922 | 21 |
| 4 Settings and format 4 | 938 | 37 |
| 5 Plane from Face | 945 | 44 |
| 6 Sketch node | 969 | 68 |
| 7 Projection and docs | 984 | 83 |

**Task order (by risk):**
1. Task 1, clockwise arcs in the shim. If OCCT built the complementary arc, or history lost the reversed edge, a notched sketch would extrude wrong, so it goes first and carries an OCCT volume test.
2. Task 2, per-node inputs in the evaluator. Every later socket rule rests on it.
3. Task 3, edge curves through the shim (C struct fields and their Swift reading).
4. Task 4, the settings and the format bump.
5. Tasks 5–7, the nodes, then projection and docs.

**Decisions made in this plan:**
- **The clockwise-arc case is taken ("unless S4 needs it": it does).** The Sketch node is the first producer of profiles from free-form regions, and a notch (a counter-clockwise outline running along an arc the other way) is ordinary sketching; S2's regions already emit it as `Segment2D.arc` with `end < start`. Rejecting it would make "Extrude failed: an arc in the profile has no sweep." the answer to a slot-shaped cut-out. The fix is local: `build_edge` makes the counter-clockwise arc from `end` to `start` and reverses the edge, the sweep check takes `abs`, `signed_area` is already exact for negative sweeps, and `Segment2D.length` takes `abs`. No new segment kind, so no other caller changes.
- **Exposed dimensions are per-node sockets, not a fixed list.** `NodeDefinition.inputs(for:)` keeps every existing definition unchanged (the default returns `inputs`). The Evaluator and `connectionProblem` read it. The graph panel (`NodeShape`, `InspectorBuilder`) still reads the static `inputs`; switching them is S5 editor work (handoff note), so this plan doesn't touch `CreatorEditor`. A wire left on a socket the node no longer lists is ignored (the stored value is used), never a crash.
- **Exposed sockets are in dimension-name order** (ties by ID), default to the stored value, and use `.millimetres` or `.degrees`. A dimension named like a fixed input (`plane`, `references`), a setting (`NodeSetting.all`), anything starting with `projection.`, an empty name or a repeated one is not a socket, and the node warns with the name.
- **Projection picks are one setting per projection:** `NodeSetting.projection(reference)` = `"projection.<reference>"` holding `.edgePicks([pick])`. This reuses `EdgePick` and its tag-subset matching, needs no new `ConstantValue` kind, and keeps `CreatorSketch` free of `CreatorKernel` (the handoff's `ProjectionSource.reference` is the key). A pick must name exactly one edge across all `references` solids; otherwise the projection is suspended (constraints skipped, nothing deleted) and named in a warning. A changed match count with one edge still chosen is a warning (parent spec §5.3 rule 6).
- **Edges carry their exact curve:** `EdgeInfo.curve: EdgeCurve?` with `.line(start:end:)` and `.circle(center:axis:radius:start:sweep:)` (counter-clockwise about `axis`). The shim fills `occt_edge_info.start/end/center/radius/sweep` from `BRepAdaptor_Curve`. `FakeKernel` fills every edge's curve so projection is testable without OCCT.
- **Projection v1** (spec §7): a line projects orthogonally (refused if it collapses to a point); a circle or arc projects only when its axis is parallel to the plane normal (1 − |cos| ≤ 1e-9), as a circle (sweep ≥ 2π − 1e-9) or a counter-clockwise `ProjectedCurve.arc`, its start moved to the far end when the axis points against the normal. Everything else is refused with a plain reason.
- **Plane from Face** stores `NodeSetting.face` = `.facePick(FacePick)`, the face's whole tag set, matched as a subset (a union merges coplanar faces and their tags). No match or a curved face is an error; several matches warn and use the first by ID. The x axis is world X projected onto the face, or world Y when X's in-plane part is shorter than 1e-3.
- **Node states** (spec §7, handoff): `.underConstrained` warns "The sketch has N degrees of freedom left, so it isn't fully constrained."; `.overConstrained` throws the solver's `conflictMessages` joined by newlines; `.failed(reason:)` throws the reason. A thrown error keeps the last good result ghosted (the Evaluator and app already do this). Open curves warn with `SketchRegionResult.warning`; an empty sketch warns "Draw a closed shape in the sketch to make a profile." and outputs an empty list, which an Extrude turns into no solid without an error.
- **Plane source:** `.fixed(plane)` uses the stored plane and warns if `plane` is wired anyway ("the wire has no effect"); `.wired` requires the wire and errors without it.
- **The node never writes the sketch back.** It solves from the stored sketch's warm start each time, so results don't depend on evaluation history; storing `Sketch.remember` after edits is S5's editor job (handoff note).
- **`measurements` never shifts.** A list position is a reference dimension (name order). The solver measures a projection from the curve stored in the sketch, which S4 never refreshes, so a reference dimension on a suspended projection would report a stale or placeholder value; and `SketchMeasure` returns nothing for a dimension that doesn't fit its geometry (a length on a projected circle). In either case the node outputs an empty `measurements` list and warns, naming each such dimension (`SketchSolve.unmeasured`), so a wired consumer never reads another dimension's value.
- **One pick resolver.** Projection resolves its pick with `EdgeTagMatch.choose` (tag subsets, then ordinals) per `references` solid and reports drift with `EdgeTagMatch.drift`, Edges by Tag's own sentence ("Matched 1 edge, expected 2."), so the two can't drift apart.
- **No inspector controls yet.** The Sketch node declares none ("Edit sketch" is S5) and Plane from Face has no "Pick face in view…" button, because `AppModel.handle(.pickFacesInView)` still refuses and `CreatorApp` is outside this track. Both nodes are created from the palette and their settings come from tests (and later the editor).
- **Built-ins are 28.** Plane from Face joins the value nodes after Plane; Sketch joins the profile nodes after Polyline.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency: data races are errors. No `@unchecked Sendable`, no new `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- One type per Swift file, named after the type. Extensions go in `Type+Purpose.swift`. Test fixture files that hold several helpers say so in their first comment line.
- **No force unwraps, no force `try`, no GCD, no third-party packages.** Use `FormatStyle` (`Int.display`, `Double.display` in node messages), never `Formatter` subclasses or `String(format:)`.
- `CreatorSketch` imports only `CreatorGeometry` and Foundation (sketcher spec §2). Never iterate a dictionary where order reaches output.
- **All OCCT work runs under `OCCTKernel.serialized`.** Tests reach the shim only through `OCCTKernel`. Every C allocation has a `*_free`; no C++ exception crosses into Swift. Shim `user_error` messages are user-facing, lower-case and unprefixed.
- `CreatorNodes` is UI-free (parent spec §3.2): inspector sections and handles are data. Create nodes only with `NodeRegistry.makeNode`.
- Adding a `ConstantValue` kind bumps `GraphFile.currentFormatVersion` (CLAUDE.md). This plan bumps it once, 3 → 4, in Task 4 (see the ruling above).
- MetalUI gaps are logged in `docs/metalui-gaps.md` and never worked around. This plan has no UI and logs none.
- `swiftlint lint --strict` reports zero violations. Lines wrap at 140 columns; multi-line collection literals take trailing commas.
- Every commit message ends with a blank line, then the implementing model's harness-provided `Co-Authored-By:` and `Claude-Session:` lines.
- Expected build noise: OCCT dylibs "built for newer macOS version" linker notes, and master's `Tests/CreatorViewportTests/ContextMenuTests.swift:70` "'underPointer' mutated after capture by sendable closure" warning (it prints twice: once with its path, once as a caret line without one). Nothing else may warn.

## Review Focus

The spec implies these inputs but says nothing about how they behave. Each is pinned by a test in the named task, most likely first.

1. **A wire left on an exposed-dimension socket after the dimension is un-exposed or renamed.** The node no longer lists the socket. The expected behaviour is that the stored value drives the dimension and nothing crashes or errors. *Task 2: `aWireToASocketTheNodeNoLongerListsIsIgnored`. Task 6: `aWireLeftOnAnUnexposedDimensionIsIgnored`.*
2. **A dimension renamed to a name the node already uses** (`plane`, `references`, `sketch`, `projection.p1`). It must not silently shadow or duplicate a socket. Instead it isn't exposed, and the warning names it. *Task 6: `aDimensionNamedLikeAnInputOrSettingIsNotExposedAndWarns`.*
3. **Non-finite or impossible driving values,** whether wired in (NaN from a Number) or stored (−5 mm). These must give a plain-language node error, never a crash or OCCT text, and the last good part stays ghosted. A non-finite sketch must never reach a file. *Task 6: `aNonFiniteWiredValueIsAPlainError`, `anImpossibleValueIsAPlainError`. Task 4: `aNonFiniteSketchIsRefused`, the `SketchFiniteTests`.*
4. **A sketch region with a notch** (a clockwise arc in a counter-clockwise loop). This is ordinary sketching, and it must extrude and revolve to the analytic volume. *Task 1: `aNotchedPlateExtrudesToItsAnalyticVolume`, `aHoleWithANotchIsCut`, `aNotchedPlateRevolves`. Task 6: `aNotchedSketchRegionExtrudes`.*
5. **A projected edge whose pick no longer names exactly one edge** after an upstream change, or that has no reference solid wired in. The projection must be suspended with a warning that names it. Constraints on it must be skipped, not reported as conflicts, and nothing may be deleted. *Task 7: `aMissingPickOrReferenceSuspendsTheEdgeWithAWarning`, `noReferenceSolidIsExplained`, `aConstraintOnASuspendedEdgeIsIgnoredNotAConflict`, `aPickWhoseMatchCountDriftedSaysSo`, `anEdgeThatProjectsToAPointIsSuspendedWithAWarning`.*
6. **A reference dimension that can't be measured,** on a suspended projection (its stored curve is stale or a placeholder) or on geometry it doesn't fit (a length on a circle). Dropping it would shift every later list position, so a wired consumer would read another dimension's value. Instead `measurements` is empty and the warning names it. *Task 6: `aReferenceDimensionThatCantBeMeasuredEmptiesMeasurementsAndSaysWhich`. Task 7: `aMissingPickOrReferenceSuspendsTheEdgeWithAWarning`.*

Also pinned: an empty sketch into an Extrude gives no solid and no error (Task 6, `anEmptySketchIntoAnExtrudeMakesNoSolidAndNoError`), and a plane wired into a fixed-plane sketch warns that it has no effect (Task 6, `aWireIntoTheOwnPlaneOfASketchWarns`).

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/CreatorGeometry/Segment2D.swift`, `Profile2D.swift` | Modify (T1) | Clockwise arcs (`end < start`) documented; positive `length` |
| `Sources/COCCT/cocct_build.cpp`, `include/cocct.h` | Modify (T1, T3) | Build clockwise arcs; report edge ends, centre, radius, sweep |
| `Sources/COCCT/cocct_inspect.cpp` | Modify (T3) | Fill the new `occt_edge_info` fields |
| `Sources/CreatorSketch/Regions/SketchRegion.swift`, `SketchRegions.swift` | Modify (T1) | Doc comments only: the shim now builds notches |
| `Sources/CreatorGraph/NodeDefinition.swift`, `Evaluator.swift`, `Graph+Connections.swift` | Modify (T2) | `inputs(for:)` and its two readers |
| `Sources/CreatorKernel/EdgeCurve.swift` | Create (T3) | An edge's exact line or circle |
| `Sources/CreatorKernel/EdgeInfo.swift`, `FakeKernel.swift` | Modify (T3) | `curve` on every edge (fake included) |
| `Sources/CreatorOCCT/OCCTRawTopology.swift`, `OCCTTagger.swift` | Modify (T3) | Read the shim's curve; carry it into `EdgeInfo` |
| `Sources/CreatorKernel/FacePick.swift`, `FacePick+Codable.swift`, `Topology+FacePicks.swift`, `TopoRole+Stability.swift` | Create (T4) | Face picks, their matching and their stability check |
| `Sources/CreatorKernel/EdgePick.swift` | Modify (T4) | `touchesUnnamedFace` uses `TopoRole.isUnstable` |
| `Sources/CreatorSketch/Model/Sketch+Finite.swift`, `SketchEntityKind+Finite.swift` | Create (T4) | A sketch's numbers are all finite |
| `Sources/CreatorGraph/ConstantValue.swift`, `Scalar.swift`, `NodeSetting.swift`, `GraphFile.swift` | Modify (T4) | `.sketch` / `.facePick` settings, setting names, format 4 |
| `Sources/CreatorNodes/Values/GraphParameterNode.swift` | Modify (T4) | Exhaustive switch over the new kinds |
| `Package.swift` | Modify (T4) | `CreatorSketch` for Graph, Nodes and their tests |
| `Sources/CreatorNodes/Support/FacePlane.swift`, `Values/PlaneFromFaceNode.swift` | Create (T5) | The Plane from Face node |
| `Sources/CreatorNodes/Sketch/SketchSockets.swift`, `SketchSolve.swift`, `Profiles/SketchNode.swift` | Create (T6) | The Sketch node: sockets, solve and states, definition |
| `Sources/CreatorNodes/Sketch/EdgeProjection.swift`, `SketchProjections.swift` | Create (T7) | Projection maths; resolving picks against `references` |
| `Sources/CreatorNodes/BuiltInNodes.swift` | Modify (T5, T6) | Register the two nodes |
| `CLAUDE.md`, sketcher spec Errata (S4), S1–S2 handoff note | Modify (T7) | Rules, decisions and the S5 handoff |
| `Tests/CreatorGeometryTests/ClockwiseArcTests.swift`, `Tests/CreatorOCCTTests/ClockwiseArcConformanceTests.swift` | Create (T1) | Clockwise arcs |
| `Tests/CreatorGraphTests/NodeInputsForNodeTests.swift`, `Support/TestNodes.swift` | Create, modify (T2) | Per-node inputs; the `ExtraInputsNode` fixture |
| `Tests/CreatorOCCTTests/EdgeCurveTests.swift`, `Tests/CreatorKernelTests/FakeKernelCurveTests.swift` | Create (T3) | Edge curves on both kernels |
| `Tests/CreatorKernelTests/FacePickTests.swift`, `Tests/CreatorSketchTests/SketchFiniteTests.swift`, `Tests/CreatorGraphTests/SketchSettingFileTests.swift`, `EdgePickFileTests.swift` | Create, modify (T4) | Picks, finiteness, files, version 4 |
| `Tests/CreatorNodesTests/PlaneFromFaceNodeTests.swift`, `OutputNodeTests.swift` | Create, modify (T5, T6) | Plane from Face; the built-in count |
| `Tests/CreatorNodesTests/Support/SketchNodeFixtures.swift`, `SketchNodeTests.swift`, `SketchIntegrationTests.swift` | Create (T6) | Sketch node, FakeKernel and OCCT |
| `Sources/CreatorNodes/Selection/EdgeTagMatch.swift` | Modify (T7) | `choose` and `drift`, shared by Edges by Tag and projection |
| `Tests/CreatorNodesTests/SketchProjectionTests.swift` | Create (T7) | Projection, FakeKernel and OCCT |
| `docs/verification/human-checks.md` | Modify (T7) | Group S4: the two nodes in the running app |

The gate used at the end of every task:

```bash
export SCRATCH=/private/tmp/claude-501/<project>/<session>/scratchpad   # your session's scratchpad, never the checkout
swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "built for newer" | grep -v "ContextMenuTests.swift:70" | grep -v underPointer
swift test > "$SCRATCH/s4-test.log" 2>&1
grep -E "Test run with" "$SCRATCH/s4-test.log" | awk '{for (i = 1; i <= NF; i++) if ($i == "with") s += $(i + 1)} END {print s}'
grep -E "failed|recorded an issue" "$SCRATCH/s4-test.log" | head
swiftlint lint --strict --quiet
```

The build line prints nothing: the last filter drops the caret continuation line of master's `ContextMenuTests` warning ("warning: 'underPointer' mutated after capture by sendable closure" without a file path), and an incremental build may not re-emit that warning at all. The `awk` line prints the task's expected total (one `Test run with N tests` line per test bundle, summed). The failure `grep` and SwiftLint print nothing.

---

### Task 1: Clockwise arcs through the shim (the handoff's notch case)

**Files:**
- Modify: `Sources/CreatorGeometry/Segment2D.swift` (the `.arc` doc and `length`), `Sources/CreatorGeometry/Profile2D.swift:1-4` (doc) — outside this track's modules, named in the header's shared files
- Modify: `Sources/COCCT/cocct_build.cpp` (`build_edge`), `Sources/COCCT/include/cocct.h` (`occt_segment`, `occt_profile` docs)
- Modify: `Sources/CreatorSketch/Regions/SketchRegion.swift:3-8`, `Sources/CreatorSketch/Regions/SketchRegions.swift:83-85` (docs only)
- Test: `Tests/CreatorGeometryTests/ClockwiseArcTests.swift`, `Tests/CreatorOCCTTests/ClockwiseArcConformanceTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Segment2D.arc(center:radius:start:end:)` with `end < start` is a valid clockwise arc everywhere. `Segment2D.length` is `r * |end − start|`. `OCCTKernel.extrude`/`revolve` build such arcs. The shim error "an arc in the profile has no sweep" now means `|end − start| ≤ 1e-12`.

- [ ] **Step 1: Write the failing tests**


Create `Tests/CreatorGeometryTests/ClockwiseArcTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry

/// S4: an arc with `end < start` runs clockwise, the way a counter-clockwise loop runs along a
/// notch cut into an outline (sketcher spec §5 step 5).
struct ClockwiseArcTests {
    /// The semicircular notch in the top edge of the 20 × 10 plate, run clockwise from (14, 10) to (6, 10).
    let notch = Segment2D.arc(center: Vector2(10, 10), radius: 4, start: .degrees(0), end: .degrees(-180))

    @Test func aClockwiseArcHasAPositiveLength() {
        #expect(isClose(notch.length, 4 * .pi))
    }

    @Test func aClockwiseArcRunsFromStartToEnd() {
        #expect(isClose(Vector3(notch.startPoint.x, notch.startPoint.y, 0), Vector3(14, 10, 0)))
        #expect(isClose(Vector3(notch.endPoint.x, notch.endPoint.y, 0), Vector3(6, 10, 0)))
    }

    @Test func aLoopThroughAClockwiseArcIsClosed() {
        let loop: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(14, 10)), notch,
            .line(Vector2(6, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        #expect(Profile2D(plane: .xy, segments: loop).isClosed)
    }
}
```

Create `Tests/CreatorOCCTTests/ClockwiseArcConformanceTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// S4 decides the S1–S2 handoff's clockwise-arc case: the shim builds an arc with `end < start`
/// clockwise, so a sketch region with a notch (a counter-clockwise loop running along an arc the
/// other way) extrudes. Without it `build_profile` threw "an arc in the profile has no sweep".
struct ClockwiseArcConformanceTests {
    /// The S2 region of a 20 × 10 plate with a semicircular r 4 notch in its top edge, exactly as
    /// `SketchRegions` emits it: counter-clockwise from (0, 0), the notch stored with `end < start`.
    static func notchedPlate(offset: Vector2 = .zero) -> [Segment2D] {
        let notch = Segment2D.arc(center: Vector2(10, 10), radius: 4, start: .degrees(0), end: .degrees(-180))
        let loop: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(14, 10)), notch,
            .line(Vector2(6, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        return loop.map { $0.translated(by: offset) }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aNotchedPlateExtrudesToItsAnalyticVolume(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await kernel.extrude(Profile2D(plane: .xy, segments: Self.notchedPlate()), distance: 3,
                                             mode: .oneSided, tag: tag)
        #expect(isClose(try await kernel.properties(of: solid).volume, 3 * (200 - 8 * Double.pi)))
        #expect(solid.topology.faces.count == 8)
        let notchWall = try #require(faces(solid, role: .side(segment: 3), of: tag).first)
        #expect(notchWall.kind == .cylinder)
        #expect(isClose(notchWall.area, 3 * 4 * Double.pi))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aHoleWithANotchIsCut(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let outline = Profile2D.rectangle(width: 40, height: 30, plane: .xy).segments
        let profile = Profile2D(plane: .xy, outer: outline, holes: [Self.notchedPlate(offset: Vector2(-10, -5))])
        let solid = try await kernel.extrude(profile, distance: 2, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 2 * (1200 - (200 - 8 * Double.pi))))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aNotchedPlateRevolves(_ under: KernelUnderTest) async throws {
        // Revolved a half turn about the plate's left edge (the y axis): Pappus, area × π × centroid x.
        let kernel = under.make()
        let solid = try await kernel.revolve(Profile2D(plane: .xy, segments: Self.notchedPlate()),
                                             axis: Axis(origin: .zero, direction: .unitY), angle: .degrees(180),
                                             tag: newTag())
        // The plate is symmetric about x = 10, so its centroid x is 10.
        #expect(isClose(try await kernel.properties(of: solid).volume, (200 - 8 * Double.pi) * Double.pi * 10))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aClockwiseArcStillNeedsASweep(_ under: KernelUnderTest) async {
        let dot = Segment2D.arc(center: .zero, radius: 2, start: .degrees(90), end: .degrees(90))
        let loop: [Segment2D] = [dot, .line(dot.endPoint, Vector2(5, 5)), .line(Vector2(5, 5), dot.startPoint)]
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(Profile2D(plane: .xy, segments: loop), distance: 1, mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude", reason: "an arc in the profile has no sweep."))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter ClockwiseArc`
Expected: `aClockwiseArcHasAPositiveLength` fails (−4π), and the three OCCT volume tests fail with `Caught error: .operationFailed(operation: "extrude", reason: "an arc in the profile has no sweep.")` (`"revolve"` for `aNotchedPlateRevolves`). `aClockwiseArcStillNeedsASweep`, `aClockwiseArcRunsFromStartToEnd` and `aLoopThroughAClockwiseArcIsClosed` already pass.

- [ ] **Step 3: Build clockwise arcs and make their length positive**


In `Sources/CreatorGeometry/Segment2D.swift`, replace:

```swift
    /// A counter-clockwise arc from `start` to `end`. `end - start` of 2π is a full circle.
    case arc(center: Vector2, radius: Double, start: Angle, end: Angle)
```

with:

```swift
    /// An arc from `start` to `end`: counter-clockwise when `end > start` (`end - start` of 2π is a full
    /// circle), clockwise when `end < start`. A clockwise arc is how a counter-clockwise loop runs
    /// along a notch cut into it (sketcher spec §5 step 5, S4).
    case arc(center: Vector2, radius: Double, start: Angle, end: Angle)
```

In `Sources/CreatorGeometry/Segment2D.swift`, replace:

```swift
        case .arc(_, let r, let start, let end): r * (end.radians - start.radians)
```

with:

```swift
        case .arc(_, let r, let start, let end): r * abs(end.radians - start.radians)
```

In `Sources/CreatorGeometry/Profile2D.swift`, replace:

```swift
/// Holes may wind either way; the kernel orients them. `Segment2D.arc` is counter-clockwise only, so a loop
/// containing an arc must be written counter-clockwise (reverse a clockwise-walked loop). Loop 0 is `outer`, loop `n` is `holes[n - 1]`,
/// which is the numbering `TopoRole.side(loop:segment:)` uses.
```

with:

```swift
/// Holes may wind either way; the kernel orients them. An arc runs clockwise when its `end < start`, so a loop
/// through a notch stays continuous (`Segment2D.arc`). Loop 0 is `outer`, loop `n` is `holes[n - 1]`,
/// which is the numbering `TopoRole.side(loop:segment:)` uses.
```

In `Sources/COCCT/cocct_build.cpp`, replace:

```cpp
    if (!(segment.end - segment.start > 1e-12)) {
        throw user_error("an arc in the profile has no sweep");
    }
```

with:

```cpp
    if (!(std::abs(segment.end - segment.start) > 1e-12)) {
        throw user_error("an arc in the profile has no sweep");
    }
```

In `Sources/COCCT/cocct_build.cpp`, replace:

```cpp
    const gp_Ax2 axes(point_on(frame, segment.cx, segment.cy), frame.Direction(), frame.XDirection());
    BRepBuilderAPI_MakeEdge make(gp_Circ(axes, segment.radius), segment.start, segment.end);
    if (!make.IsDone()) {
        throw user_error("an arc in the profile could not be built");
    }
    return make.Edge();
```

with:

```cpp
    const gp_Ax2 axes(point_on(frame, segment.cx, segment.cy), frame.Direction(), frame.XDirection());
    // A clockwise arc (end < start, a loop running along a notch) is the counter-clockwise arc from
    // end to start, reversed, so the wire still runs start → end.
    const bool clockwise = segment.end < segment.start;
    BRepBuilderAPI_MakeEdge make(gp_Circ(axes, segment.radius), std::min(segment.start, segment.end),
                                 std::max(segment.start, segment.end));
    if (!make.IsDone()) {
        throw user_error("an arc in the profile could not be built");
    }
    return clockwise ? TopoDS::Edge(make.Edge().Reversed()) : make.Edge();
```

`signed_area` needs no change: ½∮x dy − y dx over an arc is `r·cx·(sin e − sin s) − r·cy·(cos e − cos s) + r²·(e − s)` for either sign of `e − s`, so a clockwise arc already contributes its signed area. `std::min`/`std::max` come from `<algorithm>`, which the file already includes.

In `Sources/COCCT/include/cocct.h`, replace:

```cpp
/// kind 1 = counter-clockwise arc around (cx,cy) with `radius` from angle `start` to `end` (radians).
```

with:

```cpp
/// kind 1 = arc around (cx,cy) with `radius` from angle `start` to `end` (radians): counter-clockwise when
/// end > start, clockwise when end < start (a counter-clockwise loop running along a notch).
```

In `Sources/COCCT/include/cocct.h`, replace:

```cpp
/// hole wire that winds the same way as the outer loop, which is what OCCT needs.
/// Arc segments are counter-clockwise only, so a loop containing an arc arrives counter-clockwise.
```

with:

```cpp
/// hole wire that winds the same way as the outer loop, which is what OCCT needs.
```

In `Sources/CreatorSketch/Regions/SketchRegion.swift`, replace:

```swift
/// (`Profile2D.isClosed` holds) even though `Segment2D` documents its arcs as counter-clockwise.
```

with:

```swift
/// (`Profile2D.isClosed` holds); the kernel builds such clockwise arcs (S4).
```

In `Sources/CreatorSketch/Regions/SketchRegions.swift`, replace:

```swift
    /// its traversal sense, stored with `end < start`, so the loop stays continuous; the shim
    /// does not build such arcs yet (S4 handoff).
```

with:

```swift
    /// its traversal sense, stored with `end < start`, so the loop stays continuous; the shim
    /// builds it clockwise (S4).
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter "ClockwiseArc|RegionTests|HoleConformanceTests|ExtrudeConformanceTests|SweepConformanceTests"`
Expected: PASS. The S2 test `notchedPlateKeepsAContinuousLoopThroughItsClockwiseArc` still sees `end − start == −π`; only the shim and `length` changed.

- [ ] **Step 5: Run the gate**

Expected: no new warnings, **908 tests** (master + 7), all passing, SwiftLint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGeometry Sources/COCCT Sources/CreatorSketch/Regions Tests/CreatorGeometryTests/ClockwiseArcTests.swift \
  Tests/CreatorOCCTTests/ClockwiseArcConformanceTests.swift
git commit -m "feat(occt): build clockwise arcs, so notched sketch regions extrude (S4)"
```

---

### Task 2: Per-node inputs (`NodeDefinition.inputs(for:)`)

**Files:**
- Modify: `Sources/CreatorGraph/NodeDefinition.swift` (requirement and default), `Sources/CreatorGraph/Evaluator.swift` (`gather`, `run`), `Sources/CreatorGraph/Graph+Connections.swift:9`
- Modify: `Tests/CreatorGraphTests/Support/TestNodes.swift` (the `ExtraInputsNode` fixture and `testRegistry`)
- Test: `Tests/CreatorGraphTests/NodeInputsForNodeTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `NodeDefinition.inputs(for node: Node) -> [SocketSpec]` (a protocol requirement with the default `{ inputs }`). The Evaluator's gather, its `BroadcastPlan`, and `Graph.connectionProblem(from:to:registry:)` read it. A link to a socket the node doesn't list is ignored when gathering and refused (`.unknownSocket`) when connecting.

- [ ] **Step 1: Write the failing tests**

Add a fixture node to `Tests/CreatorGraphTests/Support/TestNodes.swift`, just above `testRegistry`, and register it:


In `Tests/CreatorGraphTests/Support/TestNodes.swift`, replace:

```swift
let testRegistry = NodeRegistry([
```

with:

```swift
/// Adds a number input per name in its `extra` text setting (comma-separated), each defaulting to 1,
/// like the Sketch node's exposed dimensions. `sum` adds `value` and every extra input.
enum ExtraInputsNode: NodeDefinition {
    static let typeID = "test.extraInputs"
    static let displayName = "Extra Inputs"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("sum", .number)]
    static func extras(_ node: Node) -> [SocketName] {
        guard case .text(let names)? = node.inputValues["extra"] else { return [] }
        return names.split(separator: ",").map { SocketName(String($0)) }
    }
    static func inputs(for node: Node) -> [SocketSpec] {
        inputs + extras(node).map { SocketSpec($0, .number, defaultValue: .number(1)) }
    }
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let extra = try extras(context.node).reduce(0.0) { $0 + (try inputs.number($1)) }
        return NodeOutputs(["sum": .number(try inputs.number("value") + extra)])
    }
}

let testRegistry = NodeRegistry([
```

In `Tests/CreatorGraphTests/Support/TestNodes.swift`, replace:

```swift
    SinkNode.self, OptionalOutputNode.self,
])
```

with:

```swift
    SinkNode.self, OptionalOutputNode.self, ExtraInputsNode.self,
])
```

Create `Tests/CreatorGraphTests/NodeInputsForNodeTests.swift`:

```swift
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// `NodeDefinition.inputs(for:)` (S4): sockets that depend on a node's settings, like the Sketch
/// node's exposed dimensions, are wired, gathered, broadcast and cached like declared ones.
struct NodeInputsForNodeTests {
    func evaluator() -> Evaluator { Evaluator(registry: testRegistry, kernel: FakeKernel()) }

    @Test func aDeclaredTypeHasItsFixedInputs() {
        #expect(AddNode.inputs(for: makeNode(AddNode.self)) == AddNode.inputs)
    }

    @Test func anExtraSocketCanBeWiredAndIsGathered() async throws {
        let five = makeNode(ConstantNode.self, ["value": .number(5)])
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        let wired = graph([five, node], [link(five, "value", node, "k")])
        #expect(wired.connectionProblem(from: Endpoint(node: five.id, socket: "value"),
                                        to: Endpoint(node: node.id, socket: "k"), registry: testRegistry) == nil)
        let report = try await evaluator().evaluate(wired, demand: [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [5])
    }

    @Test func anUnwiredExtraSocketUsesItsDefault() async throws {
        let node = makeNode(ExtraInputsNode.self, ["value": .number(2), "extra": .text("k,m")])
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [4])
    }

    @Test func aSocketTheNodeDoesNotListIsRefused() {
        let five = makeNode(ConstantNode.self)
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        #expect(graph([five, node]).connectionProblem(from: Endpoint(node: five.id, socket: "value"),
                                                     to: Endpoint(node: node.id, socket: "q"),
                                                     registry: testRegistry) == .unknownSocket("q"))
    }

    @Test func anExtraSocketBroadcasts() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(3)])
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        let report = try await evaluator().evaluate(graph([list, node], [link(list, "values", node, "k")]), demand: [node.id])
        let sum = try #require(report.results[node.id]?.outputs?["sum"])
        #expect(sum.isList)
        #expect(sum.numbers == [0, 1, 2])
    }

    @Test func aWireToASocketTheNodeNoLongerListsIsIgnored() async throws {
        let five = makeNode(ConstantNode.self, ["value": .number(5)])
        let node = makeNode(ExtraInputsNode.self, ["extra": .text("")])
        let report = try await evaluator().evaluate(graph([five, node], [link(five, "value", node, "k")]), demand: [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [0])
    }

    @Test func changingTheExtraSocketsInvalidatesTheCache() async throws {
        let evaluator = evaluator()
        var node = makeNode(ExtraInputsNode.self, ["extra": .text("k")])
        _ = try await evaluator.evaluate(graph([node]), demand: [node.id])
        node.inputValues["extra"] = .text("k,m")
        let report = try await evaluator.evaluate(graph([node]), demand: [node.id])
        #expect(report.evaluatedNodes == [node.id])
        #expect(report.results[node.id]?.outputs?["sum"]?.numbers == [2])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter NodeInputsForNodeTests`
Expected: build error in `aDeclaredTypeHasItsFixedInputs`: type `AddNode` has no member `inputs(for:)`. (Without the requirement, `ExtraInputsNode.inputs(for:)` is just an unused static func, and the evaluator never sees `k`.)

- [ ] **Step 3: Add the requirement and read it in the evaluator and the connection check**


In `Sources/CreatorGraph/NodeDefinition.swift`, replace:

```swift
    static var outputs: [SocketSpec] { get }
```

with:

```swift
    static var outputs: [SocketSpec] { get }
    /// The input sockets of one node. Most types have the fixed `inputs`; a type whose sockets depend on
    /// its settings (the Sketch node's exposed dimensions, sketcher spec §7) adds more. The evaluator and
    /// `Graph.connectionProblem` read this, so a socket listed here can be wired and is gathered.
    static func inputs(for node: Node) -> [SocketSpec]
```

In `Sources/CreatorGraph/NodeDefinition.swift`, replace:

```swift
    public static var typeVersion: Int { 1 }
```

with:

```swift
    public static var typeVersion: Int { 1 }
    public static func inputs(for node: Node) -> [SocketSpec] { inputs }
```

In `Sources/CreatorGraph/Evaluator.swift`, replace:

```swift
        for spec in definition.inputs {
            if let link
```

with:

```swift
        for spec in definition.inputs(for: node) {
            if let link
```

In `Sources/CreatorGraph/Evaluator.swift`, replace:

```swift
        let plan = BroadcastPlan.make(inputs: inputs, specs: definition.inputs)
```

with:

```swift
        let plan = BroadcastPlan.make(inputs: inputs, specs: definition.inputs(for: node))
```

In `Sources/CreatorGraph/Graph+Connections.swift`, replace:

```swift
        guard let input = targetDefinition.inputs.first(where: { $0.name == to.socket }) else { return .unknownSocket(to.socket) }
```

with:

```swift
        guard let input = targetDefinition.inputs(for: target).first(where: { $0.name == to.socket }) else {
            return .unknownSocket(to.socket)
        }
```

The cache key needs no change: it already hashes every stored setting (so changing which sockets exist changes the key) and, per gathered socket, the upstream key or the constant.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter CreatorGraphTests`
Expected: PASS, including the 7 new `NodeInputsForNodeTests`.

- [ ] **Step 5: Run the gate**

Expected: no new warnings, **915 tests** (master + 14), SwiftLint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): per-node input sockets through NodeDefinition.inputs(for:) (S4)"
```

---

### Task 3: Edge curves (`EdgeInfo.curve`) through the shim and FakeKernel

**Files:**
- Create: `Sources/CreatorKernel/EdgeCurve.swift`
- Modify: `Sources/CreatorKernel/EdgeInfo.swift` (field and init), `Sources/CreatorKernel/FakeKernel.swift` (`extrude`, `prism`, new `curve(of:on:at:)`)
- Modify: `Sources/COCCT/include/cocct.h` (`occt_edge_info`), `Sources/COCCT/cocct_inspect.cpp` (`describe_edge`, include)
- Modify: `Sources/CreatorOCCT/OCCTRawTopology.swift` (`Edge.curve`, `read`, `curve(_:)`), `Sources/CreatorOCCT/OCCTTagger.swift:31-32`
- Test: `Tests/CreatorOCCTTests/EdgeCurveTests.swift`, `Tests/CreatorKernelTests/FakeKernelCurveTests.swift`

**Interfaces:**
- Consumes: Task 1's clockwise arcs (FakeKernel reports one as the same circle run counter-clockwise from its end).
- Produces:
  - `public enum EdgeCurve: Hashable, Sendable { case line(start: Vector3, end: Vector3); case circle(center: Vector3, axis: Vector3, radius: Double, start: Vector3, sweep: Double) }`. A circle runs counter-clockwise about `axis` from `start` by `sweep` radians (2π when full).
  - `EdgeInfo.curve: EdgeCurve?` and `EdgeInfo.init(…, faces:, curve: EdgeCurve? = nil)`, so every existing call site compiles.
  - C: `occt_edge_info.has_ends`, `start[3]`, `end[3]`, `center[3]`, `radius`, `sweep`.
  - Both kernels set `curve` on every line and circle edge; FakeKernel sets it on every edge.

- [ ] **Step 1: Write the failing tests**


Create `Tests/CreatorOCCTTests/EdgeCurveTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// S4: every line and circle edge carries its exact curve, which the Sketch node projects.
struct EdgeCurveTests {
    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

    /// `point` turned about the axis through `center` along unit `axis` by `angle` radians (Rodrigues).
    func rotated(_ point: Vector3, about center: Vector3, axis: Vector3, by angle: Double) -> Vector3 {
        let v = point - center
        let turned = v * cos(angle) + axis.cross(v) * sin(angle) + axis * (axis.dot(v) * (1 - cos(angle)))
        return center + turned
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aBoxEdgeCarriesItsLineEnds(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let solid = try await box(under.make(), 10, 20, 30, tag: tag)
        let edge = try #require(edges(solid, between: { hasTag($0, .endCap, of: tag) },
                                      and: { hasTag($0, .side(segment: 0), of: tag) }).first)
        guard case .line(let start, let end)? = edge.curve else {
            Issue.record("expected a line, got \(String(describing: edge.curve))")
            return
        }
        let ends = [start, end].sorted { $0.x < $1.x }
        #expect(near(ends[0], Vector3(-5, -10, 30)) && near(ends[1], Vector3(5, -10, 30)))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aCircularRimCarriesItsCentreRadiusAndFullSweep(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let solid = try await under.make().extrude(.circle(radius: 3, center: Vector2(1, 2), plane: .xy), distance: 4,
                                                   mode: .oneSided, tag: tag)
        let rim = try #require(edges(solid, between: { hasTag($0, .endCap, of: tag) },
                                     and: { hasTag($0, .side(segment: 0), of: tag) }).first)
        guard case .circle(let center, let axis, let radius, let start, let sweep)? = rim.curve else {
            Issue.record("expected a circle, got \(String(describing: rim.curve))")
            return
        }
        #expect(near(center, Vector3(1, 2, 4)))
        #expect(isClose(abs(axis.dot(.unitZ)), 1))
        #expect(isClose(radius, 3))
        #expect(isClose((start - center).length, 3))
        #expect(isClose(sweep, 2 * .pi))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aCornerArcRunsCounterClockwiseAboutItsAxisFromItsStart(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let profile = Profile2D.roundedRectangle(width: 20, height: 10, radius: 2, plane: .xy)
        let solid = try await under.make().extrude(profile, distance: 1, mode: .oneSided, tag: tag)
        let corner = try #require(edges(solid, between: { hasTag($0, .endCap, of: tag) },
                                        and: { hasTag($0, .side(segment: 1), of: tag) }).first)
        guard case .circle(let center, let axis, let radius, let start, let sweep)? = corner.curve,
              let unit = axis.normalized else {
            Issue.record("expected a circle, got \(String(describing: corner.curve))")
            return
        }
        #expect(near(center, Vector3(8, -3, 1)))
        #expect(isClose(radius, 2))
        #expect(isClose(sweep, .pi / 2))
        // Half the sweep on from `start` is the edge's midpoint, whichever way OCCT oriented the circle.
        #expect(near(rotated(start, about: center, axis: unit, by: sweep / 2), corner.midpoint))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func everyLineAndCircleEdgeOfAHoledPlateHasACurve(_ under: KernelUnderTest) async throws {
        let plate = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments,
                              holes: [Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments])
        let solid = try await under.make().extrude(plate, distance: 3, mode: .oneSided, tag: newTag())
        let lineOrCircle = solid.topology.edges.filter { $0.kind == .line || $0.kind == .circle }
        #expect(!lineOrCircle.isEmpty)
        #expect(lineOrCircle.allSatisfy { $0.curve != nil })
    }
}
```

Create `Tests/CreatorKernelTests/FakeKernelCurveTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// S4: FakeKernel's cap edges carry exact curves like OCCT's, so Sketch-node projection is testable
/// without OCCT.
struct FakeKernelCurveTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func capEdgesCarryTheirLinesAtTheCapHeights() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 5,
                                                   mode: .oneSided, tag: tag)
        // Edge 0 is segment 0 on the start cap, edge 1 the same segment on the end cap.
        #expect(solid.topology.edges[0].curve == .line(start: Vector3(-5, -10, 0), end: Vector3(5, -10, 0)))
        #expect(solid.topology.edges[1].curve == .line(start: Vector3(-5, -10, 5), end: Vector3(5, -10, 5)))
    }

    @Test func wallEdgesRiseFromTheCornerWhereTheirSegmentEnds() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 5,
                                                   mode: .oneSided, tag: tag)
        // Edges 0–7 are the caps' (two per segment); edge 8 is between sides 0 and 1, at segment 0's end.
        #expect(solid.topology.edges[8].curve == .line(start: Vector3(5, -10, 0), end: Vector3(5, -10, 5)))
        #expect(solid.topology.edges.allSatisfy { $0.curve != nil })
    }

    @Test func aClockwiseArcIsReportedCounterClockwiseFromItsEnd() async throws {
        let notch = Segment2D.arc(center: Vector2(10, 10), radius: 4, start: .degrees(0), end: .degrees(-180))
        let loop: [Segment2D] = [
            .line(Vector2(0, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(14, 10)), notch,
            .line(Vector2(6, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        let solid = try await FakeKernel().extrude(Profile2D(plane: .xy, segments: loop), distance: 2, mode: .oneSided, tag: tag)
        // Segment 3's start-cap edge is edge 6.
        guard case .circle(let center, let axis, let radius, let start, let sweep)? = solid.topology.edges[6].curve else {
            Issue.record("expected a circle")
            return
        }
        #expect(center == Vector3(10, 10, 0) && axis == .unitZ && radius == 4)
        #expect((start - Vector3(6, 10, 0)).length < 1e-9)
        #expect(abs(sweep - .pi) < 1e-12)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter "EdgeCurveTests|FakeKernelCurveTests"`
Expected: build errors: `EdgeInfo` has no member `curve`, and `EdgeCurve` is not in scope.

- [ ] **Step 3: Add `EdgeCurve` and the field**


Create `Sources/CreatorKernel/EdgeCurve.swift`:

```swift
import CreatorGeometry

/// The exact shape of a line or circle edge, which the Sketch node reads to project model edges
/// into a sketch (sketcher spec §7). Other curve kinds (ellipses, B-splines) carry none.
public enum EdgeCurve: Hashable, Sendable {
    /// A straight edge from `start` to `end`.
    case line(start: Vector3, end: Vector3)
    /// A circular edge around `center` of `radius`: from `start`, counter-clockwise about `axis` by
    /// `sweep` radians (2π for a full circle).
    case circle(center: Vector3, axis: Vector3, radius: Double, start: Vector3, sweep: Double)
}
```

In `Sources/CreatorKernel/EdgeInfo.swift`, replace:

```swift
    /// The two adjacent faces. A seam edge lists the same face twice.
    public var faces: [FaceID]

    public init(id: EdgeID, kind: CurveKind, direction: Vector3?, length: Double, midpoint: Vector3,
                convexity: Convexity, faces: [FaceID]) {
```

with:

```swift
    /// The two adjacent faces. A seam edge lists the same face twice.
    public var faces: [FaceID]
    /// The exact line or circle, for projecting the edge into a sketch. `nil` for other curves.
    public var curve: EdgeCurve?

    public init(id: EdgeID, kind: CurveKind, direction: Vector3?, length: Double, midpoint: Vector3,
                convexity: Convexity, faces: [FaceID], curve: EdgeCurve? = nil) {
```

In `Sources/CreatorKernel/EdgeInfo.swift`, replace:

```swift
        self.faces = faces
    }
```

with:

```swift
        self.faces = faces
        self.curve = curve
    }
```

- [ ] **Step 4: Report the curve from the shim**


In `Sources/COCCT/include/cocct.h`, replace:

```cpp
/// face_a/face_b: 1-based face indices; equal for a seam; both 0 for a free edge.
typedef struct {
    int kind;
    int has_direction;
    double direction[3];
    double length;
    double midpoint[3];
    int convexity;
    int face_a;
    int face_b;
} occt_edge_info;
```

with:

```cpp
/// face_a/face_b: 1-based face indices; equal for a seam; both 0 for a free edge.
/// For projecting edges into a sketch (S4): when has_ends, `start` and `end` are the curve's points at
/// its first and last parameter. For a circle, `center` and `radius` are its own, and the edge runs
/// counter-clockwise about `direction` from `start` through `sweep` radians (2π for a full circle).
typedef struct {
    int kind;
    int has_direction;
    double direction[3];
    double length;
    double midpoint[3];
    int convexity;
    int face_a;
    int face_b;
    int has_ends;
    double start[3];
    double end[3];
    double center[3];
    double radius;
    double sweep;
} occt_edge_info;
```

In `Sources/COCCT/cocct_inspect.cpp`, replace:

```cpp
#include <TopoDS_Face.hxx>

#include <mutex>
```

with:

```cpp
#include <TopoDS_Face.hxx>
#include <gp_Circ.hxx>

#include <mutex>
```

In `Sources/COCCT/cocct_inspect.cpp`, replace:

```cpp
        GProp_GProps properties;
        BRepGProp::LinearProperties(edge, properties);
        info.length = properties.Mass();
        set3(info.midpoint, curve.Value(0.5 * (curve.FirstParameter() + curve.LastParameter())));
```

with:

```cpp
        GProp_GProps properties;
        BRepGProp::LinearProperties(edge, properties);
        info.length = properties.Mass();
        const double first = curve.FirstParameter();
        const double last = curve.LastParameter();
        set3(info.midpoint, curve.Value(0.5 * (first + last)));
        if (!Precision::IsInfinite(first) && !Precision::IsInfinite(last)) {
            set3(info.start, curve.Value(first));
            set3(info.end, curve.Value(last));
            info.has_ends = 1;
        }
        if (info.kind == 1) {
            const gp_Circ circle = curve.Circle();
            set3(info.center, circle.Location());
            info.radius = circle.Radius();
            info.sweep = last - first;
        }
```

`occt_read_topology` value-initialises its `std::vector<occt_edge_info>`, so a degenerate edge keeps `has_ends == 0`. `BRepAdaptor_Curve` applies the edge's location and ignores its orientation, so `start`/`end` are in parameter order. A circle's parameter increases counter-clockwise about `Circle().Axis().Direction()`, which is the `direction` the struct already reports.

- [ ] **Step 5: Read it in Swift and carry it into `EdgeInfo`**


In `Sources/CreatorOCCT/OCCTRawTopology.swift`, replace:

```swift
        /// none for a free edge.
        var faces: [Int]
    }
```

with:

```swift
        /// none for a free edge.
        var faces: [Int]
        /// The exact line or circle, when the shim reported its ends.
        var curve: EdgeCurve?
    }
```

In `Sources/CreatorOCCT/OCCTRawTopology.swift`, replace:

```swift
                 faces: info.face_a > 0 && info.face_b > 0 ? [Int(info.face_a) - 1, Int(info.face_b) - 1] : [])
        }
```

with:

```swift
                 faces: info.face_a > 0 && info.face_b > 0 ? [Int(info.face_a) - 1, Int(info.face_b) - 1] : [],
                 curve: curve(info))
        }
```

In `Sources/CreatorOCCT/OCCTRawTopology.swift`, replace:

```swift
    static func vector(_ value: (Double, Double, Double)) -> Vector3 {
```

with:

```swift
    /// The edge's line or circle from the shim's ends, centre, radius and sweep.
    static func curve(_ info: occt_edge_info) -> EdgeCurve? {
        guard info.has_ends != 0 else { return nil }
        switch info.kind {
        case 0:
            return .line(start: vector(info.start), end: vector(info.end))
        case 1 where info.has_direction != 0:
            return .circle(center: vector(info.center), axis: vector(info.direction), radius: info.radius,
                           start: vector(info.start), sweep: info.sweep)
        default:
            return nil
        }
    }

    static func vector(_ value: (Double, Double, Double)) -> Vector3 {
```

In `Sources/CreatorOCCT/OCCTTagger.swift`, replace:

```swift
                     midpoint: edge.midpoint, convexity: edge.convexity, faces: edge.faces.map(FaceID.init))
```

with:

```swift
                     midpoint: edge.midpoint, convexity: edge.convexity, faces: edge.faces.map(FaceID.init),
                     curve: edge.curve)
```

`Edge.curve` is an optional `var` with no initializer, so the memberwise initializer `TaggerTests` uses still compiles (it defaults to `nil`).

- [ ] **Step 6: Give FakeKernel's edges their curves**

FakeKernel's prism numbers edges as before: per loop, two cap edges per segment (start cap, then end cap), then the wall edges. Each now carries its curve at the extrusion's heights.


In `Sources/CreatorKernel/FakeKernel.swift`, replace:

```swift
        return Solid(topology: Self.prism(profile, distance: distance, tag: tag), bounds: bounds, storage: FakeStorage())
```

with:

```swift
        return Solid(topology: Self.prism(profile, distance: distance, heights: (back, front), tag: tag), bounds: bounds,
                     storage: FakeStorage())
```

In `Sources/CreatorKernel/FakeKernel.swift`, replace:

```swift
    /// concave. The outer loop's faces and edges are numbered exactly as for a profile without holes.
    private static func prism(_ profile: Profile2D, distance: Double, tag: NodeTag) -> Topology {
```

with:

```swift
    /// concave. The outer loop's faces and edges are numbered exactly as for a profile without holes.
    /// Every edge carries its exact curve, the caps' at `heights` along the normal (S4 projection).
    private static func prism(_ profile: Profile2D, distance: Double, heights: (Double, Double), tag: NodeTag) -> Topology {
```

In `Sources/CreatorKernel/FakeKernel.swift`, replace:

```swift
        func addEdge(_ kind: CurveKind, _ direction: Vector3?, _ length: Double, _ convexity: Convexity, _ a: Int, _ b: Int) {
            edges.append(EdgeInfo(id: EdgeID(edges.count), kind: kind, direction: direction, length: length,
                                  midpoint: .zero, convexity: convexity, faces: [FaceID(a), FaceID(b)]))
        }
```

with:

```swift
        func addEdge(_ kind: CurveKind, _ direction: Vector3?, _ length: Double, _ convexity: Convexity, _ a: Int, _ b: Int,
                     curve: EdgeCurve? = nil) {
            edges.append(EdgeInfo(id: EdgeID(edges.count), kind: kind, direction: direction, length: length,
                                  midpoint: .zero, convexity: convexity, faces: [FaceID(a), FaceID(b)], curve: curve))
        }
```

In `Sources/CreatorKernel/FakeKernel.swift`, replace:

```swift
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 0, side)
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 1, side)
            }
            if segments.count == 1 {
                addEdge(.line, normal, distance, .smooth, first, first)
            } else {
                for k in segments.indices {
                    addEdge(.line, normal, distance, loop == 0 ? .convex : .concave, first + k, first + (k + 1) % segments.count)
                }
            }
```

with:

```swift
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 0, side,
                        curve: curve(of: segment, on: profile.plane, at: heights.0))
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 1, side,
                        curve: curve(of: segment, on: profile.plane, at: heights.1))
            }
            // A wall edge rises from the corner where segment k ends (a circle's seam from its start).
            func rising(from corner: Vector2) -> EdgeCurve {
                .line(start: profile.plane.point(corner) + normal * heights.0, end: profile.plane.point(corner) + normal * heights.1)
            }
            if segments.count == 1 {
                addEdge(.line, normal, distance, .smooth, first, first, curve: rising(from: segments[0].startPoint))
            } else {
                for k in segments.indices {
                    addEdge(.line, normal, distance, loop == 0 ? .convex : .concave, first + k, first + (k + 1) % segments.count,
                            curve: rising(from: segments[k].endPoint))
                }
            }
```

In `Sources/CreatorKernel/FakeKernel.swift`, replace:

```swift
    /// `other`'s faces and edges, renumbered after `base`'s, appended to `base`.
```

with:

```swift
    /// A profile segment's exact curve, lifted `height` along the plane normal. A clockwise arc
    /// (`end < start`) is the same circle run counter-clockwise from its end.
    private static func curve(of segment: Segment2D, on plane: Plane, at height: Double) -> EdgeCurve {
        let lift = plane.normal * height
        switch segment {
        case .line(let a, let b):
            return .line(start: plane.point(a) + lift, end: plane.point(b) + lift)
        case .arc(let center, let radius, let start, let end):
            let from = min(start, end).radians
            let first = center + Vector2(cos(from), sin(from)) * radius
            return .circle(center: plane.point(center) + lift, axis: plane.normal, radius: radius,
                           start: plane.point(first) + lift, sweep: abs(end.radians - start.radians))
        }
    }

    /// `other`'s faces and edges, renumbered after `base`'s, appended to `base`.
```

- [ ] **Step 7: Run the tests**

Run: `swift test --filter "EdgeCurveTests|FakeKernelCurveTests|TaggerTests|RawTopologyTests|FakeKernel"`
Expected: PASS.

- [ ] **Step 8: Run the gate**

Expected: no new warnings, **922 tests** (master + 21), SwiftLint clean.

- [ ] **Step 9: Commit**

```bash
git add Sources/CreatorKernel Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests/EdgeCurveTests.swift \
  Tests/CreatorKernelTests/FakeKernelCurveTests.swift
git commit -m "feat(kernel): edges carry their exact line or circle for sketch projection (S4)"
```

---

### Task 4: The S4 settings — `.sketch`, `.facePick`, setting names, format 4

**Files:**
- Modify: `Package.swift` (four dependency lists)
- Create: `Sources/CreatorKernel/FacePick.swift`, `FacePick+Codable.swift`, `Topology+FacePicks.swift`, `TopoRole+Stability.swift`
- Modify: `Sources/CreatorKernel/EdgePick.swift` (`touchesUnnamedFace`)
- Create: `Sources/CreatorSketch/Model/Sketch+Finite.swift`, `Sources/CreatorSketch/Model/SketchEntityKind+Finite.swift`
- Modify: `Sources/CreatorGraph/ConstantValue.swift`, `Scalar.swift`, `NodeSetting.swift`, `GraphFile.swift`
- Modify: `Sources/CreatorNodes/Values/GraphParameterNode.swift` (exhaustive switch)
- Modify: `Tests/CreatorGraphTests/EdgePickFileTests.swift` (the version test)
- Test: `Tests/CreatorKernelTests/FacePickTests.swift`, `Tests/CreatorSketchTests/SketchFiniteTests.swift`, `Tests/CreatorGraphTests/SketchSettingFileTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `public struct FacePick: Hashable, Sendable, Codable { public var tags: Set<TopoTag>; public init(tags:); public var touchesUnnamedFace: Bool }`. It encodes its tags sorted by `sortKey`.
  - `Topology.faces(matching: FacePick) -> [FaceInfo]` (pick tags ⊆ face tags, in ID order; an empty pick matches nothing) and `Topology.facePick(for: FaceID) -> FacePick?`.
  - `TopoRole.isUnstable: Bool` (`.unnamed`, or a blend of such).
  - `Sketch.isFinite: Bool` (public).
  - `ConstantValue.sketch(Sketch)`, `ConstantValue.facePick(FacePick)`. Both are settings: `Scalar(_:)` returns `nil` for them, and `isFinite` checks the sketch.
  - `NodeSetting.sketch = "sketch"`, `NodeSetting.face = "face"`, `NodeSetting.projectionPrefix = "projection."`, and `NodeSetting.projection(_ reference: String) -> SocketName`. `NodeSetting.all` gains `sketch` and `face`.
  - `GraphFile.currentFormatVersion == 4`.

- [ ] **Step 1: Give the graph and the node targets `CreatorSketch`**


In `Package.swift`, replace:

```swift
        .target(name: "CreatorGraph", dependencies: ["CreatorKernel", "CreatorGeometry"]),
        .target(name: "CreatorNodes", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry"]),
```

with:

```swift
        // CreatorSketch: `ConstantValue.sketch` (S4). The Sketch node in CreatorNodes solves it.
        .target(name: "CreatorGraph", dependencies: ["CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
        .target(name: "CreatorNodes", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
```

In `Package.swift`, replace:

```swift
        .testTarget(name: "CreatorGraphTests", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorNodesTests",
                    dependencies: ["CreatorNodes", "CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorOCCT"]),
```

with:

```swift
        .testTarget(name: "CreatorGraphTests", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorSketch"]),
        .testTarget(name: "CreatorNodesTests",
                    dependencies: ["CreatorNodes", "CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorSketch", "CreatorOCCT"]),
```

`CreatorSketch` depends only on `CreatorGeometry`, so this adds no cycle. The targets that import `CreatorGraph` (Editor, App, their tests, GraphPanelPreview) see `CreatorSketch` transitively and need no edit.

- [ ] **Step 2: Write the failing tests**


Create `Tests/CreatorKernelTests/FacePickTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// S4: the face pick a Plane from Face node remembers (sketcher spec §7).
struct FacePickTests {
    let node = NodeID()
    let other = NodeID()

    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var bottom: TopoTag { TopoTag(node: node, item: 0, role: .startCap) }
    var flangeTop: TopoTag { TopoTag(node: other, item: 0, role: .endCap) }

    /// Face 0: bottom. Face 1: top, merged with a coplanar flange top by a union. Face 2: the flange top again
    /// (a cut split it off).
    func sample() -> Topology {
        Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -.unitZ, area: 1, centroid: .zero, tags: [bottom]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top, flangeTop]),
            FaceInfo(id: FaceID(2), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [flangeTop]),
        ], edges: [])
    }

    @Test func aPickMatchesEveryFaceWhoseTagsIncludeItsOwn() {
        #expect(sample().faces(matching: FacePick(tags: [top])).map(\.id) == [FaceID(1)])
        #expect(sample().faces(matching: FacePick(tags: [flangeTop])).map(\.id) == [FaceID(1), FaceID(2)])
        #expect(sample().faces(matching: FacePick(tags: [top, bottom])).isEmpty)
    }

    @Test func anEmptyPickMatchesNothing() {
        #expect(sample().faces(matching: FacePick(tags: [])).isEmpty)
    }

    @Test func aFacesPickIsItsWholeTagSet() {
        #expect(sample().facePick(for: FaceID(1)) == FacePick(tags: [top, flangeTop]))
        #expect(sample().facePick(for: FaceID(9)) == nil)
    }

    @Test func picksRoundTripAndEncodeDeterministically() throws {
        let pick = FacePick(tags: [top, flangeTop, bottom])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pick)
        #expect(try JSONDecoder().decode(FacePick.self, from: data) == pick)
        let reordered = FacePick(tags: Set([bottom, flangeTop, top].reversed()))
        #expect(try encoder.encode(reordered) == data)
    }

    @Test func aPickOnAnUnnamedOrBlendOfUnnamedFaceIsUnstable() {
        let unnamed = TopoTag(node: node, item: 0, role: .unnamed(face: 4))
        let blend = TopoTag(node: other, item: 0, role: .blend(sourceEdge: EdgeKey([top], [unnamed])))
        #expect(!FacePick(tags: [top]).touchesUnnamedFace)
        #expect(FacePick(tags: [unnamed]).touchesUnnamedFace)
        #expect(FacePick(tags: [blend]).touchesUnnamedFace)
    }
}
```

Create `Tests/CreatorSketchTests/SketchFiniteTests.swift`:

```swift
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// S4: the graph stores a sketch as a setting in JSON, which can't hold NaN or ±∞.
struct SketchFiniteTests {
    @Test func aDrawnSketchIsFinite() {
        #expect(ConstrainedRectangle().sketch.isFinite)
    }

    @Test func aNonFinitePointRadiusOrPlaneIsNot() {
        var point = Sketch()
        point.addPoint(Vector2(.nan, 0))
        #expect(!point.isFinite)
        var circle = Sketch()
        circle.addCircle(center: .zero, radius: .infinity)
        #expect(!circle.isFinite)
        let plane = Sketch(plane: .fixed(Plane(origin: Vector3(0, .nan, 0), normal: .unitZ, xAxis: .unitX)))
        #expect(!plane.isFinite)
    }

    @Test func aNonFiniteDimensionFixOrWarmStartIsNot() {
        var dimension = ConstrainedRectangle().sketch
        dimension.dimensions[ConstrainedRectangle().width]?.value = .nan
        #expect(!dimension.isFinite)
        var fix = Sketch()
        let point = fix.addPoint(.zero)
        fix.add(.fix(point, at: Vector2(0, .infinity)))
        #expect(!fix.isFinite)
        var warm = Sketch()
        let moved = warm.addPoint(.zero)
        warm.solved[moved] = .point(Vector2(.nan, .nan))
        #expect(!warm.isFinite)
    }

    @Test func aNonFiniteProjectedCurveIsNot() {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .circle(center: .zero, radius: .nan)))))
        #expect(!sketch.isFinite)
    }
}
```

Create `Tests/CreatorGraphTests/SketchSettingFileTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// S4: `ConstantValue.sketch` and `.facePick` are settings saved in `.mcgraph` files (format 4).
struct SketchSettingFileTests {
    func sampleSketch() -> Sketch {
        var sketch = Sketch(plane: .fixed(.xz))
        let a = sketch.addPoint(Vector2(0, 0)), b = sketch.addPoint(Vector2(30, 0)), c = sketch.addPoint(Vector2(0, 20))
        let bottom = sketch.addLine(from: a, to: b)
        sketch.addLine(from: b, to: c)
        sketch.addLine(from: c, to: a)
        sketch.add(.horizontal(bottom))
        sketch.addDimension(.length(bottom), value: 30)
        sketch.addCircle(center: Vector2(8, 5), radius: 2)
        return sketch
    }

    @Test func aSketchSettingRoundTripsThroughAFile() throws {
        let node = makeNode(ConstantNode.self, [NodeSetting.sketch: .sketch(sampleSketch())])
        let file = GraphFile(graph: graph([node]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] == .sketch(sampleSketch()))
    }

    @Test func aSavedSketchIsByteIdenticalWhenSavedAgain() throws {
        let node = makeNode(ConstantNode.self, [NodeSetting.sketch: .sketch(sampleSketch())])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([node])))
        let reloaded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(try GraphFileIO.encode(reloaded) == data)
    }

    @Test func aFacePickSettingRoundTripsThroughAFile() throws {
        let plate = NodeID()
        let pick = FacePick(tags: [TopoTag(node: plate, item: 0, role: .endCap), TopoTag(node: plate, item: 1, role: .endCap)])
        let node = makeNode(ConstantNode.self, [NodeSetting.face: .facePick(pick)])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([node])))
        #expect(try #require(String(bytes: data, encoding: .utf8)).contains(#""type" : "facePick""#))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.face] == .facePick(pick))
    }

    @Test func sketchesAndFacePicksAreSettingsWithNoRuntimeValue() {
        #expect(Scalar(.sketch(sampleSketch())) == nil)
        #expect(Scalar(.facePick(FacePick(tags: []))) == nil)
    }

    @Test func aNonFiniteSketchIsRefused() {
        var broken = sampleSketch()
        broken.addPoint(Vector2(.nan, 0))
        let node = makeNode(ConstantNode.self)
        var target = graph([node])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try target.apply(.setInput(node.id, NodeSetting.sketch, .sketch(broken)), registry: testRegistry)
        }
    }

    @Test func projectionSettingsAreNamedAfterTheirReference() {
        #expect(NodeSetting.projection("p1") == "projection.p1")
        #expect(NodeSetting.all.isSuperset(of: [NodeSetting.sketch, NodeSetting.face]))
    }

    @Test func versionThreeFilesStillLoad() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 3, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "inputValues": {"value": {"type": "number", "value": 3}},
        "position": {"x": 0, "y": 0}, "isOutput": false}]}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(3))
    }
}
```

Then update the version test in `Tests/CreatorGraphTests/EdgePickFileTests.swift`:

In `Tests/CreatorGraphTests/EdgePickFileTests.swift`, replace:

```swift
    @Test func savedFilesCarryFormatVersionThree() throws {
        #expect(GraphFile.currentFormatVersion == 3)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 3"#))
    }
```

with:

```swift
    /// 4 since S4 (`sketch` and `facePick` settings). Whichever of S4 and another format-bumping branch
    /// merges second takes the next number and updates both literals here.
    @Test func savedFilesCarryTheCurrentFormatVersion() throws {
        #expect(GraphFile.currentFormatVersion == 4)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 4"#))
    }
```

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --filter "FacePickTests|SketchFiniteTests|SketchSettingFileTests|EdgePickFileTests"`
Expected: build errors: `FacePick` is not in scope, `Sketch` has no member `isFinite`, `ConstantValue` has no member `sketch`, and `NodeSetting` has no member `sketch`.

- [ ] **Step 4: Face picks in the kernel**


Create `Sources/CreatorKernel/FacePick.swift`:

```swift
/// A remembered face pick (sketcher spec §7, Plane from Face): the picked face's tags. It names every
/// face whose tags include all of them, so a face a union merged with a coplanar one still matches.
public struct FacePick: Hashable, Sendable {
    public var tags: Set<TopoTag>

    public init(tags: Set<TopoTag>) {
        self.tags = tags
    }

    /// True when a tag is the `.unnamed` fallback (directly or inside a blend's source edge), which is
    /// unstable across rebuilds, like `EdgePick.touchesUnnamedFace`.
    public var touchesUnnamedFace: Bool { tags.contains { $0.role.isUnstable } }
}
```

Create `Sources/CreatorKernel/FacePick+Codable.swift`:

```swift
extension FacePick: Codable {
    private enum CodingKeys: String, CodingKey { case tags }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tags: Set(try container.decode([TopoTag].self, forKey: .tags)))
    }

    /// Tags are written sorted by `sortKey`, so encoding is deterministic (`EdgeKey` does the same).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tags.sorted { $0.sortKey < $1.sortKey }, forKey: .tags)
    }
}
```

Create `Sources/CreatorKernel/Topology+FacePicks.swift`:

```swift
extension Topology {
    /// Every face whose tags include all of `pick`'s, in ID order. An empty pick matches nothing.
    public func faces(matching pick: FacePick) -> [FaceInfo] {
        guard !pick.tags.isEmpty else { return [] }
        return faces.filter { pick.tags.isSubset(of: $0.tags) }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The pick that names face `id`: its whole tag set. `nil` for a face that isn't in the table.
    public func facePick(for id: FaceID) -> FacePick? {
        face(id).map { FacePick(tags: $0.tags) }
    }
}
```

Create `Sources/CreatorKernel/TopoRole+Stability.swift`:

```swift
extension TopoRole {
    /// True for the `.unnamed` fallback, and for a blend whose source edge borders such a face: names
    /// that may move to a different face when the model is rebuilt.
    public var isUnstable: Bool {
        switch self {
        case .unnamed: true
        case .blend(let source): source.first.union(source.second).contains { $0.role.isUnstable }
        case .startCap, .endCap, .side: false
        }
    }
}
```

`EdgePick` uses the same check, so the two pick kinds agree on what is unstable:

In `Sources/CreatorKernel/EdgePick.swift`, replace:

```swift
    public var touchesUnnamedFace: Bool { Self.mentionsUnnamedFace(key) }

    private static func mentionsUnnamedFace(_ key: EdgeKey) -> Bool {
        key.first.union(key.second).contains { tag in
            switch tag.role {
            case .unnamed: true
            case .blend(let source): mentionsUnnamedFace(source)
            case .startCap, .endCap, .side: false
            }
        }
    }
```

with:

```swift
    public var touchesUnnamedFace: Bool { key.first.union(key.second).contains { $0.role.isUnstable } }
```

- [ ] **Step 5: A sketch knows whether all its numbers are finite**


Create `Sources/CreatorSketch/Model/Sketch+Finite.swift`:

```swift
import CreatorGeometry

extension Sketch {
    /// False when any stored number is NaN or ±∞: the plane, a drawn point, radius or projected
    /// curve, a fix target, a dimension value or a warm start. JSON can't store those, so the graph
    /// refuses such a sketch as a setting (S4).
    public var isFinite: Bool {
        if case .fixed(let plane) = plane, !(plane.origin.isFinite && plane.normal.isFinite && plane.xAxis.isFinite) {
            return false
        }
        return entities.values.allSatisfy { $0.kind.isFinite }
            && constraints.values.allSatisfy { constraint in
                if case .fix(_, let at) = constraint { return at.isFinite }
                return true
            }
            && dimensions.values.allSatisfy(\.value.isFinite)
            && solved.values.allSatisfy { state in
                switch state {
                case .point(let point): point.isFinite
                case .radius(let radius): radius.isFinite
                }
            }
    }
}
```

Create `Sources/CreatorSketch/Model/SketchEntityKind+Finite.swift`:

```swift
extension SketchEntityKind {
    /// False when the drawn position, radius or projected curve holds NaN or ±∞.
    var isFinite: Bool {
        switch self {
        case .point(let position): position.isFinite
        case .line, .arc: true
        case .circle(_, let radius): radius.isFinite
        case .projected(let source):
            switch source.curve {
            case .line(let a, let b): a.isFinite && b.isFinite
            case .arc(let center, let radius, let start, let end):
                center.isFinite && radius.isFinite && start.radians.isFinite && end.radians.isFinite
            case .circle(let center, let radius): center.isFinite && radius.isFinite
            }
        }
    }
}
```

- [ ] **Step 6: The two settings, their names and format 4**


In `Sources/CreatorGraph/ConstantValue.swift`, replace:

```swift
import CreatorGeometry
import CreatorKernel
```

with:

```swift
import CreatorGeometry
import CreatorKernel
import CreatorSketch
```

In `Sources/CreatorGraph/ConstantValue.swift`, replace:

```swift
    case edgePicks([EdgePick])
```

with:

```swift
    case edgePicks([EdgePick])
    /// A Sketch node's sketch (sketcher spec §3, §7). A setting, never a socket value.
    case sketch(Sketch)
    /// The face a Plane from Face node is on (sketcher spec §7). A setting, never a socket value.
    case facePick(FacePick)
```

In `Sources/CreatorGraph/ConstantValue.swift`, replace:

```swift
        case .integer, .bool, .text, .edgePicks: true
```

with:

```swift
        case .sketch(let sketch): sketch.isFinite
        case .integer, .bool, .text, .edgePicks, .facePick: true
```

In `Sources/CreatorGraph/ConstantValue.swift`, replace:

```swift
    private enum Kind: String, Codable { case number, integer, bool, vector, plane, text, edgePicks }
```

with:

```swift
    private enum Kind: String, Codable { case number, integer, bool, vector, plane, text, edgePicks, sketch, facePick }
```

In `Sources/CreatorGraph/ConstantValue.swift`, replace:

```swift
        case .edgePicks: self = .edgePicks(try container.decode([EdgePick].self, forKey: .value))
        }
```

with:

```swift
        case .edgePicks: self = .edgePicks(try container.decode([EdgePick].self, forKey: .value))
        case .sketch: self = .sketch(try container.decode(Sketch.self, forKey: .value))
        case .facePick: self = .facePick(try container.decode(FacePick.self, forKey: .value))
        }
```

In `Sources/CreatorGraph/ConstantValue.swift`, replace:

```swift
        case .edgePicks(let value): try container.encode(Kind.edgePicks, forKey: .type); try container.encode(value, forKey: .value)
        }
```

with:

```swift
        case .edgePicks(let value): try container.encode(Kind.edgePicks, forKey: .type); try container.encode(value, forKey: .value)
        case .sketch(let value): try container.encode(Kind.sketch, forKey: .type); try container.encode(value, forKey: .value)
        case .facePick(let value): try container.encode(Kind.facePick, forKey: .type); try container.encode(value, forKey: .value)
        }
```

In `Sources/CreatorGraph/Scalar.swift`, replace:

```swift
    /// The runtime form of a stored constant. `text` and `edgePicks` settings have none.
```

with:

```swift
    /// The runtime form of a stored constant. `text`, `edgePicks`, `sketch` and `facePick` settings have none.
```

In `Sources/CreatorGraph/Scalar.swift`, replace:

```swift
        case .text, .edgePicks: return nil
```

with:

```swift
        case .text, .edgePicks, .sketch, .facePick: return nil
```

In `Sources/CreatorNodes/Values/GraphParameterNode.swift`, replace:

```swift
        case .plane, .text, .edgePicks:
```

with:

```swift
        case .plane, .text, .edgePicks, .sketch, .facePick:
```

In `Sources/CreatorGraph/NodeSetting.swift`, replace:

```swift
    public static let showHandle: SocketName = "showHandle"

    public static let all: Set<SocketName> = [parameter, picks, showHandle]
```

with:

```swift
    public static let showHandle: SocketName = "showHandle"
    /// Sketch: the sketch, as `.sketch(_:)`. New nodes are seeded with an empty sketch on XY.
    public static let sketch: SocketName = "sketch"
    /// Plane from Face: the picked face, as `.facePick(topology.facePick(for:))`.
    public static let face: SocketName = "face"

    public static let all: Set<SocketName> = [parameter, picks, showHandle, sketch, face]

    /// The start of every projection setting's name, which no exposed dimension may use.
    public static let projectionPrefix = "projection."

    /// Sketch: the edge pick of one projected edge, as `.edgePicks([pick])`, stored under the
    /// projection's `ProjectionSource.reference` (sketcher spec §7, S1–S2 handoff).
    public static func projection(_ reference: String) -> SocketName {
        SocketName(projectionPrefix + reference)
    }
```

In `Sources/CreatorGraph/GraphFile.swift`, replace:

```swift
    /// 2: adds the `edgePicks` constant kind (M3). 3: side-face tags may carry a `loop` (S3, hole
    /// walls), which a version-2 reader would silently drop. Version-1 and -2 files still load unchanged.
    public static let currentFormatVersion = 3
```

with:

```swift
    /// 2: adds the `edgePicks` constant kind (M3). 3: side-face tags may carry a `loop` (S3, hole
    /// walls), which a version-2 reader would silently drop. 4: adds the `sketch` and `facePick` setting
    /// kinds (S4), which a version-3 reader can't decode. Version-1 to -3 files still load unchanged.
    public static let currentFormatVersion = 4
```

`Sketch` already encodes deterministically (its ID-keyed dictionaries are JSON objects, and `GraphFileIO` writes `.sortedKeys`), which `aSavedSketchIsByteIdenticalWhenSavedAgain` pins. `ValueText.format` (CreatorEditor) uses `if case` and shows "—" for the new kinds, so the editor needs no change.

- [ ] **Step 7: Run the tests**

Run: `swift test --filter "FacePickTests|SketchFiniteTests|SketchSettingFileTests|EdgePickFileTests|EdgePickTests|FileTests"`
Expected: PASS.

- [ ] **Step 8: Run the gate**

Expected: no new warnings, **938 tests** (master + 37), SwiftLint clean.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/CreatorKernel Sources/CreatorSketch/Model Sources/CreatorGraph Sources/CreatorNodes/Values/GraphParameterNode.swift \
  Tests/CreatorKernelTests/FacePickTests.swift Tests/CreatorSketchTests/SketchFiniteTests.swift Tests/CreatorGraphTests
git commit -m "feat(graph): sketch and face-pick settings, file format 4 (S4)"
```

---

### Task 5: The Plane from Face node

**Files:**
- Create: `Sources/CreatorNodes/Support/FacePlane.swift`, `Sources/CreatorNodes/Values/PlaneFromFaceNode.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift` (doc and list), `Tests/CreatorNodesTests/OutputNodeTests.swift` (the count test)
- Test: `Tests/CreatorNodesTests/PlaneFromFaceNodeTests.swift`

**Interfaces:**
- Consumes: Task 4's `FacePick`, `Topology.faces(matching:)`, `Topology.facePick(for:)`, `FacePick.touchesUnnamedFace`, `NodeSetting.face`, `ConstantValue.facePick`.
- Produces:
  - `PlaneFromFaceNode` (`creator.planeFromFace`, "Plane from Face", `.value`). Input `solid` (solid); output `plane` (plane); setting `NodeSetting.face`. Its message constants (`nothingPicked`, `unreadablePick`, `noMatch`, `notFlat`, `unnamedPick`) are internal statics the tests compare with.
  - `FacePlane.plane(origin: Vector3, normal: Vector3) -> Plane` (internal), and `FacePlane.parallelLimit = 1e-3`.
  - `BuiltInNodes.all` has 27 entries (9 value nodes).

- [ ] **Step 1: Write the failing tests**


Create `Tests/CreatorNodesTests/PlaneFromFaceNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Sketcher spec §7, Plane from Face.
struct PlaneFromFaceNodeTests {
    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

    /// A 20 × 10 × `height` box wired into a Plane from Face picking the box's face with `role`.
    func plane(on role: TopoRole, height: Double = 6, kernel: any Kernel) async throws -> (Harness, Node, Node) {
        var h = Harness()
        let box = h.box(20, 10, height)
        let plane = h.add(PlaneFromFaceNode.self)
        h.wire(box, "solid", to: plane, "solid")
        let solid = try onlySolid(try await h.run([box], kernel: kernel), box)
        let face = try #require(solid.topology.faces.first { $0.tags.contains(TopoTag(node: box.id, item: 0, role: role)) })
        h.set(plane, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: face.id))))
        return (h, box, plane)
    }

    @Test func aTopFacePlaneSitsOnItsCentroidFacingOut() async throws {
        let kernel = OCCTKernel()
        let (h, _, plane) = try await plane(on: .endCap, kernel: kernel)
        let report = try await h.run([plane], kernel: kernel)
        let result = try #require(report.value(plane, "plane")?.planes?.first)
        #expect(report.isOK(plane))
        #expect(near(result.origin, Vector3(0, 0, 6)))
        #expect(near(result.normal, .unitZ))
        #expect(near(result.xAxis, .unitX))
    }

    @Test func aFaceFacingWorldXTakesWorldYAsItsXAxis() async throws {
        let kernel = OCCTKernel()
        // Segment 1 of the centred rectangle is its right side, facing +X.
        let (h, _, plane) = try await plane(on: .side(segment: 1), kernel: kernel)
        let result = try #require(try await h.run([plane], kernel: kernel).value(plane, "plane")?.planes?.first)
        #expect(near(result.origin, Vector3(10, 0, 3)))
        #expect(near(result.normal, .unitX))
        #expect(near(result.xAxis, .unitY))
        #expect(near(result.yAxis, .unitZ))
    }

    @Test func thePlaneFollowsTheFaceWhenTheModelChanges() async throws {
        let kernel = OCCTKernel()
        let (start, box, plane) = try await plane(on: .endCap, kernel: kernel)
        var h = start
        h.set(box, "distance", .number(15))
        let report = try await h.run([plane], kernel: kernel)
        #expect(report.isOK(plane))
        #expect(near(try #require(report.value(plane, "plane")?.planes?.first).origin, Vector3(0, 0, 15)))
    }

    @Test func aCurvedFaceIsAPlainError() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(10)])
        let rod = h.add(ExtrudeNode.self, ["distance": .number(5)])
        h.wire(circle, "profile", to: rod, "profile")
        let wall = FacePick(tags: [TopoTag(node: rod.id, item: 0, role: .side(segment: 0))])
        let plane = h.add(PlaneFromFaceNode.self, [NodeSetting.face: .facePick(wall)])
        h.wire(rod, "solid", to: plane, "solid")
        #expect(try await h.run([plane], kernel: kernel).error(plane) == PlaneFromFaceNode.notFlat)
    }

    @Test func aMissingUnreadableOrStalePickIsAPlainError() async throws {
        var h = Harness()
        let box = h.box(20, 10, 6)
        let plane = h.add(PlaneFromFaceNode.self)
        h.wire(box, "solid", to: plane, "solid")
        #expect(try await h.run([plane]).error(plane) == PlaneFromFaceNode.nothingPicked)
        h.set(plane, NodeSetting.face, .text("top"))
        #expect(try await h.run([plane]).error(plane) == PlaneFromFaceNode.unreadablePick)
        h.set(plane, NodeSetting.face, .facePick(FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .endCap)])))
        #expect(try await h.run([plane]).error(plane) == PlaneFromFaceNode.noMatch)
    }

    @Test func aPickMatchingSeveralFacesWarnsAndUsesTheFirst() async throws {
        // FakeKernel's union keeps both operands' faces, so a box unioned with itself has two top caps.
        var h = Harness()
        let box = h.box(20, 10, 6)
        let union = h.add(BooleanNode.self)
        h.wire(box, "solid", to: union, "target")
        h.wire(box, "solid", to: union, "tools")
        let top = FacePick(tags: [TopoTag(node: box.id, item: 0, role: .endCap)])
        let plane = h.add(PlaneFromFaceNode.self, [NodeSetting.face: .facePick(top)])
        h.wire(union, "solid", to: plane, "solid")
        let report = try await h.run([plane])
        #expect(report.warning(plane) == "The pick matches 2 faces; the plane is on the first.")
        #expect(report.value(plane, "plane")?.planes?.first?.normal == .unitZ)
    }

    @Test func xAxisIsWorldXProjectedOntoTheFace() {
        let tilted = FacePlane.plane(origin: .zero, normal: Vector3(1, 1, 0) * (1 / 2.0.squareRoot()))
        #expect(near(tilted.xAxis, Vector3(1, -1, 0) * (1 / 2.0.squareRoot())))
        let almostX = FacePlane.plane(origin: .zero, normal: Vector3(1, 1e-6, 0).normalized ?? .unitX)
        #expect(abs(almostX.xAxis.dot(.unitY)) > 0.999)
        #expect(abs(almostX.xAxis.dot(almostX.normal)) < 1e-12)
    }
}
```

In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
    @Test func theSliceHasTwentySixNodesInSixCategories() {
        #expect(BuiltInNodes.all.count == 26)
        let counts = Dictionary(grouping: BuiltInNodes.all, by: { $0.category }).mapValues(\.count)
        #expect(counts == [.value: 8, .profile: 5, .solid: 5, .selection: 5, .feature: 2, .output: 1])
```

with:

```swift
    /// The slice's 26 (spec §7.1) plus Plane from Face (S4).
    @Test func theBuiltInsAreTheSliceAndTheSketcherNodesInSixCategories() {
        #expect(BuiltInNodes.all.count == 27)
        let counts = Dictionary(grouping: BuiltInNodes.all, by: { $0.category }).mapValues(\.count)
        #expect(counts == [.value: 9, .profile: 5, .solid: 5, .selection: 5, .feature: 2, .output: 1])
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter "PlaneFromFaceNodeTests|OutputNodeTests"`
Expected: build errors: `PlaneFromFaceNode` and `FacePlane` are not in scope.

- [ ] **Step 3: Write the node and register it**


Create `Sources/CreatorNodes/Support/FacePlane.swift`:

```swift
import CreatorGeometry

/// The plane a Plane from Face node puts on a flat face (sketcher spec §7).
enum FacePlane {
    /// World X counts as "nearly parallel" to the normal when its in-plane part is shorter than this.
    static let parallelLimit = 1e-3

    /// A plane through `origin` facing `normal` (unit). Its x axis is world X projected onto the face, or
    /// world Y projected when X is nearly parallel to the normal, so it is deterministic.
    static func plane(origin: Vector3, normal: Vector3) -> Plane {
        func inPlane(_ axis: Vector3) -> Vector3 { axis - normal * axis.dot(normal) }
        let projectedX = inPlane(.unitX)
        let xAxis = projectedX.length >= parallelLimit ? projectedX : inPlane(.unitY)
        return Plane(origin: origin, normal: normal, xAxis: xAxis.normalized ?? .unitX)
    }
}
```

Create `Sources/CreatorNodes/Values/PlaneFromFaceNode.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A plane on a flat face of a solid (sketcher spec §7): origin at the face centroid, normal along the
/// face's outward normal, x axis from `FacePlane`. The face is the remembered `FacePick` in the `face`
/// setting, so the plane follows the face when the model changes. "New sketch on face" (S5) wires this
/// node into a Sketch.
public enum PlaneFromFaceNode: NodeDefinition {
    public static let typeID = "creator.planeFromFace"
    public static let displayName = "Plane from Face"
    public static let category = NodeCategory.value
    public static let inputs = [SocketSpec("solid", .solid)]
    public static let outputs = [SocketSpec("plane", .plane)]

    static let nothingPicked = "Pick a face for this plane to sit on."
    static let unreadablePick = "This plane's picked face can't be read. Pick the face again."
    static let noMatch = "The picked face isn't on this solid any more. Pick it again."
    static let notFlat = "The picked face isn't flat, so it has no plane."
    static let unnamedPick = "The picked face has no stable name, so the plane may move to a different face "
        + "when the model changes. Pick it again after the change."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        let pick: FacePick
        switch context.node.inputValues[NodeSetting.face] {
        case nil: throw NodeError.invalidValue(nothingPicked)
        case .facePick(let stored)?: pick = stored
        case .some: throw NodeError.invalidValue(unreadablePick)
        }
        let matches = solid.topology.faces(matching: pick)
        guard let face = matches.first else { throw NodeError.invalidValue(noMatch) }
        guard face.kind == .plane, let normal = face.normal?.normalized else { throw NodeError.invalidValue(notFlat) }
        var warnings: [String] = []
        if matches.count > 1 {
            warnings.append("The pick matches \(matches.count.display) faces; the plane is on the first.")
        }
        if pick.touchesUnnamedFace { warnings.append(unnamedPick) }
        return NodeOutputs(["plane": .plane(FacePlane.plane(origin: face.centroid, normal: normal))], warnings: warnings)
    }
}
```

In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
/// The 26 node types of the vertical slice (spec §7.1), in palette order.
public enum BuiltInNodes {
    public static let all: [any NodeDefinition.Type] = [
        NumberNode.self, IntegerNode.self, VectorNode.self, PlaneNode.self, GraphParameterNode.self,
```

with:

```swift
/// The built-in node types in palette order: the vertical slice's 26 (spec §7.1) plus the sketcher's
/// Plane from Face and Sketch (sketcher spec §7, S4).
public enum BuiltInNodes {
    public static let all: [any NodeDefinition.Type] = [
        NumberNode.self, IntegerNode.self, VectorNode.self, PlaneNode.self, PlaneFromFaceNode.self, GraphParameterNode.self,
```

The node declares no inspector: the editor's fallback shows no rows for a solid input, and "Pick face in view…" waits for the app to write `.facePick` (Decisions). `BuiltInNodesInspectorTests` (CreatorEditorTests) picks the new node up automatically and checks that it draws.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter "PlaneFromFaceNodeTests|OutputNodeTests|CatalogTests|BuiltInNodesInspectorTests"`
Expected: PASS.

- [ ] **Step 5: Run the gate**

Expected: no new warnings, **945 tests** (master + 44), SwiftLint clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorNodes Tests/CreatorNodesTests
git commit -m "feat(nodes): Plane from Face puts a plane on a picked flat face (S4)"
```

---

### Task 6: The Sketch node — solve, regions, exposed dimensions, measurements, states

**Files:**
- Create: `Sources/CreatorNodes/Sketch/SketchSockets.swift`, `Sources/CreatorNodes/Sketch/SketchSolve.swift`, `Sources/CreatorNodes/Profiles/SketchNode.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift` (list), `Tests/CreatorNodesTests/OutputNodeTests.swift` (the count test)
- Test: `Tests/CreatorNodesTests/Support/SketchNodeFixtures.swift`, `Tests/CreatorNodesTests/SketchNodeTests.swift`, `Tests/CreatorNodesTests/SketchIntegrationTests.swift`

**Interfaces:**
- Consumes: Task 2's `inputs(for:)`, Task 4's `NodeSetting.sketch`/`.sketch(_:)`/`NodeSetting.all`/`projectionPrefix`, Task 5's `PlaneFromFaceNode` (in the face integration test), Task 1's clockwise arcs (notched region). From S1–S2: `SketchSolver.solve(_:)`, `SketchSolution.status`/`conflictMessages`/`degreesOfFreedom`/`measurements`, `Sketch.remember(_:)`, `SketchRegions.find(in:)`, `SketchRegion.profile(on:)`, `SketchRegionResult.warning`.
- Produces:
  - `SketchNode` (`creator.sketch`, "Sketch", `.profile`). Inputs `plane` (plane, optional) and `references` (solid, list access, optional), plus one number socket per exposed dimension from `inputs(for:)`. Outputs `profiles` (profile, always a list) and `measurements` (number, always a list). `defaultSettings == [NodeSetting.sketch: .sketch(Sketch())]`. Message statics: `missingSketch`, `unreadableSketch`, `wiredPlaneMissing`, `ignoredPlane`.
  - `SketchSockets.exposed(_ sketch: Sketch) -> [(id: DimensionID, spec: SocketSpec)]`, `SketchSockets.refused(_:) -> [String]`, `SketchSockets.isReserved(_ name: String) -> Bool`.
  - `SketchSolve.run(_ sketch: Sketch, on plane: Plane) throws -> SketchSolve.Output` (`profiles: [Profile2D]`, `measurements: [Double]`, `warnings: [String]`), `SketchSolve.nothingDrawn`, and `SketchSolve.unmeasured(_ name:because:)` with the reasons `onSuspendedEdge` and `wrongGeometry`. When any reference dimension can't be measured, `measurements` is empty (never shifted) and each such dimension is named in a warning.
  - Task 7 inserts projection resolution into `SketchNode.evaluate`, just before the exposed-dimension loop.

- [ ] **Step 1: Write the fixtures and the failing tests**


Create `Tests/CreatorNodesTests/Support/SketchNodeFixtures.swift`:

```swift
// Test fixture file: sketches for the Sketch node tests (several helpers by design).
import CreatorGeometry
import CreatorSketch

/// A `width` × `height` rectangle with its bottom-left corner fixed at `origin`, fully constrained:
/// horizontal bottom and top, vertical sides, `width` (d1) on the bottom line and `height` (d2) on the
/// left line. Drawn slightly off so the solver has work to do. Lines: bottom, right, top, left.
struct RectangleSketch {
    var sketch: Sketch
    let lines: [SketchEntityID]
    let corners: [SketchEntityID]
    let width: DimensionID
    let height: DimensionID

    init(width: Double = 60, height: Double = 40, origin: Vector2 = .zero, plane: SketchPlaneSource = .fixed(.xy)) {
        var sketch = Sketch(plane: plane)
        let drawn = [Vector2(0.5, -0.3), Vector2(width + 0.4, 0.2), Vector2(width - 0.3, height + 0.5), Vector2(-0.2, height - 0.4)]
        let corners = drawn.map { sketch.addPoint($0 + origin) }
        let lines = corners.indices.map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
        sketch.add(.fix(corners[0], at: origin))
        sketch.add(.horizontal(lines[0]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[3]))
        self.width = sketch.addDimension(.length(lines[0]), value: width)
        self.height = sketch.addDimension(.length(lines[3]), value: height)
        self.sketch = sketch
        self.lines = lines
        self.corners = corners
    }

    /// Adds a fully constrained circle (fixed centre, radius dimension) and returns the radius dimension.
    @discardableResult
    mutating func addHole(center: Vector2, radius: Double) -> DimensionID {
        let circle = sketch.addCircle(center: center, radius: radius * 1.1)
        guard case .circle(let centre, _)? = sketch.entities[circle]?.kind else { preconditionFailure("not a circle") }
        sketch.add(.fix(centre, at: center))
        return sketch.addDimension(.radius(circle), value: radius)
    }

    mutating func expose(_ id: DimensionID) {
        sketch.dimensions[id]?.isExposed = true
    }
}

extension Profile2D {
    /// The outer loop's start points.
    var corners: [Vector2] { outer.map(\.startPoint) }
}
```

Create `Tests/CreatorNodesTests/SketchNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorSketch
import Testing

/// Sketcher spec §7, the Sketch node: solve, regions, exposed dimensions, measurements and states.
struct SketchNodeTests {
    func near(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length <= 1e-6 }

    func sketchNode(_ h: inout Harness, _ sketch: Sketch) -> Node {
        h.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
    }

    @Test func aNewSketchHoldsAnEmptySketchOnXYAndAsksForAShape() async throws {
        #expect(BuiltInNodes.registry.makeNode(SketchNode.typeID).inputValues[NodeSetting.sketch] == .sketch(Sketch()))
        var h = Harness()
        let node = h.add(SketchNode.self)
        let report = try await h.run([node])
        #expect(report.warning(node) == SketchSolve.nothingDrawn)
        #expect(report.value(node, "profiles")?.profiles?.isEmpty == true)
        #expect(report.value(node, "profiles")?.isList == true)
    }

    @Test func aFullyConstrainedRectangleIsOneProfileOnTheSketchPlane() async throws {
        var h = Harness()
        let node = sketchNode(&h, RectangleSketch(width: 60, height: 40, plane: .fixed(.xz)).sketch)
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let profiles = try #require(report.value(node, "profiles")?.profiles)
        try #require(profiles.count == 1)
        #expect(profiles[0].plane == .xz)
        #expect(profiles[0].isClosed)
        let expected = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)]
        #expect(zip(profiles[0].corners, expected).allSatisfy(near) && profiles[0].corners.count == 4)
    }

    @Test func regionsComeOutLargestFirstWithTheirHoles() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.addHole(center: Vector2(15, 20), radius: 5)
        rectangle.addHole(center: Vector2(100, 0), radius: 3)
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let profiles = try #require(report.value(node, "profiles")?.profiles)
        #expect(profiles.map(\.holes.count) == [1, 0])
        #expect(profiles.map(\.outer.count) == [4, 1])
    }

    @Test func anUnderConstrainedSketchWarnsAndStillOutputs() async throws {
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)].map { sketch.addPoint($0) }
        for k in 0..<4 { sketch.addLine(from: corners[k], to: corners[(k + 1) % 4]) }
        var h = Harness()
        let node = sketchNode(&h, sketch)
        let report = try await h.run([node])
        #expect(report.warning(node) == "The sketch has 8 degrees of freedom left, so it isn't fully constrained.")
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
    }

    @Test func anOverConstrainedSketchIsAnErrorNamingTheConflict() async throws {
        var rectangle = RectangleSketch()
        rectangle.sketch.add(.horizontal(rectangle.lines[1]))
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let error = try #require(try await h.run([node]).error(node))
        #expect(error == SketchSolver.solve(rectangle.sketch).conflictMessages.joined(separator: "\n"))
        #expect(error.contains("Horizontal on Line 2"))
    }

    @Test func anImpossibleValueIsAPlainError() async throws {
        var rectangle = RectangleSketch()
        rectangle.sketch.dimensions[rectangle.width]?.value = -5
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let error = try #require(try await h.run([node]).error(node))
        guard case .failed(let reason) = SketchSolver.solve(rectangle.sketch).status else {
            Issue.record("expected the solver to refuse a negative length")
            return
        }
        #expect(error == reason)
    }

    @Test func openCurvesWarn() async throws {
        var rectangle = RectangleSketch()
        let a = rectangle.sketch.addPoint(Vector2(80, 0)), b = rectangle.sketch.addPoint(Vector2(90, 0))
        rectangle.sketch.addLine(from: a, to: b)
        rectangle.sketch.add(.fix(a, at: Vector2(80, 0)))
        rectangle.sketch.add(.fix(b, at: Vector2(90, 0)))
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.warning(node) == "1 curve doesn't form a closed region.")
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
    }

    @Test func anExposedDimensionIsANumberInputNamedAfterIt() {
        var rectangle = RectangleSketch(width: 60)
        rectangle.expose(rectangle.width)
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID)
        node.inputValues[NodeSetting.sketch] = .sketch(rectangle.sketch)
        let exposed = SketchNode.inputs(for: node).dropFirst(SketchNode.inputs.count)
        #expect(exposed.map(\.name) == ["d1"])
        #expect(exposed.first?.type == .number && exposed.first?.unit == .millimetres)
        #expect(exposed.first?.defaultValue == .number(60))
    }

    @Test func aWiredValueDrivesItsExposedDimension() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(80)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(width, "value", to: node, "d1")
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let profile = try #require(report.value(node, "profiles")?.profiles?.first)
        #expect(near(profile.corners[1], Vector2(80, 0)))
    }

    @Test func aListIntoAnExposedDimensionBroadcastsOneProfilePerValue() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let widths = h.add(SeriesNode.self, ["start": .number(20), "step": .number(10), "count": .integer(3)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(widths, "values", to: node, "d1")
        let profiles = try #require(try await h.run([node]).value(node, "profiles")?.profiles)
        #expect(profiles.map { $0.corners[1].x.rounded() } == [20, 30, 40])
    }

    @Test func aDimensionNamedLikeAnInputOrSettingIsNotExposedAndWarns() async throws {
        var rectangle = RectangleSketch()
        rectangle.expose(rectangle.width)
        rectangle.sketch.renameDimension(rectangle.width, to: "plane")
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        #expect(SketchNode.inputs(for: h.graph.nodes[node.id] ?? node).map(\.name) == ["plane", "references"])
        let report = try await h.run([node])
        #expect(report.warning(node) == "Dimension “plane” can't be an input: the node already has an input or setting "
            + "with that name. Rename it.")
        #expect(SketchSockets.isReserved("sketch") && SketchSockets.isReserved("projection.p1") && !SketchSockets.isReserved("d1"))
    }

    @Test func referenceDimensionsComeOutAsMeasurementsInNameOrder() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        let diagonal = rectangle.sketch.addDimension(.distance(rectangle.corners[0], rectangle.corners[2]), value: 1,
                                                     isDriving: false)
        let top = rectangle.sketch.addDimension(.length(rectangle.lines[2]), value: 1, isDriving: false)
        rectangle.sketch.renameDimension(diagonal, to: "b")
        rectangle.sketch.renameDimension(top, to: "a")
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let measured = try #require(report.value(node, "measurements")?.numbers)
        #expect(measured.count == 2)
        #expect(isClose(measured[0], 60) && isClose(measured[1], 5200.squareRoot()))
    }

    @Test func aReferenceDimensionThatCantBeMeasuredEmptiesMeasurementsAndSaysWhich() async throws {
        // Dropping "a" would move "b" up to position 0, so a wired consumer of position 0 would read b.
        var rectangle = RectangleSketch(width: 60, height: 40)
        let hole = rectangle.addHole(center: Vector2(15, 20), radius: 5)
        guard case .radius(let circle)? = rectangle.sketch.dimensions[hole]?.kind else {
            Issue.record("expected a radius dimension")
            return
        }
        let wrong = rectangle.sketch.addDimension(.length(circle), value: 1, isDriving: false)
        let top = rectangle.sketch.addDimension(.length(rectangle.lines[2]), value: 1, isDriving: false)
        rectangle.sketch.renameDimension(wrong, to: "a")
        rectangle.sketch.renameDimension(top, to: "b")
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.warning(node) == SketchSolve.unmeasured("a", because: SketchSolve.wrongGeometry))
        #expect(report.value(node, "measurements")?.numbers == [])
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
    }

    @Test func aWiredPlaneSketchIsDrawnOnTheWiredPlane() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["orientation": .integer(1), "offset": .number(5)])
        let node = sketchNode(&h, RectangleSketch(plane: .wired).sketch)
        #expect(try await h.run([node]).error(node) == SketchNode.wiredPlaneMissing)
        h.wire(plane, "plane", to: node, "plane")
        let report = try await h.run([node])
        #expect(report.isOK(node))
        #expect(report.value(node, "profiles")?.profiles?.first?.plane == Plane.xz.offset(by: 5))
    }

    @Test func aWireIntoTheOwnPlaneOfASketchWarns() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["orientation": .integer(1)])
        let node = sketchNode(&h, RectangleSketch(plane: .fixed(.xy)).sketch)
        h.wire(plane, "plane", to: node, "plane")
        let report = try await h.run([node])
        #expect(report.warning(node) == SketchNode.ignoredPlane)
        #expect(report.value(node, "profiles")?.profiles?.first?.plane == .xy)
    }

    @Test func aMissingOrUnreadableSketchIsAPlainError() async throws {
        var h = Harness()
        let node = h.add(SketchNode.self)
        h.set(node, NodeSetting.sketch, nil)
        #expect(try await h.run([node]).error(node) == SketchNode.missingSketch)
        h.set(node, NodeSetting.sketch, .text("square"))
        #expect(try await h.run([node]).error(node) == SketchNode.unreadableSketch)
    }

    @Test func sketchProfilesExtrudeWithTheirHoleWallsNamed() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.addHole(center: Vector2(15, 20), radius: 5)
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(node, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude])
        let solid = try onlySolid(report, extrude)
        #expect(solid.topology.faces.contains { $0.tags.contains(TopoTag(node: extrude.id, item: 0, role: .side(loop: 1, segment: 0))) })
    }

    @Test func aWireLeftOnAnUnexposedDimensionIsIgnored() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(80)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(width, "value", to: node, "d1")
        rectangle.sketch.dimensions[rectangle.width]?.isExposed = false
        h.set(node, NodeSetting.sketch, .sketch(rectangle.sketch))
        let report = try await h.run([node])
        #expect(report.isOK(node))
        #expect(near(try #require(report.value(node, "profiles")?.profiles?.first).corners[1], Vector2(60, 0)))
    }

    @Test func anEmptySketchIntoAnExtrudeMakesNoSolidAndNoError() async throws {
        var h = Harness()
        let node = h.add(SketchNode.self)
        let extrude = h.add(ExtrudeNode.self)
        h.wire(node, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude])
        #expect(report.isOK(extrude))
        #expect(report.value(extrude, "solid")?.solids?.isEmpty == true)
    }

    @Test func aNonFiniteWiredValueIsAPlainError() async throws {
        var rectangle = RectangleSketch()
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(.nan)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(width, "value", to: node, "d1")
        let report = try await h.run([node])
        #expect(report.error(node) == "Length d1 is not a number.")
    }
}
```

Create `Tests/CreatorNodesTests/SketchIntegrationTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import CreatorSketch
import Testing

/// Sketcher spec §10, Integration (OCCTKernel): sketch → extrude, an exposed dimension driving the part
/// with downstream picks keeping their keys, and a sketch on a face following the face. The projected
/// edge across an upstream change is in `SketchProjectionTests`.
struct SketchIntegrationTests {
    @Test func aSketchWithAHoleExtrudesToItsAnalyticVolume() async throws {
        let kernel = OCCTKernel()
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.addHole(center: Vector2(15, 20), radius: 5)
        var h = Harness()
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude], kernel: kernel)
        #expect(report.isOK(sketch) && report.isOK(extrude))
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 6 * (2400 - 25 * Double.pi)))
    }

    @Test func aNotchedSketchRegionExtrudes() async throws {
        // The S2 handoff's case: the notch's arc runs clockwise in the counter-clockwise outline.
        let kernel = OCCTKernel()
        var drawing = Sketch()
        let corners = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(14, 10), Vector2(6, 10), Vector2(0, 10)]
        let points = corners.map { drawing.addPoint($0) }
        for (a, b) in [(0, 1), (1, 2), (2, 3), (4, 5), (5, 0)] { drawing.addLine(from: points[a], to: points[b]) }
        drawing.addArc(center: drawing.addPoint(Vector2(10, 10)), start: points[4], end: points[3])
        var h = Harness()
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(3)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude], kernel: kernel)
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 3 * (200 - 8 * Double.pi)))
    }

    @Test func anExposedDimensionChangesThePartAndDownstreamPicksKeepTheirKeys() async throws {
        let kernel = OCCTKernel()
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(60)])
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangle.sketch)])
        h.wire(width, "value", to: sketch, "d1")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let rule = h.add(EdgesByTagNode.self)
        h.wire(extrude, "solid", to: rule, "solid")
        let chamfer = h.add(ChamferNode.self, ["distance": .number(0.5)])
        h.wire(rule, "edges", to: chamfer, "edges")

        // Pick the top cap's four edges, as the viewport would.
        let plate = try onlySolid(try await h.run([extrude], kernel: kernel), extrude)
        let top = plate.topology.edges.filter { edge in
            let cap = TopoTag(node: extrude.id, item: 0, role: .endCap)
            return edge.faces.compactMap { plate.topology.face($0) }.contains { $0.tags.contains(cap) }
        }
        #expect(top.count == 4)
        let picks = plate.topology.picks(for: top.map(\.id))
        h.set(rule, NodeSetting.picks, .edgePicks(picks))
        let before = try await h.run([chamfer], kernel: kernel)
        #expect(before.isOK(rule) && before.isOK(chamfer))

        h.set(width, "value", .number(80))
        let after = try await h.run([chamfer], kernel: kernel)
        #expect(after.isOK(sketch) && after.isOK(rule) && after.isOK(chamfer))
        let widened = try onlySolid(after, extrude)
        #expect(isClose(try await volume(widened, kernel), 80 * 40 * 6))
        #expect(widened.topology.picks(for: try #require(after.value(rule, "edges")?.edgeSets?.first).edges) == picks)
    }

    @Test func aSketchOnAFaceFollowsTheFaceWhenTheModelChanges() async throws {
        // "New sketch on face": Plane from Face wired into a Sketch whose plane is `.wired`.
        let kernel = OCCTKernel()
        var h = Harness()
        let box = h.box(20, 10, 6)
        let top = FacePick(tags: [TopoTag(node: box.id, item: 0, role: .endCap)])
        let face = h.add(PlaneFromFaceNode.self, [NodeSetting.face: .facePick(top)])
        h.wire(box, "solid", to: face, "solid")
        var drawing = Sketch(plane: .wired)
        let circle = drawing.addCircle(center: Vector2(0.3, -0.2), radius: 2.5)
        guard case .circle(let center, _)? = drawing.entities[circle]?.kind else { preconditionFailure("not a circle") }
        drawing.add(.fix(center, at: .zero))
        drawing.addDimension(.radius(circle), value: 2)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(face, "plane", to: sketch, "plane")
        let boss = h.add(ExtrudeNode.self, ["distance": .number(4)])
        h.wire(sketch, "profiles", to: boss, "profile")
        let union = h.add(BooleanNode.self)
        h.wire(box, "solid", to: union, "target")
        h.wire(boss, "solid", to: union, "tools")

        for height in [6.0, 10] {
            h.set(box, "distance", .number(height))
            let report = try await h.run([union], kernel: kernel)
            #expect(report.isOK(face) && report.isOK(sketch) && report.isOK(union))
            let cylinder = try onlySolid(report, boss)
            #expect(abs(cylinder.bounds.min.z - height) < 1e-6)
            #expect(isClose(try await volume(try onlySolid(report, union), kernel), 20 * 10 * height + 16 * Double.pi))
        }
    }
}
```

In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
    /// The slice's 26 (spec §7.1) plus Plane from Face (S4).
    @Test func theBuiltInsAreTheSliceAndTheSketcherNodesInSixCategories() {
        #expect(BuiltInNodes.all.count == 27)
        let counts = Dictionary(grouping: BuiltInNodes.all, by: { $0.category }).mapValues(\.count)
        #expect(counts == [.value: 9, .profile: 5, .solid: 5, .selection: 5, .feature: 2, .output: 1])
```

with:

```swift
    /// The slice's 26 (spec §7.1) plus Plane from Face and Sketch (S4).
    @Test func theBuiltInsAreTheSliceAndTheSketcherNodesInSixCategories() {
        #expect(BuiltInNodes.all.count == 28)
        let counts = Dictionary(grouping: BuiltInNodes.all, by: { $0.category }).mapValues(\.count)
        #expect(counts == [.value: 9, .profile: 6, .solid: 5, .selection: 5, .feature: 2, .output: 1])
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter "SketchNodeTests|SketchIntegrationTests|OutputNodeTests"`
Expected: build errors: `SketchNode`, `SketchSolve` and `SketchSockets` are not in scope.

- [ ] **Step 3: The exposed-dimension sockets**


Create `Sources/CreatorNodes/Sketch/SketchSockets.swift`:

```swift
import CreatorGraph
import CreatorSketch

/// The Sketch node's exposed-dimension sockets (sketcher spec §7): one number input per dimension
/// with `isExposed`, named after it, in name order, whose unwired value is the stored one.
enum SketchSockets {
    /// The exposed dimensions that are sockets, with their specs. A name the node already uses (a
    /// fixed input, a setting or a projection setting), an empty name or a repeated one is left out,
    /// and `refused` names it.
    static func exposed(_ sketch: Sketch) -> [(id: DimensionID, spec: SocketSpec)] {
        partition(sketch).sockets
    }

    /// Exposed dimensions that can't be sockets, as warnings for the node.
    static func refused(_ sketch: Sketch) -> [String] {
        partition(sketch).refused.map { name in
            name.isEmpty
                ? "An exposed dimension has no name, so it isn't an input. Name it to expose it."
                : "Dimension “\(name)” can't be an input: the node already has an input or setting with that name. Rename it."
        }
    }

    private static func partition(_ sketch: Sketch) -> (sockets: [(id: DimensionID, spec: SocketSpec)], refused: [String]) {
        var sockets: [(id: DimensionID, spec: SocketSpec)] = []
        var refused: [String] = []
        var used = Set<String>()
        let exposed = sketch.dimensionIDs.compactMap { id in sketch.dimensions[id].map { (id, $0) } }
            .filter { $0.1.isExposed }
            .sorted { ($0.1.name, $0.0) < ($1.1.name, $1.0) }
        for (id, dimension) in exposed {
            guard !isReserved(dimension.name), used.insert(dimension.name).inserted else {
                refused.append(dimension.name)
                continue
            }
            let unit: ValueUnit = if case .angle = dimension.kind { .degrees } else { .millimetres }
            sockets.append((id, SocketSpec(SocketName(dimension.name), .number, defaultValue: .number(dimension.value), unit: unit)))
        }
        return (sockets, refused)
    }

    /// Names an exposed dimension may not take.
    static func isReserved(_ name: String) -> Bool {
        name.isEmpty || name.hasPrefix(NodeSetting.projectionPrefix) || NodeSetting.all.contains(SocketName(name))
            || SketchNode.inputs.contains { $0.name.rawValue == name }
    }
}
```

- [ ] **Step 4: Solve, regions, measurements and states**


Create `Sources/CreatorNodes/Sketch/SketchSolve.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorSketch

/// What the Sketch node makes of a sketch whose wired values and projections are applied (sketcher
/// spec §7): solve, find regions, read reference dimensions, and map the solver's status to node states.
enum SketchSolve {
    struct Output {
        /// The regions as profiles on the sketch plane, largest first (spec §5 step 5).
        var profiles: [Profile2D]
        /// Reference (non-driving) dimensions' measured values, in name order.
        var measurements: [Double]
        var warnings: [String]
    }

    static let nothingDrawn = "Draw a closed shape in the sketch to make a profile."

    /// Over-constrained and failed solves throw their plain-language messages, so the evaluator shows an
    /// error and the viewport keeps the last good result as a ghost (parent spec §4.4).
    static func run(_ sketch: Sketch, on plane: Plane) throws -> Output {
        let solution = SketchSolver.solve(sketch)
        switch solution.status {
        case .overConstrained:
            let messages = solution.conflictMessages.filter { !$0.isEmpty }
            throw NodeError.invalidValue(messages.isEmpty ? "The sketch's constraints conflict." : messages.joined(separator: "\n"))
        case .failed(let reason):
            throw NodeError.invalidValue(reason)
        case .solved, .underConstrained:
            break
        }
        var warnings: [String] = []
        let freedom = solution.degreesOfFreedom
        if freedom > 0 {
            let count = freedom == 1 ? "1 degree" : "\(freedom.display) degrees"
            warnings.append("The sketch has \(count) of freedom left, so it isn't fully constrained.")
        }
        var solved = sketch
        solved.remember(solution)
        let found = SketchRegions.find(in: solved)
        if let open = found.warning { warnings.append(open) }
        if found.regions.isEmpty, found.openCurves.isEmpty { warnings.append(nothingDrawn) }
        let measured = measurements(sketch, solution)
        return Output(profiles: found.regions.map { $0.profile(on: plane) }, measurements: measured.values,
                      warnings: warnings + measured.warnings)
    }

    /// Why a reference dimension isn't measured, for `unmeasured(_:because:)`.
    static let onSuspendedEdge = "its projected edge is suspended"
    static let wrongGeometry = "it doesn't fit the curve it is on"

    static func unmeasured(_ name: String, because reason: String) -> String {
        "Reference dimension “\(name)” can't be measured: \(reason). “measurements” is empty until it can be."
    }

    /// The reference dimensions' values in name order. A position in the list is a dimension, so when one
    /// can't be measured (on a suspended projection, whose stored curve S4 never refreshes, or on geometry
    /// it doesn't fit) the list is empty rather than shifted, and a warning names each such dimension.
    private static func measurements(_ sketch: Sketch, _ solution: SketchSolution) -> (values: [Double], warnings: [String]) {
        let references = sketch.dimensionIDs.compactMap { id in sketch.dimensions[id].map { (id, $0) } }
            .filter { !$0.1.isDriving }
            .sorted { ($0.1.name, $0.0) < ($1.1.name, $1.0) }
        var values: [Double] = []
        var warnings: [String] = []
        for (id, dimension) in references {
            let onSuspended = dimension.kind.entities.contains { entity in
                if case .projected(let source)? = sketch.entities[entity]?.kind { return source.isSuspended }
                return false
            }
            if onSuspended {
                warnings.append(unmeasured(dimension.name, because: onSuspendedEdge))
            } else if let value = solution.measurements[id] {
                values.append(value)
            } else {
                warnings.append(unmeasured(dimension.name, because: wrongGeometry))
            }
        }
        return (warnings.isEmpty ? values : [], warnings)
    }
}
```

- [ ] **Step 5: The node, registered after Polyline**


Create `Sources/CreatorNodes/Profiles/SketchNode.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch

/// A constraint sketch (sketcher spec §7): the `sketch` setting holds the geometry, constraints and
/// dimensions; the node solves it and outputs its closed regions as a list of profiles. Each exposed
/// dimension adds a number input named after it, whose wired value overrides the stored one, so graph
/// parameters drive the sketch. Reference dimensions come out of `measurements`, in name order.
///
/// States: an under-constrained sketch, open curves and an exposed dimension that can't be a socket
/// are warnings; an over-constrained or failed solve is an error, and the last good part stays ghosted.
public enum SketchNode: NodeDefinition {
    public static let typeID = "creator.sketch"
    public static let displayName = "Sketch"
    public static let category = NodeCategory.profile
    public static let inputs = [
        SocketSpec("plane", .plane, optional: true),
        SocketSpec("references", .solid, access: .list, optional: true),
    ]
    public static let outputs = [
        SocketSpec("profiles", .profile),
        SocketSpec("measurements", .number),
    ]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.sketch: .sketch(Sketch())]

    static let missingSketch = "This sketch's drawing is missing. Undo the last change, or add a new Sketch."
    static let unreadableSketch = "This sketch's drawing can't be read. Undo the last change, or add a new Sketch."
    static let wiredPlaneMissing = "Wire a plane into “plane”: this sketch is drawn on the wired plane."
    static let ignoredPlane = "“plane” is wired, but this sketch is drawn on its own plane, so the wire has no effect."

    public static func inputs(for node: Node) -> [SocketSpec] {
        guard case .sketch(let sketch)? = node.inputValues[NodeSetting.sketch] else { return inputs }
        return inputs + SketchSockets.exposed(sketch).map(\.spec)
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        var sketch: Sketch
        switch context.node.inputValues[NodeSetting.sketch] {
        case nil: throw NodeError.invalidValue(missingSketch)
        case .sketch(let stored)?: sketch = stored
        case .some: throw NodeError.invalidValue(unreadableSketch)
        }
        var warnings = SketchSockets.refused(sketch)
        let plane: Plane
        switch sketch.plane {
        case .fixed(let own):
            plane = own
            if inputs.has("plane") { warnings.append(ignoredPlane) }
        case .wired:
            guard inputs.has("plane") else { throw NodeError.invalidValue(wiredPlaneMissing) }
            plane = try inputs.plane("plane")
        }
        for (id, spec) in SketchSockets.exposed(sketch) where inputs.has(spec.name) {
            sketch.dimensions[id]?.value = try inputs.number(spec.name)
        }
        let output = try SketchSolve.run(sketch, on: plane)
        let lists: [SocketName: [Scalar]] = [
            "profiles": output.profiles.map(Scalar.profile),
            "measurements": output.measurements.map(Scalar.number),
        ]
        return NodeOutputs(lists: lists, warnings: warnings + output.warnings)
    }
}
```

In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
RegularPolygonNode.self, PolylineNode.self,
```

with:

```swift
RegularPolygonNode.self, PolylineNode.self,
        SketchNode.self,
```

`profiles` and `measurements` always come out as lists (`NodeOutputs(lists:)`), so a downstream Extrude broadcasts over the regions, and an empty sketch gives an empty list rather than an error. A list wired into an exposed dimension broadcasts the whole node, so its regions are concatenated in item order.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter "SketchNodeTests|SketchIntegrationTests|OutputNodeTests|CatalogTests|BuiltInNodesInspectorTests"`
Expected: PASS: 20 `SketchNodeTests` and 4 `SketchIntegrationTests`. The OCCT ones take a few tenths of a second.

- [ ] **Step 7: Run the gate**

Expected: no new warnings, **969 tests** (master + 68), SwiftLint clean.

- [ ] **Step 8: Commit**

```bash
git add Sources/CreatorNodes Tests/CreatorNodesTests
git commit -m "feat(nodes): the Sketch node solves a sketch into profiles, with exposed dimensions (S4)"
```

---

### Task 7: Projection, and the docs

**Files:**
- Create: `Sources/CreatorNodes/Sketch/EdgeProjection.swift`, `Sources/CreatorNodes/Sketch/SketchProjections.swift`
- Modify: `Sources/CreatorNodes/Profiles/SketchNode.swift` (doc and `evaluate`), `Sources/CreatorNodes/Selection/EdgeTagMatch.swift` (factor out `choose` and `drift`)
- Modify: `docs/verification/human-checks.md` (append Group S4)
- Modify: `CLAUDE.md` (three passages), `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (append Errata (S4)), `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` (S4 done, S4 → S5)
- Test: `Tests/CreatorNodesTests/SketchProjectionTests.swift`

**Interfaces:**
- Consumes: Task 3's `EdgeInfo.curve`/`EdgeCurve`, Task 4's `NodeSetting.projection(_:)`, Task 6's `SketchNode`. From S1: `ProjectionSource(reference:curve:isSuspended:)`, `ProjectedCurve`, `Sketch.label(of:)` ("Projected edge 1"). From M3: `Topology.edges(matching:)`, `Topology.picks(for:)`, `EdgePick.ordinals`/`matchCount`, `EdgeTagMatch.resolve`. Task 6's `SketchSolve.unmeasured`/`onSuspendedEdge`.
- Produces:
  - `EdgeProjection.project(_ edge: EdgeInfo, onto plane: Plane) -> EdgeProjection.Outcome` (`.curve(ProjectedCurve)` or `.refused(String)`), `EdgeProjection.local(_:on:)`, and the reasons `toPoint`, `oblique`, `unsupported`.
  - `EdgeTagMatch.choose(_ pick: EdgePick, in: Topology) -> (chosen: [EdgeInfo], matchCount: Int)` and `EdgeTagMatch.drift(_: [(found: Int, expected: Int)]) -> String`, which `EdgeTagMatch.resolve` now uses too (behaviour unchanged).
  - `SketchProjections.resolve(_ sketch: inout Sketch, settings: [SocketName: ConstantValue], references: [Solid], on plane: Plane) -> [String]` (warnings in entity order), `SketchProjections.locate(_:in:)`, and `SketchProjections.ignored` (" Its constraints are ignored.").

- [ ] **Step 1: Write the failing tests**


Create `Tests/CreatorNodesTests/SketchProjectionTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import CreatorSketch
import Testing

/// Sketcher spec §7, projecting model edges into a sketch.
struct SketchProjectionTests {
    func edge(_ kind: CurveKind, _ curve: EdgeCurve?) -> EdgeInfo {
        EdgeInfo(id: EdgeID(0), kind: kind, direction: nil, length: 1, midpoint: .zero, convexity: .convex,
                 faces: [FaceID(0), FaceID(1)], curve: curve)
    }

    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 }

    // MARK: - The projection itself

    @Test func aLineProjectsAlongThePlaneNormal() {
        let line = edge(.line, .line(start: Vector3(0, 3, 5), end: Vector3(10, 4, 7)))
        #expect(EdgeProjection.project(line, onto: .xy) == .curve(.line(Vector2(0, 3), Vector2(10, 4))))
        #expect(EdgeProjection.project(line, onto: .xz) == .curve(.line(Vector2(0, 5), Vector2(10, 7))))
    }

    @Test func aLinePerpendicularToThePlaneIsRefused() {
        let upright = edge(.line, .line(start: Vector3(1, 1, 0), end: Vector3(1, 1, 9)))
        #expect(EdgeProjection.project(upright, onto: .xy) == .refused(EdgeProjection.toPoint))
    }

    @Test func aCircleFacingThePlaneBecomesACircle() {
        let rim = edge(.circle, .circle(center: Vector3(1, 2, 4), axis: -.unitZ, radius: 3, start: Vector3(4, 2, 4),
                                        sweep: 2 * .pi))
        #expect(EdgeProjection.project(rim, onto: .xy) == .curve(.circle(center: Vector2(1, 2), radius: 3)))
    }

    @Test func anArcComesOutCounterClockwiseInThePlaneWhicheverWayItsAxisPoints() {
        let up = edge(.circle, .circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2))
        guard case .curve(.arc(_, _, let start, let end)) = EdgeProjection.project(up, onto: .xy) else {
            Issue.record("expected an arc")
            return
        }
        #expect(near(start.radians, 0) && near(end.radians, .pi / 2))
        // About −Z the same start sweeps clockwise in the plane, to −90°.
        let down = edge(.circle, .circle(center: .zero, axis: -.unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2))
        guard case .curve(.arc(_, _, let downStart, let downEnd)) = EdgeProjection.project(down, onto: .xy) else {
            Issue.record("expected an arc")
            return
        }
        #expect(near(downStart.radians, -.pi / 2) && near(downEnd.radians, 0))
    }

    @Test func anObliqueCircleOrAnUnsupportedCurveIsRefused() {
        let tilted = edge(.circle, .circle(center: .zero, axis: .unitX, radius: 2, start: Vector3(0, 2, 0), sweep: 2 * .pi))
        #expect(EdgeProjection.project(tilted, onto: .xy) == .refused(EdgeProjection.oblique))
        #expect(EdgeProjection.project(edge(.bspline, nil), onto: .xy) == .refused(EdgeProjection.unsupported))
    }

    // MARK: - Through the Sketch node

    /// A 20 × 10 × 6 box wired into a Sketch's `references`. The sketch holds projection `p1` of the
    /// box edge between `first` and `second` (by role) and a reference length `d1` on it.
    struct Projected {
        var h = Harness()
        let box: Node
        let sketch: Node

        init(width: Double = 20) {
            box = h.box(width, 10, 6)
            var drawing = Sketch()
            let projected = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1",
                                                                                 curve: .line(.zero, Vector2(1, 0))))))
            drawing.addDimension(.length(projected), value: 1, isDriving: false)
            sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
            h.wire(box, "solid", to: sketch, "references")
        }

        mutating func pick(between first: TopoRole, and second: TopoRole, kernel: any Kernel = FakeKernel()) async throws {
            let solid = try onlySolid(try await h.run([box], kernel: kernel), box)
            let tags = [TopoTag(node: box.id, item: 0, role: first), TopoTag(node: box.id, item: 0, role: second)]
            let edge = try #require(solid.topology.edges.first { edge in
                guard let key = solid.topology.key(of: edge) else { return false }
                return key.first.union(key.second) == Set(tags)
            })
            h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [edge.id])))
        }
    }

    @Test func aProjectedEdgeTakesItsPickedEdgesShape() async throws {
        var projected = Projected(width: 20)
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        let report = try await projected.h.run([projected.sketch])
        // Open on its own, so the sketch warns, but the edge is resolved and measured.
        #expect(report.warning(projected.sketch) == "1 curve doesn't form a closed region.")
        #expect(report.value(projected.sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [20])
    }

    @Test func aProjectedEdgeFollowsAnUpstreamChange() async throws {
        var projected = Projected(width: 20)
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        projected.h.set(projected.box, "distance", .number(6))
        let rectangle = try #require(projected.h.graph.incomingLink(to: Endpoint(node: projected.box.id, socket: "profile")))
        projected.h.set(try #require(projected.h.graph.nodes[rectangle.from.node]), "width", .number(35))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.value(projected.sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [35])
    }

    @Test func aMissingPickOrReferenceSuspendsTheEdgeWithAWarning() async throws {
        var projected = Projected()
        var report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 has no picked edge." + SketchProjections.ignored) == true)
        // Its reference length would read the placeholder curve stored in the sketch (1 mm), so it isn't output.
        #expect(report.warning(projected.sketch)?.contains(SketchSolve.unmeasured("d1", because: SketchSolve.onSuspendedEdge)) == true)
        #expect(report.value(projected.sketch, "measurements")?.numbers == [])
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        projected.h.set(projected.sketch, NodeSetting.projection("p1"),
                        .edgePicks([EdgePick(key: EdgeKey([TopoTag(node: NodeID(), item: 0, role: .endCap)], []), matchCount: 1)]))
        report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 matches no edge of the references."
            + SketchProjections.ignored) == true)
    }

    @Test func noReferenceSolidIsExplained() async throws {
        var projected = Projected()
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        let link = try #require(projected.h.graph.incomingLink(to: Endpoint(node: projected.sketch.id, socket: "references")))
        var graph = projected.h.graph
        graph.links.removeAll { $0 == link }
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(graph, demand: [projected.sketch.id])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 has no reference solid: wire the solid it was "
            + "picked on into “references”." + SketchProjections.ignored) == true)
    }

    @Test func anEdgeThatProjectsToAPointIsSuspendedWithAWarning() async throws {
        var projected = Projected()
        try await projected.pick(between: .side(segment: 0), and: .side(segment: 1))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 can't be projected: \(EdgeProjection.toPoint)."
            + SketchProjections.ignored) == true)
    }

    @Test func aConstraintOnASuspendedEdgeIsIgnoredNotAConflict() async throws {
        var projected = Projected()
        var drawing = Sketch()
        let edge = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let point = drawing.addPoint(Vector2(3, 3))
        drawing.add(.fix(point, at: Vector2(3, 3)))
        drawing.add(.pointOn(point: point, curve: edge))
        projected.h.set(projected.sketch, NodeSetting.sketch, .sketch(drawing))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.error(projected.sketch) == nil)
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1 has no picked edge.") == true)
    }

    @Test func aPickWhoseMatchCountDriftedSaysSo() async throws {
        var projected = Projected()
        try await projected.pick(between: .endCap, and: .side(segment: 0))
        guard case .edgePicks(var picks)? = projected.h.graph.nodes[projected.sketch.id]?.inputValues[NodeSetting.projection("p1")] else {
            Issue.record("no pick stored")
            return
        }
        picks[0].matchCount = 2
        projected.h.set(projected.sketch, NodeSetting.projection("p1"), .edgePicks(picks))
        let report = try await projected.h.run([projected.sketch])
        #expect(report.warning(projected.sketch)?.contains("Projected edge 1's pick changed. Matched 1 edge, expected 2.") == true)
        #expect(EdgeTagMatch.drift([(1, 2)]) == "Matched 1 edge, expected 2.")
    }

    // MARK: - On OCCT (sketcher spec §10, Integration)

    @Test func aProjectedEdgeSurvivesAnUpstreamWidthChangeOnOCCT() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let box = h.box(20, 10, 6)
        // Three sides of a rectangle; the fourth (y = −depth / 2) is the box's projected top-front edge.
        var drawing = Sketch()
        let edge = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let a = drawing.addPoint(Vector2(-10, -4)), b = drawing.addPoint(Vector2(10, -4))
        let c = drawing.addPoint(Vector2(10, 5)), d = drawing.addPoint(Vector2(-10, 5))
        let right = drawing.addLine(from: b, to: c)
        drawing.addLine(from: c, to: d)
        let left = drawing.addLine(from: d, to: a)
        drawing.add(.fix(c, at: Vector2(10, 5)))
        drawing.add(.fix(d, at: Vector2(-10, 5)))
        drawing.add(.vertical(left))
        drawing.add(.vertical(right))
        drawing.add(.pointOn(point: a, curve: edge))
        drawing.add(.pointOn(point: b, curve: edge))
        drawing.addDimension(.length(edge), value: 1, isDriving: false)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(box, "solid", to: sketch, "references")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(2)])
        h.wire(sketch, "profiles", to: extrude, "profile")

        let solid = try onlySolid(try await h.run([box], kernel: kernel), box)
        let tags: Set = [TopoTag(node: box.id, item: 0, role: .endCap), TopoTag(node: box.id, item: 0, role: .side(segment: 0))]
        let picked = try #require(solid.topology.edges.first { edge in
            solid.topology.key(of: edge).map { $0.first.union($0.second) == tags } ?? false
        })
        h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [picked.id])))

        // Widening the box lengthens the edge, so its measurement follows. Deepening it moves the edge to
        // y = −depth / 2, so the sketch's bottom side follows it and the region grows.
        for (boxWidth, depth) in [(20.0, 10.0), (30, 14)] {
            let link = try #require(h.graph.incomingLink(to: Endpoint(node: box.id, socket: "profile")))
            let rectangle = try #require(h.graph.nodes[link.from.node])
            h.set(rectangle, "width", .number(boxWidth))
            h.set(rectangle, "height", .number(depth))
            let report = try await h.run([extrude], kernel: kernel)
            #expect(report.isOK(sketch), "\(String(describing: report.state(sketch)))")
            #expect(report.value(sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [boxWidth])
            #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 2 * 20 * (5 + depth / 2)))
        }
    }

    /// The edge of `solid` between the faces tagged `first` and `second` by `node`.
    func edge(of solid: Solid, _ node: Node, between first: TopoRole, and second: TopoRole) throws -> EdgeInfo {
        let tags: Set = [TopoTag(node: node.id, item: 0, role: first), TopoTag(node: node.id, item: 0, role: second)]
        return try #require(solid.topology.edges.first { edge in
            solid.topology.key(of: edge).map { $0.first.union($0.second) == tags } ?? false
        })
    }

    /// A Ø6 cylinder on (4, −3), picked at either rim (OCCT may run one of them about −Z): the rim
    /// projects to its circle, which bounds a region and is measured by a reference radius.
    @Test(arguments: [TopoRole.startCap, .endCap])
    func aCylinderRimProjectsToItsCircleOnOCCT(_ rim: TopoRole) async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(6), "plane": .plane(.through(Vector3(4, -3, 0)))])
        let cylinder = h.add(ExtrudeNode.self, ["distance": .number(5)])
        h.wire(circle, "profile", to: cylinder, "profile")
        var drawing = Sketch()
        let projected = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        drawing.addDimension(.radius(projected), value: 1, isDriving: false)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(cylinder, "solid", to: sketch, "references")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(2)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let solid = try onlySolid(try await h.run([cylinder], kernel: kernel), cylinder)
        let picked = try edge(of: solid, cylinder, between: rim, and: .side(segment: 0))
        h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [picked.id])))

        let report = try await h.run([extrude], kernel: kernel)
        #expect(report.isOK(sketch), "\(String(describing: report.state(sketch)))")
        let measured = try #require(report.value(sketch, "measurements")?.numbers)
        #expect(measured.count == 1 && isClose(measured[0], 3))
        let outline = try #require(report.value(sketch, "profiles")?.profiles?.first).outer
        guard outline.count == 1, case .arc(let center, let radius, _, _)? = outline.first else {
            Issue.record("expected one circle, got \(outline)")
            return
        }
        #expect((center - Vector2(4, -3)).length < 1e-9 && isClose(radius, 3))
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 2 * 9 * Double.pi))
    }

    /// A 20 × 10 plate's R2 corner arc about (8, −3) in world XY, picked at either rim, closed into a
    /// quarter disc by two fixed lines through its centre, on a sketch plane facing up (+Z) or down (−Z,
    /// where the arc's axis points against the normal and the plane's y is world −Y). The region extrudes
    /// to the quarter disc only if the arc came out counter-clockwise in the plane between the lines' ends.
    @Test(arguments: [TopoRole.startCap, .endCap], [false, true])
    func aCornerArcProjectsCounterClockwiseFromEitherRimOnOCCT(_ rim: TopoRole, facingDown: Bool) async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let outline = h.add(RoundedRectangleNode.self, ["width": .number(20), "height": .number(10), "cornerRadius": .number(2)])
        let plate = h.add(ExtrudeNode.self, ["distance": .number(3)])
        h.wire(outline, "profile", to: plate, "profile")
        var drawing = Sketch(plane: .fixed(facingDown ? Plane(origin: .zero, normal: -.unitZ, xAxis: .unitX) : .xy))
        let arc = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .line(.zero, Vector2(1, 0))))))
        let y = facingDown ? -1.0 : 1
        let corners = [Vector2(10, -3 * y), Vector2(8, -3 * y), Vector2(8, -5 * y)]
        let points = corners.map { drawing.addPoint($0) }
        for (point, at) in zip(points, corners) { drawing.add(.fix(point, at: at)) }
        drawing.addLine(from: points[0], to: points[1])
        drawing.addLine(from: points[1], to: points[2])
        drawing.addDimension(.radius(arc), value: 1, isDriving: false)
        let sketch = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing)])
        h.wire(plate, "solid", to: sketch, "references")
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(2)])
        h.wire(sketch, "profiles", to: extrude, "profile")
        let solid = try onlySolid(try await h.run([plate], kernel: kernel), plate)
        let picked = try edge(of: solid, plate, between: rim, and: .side(segment: 1))
        h.set(sketch, NodeSetting.projection("p1"), .edgePicks(solid.topology.picks(for: [picked.id])))

        let report = try await h.run([extrude], kernel: kernel)
        #expect(report.isOK(sketch), "\(String(describing: report.state(sketch)))")
        #expect(report.value(sketch, "measurements")?.numbers.map { $0.map { $0.rounded() } } == [2])
        #expect(isClose(try await volume(try onlySolid(report, extrude), kernel), 2 * Double.pi))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter SketchProjectionTests`
Expected: build errors: `EdgeProjection` and `SketchProjections` are not in scope.

- [ ] **Step 3: The projection maths**


Create `Sources/CreatorNodes/Sketch/EdgeProjection.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import CreatorSketch
import Foundation

/// Projects a model edge onto a sketch plane (sketcher spec §7, "Projection, v1"): a line becomes a
/// 2D line, and a circle or arc whose axis is parallel to the plane normal becomes a 2D circle or
/// arc. Anything else is refused, with the reason for the node's warning.
enum EdgeProjection {
    enum Outcome: Equatable {
        case curve(ProjectedCurve)
        case refused(String)
    }

    /// How far a circle's axis may be from parallel to the plane normal, as 1 − |cos|.
    static let axisTolerance = 1e-9
    /// A projected line shorter than this (mm) is a point.
    static let pointTolerance = 1e-9

    static let toPoint = "it is perpendicular to the sketch plane, so it projects to a point"
    static let oblique = "it is a circle or arc that doesn't face the sketch plane"
    static let unsupported = "only lines, circles and arcs can be projected"

    static func project(_ edge: EdgeInfo, onto plane: Plane) -> Outcome {
        switch edge.curve {
        case .line(let start, let end)?:
            let (a, b) = (local(start, on: plane), local(end, on: plane))
            return (b - a).length > pointTolerance ? .curve(.line(a, b)) : .refused(toPoint)
        case .circle(let center, let axis, let radius, let start, let sweep)?:
            guard let unit = axis.normalized, let normal = plane.normal.normalized,
                  abs(abs(unit.dot(normal)) - 1) <= axisTolerance else { return .refused(oblique) }
            let c = local(center, on: plane)
            if sweep >= 2 * .pi - 1e-9 { return .curve(.circle(center: c, radius: radius)) }
            let offset = local(start, on: plane) - c
            let from = atan2(offset.y, offset.x)
            // Counter-clockwise about an axis along the normal is counter-clockwise in the plane; about
            // an axis against it, clockwise, so the counter-clockwise arc then starts at the far end.
            let first = unit.dot(normal) > 0 ? from : from - sweep
            return .curve(.arc(center: c, radius: radius, start: Angle(radians: first), end: Angle(radians: first + sweep)))
        case nil:
            return .refused(unsupported)
        }
    }

    /// `point` in the plane's coordinates, projected along the normal.
    static func local(_ point: Vector3, on plane: Plane) -> Vector2 {
        let offset = point - plane.origin
        return Vector2(offset.dot(plane.xAxis), offset.dot(plane.yAxis))
    }
}
```

- [ ] **Step 4: Resolve each projection's pick against `references`**

One pick resolver serves both Edges by Tag and projection: factor `EdgeTagMatch`'s per-pick matching and its drift sentence out, so the two can't drift apart.

In `Sources/CreatorNodes/Selection/EdgeTagMatch.swift`, replace:

```swift
        for pick in picks {
            let matches = topology.edges(matching: pick.key)
            if matches.count != pick.matchCount { drifts.append((matches.count, pick.matchCount)) }
            let chosen = pick.ordinals.map { ordinals in ordinals.filter(matches.indices.contains).map { matches[$0] } } ?? matches
            for edge in chosen where seen.insert(edge.id).inserted {
                selected.append(edge.id)
            }
        }
        var warnings: [String] = []
        if !drifts.isEmpty {
            let counts = drifts.map { "\($0.found) \($0.found == 1 ? "edge" : "edges"), expected \($0.expected)" }
            warnings.append("Matched \(counts.joined(separator: "; ")).")
        } else if selected.isEmpty {
```

with:

```swift
        for pick in picks {
            let choice = choose(pick, in: topology)
            if choice.matchCount != pick.matchCount { drifts.append((choice.matchCount, pick.matchCount)) }
            for edge in choice.chosen where seen.insert(edge.id).inserted {
                selected.append(edge.id)
            }
        }
        var warnings: [String] = []
        if !drifts.isEmpty {
            warnings.append(drift(drifts))
        } else if selected.isEmpty {
```

In `Sources/CreatorNodes/Selection/EdgeTagMatch.swift`, replace:

```swift
        return EdgeTagMatch(edges: selected, warnings: warnings)
    }
```

with:

```swift
        return EdgeTagMatch(edges: selected, warnings: warnings)
    }

    /// The edges one pick chooses in `topology` (its key's tag-subset matches, narrowed by its
    /// ordinals), and how many edges the key matched. The Sketch node's projections use it too.
    static func choose(_ pick: EdgePick, in topology: Topology) -> (chosen: [EdgeInfo], matchCount: Int) {
        let matches = topology.edges(matching: pick.key)
        let chosen = pick.ordinals.map { ordinals in ordinals.filter(matches.indices.contains).map { matches[$0] } } ?? matches
        return (chosen, matches.count)
    }

    /// "Matched 1 edge, expected 2." (several drifts joined by "; ").
    static func drift(_ drifts: [(found: Int, expected: Int)]) -> String {
        let counts = drifts.map { "\($0.found) \($0.found == 1 ? "edge" : "edges"), expected \($0.expected)" }
        return "Matched \(counts.joined(separator: "; "))."
    }
```


Create `Sources/CreatorNodes/Sketch/SketchProjections.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch

/// Refreshes a sketch's projected edges before it is solved (sketcher spec §7, S1–S2 handoff). Each
/// projection's `EdgePick` is the node setting `NodeSetting.projection(reference)`. A pick that names
/// exactly one edge of the `references` solids gets that edge's projected curve; any other projection
/// is suspended (the solver skips its constraints and regions ignore it, nothing is deleted) and
/// named in a warning.
enum SketchProjections {
    enum Located {
        case found(EdgeInfo, drift: String?)
        case problem(String)
    }

    static let ignored = " Its constraints are ignored."

    /// Updates every projected entity of `sketch` in place and returns the warnings, in entity order.
    static func resolve(_ sketch: inout Sketch, settings: [SocketName: ConstantValue], references: [Solid],
                        on plane: Plane) -> [String] {
        var warnings: [String] = []
        for id in sketch.entityIDs {
            guard case .projected(var source)? = sketch.entities[id]?.kind else { continue }
            let label = sketch.label(of: id)
            var problem: String?
            switch locate(settings[NodeSetting.projection(source.reference)], in: references) {
            case .found(let edge, let drift):
                if let drift { warnings.append("\(label)'s pick changed. \(drift)") }
                switch EdgeProjection.project(edge, onto: plane) {
                case .curve(let curve): source.curve = curve
                case .refused(let reason): problem = "\(label) can't be projected: \(reason)."
                }
            case .problem(let text):
                problem = "\(label) \(text)"
            }
            source.isSuspended = problem != nil
            if let problem { warnings.append(problem + ignored) }
            sketch.entities[id]?.kind = .projected(source)
        }
        return warnings
    }

    /// The one edge a stored pick names among `references`, or why there isn't one. Each solid is
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
        default: return .problem("matches \(found.count.display) edges of the references.")
        }
    }
}
```

- [ ] **Step 5: Resolve projections in the Sketch node before solving**


In `Sources/CreatorNodes/Profiles/SketchNode.swift`, replace:

```swift
/// States: an under-constrained sketch, open curves and an exposed dimension that can't be a socket
/// are warnings; an over-constrained or failed solve is an error, and the last good part stays ghosted.
```

with:

```swift
/// Projected edges are re-resolved on every evaluation against the `references` solids
/// (`SketchProjections`), so a projection follows its edge when the model upstream changes.
///
/// States: an under-constrained sketch, open curves, a projection whose pick matches no edge or
/// several (suspended, not deleted) and an exposed dimension that can't be a socket are warnings; an
/// over-constrained or failed solve is an error, and the last good part stays ghosted.
```

In `Sources/CreatorNodes/Profiles/SketchNode.swift`, replace:

```swift
        for (id, spec) in SketchSockets.exposed(sketch) where inputs.has(spec.name) {
```

with:

```swift
        let references = inputs.has("references") ? try inputs.solids("references") : []
        warnings += SketchProjections.resolve(&sketch, settings: context.node.inputValues, references: references, on: plane)
        for (id, spec) in SketchSockets.exposed(sketch) where inputs.has(spec.name) {
```

The S1 solver already skips every constraint and dimension on an entity whose `ProjectionSource.isSuspended` is true (it reports them in `SketchSolution.suspended`), and S2's regions ignore suspended projections. So suspension is just setting the flag.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter "SketchProjectionTests|SketchNodeTests|SketchIntegrationTests"`
Expected: PASS: 15 `SketchProjectionTests`, three of them on OCCT (the two parameterized ones run 2 and 4 cases). `EdgeTagMatchTests` still pass unchanged.

- [ ] **Step 7: Update CLAUDE.md, the sketcher spec and the handoff note**


In `CLAUDE.md`, replace:

```markdown
M3 (the 26 nodes) and S3 (profile holes) are done.
```

with:

```markdown
M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done.
```

In `CLAUDE.md`, replace:

```markdown
- `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
  `.mcgraph` files, `DocumentModel`.
- `CreatorNodes`: the 26 built-in node definitions (`BuiltInNodes.registry`), UI-free: inspector sections and handles
  are data. Non-socket settings (`NodeSetting` in CreatorGraph: parameter, picks, showHandle) live in `Node.inputValues`;
  `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
```

with:

```markdown
- `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
  `.mcgraph` files, `DocumentModel`. Depends on `CreatorSketch` for the `ConstantValue.sketch` setting. A node's inputs
  are `NodeDefinition.inputs(for: node)` (default: the static `inputs`); the Evaluator and `connectionProblem` read
  it, so per-node sockets (the Sketch node's exposed dimensions) wire and gather like declared ones.
- `CreatorNodes`: the 28 built-in node definitions (`BuiltInNodes.registry`: the slice's 26 plus Plane from Face and
  Sketch), UI-free: inspector sections and handles are data. Non-socket settings (`NodeSetting` in CreatorGraph:
  parameter, picks, showHandle, sketch, face, and `projection(reference)` per projected edge) live in
  `Node.inputValues`; `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
```

In `CLAUDE.md`, replace:

```markdown
File format is version 3 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero).
```

with:

```markdown
File format is version 4 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
4 added the `.sketch` and `.facePick` settings).
A `Segment2D.arc` with `end < start` runs clockwise (a sketch region's notch); the shim builds it reversed and
`length` is positive. Edges carry `EdgeInfo.curve` (`EdgeCurve`, lines and circles) for sketch projection; a
`FacePick` names faces by tag subset like `EdgePick`. The Sketch node solves on every evaluation from the stored
sketch's warm start; writing `Sketch.remember` back into the setting is the editor's job (S5).
```

Append to `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md`:

```markdown
## Errata (S4)

- §6's deferred clockwise-arc case is taken in S4: a `Segment2D.arc` with `end < start` runs clockwise, `build_edge`
  builds it as the counter-clockwise arc from `end` to `start`, reversed, and `Segment2D.length` is positive. A
  region with a notch (a counter-clockwise outline running along an arc the other way) extrudes and revolves.
- §6's format bump: S4 takes `GraphFile.currentFormatVersion` 3 → 4 for `ConstantValue.sketch` and `.facePick`. If
  another branch bumps the version first, whichever merges second takes the next number (the constant, the test
  `savedFilesCarryTheCurrentFormatVersion`, the doc comment on the constant and the CLAUDE.md line).
- §7's exposed-dimension sockets come from `NodeDefinition.inputs(for: node)` (CreatorGraph), in dimension-name order,
  defaulting to the stored value. A dimension named like a fixed input (`plane`, `references`), a setting, a
  `projection.` setting, empty or repeated is not exposed, and the node warns. The graph panel draws a node's
  static `inputs` until S5 switches `NodeShape` and the inspector to `inputs(for:)`, so exposed sockets can be wired
  (by `Graph.apply(.connect)`) but aren't drawn yet.
- §7's "pick data for projected edges" is one setting per projection, `NodeSetting.projection(reference)` =
  `"projection.<reference>"`, holding `.edgePicks([pick])`. The pick resolves by tag subsets across every
  `references` solid and must name exactly one edge; a changed match count is a warning (parent spec §5.3 rule 6).
  A reference dimension on a suspended projection would measure the curve stored in the sketch (S4 never refreshes
  it), so it isn't output: `measurements` is empty and the node warns naming it. The same holds for a reference
  dimension that doesn't fit its geometry (a length on a projected circle), so list positions never shift.
- §7's Plane from Face stores its face as `NodeSetting.face` = `.facePick(FacePick)`, the picked face's whole tag set
  (`Topology.facePick(for:)`), matched as a subset like an edge pick. Its "nearly parallel" threshold: world X is
  used unless its in-plane part is shorter than 1e-3.
- §7's Sketch node has no inspector controls in S4 ("Edit sketch" is S5) and Plane from Face has no "Pick face in
  view…" button: the app's `pickFacesInView` still refuses, so the button waits for the app to write `.facePick`.
- §7's under-constrained warning reads "The sketch has N degrees of freedom left, so it isn't fully constrained."; an
  empty sketch warns "Draw a closed shape in the sketch to make a profile."; a fixed-plane sketch with a wired
  `plane` warns that the wire has no effect.
- §7's evaluate does not store the solve's warm start: it solves from the stored sketch every time, so results don't
  depend on evaluation history. S5's editor writes `Sketch.remember(_:)` into the setting after each edit.
```

In `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`, replace:

```markdown
## S4 (Sketch node)
```

with:

```markdown
## S4 (Sketch node) — done; picked up as below (plan `docs/superpowers/plans/2026-10-09-sketcher-s4-sketch-node.md`)
- The clockwise-arc case is taken: the shim builds an arc with `end < start` clockwise, so notched regions extrude.
- Every item below is implemented by `SketchNode`, `SketchSolve`, `SketchProjections` and `SketchSockets` in
  `Sources/CreatorNodes`; the sketcher spec's Errata (S4) lists the choices.

## S4 → S5 (editor)
- Draw exposed-dimension sockets: `NodeShape(_:in:registry:)` and `InspectorBuilder` read `definition.inputs`; switch
  them to `definition.inputs(for: node)`.
- After each edit, store `Sketch.remember(SketchSolver.solve(sketch))` in the `sketch` setting as one `setInput`, so the
  node's solve warm-starts from what the user sees (the node itself never writes the setting).
- Project writes `.edgePicks(topology.picks(for: [edge]))` under `NodeSetting.projection(reference)` and wires the
  picked edge's solid into `references`. A new projection's `reference` must be unique in the sketch.
- "New sketch on face" writes `.facePick(topology.facePick(for: face))` into a new Plane from Face's `face` setting and
  wires its `plane` into a Sketch whose plane is `.wired`. `AppModel.handle(.pickFacesInView)` still refuses.
- Dimension names: `SketchSockets.isReserved` names the ones that can't be sockets; refuse them when renaming.

## S4 (Sketch node), as handed over by S1–S2
```

S4 adds no views, but the palette now lists 28 nodes and the two new ones draw and evaluate in the app, so one smoke check goes to a person.

Append to `docs/verification/human-checks.md`:

```markdown
## Group S4 — the Sketch and Plane from Face nodes (S4)

**Status: NOT RUN.** S4 adds no views; this checks that the two new nodes reach the running app.

Run `swift run MetalCreatorApp`, with the preview mode set to Selected node.

- [ ] **S4-1 The new nodes in the palette.** Open the add-node palette over the canvas and search "sketch", then
  "face": Sketch and Plane from Face are listed. Add both. Sketch draws with inputs `plane` and `references` and
  outputs `profiles` and `measurements`; select it: its badge is a warning, "Draw a closed shape in the sketch to make
  a profile.", and the viewport shows nothing. Plane from Face draws with input `solid` and output `plane`; select it:
  its badge is an error until a solid is wired. Wire an Extrude's solid into it and select it again: the error reads
  "Pick a face for this plane to sit on." Nothing crashes, Undo removes each node, and Save then Open keeps both.
  Known (S5): exposed-dimension sockets aren't drawn, and neither node has inspector controls of its own. Pinned:
  `theBuiltInsAreTheSliceAndTheSketcherNodesInSixCategories`, `aNewSketchHoldsAnEmptySketchOnXYAndAsksForAShape`,
  `aMissingUnreadableOrStalePickIsAPlainError`, `aSketchSettingRoundTripsThroughAFile`. **Observed:**
```

`docs/metalui-gaps.md` is unchanged: S4 has no UI, so it hit no MetalUI gap.

- [ ] **Step 8: Run the gate**

Expected: no new warnings, **984 tests** (master + 83), SwiftLint clean.

- [ ] **Step 9: Commit**

```bash
git add Sources/CreatorNodes Tests/CreatorNodesTests CLAUDE.md docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md \
  docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md docs/verification/human-checks.md
git commit -m "feat(nodes): project model edges into sketches; document S4"
```

---

## Self-Review

**Spec coverage** (sketcher spec, every rule it gives S4):
- §2 `CreatorGraph` "`ConstantValue.sketch(Sketch)`; `GraphFile.currentFormatVersion` bumped": Task 4 (and `.facePick`, the other new kind).
- §2 `CreatorNodes` "+ `CreatorSketch`: Sketch node and Plane from Face node": Task 4 (`Package.swift`), Tasks 5 and 6.
- §2 boundary "`CreatorSketch` never imports anything but `CreatorGeometry`": Task 4 adds only `Sketch+Finite`/`SketchEntityKind+Finite` (CreatorGeometry); projection lives in `CreatorNodes` (Task 7).
- §3 "saved inside the `.mcgraph` file", deterministic encoding (handoff): Task 4 `aSketchSettingRoundTripsThroughAFile`, `aSavedSketchIsByteIdenticalWhenSavedAgain`.
- §3 `ProjectionSource` "holds an `EdgePick` … plus the cached 2D geometry": the pick is the node setting `projection.<reference>` (Task 4 names it, Task 7 resolves it). Decision recorded in the spec's Errata (S4).
- §6 "S4 adds `ConstantValue.sketch(Sketch)` and bumps it again, to 4": Task 4, with the merge-order ruling.
- §6 "A clockwise-arc segment case is deferred unless S4 needs it" and the handoff's notch: decided yes, Task 1 (shim, `length`), proven through the node in Task 6 (`aNotchedSketchRegionExtrudes`).
- §7 Sketch sockets (`plane` optional, `references` optional list, one input per exposed dimension, `profiles` list, `measurements` list in name order): Task 6 (`anExposedDimensionIsANumberInputNamedAfterIt`, `referenceDimensionsComeOutAsMeasurementsInNameOrder`), Task 2 (the mechanism).
- §7 "a wired value overrides the stored one": Task 6 `aWiredValueDrivesItsExposedDimension`, `aListIntoAnExposedDimensionBroadcastsOneProfilePerValue`.
- §7 Evaluate "apply wired dimension values, resolve projected edges against `references`, solve, find regions, output": Tasks 6 and 7, in that order in `SketchNode.evaluate`.
- §7 States: under-constrained `.warning` (Task 6), open curves `.warning` (Task 6 `openCurvesWarn`), projected edge matching nothing or several `.warning` with suspended constraints (Task 7), over-constrained and failed `.error` (Task 6).
- §7 Projection v1 (lines; circles and arcs with axis ∥ normal; others refused with a plain warning): Task 7 `EdgeProjection` tests.
- §7 Plane from Face (inputs, centroid origin, face normal, deterministic xAxis with the Y fallback, non-planar or no match `.error`, several matches `.warning` and first by ID): Task 5.
- §7 "New sketch on face creates a Plane from Face node wired into a new Sketch node": the graph half is Task 6 `aSketchOnAFaceFollowsTheFaceWhenTheModelChanges`. The menu item is S5 (handoff note).
- §9 S4 row (`ConstantValue.sketch`, Sketch node, Plane from Face node, projection): Tasks 4–7.
- §10 Integration (OCCTKernel): Sketch → Extrude (Task 6, two tests); an exposed dimension changes the part and downstream edge picks keep their keys (Task 6 `anExposedDimensionChangesThePartAndDownstreamPicksKeepTheirKeys`); a projected edge survives an upstream width change, and follows a depth change that moves it (Task 7 `aProjectedEdgeSurvivesAnUpstreamWidthChangeOnOCCT`); real circle and arc edges project through the node from either rim and onto a plane facing either way (Task 7 `aCylinderRimProjectsToItsCircleOnOCCT`, `aCornerArcProjectsCounterClockwiseFromEitherRimOnOCCT`); Plane from Face follows a moved face (Task 5 `thePlaneFollowsTheFaceWhenTheModelChanges`, and through a Sketch in Task 6).
- Handoff S4 items: projection refresh before solving, statuses → states, every conflict message shown, `.sortedKeys`, angle senses untouched (the node keeps `angleSense` as stored), monotonic names (sockets keyed by name), `.failed` for collapse and NaN (Task 6 `aNonFiniteWiredValueIsAPlainError`), `remember` before regions (`SketchSolve`), the open-curve warning text.
- Out of scope by the task statement: the 2D editor UI (S5) and every `CreatorEditor` view. The S5 items this plan leaves are listed in the handoff note (Task 7 Step 7).

**Placeholder scan:** every step names exact files. Every code step has complete code. Every run step has the command and its expected result. There are no "TBD", "similar to" or unnamed helpers.

**Type consistency:** `NodeDefinition.inputs(for:)` (Task 2) is used by `SketchNode.inputs(for:)` (Task 6). `EdgeCurve` cases and labels (`.line(start:end:)`, `.circle(center:axis:radius:start:sweep:)`) are identical in Task 3's kernel, shim reader and fake, and in Task 7's `EdgeProjection`. `NodeSetting.sketch`, `.face`, `.projection(_:)` and `.projectionPrefix` (Task 4) are used with those names in Tasks 5–7. `FacePick(tags:)`, `faces(matching:)` and `facePick(for:)` are used by Task 5 and the Task 6 face test. `SketchSockets.exposed`/`refused`/`isReserved` and `SketchSolve.run`/`Output`/`nothingDrawn` match between Task 6 and Task 7's edits. The fixture `RectangleSketch` (`lines`, `corners`, `width`, `height`, `addHole`, `expose`) is defined once, in Task 6.

**Review Focus:** each of the six lines has its test in the owning task (listed in the section). The checks for an empty sketch and for a plane wired into a fixed-plane sketch are pinned too.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-09-sketcher-s4-sketch-node.md`. Please review the plan. Which execution approach would you prefer?

- **Subagent-driven:** a fresh subagent implements each task and a fresh reviewer checks it before the next one starts, then a whole-branch review at the end. Most thorough; costs a fresh context per task and per review.
- **Native:** one session implements every task, then one fresh reviewer on the most capable model checks the whole branch. Cheapest and fastest; no independent review until the end.

For this plan I recommend **subagent-driven**, because Tasks 6 and 7 build on interfaces from four earlier tasks across five modules and the shim, and a shipped mistake in the format version or the shim's arc orientation would reach users' files and parts.
