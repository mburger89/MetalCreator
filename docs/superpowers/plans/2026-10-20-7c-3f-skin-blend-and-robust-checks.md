# 7c-3f: A Blended Skin Join and Robust Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the lightweight bracket meet the spec's "0 voids, no thin walls" by blending the skin into the lattice (a `blend` input on the TPMS, Strut and Voronoi nodes) and by making Check Trapped Volumes and Check Thin Walls robust where the sheet meets the skin (spec Errata D18, which resolves M5).

**Architecture:** `LatticeFill` joins the skin and the lattice with the kernel's existing smooth union of radius `blend` (default 1 mm on a new node; a node saved before 7c-3f is migrated to 0, the sharp join, through `typeVersion` 2). Check Trapped Volumes fills its occupancy grid from the mesh's unsigned distance and decides, once per pocket the flood fill leaves, whether the pocket is material or a cavity from the generalized winding number (a new `WindingNumber`: exact near the point, BVH-cluster dipoles far from it); the pseudonormal sign stays for the bake. Check Thin Walls skips a ray hit nearer than 0.05 mm on a face that touches the start vertex's one-ring and lets the ray go on.

**Tech Stack:** Swift 6.2 strict concurrency, Swift Testing, SwiftPM (`CreatorNodes`, `CreatorImplicit`, `CreatorAppTests`). No new dependencies, no UIKit, no MetalUI change (no new MetalUI gap).

**Spec:** `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md`, erratum **D18** (binding; read it first), with M5 (resolved by this track), M6 and D16, under the parent `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` and all its Errata. Diagnosis data: `scratchpad/exp_all.txt`, `exp2_all.txt` and `probe*.log` of the planning session (the numbers are quoted in D18 and below).

**Branch and worktree:** `7c-3f` in `/Users/maxburger/Developer/MetalCreator-7c3f`, off master `6072fc6` (4593 tests). Run every command from that worktree. Never edit `Package.swift`'s MetalUI path, never touch `../MetalUI`, never take screenshots. Do not `pkill` by a broad pattern (`swift-test`, `swift-build`, `xctest`): other sessions run tests on this Mac; kill only your own processes by captured PID.

**Files shared with other tracks.** The only other code track, c14c-adopt, touched `BoxSelectionView`, `CanvasLayers`, `CanvasContentSkipWindowTests`, `xp.yml` and docs, and **it has already merged into master** (`d43f57f`), so 7c-3f is the side that merges second. s7-adopt, also in master (`5adcfe4`; it touches `LaunchCommand`, `main.swift` and `xp.yml`), shares no file with 7c-3f. No source or test file is shared. Three record files are shared, and master's edits there are in different paragraphs from ours:
- `CLAUDE.md`: master rewrote the MetalUI C14-c paragraph (the `.equatable()` / `@Environment` text about `BoxSelectionView`, pin `fa6464ba`). 7c-3f edits the 7c-3 paragraph area (a new 7c-3f paragraph after it), the `SignedDistanceMesh` sentence, the mesh-tools sentence, the lattice-nodes sentence and the `typeVersion` sentence near the end of the editor section. **Keep master's C14-c wording whole and ours whole; on a conflict take both.**
- `docs/verification/human-checks.md`: master added XP-15 (group XP); we add IL-10 (group IL) and amend MT-9. Keep both.
- `docs/verification/performance.md`: master appended a C14-c sentence to the canvas-skip paragraph; we add the i-8 row, the "runs rows i-1 to i-8" words and a new subsection before "Raw output". Keep both.
The spec file (`docs/superpowers/specs/2026-10-13-implicit-lattices-design.md`) and `docs/roadmap.md` are ours alone; the D18 commit `6072fc6` exists only on this branch (master's spec lacks D18), so the merge brings it in. **The side that merges second (this branch) keeps both sides of every conflict in the three record files and then reruns the Task 6 anchor check (Task 7, Step 3): each `replace` text of Task 6 must still match exactly once.** On master `d43f57f` every anchor does (checked), except the one in the spec that D18's own commit adds.

## Global Constraints

- Target iOS 26 / macOS; Swift 6.2 or later, strict concurrency; async/await, never GCD; `@MainActor @Observable` models; no `ObservableObject`.
- No third-party frameworks; no UIKit.
- Swift Testing (`@Test`, `#expect`), not XCTest; one type per file; no force unwraps or force `try` outside tests that `#require`.
- `FormatStyle` for numbers and dates, never `String(format:)`, `DateFormatter` or `NumberFormatter`.
- `swiftlint lint --strict` must report zero violations (line length 140, trailing commas required).
- The Swift 6.4 Windows compiler crashes (`CoroFrame.cpp`, "Layout->getElementOffset") in `async` functions that hold a loop's locals across an `await`: keep heavy loops in non-async helpers, and in tests use one parametrized case per value instead of a loop around an `await`.
- A MetalUI gap goes into `docs/metalui-gaps.md` (the entry and the summary-table row) and is never worked around. This track found none.
- Verification (the user's decision): per task run `swift build --build-tests`, then `swift test --filter` on the suites the task adds or touches, then `swiftlint lint --strict`. Run **one** full macOS `swift test`, at the end (Task 7).
- A full `swift test` passes only if the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and **12** "Test run with" lines appear on macOS (Linux and Windows CI expect 11; the twelfth is `CreatorOCCTTests`).
- Spec D18, verbatim where it binds the numbers: the `blend` input is in mm, default 1.0, and a file saved before 7c-3f reads it as 0; a cell's inside comes from the generalized winding number (inside if ≥ ½) or an equally robust test, "never from the pseudonormal sign alone"; Check Thin Walls skips a hit closer than 0.05 mm on a face sharing a vertex or edge with the start's one-ring; real knife edges are still reported; the acceptance test asserts 0 voids and no thin walls at the default blend; the volume fraction stays inside 15 to 75 %.
- i-5 (Decimate, under 10 s) and i-6 (Mesh to Solid, under 15 s) in `docs/verification/performance.md` must still be met.

## Review Focus

Input classes and failure modes the spec implies; each has a test in the task named.

1. **A graph saved before 7c-3f must open with the geometry it was saved with.** Version-1 lattice nodes have no `blend` key; the socket's default is 1.0, so without the migration an old graph would silently change shape. Task 1: `aFileWithoutABlendKeyReadsZeroAndKeepsItsGeometry` (also pins that a hand-edited version-2 node without the key reads the socket's 1 mm and is not rewritten).
2. **A bad `blend` (negative, NaN, infinite) or a `blend` with no skin.** It must be refused with a message, or change nothing. Task 1: `aNegativeOrNonFiniteBlendIsRefused` (3 values times 3 nodes), `withoutASkinTheBlendChangesNothing`.
3. **A mesh that overlaps itself must still have an inside, and a cavity must still be a void.** The pseudonormal sign flips in a wedge narrower than the mesh cell; a winding number of a hollow part is 0 in the cavity. Task 2: `aMeshThatOverlapsItselfStillHasAnInside`, `aCavityIsWoundTheOtherWayAndSoIsNotInside`; Task 3: `aWedgeOfSheetOnSkinIsNotAVoid`, `everyVoidItFindsIsAirOutsideThePart`, and the existing `aSealedVoidIsFoundAndItsWallsAreTheOnesThatLookIntoIt`.
4. **A real thin wall or knife edge must still be reported after the self-hit rule.** Skipping hits near the start vertex must not hide a 0.2 mm wall, a plate on other vertices 0.01 mm away, or a knife edge away from its tip. Task 4: `aKnifeEdgeIsStillReportedAwayFromItsTip`, `aPlateOutsideTheNeighbourhoodIsAWallHoweverClose`, `aFoldBesideTheVertexFartherThanTheLimitIsTheWall`, and the existing `aWallOfAFifthOfAMillimetreIsFoundWhereverTheCubeHasOne`.
5. **A big mesh must not turn the check into minutes, and degenerate grids must not be asked.** A winding number at every cell is 23 to 35 times the cost of the pseudonormal sign (18.5 s and 138.6 s on 0.55 and 2.55 million triangles). Task 3: `theOutsideAndAOneCellPocketAreNeverAsked`, `aRegionTheCallerSaysIsInsideIsMaterialAndNotAVoid` (once per pocket, five cells), `aPocketBiggerThanTheJudgingSizeIsJudgedBeforeItIsListedInFull` (a thick part's interior is not listed in full); Task 5: bench row i-8 times both checks and rows i-7s and i-7h the memory of a solid and of a hollow 150 mm cube through the whole check.

## File Structure

New files:
- `Sources/CreatorImplicit/Bake/WindingNumber.swift`: the generalized winding number of a closed mesh over the existing `TriangleBVH`, with dipole clusters (Task 2).
- `Sources/CreatorImplicit/Bake/LazyWindingNumber.swift`: builds that winding number on the first question, so To Implicit's bake never pays for the clusters (Task 2).
- `Tests/CreatorNodesTests/Implicit/LatticeSkinBlendTests.swift`: the `blend` input, its default, the smooth union, the file round trip and the missing key (Task 1).
- `Tests/CreatorImplicitTests/WindingNumberTests.swift`: the winding number against the exact sum, a cavity, an empty mesh (Task 2).
- `Tests/CreatorImplicitTests/TrappedVolumePhantomTests.swift`: the phantom-void wedge fixture and its tests (Task 3).
- `Tests/CreatorImplicitTests/Support/MeshFixtures+Wedge.swift`: a knife-edge wedge mesh for Check Thin Walls (Task 4).
- `Tests/CreatorAppTests/Bench/ImplicitBenchChecks.swift`: bench rows i-8, i-7s and i-7h (Task 5).

Modified files:
- `Sources/CreatorNodes/Implicit/Lattices/LatticeFill.swift`, `LatticeSetup.swift`, `TPMSNode.swift`, `StrutLatticeNode.swift`, `VoronoiLatticeNode.swift` (Task 1).
- `Sources/CreatorImplicit/Bake/SignedDistanceMesh.swift`: `unsignedDistance`, `windingNumber`, `isInside`, `robustSignedDistance` (the winding number is built lazily); the pseudonormal sign stays and is documented (Task 2).
- `Sources/CreatorImplicit/Mesh/Checks/EnclosedVoids.swift`, `TrappedVolumeCheck.swift`, `OccupancyGrid.swift` (comment), `DrainHoles.swift` (comment) (Task 3).
- `Sources/CreatorImplicit/Mesh/Checks/ThinWallCheck.swift` (Task 4).
- `Tests/CreatorImplicitTests/SignedDistanceMeshTests.swift`, `OccupancyGridTests.swift`, `DrainHolesTests.swift`, `ThinWallCheckTests.swift`; `Tests/CreatorAppTests/LightweightBracketAcceptanceTests.swift`, `Bench/ImplicitBench.swift`, `Bench/ImplicitBenchFixtures.swift`, `Bench/ImplicitBenchFixturesTests.swift` (Tasks 2 to 5).
- Records (Task 6): the spec (M5, D18), `docs/roadmap.md`, `CLAUDE.md`, `docs/verification/human-checks.md`, `docs/verification/performance.md`.

Test count: this plan adds 28 test functions (Task 1: 6, Task 2: 7, Task 3: 7, Task 4: 4, Task 5: 4, the last counting bench rows i-8, i-7s and i-7h). A parametrized test counts once. The bench suite is skipped without `METALCREATOR_BENCH=1`, but its tests still appear in the "Test run with" totals (i-7s and i-7h added 2 to the app target's count). The final full macOS run measured **4620** tests (verification record). The brief gives master `6072fc6` as 4593, and 4593 + 28 is 4621, so master's own count is 4592 by subtraction, or one function is not counted separately; master was not re-run here, so the discrepancy of one is not attributed. `thePseudonormalSignFindsAPhantomVoidInTheSameMesh` is macOS-only (Task 3), so Linux and Windows run one test fewer.

## Measured facts the plan rests on

- The 103 voids and 127 thin places of M5 are phantoms of the sharp join and of the checks (D18). Old checks with the node's blend: r 0.5 gives 1 void, 5 thin places, 67.8 %; r 1.0 gives 1, 1, 70.0 %; r 1.5 gives 0, 0, 73.5 %. With the robust checks r 1.0 gives **0 voids, 0 thin places, 70.04 %** (release run of `LightweightBracketAcceptanceTests`, 47 s), so the node default of 1.0 is enough and the bracket's blend is not raised.
- Cost of the inside test (release, `docs/verification/performance.md`): pseudonormal per cell 0.81 s and 3.92 s; winding number per cell 18.5 s and 138.6 s; unsigned distance plus the winding number once per pocket 0.81 s and 3.91 s (555 k and 2.55 M triangles). The plan ships the last.
- i-5 7.04 s of 10 s, i-6 14.36 s of 15 s, i-7 3.65 s with 738 MB peak resident: unchanged by this track, still met.

---

### Task 1: The `blend` input on the three lattice nodes

The skin joins the lattice with a smooth union of radius `blend`. `typeVersion` goes to 2 on TPMS, Strut Lattice and Voronoi Lattice; their `migrate` stores a `blend` of 0 on a node saved as version 1, so a saved graph's geometry does not change (the precedent is Regular Polygon's `rotation`, but its default was the old behaviour; here the new default, 1 mm, differs from the old behaviour, so the migration must store 0 explicitly). A new node has no `blend` in `inputValues`, so it reads the socket's default of 1.

**Files:**
- Create: `Tests/CreatorNodesTests/Implicit/LatticeSkinBlendTests.swift`
- Modify: `Sources/CreatorNodes/Implicit/Lattices/LatticeFill.swift`, `LatticeSetup.swift`, `TPMSNode.swift`, `StrutLatticeNode.swift`, `VoronoiLatticeNode.swift`

**Interfaces:**
- Consumes: `ImplicitSolid.union(_:blend: Grading)` and `Grading.constant(_:)` (existing; a union's bounds grow by a quarter of the blend radius, its lipschitz bound is unchanged for a constant blend); `Harness` (the CreatorNodesTests helper with `add`, `wire`, `run`, `graph`); `NodeDefinition.migrate(_:from:)` and `GraphFileIO.decode`, which calls it for every node whose `typeVersion` is below its definition's.
- Produces: `LatticeSetup.blendSocket: SocketSpec` (`"blend"`, `.number`, default 1, mm, 0...5), `LatticeSetup.blend(_ inputs: NodeInputs) throws -> Double` (refuses a negative or non-finite value with “blend” must be 0 or more.), `LatticeSetup.sharpJoin(_ node: Node) -> Node` (stores 0 when the key is absent), `LatticeFill.fill(region:lattice:skin:blend:)`, and `typeVersion` 2 on the three nodes.

The `blend` control sits beside `skin` in each node's inspector, as a `.number` like the other mm inputs. It is a number socket, not a field socket, like `skin` and the Strut Lattice's `node blend` (the lattice's graded settings, `cell size`, `thickness` and `strut radius`, are fields; the join's radius is not graded). The Strut Lattice already has `node blend` (the rounding of its struts' joints); the new input is named `blend` as D18 says, and each node's help text says what it joins.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorNodesTests/Implicit/LatticeSkinBlendTests.swift` (new):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The blended join between a lattice's skin and its lattice (implicit spec Errata D18): the `blend` input on the three lattice nodes,
/// its default of 1 mm on a new node, and the 0 (the sharp join) that a graph saved before 7c-3f reads.
struct LatticeSkinBlendTests {
    /// The three lattice nodes, each with settings that give a lattice inside a 40 mm cube with a 1.5 mm skin.
    static let nodes: [(definition: any NodeDefinition.Type, settings: [SocketName: ConstantValue])] = [
        (TPMSNode.self, ["skin": .number(1.5), "cell size": .number(8), "thickness": .number(1)]),
        (StrutLatticeNode.self, ["skin": .number(1.5), "cell size": .number(8), "strut radius": .number(0.6)]),
        (VoronoiLatticeNode.self, ["skin": .number(1.5), "count": .integer(30), "thickness": .number(0.8)]),
    ]

    /// A 40 mm cube wired into a lattice node of `definition`.
    func lattice(_ h: inout Harness, _ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue]) -> Node {
        let cube = h.add(ImplicitBoxNode.self, ["size": .vector(Vector3(40, 40, 40))])
        let node = h.add(definition, values)
        h.wire(cube, "implicit", to: node, "region")
        return node
    }

    func solid(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue]) async throws -> ImplicitSolid {
        var h = Harness()
        let node = lattice(&h, definition, values)
        return try #require(try await h.run([node]).implicitSolid(node))
    }

    /// Points through the layer round the skin's inner face (x = 18.5) where the lattice meets it: 0.25 mm apart across the layer, 1.1 mm
    /// apart along it.
    static let samples: [Vector3] = (-6...6).flatMap { layer in
        (-15...15).flatMap { j in (-15...15).map { k in Vector3(18.5 + Double(layer) * 0.25, Double(j) * 1.1, Double(k) * 1.1) } }
    }

    /// Whether two solids agree at every sample, and where the first differs: the points and values.
    static func agree(_ a: ImplicitSolid, _ b: ImplicitSolid) -> Bool {
        samples.allSatisfy { abs(a.signedDistance(at: $0) - b.signedDistance(at: $0)) < 1e-12 }
    }

    @Test(arguments: Self.nodes.indices) func aNewNodeHasABlendOfOneMillimetre(_ index: Int) throws {
        let definition = Self.nodes[index].definition
        let spec = try #require(definition.inputs.first { $0.name == "blend" })
        #expect(spec.type == .number && spec.defaultValue == .number(1) && spec.unit == .millimetres)
        #expect(definition.typeVersion == 2)
        #expect(definition.inspector.flatMap(\.controls).contains(.number("blend")), "the inspector shows it like the skin")
    }

    @Test(arguments: Self.nodes.indices) func theSkinJoinsTheLatticeWithASmoothUnionOfTheBlendRadius(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        let blended = try await solid(definition, settings)
        #expect(blended.description.contains("blend 1 mm"), "the default 1 mm: \(blended.description)")
        let sharp = try await solid(definition, settings.merging(["blend": .number(0)]) { _, given in given })
        #expect(sharp.description.hasPrefix("union(shell("), "blend 0 is the sharp union: \(sharp.description)")
        #expect(!sharp.description.contains("blend 1 mm"))
        // A smooth union is never farther than the sharp one, and is nearer where the two parts meet.
        let pairs = Self.samples.map { (blended.signedDistance(at: $0), sharp.signedDistance(at: $0)) }
        #expect(pairs.allSatisfy { $0.0 <= $0.1 + 1e-9 }, "never farther than the sharp union")
        #expect(pairs.contains { $0.0 < $0.1 - 0.05 }, "the join fills the crease between the skin and the lattice")
    }

    @Test(arguments: Self.nodes.indices) func withoutASkinTheBlendChangesNothing(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        let plain = settings.merging(["skin": .number(0)]) { _, given in given }
        let one = try await solid(definition, plain)
        let five = try await solid(definition, plain.merging(["blend": .number(5)]) { _, given in given })
        #expect(one.description == five.description && Self.agree(one, five))
    }

    /// One case per blend, not a loop: the Windows 6.4 toolchain asserts on an async function that holds a loop's locals across an await.
    @Test(arguments: Self.nodes.indices, [-1.0, Double.nan, Double.infinity])
    func aNegativeOrNonFiniteBlendIsRefused(_ index: Int, _ bad: Double) async throws {
        let (definition, settings) = Self.nodes[index]
        var h = Harness()
        let node = lattice(&h, definition, settings.merging(["blend": .number(bad)]) { _, given in given })
        #expect(try await h.run([node]).error(node) == "“blend” must be 0 or more.", "\(bad)")
    }

    // MARK: Files

    @Test(arguments: Self.nodes.indices) func theBlendSurvivesASaveAndReopen(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        var h = Harness()
        let node = lattice(&h, definition, settings.merging(["blend": .number(2.5)]) { _, given in given })
        let data = try GraphFileIO.encode(GraphFile(graph: h.graph))
        let file = try GraphFileIO.decode(data, registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[node.id])
        #expect(loaded.typeVersion == 2 && loaded.inputValues["blend"] == .number(2.5))
        #expect(file.graph.nodes == h.graph.nodes)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel()).evaluate(file.graph, demand: [node.id])
        #expect(try #require(report.implicitSolid(node)).description.contains("blend 2.5 mm"))
    }

    /// A graph saved before 7c-3f has no `blend` and node version 1: it reads 0, so its geometry does not change.
    @Test(arguments: Self.nodes.indices) func aFileWithoutABlendKeyReadsZeroAndKeepsItsGeometry(_ index: Int) async throws {
        let (definition, settings) = Self.nodes[index]
        var h = Harness()
        var old = lattice(&h, definition, settings)
        old.typeVersion = 1
        old.inputValues["blend"] = nil
        var graph = h.graph
        graph.nodes[old.id] = old
        let data = try GraphFileIO.encode(GraphFile(graph: graph))
        let file = try GraphFileIO.decode(data, registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[old.id])
        #expect(loaded.typeVersion == 2)
        #expect(loaded.inputValues["blend"] == .number(0), "an old node keeps the sharp join")
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel()).evaluate(file.graph, demand: [old.id])
        let reopened = try #require(report.implicitSolid(old))
        let sharp = try await solid(definition, settings.merging(["blend": .number(0)]) { _, given in given })
        #expect(reopened.description == sharp.description && Self.agree(reopened, sharp), "\(reopened.description)")
        #expect(!reopened.description.contains("blend 1 mm"))
        // A node already at version 2 whose file lacks the key (hand-edited) is not rewritten, and reads the socket's 1 mm.
        var current = old
        current.typeVersion = 2
        graph.nodes[old.id] = current
        let again = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph)), registry: BuiltInNodes.registry)
        #expect(again.graph.nodes[old.id]?.inputValues["blend"] == nil)
    }
}
```


- [ ] **Step 2: Run them and see them fail**

Run: `swift build --build-tests` (it builds: the tests use only API that exists).
Run: `swift test --filter LatticeSkinBlendTests 2>&1 | grep -E "recorded an issue|Test run with"`
Expected: FAIL. `aNewNodeHasABlendOfOneMillimetre`, `theSkinJoinsTheLatticeWithASmoothUnionOfTheBlendRadius`, the refusal, round-trip and missing-key tests record issues (no `blend` input yet, `typeVersion` is 1).

- [ ] **Step 3: Implement**

`Sources/CreatorNodes/Implicit/Lattices/LatticeFill.swift`:

```diff
@@ -1,17 +1,20 @@
 import CreatorGeometry
 import CreatorImplicit
 
-/// What the three lattice nodes output (implicit spec §3.4): the lattice cut to the region, and with a skin the region's own wall as
-/// well, `Shell(region, inward, skin) ∪ (lattice ∩ Offset(region, −skin))`, which turns lightweighting into one node.
+/// What the three lattice nodes output (implicit spec §3.4, Errata D18): the lattice cut to the region, and with a skin the region's own
+/// wall as well, `Shell(region, inward, skin) ∪ (lattice ∩ Offset(region, −skin))`, which turns lightweighting into one node. The
+/// union is the kernel's smooth union of radius `blend`, so a sheet that meets the skin tangentially leaves no wedge narrower than a
+/// mesh cell; a blend of 0 is the sharp union.
 enum LatticeFill {
     /// - Parameters:
     ///   - region: the solid to fill.
     ///   - lattice: the lattice, already cut to the region's box.
     ///   - skin: the wall thickness in millimetres, 0 for none.
-    static func fill(region: ImplicitSolid, lattice: ImplicitSolid, skin: Double) -> ImplicitSolid {
+    ///   - blend: the radius in millimetres of the smooth union that joins the skin and the lattice. It has no effect without a skin.
+    static func fill(region: ImplicitSolid, lattice: ImplicitSolid, skin: Double, blend: Double) -> ImplicitSolid {
         guard skin > 0 else { return .intersect([region, lattice], blend: .constant(0)) }
         let wall = ImplicitSolid.shell(region, thickness: .constant(skin), side: .inward)
         let inside = ImplicitSolid.offset(region, distance: .constant(-skin))
-        return .union([wall, .intersect([lattice, inside], blend: .constant(0))], blend: .constant(0))
+        return .union([wall, .intersect([lattice, inside], blend: .constant(0))], blend: .constant(blend))
     }
 }
```

`Sources/CreatorNodes/Implicit/Lattices/LatticeSetup.swift`:

```diff
@@ -24,6 +24,24 @@ enum LatticeSetup {
         return skin
     }
 
+    /// The `blend` radius of the join between the skin and the lattice, in millimetres.
+    static func blend(_ inputs: NodeInputs) throws -> Double {
+        let blend = try inputs.number("blend")
+        guard blend.isFinite, blend >= 0 else { throw NodeError.invalidValue("“blend” must be 0 or more.") }
+        return blend
+    }
+
+    /// The socket the three lattice nodes share for the radius of the skin's join (Errata D18): 1 mm on a new node.
+    static let blendSocket = SocketSpec("blend", .number, defaultValue: .number(1), unit: .millimetres, range: 0...5)
+
+    /// The migration of a lattice node saved before `typeVersion` 2 (7c-3f): it had a sharp join, so it keeps one. A node that already
+    /// stores a blend is left alone.
+    static func sharpJoin(_ node: Node) -> Node {
+        var migrated = node
+        if migrated.inputValues["blend"] == nil { migrated.inputValues["blend"] = .number(0) }
+        return migrated
+    }
+
     /// The `cell size` field and the `cell stretch` of a lattice over `box`.
     static func cells(_ inputs: NodeInputs, over box: BoundingBox, kernel: any Kernel,
                       context: EvalContext) async throws -> (cells: LatticeCells, warnings: [String]) {
```

`Sources/CreatorNodes/Implicit/Lattices/TPMSNode.swift`:

```diff
@@ -8,11 +8,14 @@ import CreatorKernel
 /// a 7b field can grade them. With a `skin` the region keeps a wall of that thickness and the lattice fills the inside.
 public enum TPMSNode: NodeDefinition {
     public static let typeID = "creator.tpms"
+    /// 2: `blend` (7c-3f, Errata D18). A node saved as version 1 reads it as 0, the sharp join it was made with.
+    public static let typeVersion = 2
     public static let displayName = "TPMS"
     public static let category = NodeCategory.implicit
     public static let inputs = [
         SocketSpec("region", .implicit, optional: true),
         SocketSpec("skin", .number, defaultValue: .number(0), unit: .millimetres, range: 0...20),
+        LatticeSetup.blendSocket,
         SocketSpec("type", .integer, defaultValue: .integer(TPMSType.gyroid.rawValue)),
         SocketSpec("form", .integer, defaultValue: .integer(TPMSForm.sheet.rawValue)),
         SocketSpec("cell size", .field, defaultValue: .number(8), unit: .millimetres, range: 1...50),
@@ -23,18 +26,22 @@ public enum TPMSNode: NodeDefinition {
     /// The resolution warnings differ between a preview and an export, so the cache keys the node by the mesh quality.
     public static let readsMeshQuality = true
     public static let help = "Where the cell size field changes fast the pattern stretches, and the preview gets slower: the "
-        + "lipschitz bound grows with the field's slope. A network's thickness moves the level, so 0 fills half the region."
+        + "lipschitz bound grows with the field's slope. A network's thickness moves the level, so 0 fills half the region. "
+        + "“blend” rounds the join between the skin and the lattice; it does nothing without a skin."
     public static let inspector = [
         InspectorSection(title: "Surface", controls: [
             .segmented("type", options: TPMSType.options), .segmented("form", options: TPMSForm.options),
         ]),
         InspectorSection(title: "Cells", controls: [.number("cell size"), .vector("cell stretch")]),
-        InspectorSection(title: "Wall", controls: [.number("thickness"), .number("skin"), .note(help)]),
+        InspectorSection(title: "Wall", controls: [.number("thickness"), .number("skin"), .number("blend"), .note(help)]),
     ]
 
+    public static func migrate(_ node: Node, from version: Int) -> Node { LatticeSetup.sharpJoin(node) }
+
     public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
         let region = try LatticeSetup.region(inputs)
         let skin = try LatticeSetup.skin(inputs)
+        let join = try LatticeSetup.blend(inputs)
         let type = TPMSType(rawValue: try inputs.choice("type", options: TPMSType.options)) ?? .gyroid
         let form = TPMSForm(rawValue: try inputs.choice("form", options: TPMSForm.options)) ?? .sheet
         let box = region.bounds
@@ -46,7 +53,7 @@ public enum TPMSNode: NodeDefinition {
         var warnings = cellWarnings + wall.warnings + LatticeSetup.cellWarnings(cells, voxel: voxel)
         if form == .sheet { warnings += LatticeSetup.thinWarnings("Walls", thickest: wall.grading.range.upperBound, voxel: voxel) }
         warnings += ImplicitReach.warnings(for: region, reachedBy: skin)
-        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin)
+        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin, blend: join)
         return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
     }
 }
```

`Sources/CreatorNodes/Implicit/Lattices/StrutLatticeNode.swift`:

```diff
@@ -7,11 +7,14 @@ import CreatorKernel
 /// cell size and the strut radius are fields; `node blend` rounds the joints. With a `skin` the region keeps a wall of that thickness.
 public enum StrutLatticeNode: NodeDefinition {
     public static let typeID = "creator.strutLattice"
+    /// 2: `blend` (7c-3f, Errata D18). A node saved as version 1 reads it as 0, the sharp join it was made with.
+    public static let typeVersion = 2
     public static let displayName = "Strut Lattice"
     public static let category = NodeCategory.implicit
     public static let inputs = [
         SocketSpec("region", .implicit, optional: true),
         SocketSpec("skin", .number, defaultValue: .number(0), unit: .millimetres, range: 0...20),
+        LatticeSetup.blendSocket,
         SocketSpec("cell", .integer, defaultValue: .integer(StrutCell.cubic.rawValue)),
         SocketSpec("cell size", .field, defaultValue: .number(8), unit: .millimetres, range: 1...50),
         SocketSpec("cell stretch", .vector, defaultValue: .vector(Vector3(1, 1, 1))),
@@ -22,16 +25,22 @@ public enum StrutLatticeNode: NodeDefinition {
     /// The warnings about cells and walls depend on the voxel size, which differs between preview and export.
     public static let readsMeshQuality = true
     public static let help = "Where the cell size field changes fast the pattern stretches, and the preview gets slower: the "
-        + "lipschitz bound grows with the field's slope. A node blend of up to a quarter of the smallest cell is allowed."
+        + "lipschitz bound grows with the field's slope. A node blend of up to a quarter of the smallest cell is allowed. "
+        + "“blend” rounds the join between the skin and the lattice; it does nothing without a skin."
     public static let inspector = [
         InspectorSection(title: "Cell", controls: [.segmented("cell", options: StrutCell.options)]),
         InspectorSection(title: "Size", controls: [.number("cell size"), .vector("cell stretch")]),
-        InspectorSection(title: "Struts", controls: [.number("strut radius"), .number("node blend"), .number("skin"), .note(help)]),
+        InspectorSection(title: "Struts", controls: [
+            .number("strut radius"), .number("node blend"), .number("skin"), .number("blend"), .note(help),
+        ]),
     ]
 
+    public static func migrate(_ node: Node, from version: Int) -> Node { LatticeSetup.sharpJoin(node) }
+
     public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
         let region = try LatticeSetup.region(inputs)
         let skin = try LatticeSetup.skin(inputs)
+        let join = try LatticeSetup.blend(inputs)
         let cell = StrutCell(rawValue: try inputs.choice("cell", options: StrutCell.options)) ?? .cubic
         let box = region.bounds
         let (cells, cellWarnings) = try await LatticeSetup.cells(inputs, over: box, kernel: kernel, context: context)
@@ -52,7 +61,7 @@ public enum StrutLatticeNode: NodeDefinition {
             warnings.append("Struts are thicker than the cells; the lattice is solid.")
         }
         warnings += ImplicitReach.warnings(for: region, reachedBy: skin)
-        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin)
+        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin, blend: join)
         return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
     }
 }
```

`Sources/CreatorNodes/Implicit/Lattices/VoronoiLatticeNode.swift`:

```diff
@@ -8,11 +8,14 @@ import CreatorKernel
 /// `density` and `seed` (`VoronoiSeedSource`). `thickness` is the strut diameter or the wall thickness, a field.
 public enum VoronoiLatticeNode: NodeDefinition {
     public static let typeID = "creator.voronoiLattice"
+    /// 2: `blend` (7c-3f, Errata D18). A node saved as version 1 reads it as 0, the sharp join it was made with.
+    public static let typeVersion = 2
     public static let displayName = "Voronoi Lattice"
     public static let category = NodeCategory.implicit
     public static let inputs = [
         SocketSpec("region", .implicit, optional: true),
         SocketSpec("skin", .number, defaultValue: .number(0), unit: .millimetres, range: 0...20),
+        LatticeSetup.blendSocket,
         SocketSpec("seeds", .plane, access: .list, optional: true),
         SocketSpec("form", .integer, defaultValue: .integer(VoronoiForm.struts.rawValue)),
         SocketSpec("thickness", .field, defaultValue: .number(0.8), unit: .millimetres, range: 0...10),
@@ -28,12 +31,15 @@ public enum VoronoiLatticeNode: NodeDefinition {
     public static let inspector = [
         InspectorSection(title: "Form", controls: [.segmented("form", options: VoronoiForm.options), .number("thickness")]),
         InspectorSection(title: "Seeds", controls: [.integer("count"), .number("density"), .integer("seed"), .note(help)]),
-        InspectorSection(title: "Skin", controls: [.number("skin")]),
+        InspectorSection(title: "Skin", controls: [.number("skin"), .number("blend")]),
     ]
 
+    public static func migrate(_ node: Node, from version: Int) -> Node { LatticeSetup.sharpJoin(node) }
+
     public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
         let region = try LatticeSetup.region(inputs)
         let skin = try LatticeSetup.skin(inputs)
+        let join = try LatticeSetup.blend(inputs)
         let form = VoronoiForm(rawValue: try inputs.choice("form", options: VoronoiForm.options)) ?? .struts
         let box = region.bounds
         let wall = try await LatticeSetup.grading(inputs, "thickness", over: box, kernel: kernel, context: context)
@@ -50,7 +56,7 @@ public enum VoronoiLatticeNode: NodeDefinition {
         let noun = form == .struts ? "Struts" : "Walls"
         warnings += LatticeSetup.thinWarnings(noun, thickest: wall.grading.range.upperBound, voxel: voxel)
         warnings += ImplicitReach.warnings(for: region, reachedBy: skin)
-        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin)
+        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin, blend: join)
         return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
     }
 
```


- [ ] **Step 4: Build, run the suites the task touches, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"` (expected: no output)
Run: `swift test --filter "LatticeSkinBlendTests|TPMSNodeTests|StrutLatticeNodeTests|VoronoiLatticeNodeTests|LatticeEdgeCaseTests|LatticeMeshTests"`
Expected: PASS, "Test run with 59 tests in 6 suites passed" (the 6 new test functions among them).
Run: `swiftlint lint --strict` (expected: `Found 0 violations`)

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorNodes/Implicit/Lattices Tests/CreatorNodesTests/Implicit/LatticeSkinBlendTests.swift
git commit -m "feat(lattices): a blend input joins the skin and the lattice by a smooth union (Errata D18); version 1 nodes read 0"
```

### Task 2: The generalized winding number and a robust sign on `SignedDistanceMesh`

`WindingNumber` sums the solid angles of the triangles at a point (Jacobson et al. 2013): 1 inside a closed, consistently wound mesh, 0 outside, 0 in a cavity, 2 where two shells overlap. Near the point it sums the triangles exactly; a BVH node whose centre is more than `farRatio` (3) radii away counts as one dipole (Barill et al. 2018, zeroth order), so a query costs about a nearest-triangle query. `contains(_:)` re-sums exactly when the fast value is within `margin` (0.15) of ½, so a point is never classified on the far field's error. The clusters cost build time and about 80 bytes a BVH node, and To Implicit's bake (`DistanceBaker`) never asks for a winding number, so `SignedDistanceMesh` holds a `LazyWindingNumber` that builds them on the first `isInside`, `windingNumber` or `robustSignedDistance` and never for the bake (`theWindingNumberIsBuiltOnlyWhenAskedFor`); i-3 therefore needs no re-run. `SignedDistanceMesh` keeps `signedDistance(at:)` (pseudonormal sign) for the bake, where the meshes are the kernel's clean tessellations and a second query per sample would double the cost, and gains `unsignedDistance(at:)`, `windingNumber(at:)`, `isInside(_:)` and `robustSignedDistance(at:)`. D18 allows either: "takes its sign from the same robust test, or documents where the pseudonormal sign is kept"; the doc comment documents it.

**Files:**
- Create: `Sources/CreatorImplicit/Bake/WindingNumber.swift`, `Sources/CreatorImplicit/Bake/LazyWindingNumber.swift`, `Tests/CreatorImplicitTests/WindingNumberTests.swift`
- Modify: `Sources/CreatorImplicit/Bake/SignedDistanceMesh.swift` (the type's doc comment, a stored lazy `winding`, the nearest-feature search split out of `signedDistance`), `Tests/CreatorImplicitTests/SignedDistanceMeshTests.swift`

**Interfaces:**
- Consumes: `TriangleBVH` (`nodes`, `order`; a node has `count`, `first`, `second`, a leaf when `count > 0`), `MeshFixtures.cube`, `MeshFixtures.sphere(radius:subdivisions:)`, `MeshFixtures.hollowCube(size:wall:divisions:)` (existing fixtures), `SeededRandom`.
- Produces: `WindingNumber(vertices:triangles:bvh:)`, `WindingNumber.value(at: SIMD3<Double>, farRatio: Double = 3) -> Double`, `WindingNumber.contains(_:) -> Bool`; `LazyWindingNumber(vertices:triangles:bvh:)` with `number` (built on first use, under a `Mutex`; queries run outside the lock) and `isBuilt`; on `SignedDistanceMesh`: `unsignedDistance(at: Vector3) -> Double`, `windingNumber(at: Vector3) -> Double`, `isInside(_ point: Vector3) -> Bool` (winding ≥ ½), `robustSignedDistance(at: Vector3) -> Double`, and the internal `hasBuiltWindingNumber`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorImplicitTests/WindingNumberTests.swift` (new):

```swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The generalized winding number (implicit spec Errata D18): 1 inside a closed mesh and 0 outside, the BVH clusters held to the exact
/// sum, a hollow part and a mesh that overlaps itself.
struct WindingNumberTests {
    /// The winding number machinery over `positions` and `indices`, as `SignedDistanceMesh` builds it.
    func machinery(_ positions: [Vector3], _ indices: [UInt32]) -> WindingNumber {
        let vertices = positions.map { SIMD3($0.x, $0.y, $0.z) }
        let triangles = stride(from: 0, to: indices.count, by: 3).map {
            SIMD3(Int32(indices[$0]), Int32(indices[$0 + 1]), Int32(indices[$0 + 2]))
        }
        return WindingNumber(vertices: vertices, triangles: triangles, bvh: TriangleBVH(vertices: vertices, triangles: triangles))
    }

    func vectors(_ mesh: TriangleMesh) -> [Vector3] { (0..<mesh.vertexCount).map { mesh.point($0) } }

    @Test func aCubeIsOneInsideAndZeroOutside() {
        let cube = machinery(vectors(MeshFixtures.cube), MeshFixtures.cube.triangles)
        func winding(_ x: Double, _ y: Double, _ z: Double) -> Double { cube.value(at: SIMD3(x, y, z), farRatio: .infinity) }
        #expect(abs(winding(0.5, 0.5, 0.5) - 1) < 1e-12)
        #expect(abs(winding(0.99, 0.5, 0.5) - 1) < 1e-12 && abs(winding(0.01, 0.01, 0.01) - 1) < 1e-12)
        #expect(abs(winding(1.01, 0.5, 0.5)) < 1e-12 && abs(winding(-3, 4, 9)) < 1e-12)
        #expect(abs(winding(2, 2, 2)) < 1e-12, "past a corner")
    }

    @Test func theClustersAgreeWithTheExactSumAndClassifyTheSame() {
        let sphere = MeshFixtures.sphere(radius: 5, subdivisions: 4)
        let winding = machinery(sphere.positions, sphere.indices)
        let random = SeededRandom(seed: 11, stream: 2)
        var worst = 0.0
        for index in 0..<400 {
            let point = SIMD3(random.unit(at: 3 * index) * 16 - 8, random.unit(at: 3 * index + 1) * 16 - 8,
                              random.unit(at: 3 * index + 2) * 16 - 8)
            let (fast, exact) = (winding.value(at: point), winding.value(at: point, farRatio: .infinity))
            worst = max(worst, abs(fast - exact))
            #expect(winding.contains(point) == (exact >= 0.5), "at \(point): \(fast) against \(exact)")
        }
        #expect(worst < 0.05, "the far field is within \(worst) of the exact sum")
    }

    @Test func aCavityIsWoundTheOtherWayAndSoIsNotInside() {
        let part = MeshFixtures.hollowCube(size: 10, wall: 1, divisions: 4)
        let winding = machinery(vectors(part), part.triangles)
        #expect(abs(winding.value(at: SIMD3(0.5, 5, 5)) - 1) < 0.05, "in the wall")
        #expect(abs(winding.value(at: SIMD3(5, 5, 5))) < 0.05, "in the cavity")
        #expect(abs(winding.value(at: SIMD3(20, 5, 5))) < 0.05, "outside")
    }

    @Test func anEmptyMeshHasNoWinding() {
        let none = machinery([], [])
        #expect(none.value(at: SIMD3(1, 2, 3)) == 0)
    }
}
```

`Tests/CreatorImplicitTests/SignedDistanceMeshTests.swift`:

```diff
@@ -126,3 +126,50 @@ struct SignedDistanceMeshTests {
         }.min() ?? .infinity
     }
 }
+
+/// The sign from the winding number (implicit spec Errata D18).
+extension SignedDistanceMeshTests {
+    /// Two cubes of 2 mm, the second 1 mm to the right of the first, as the two shells of a part that was not merged: each is closed, and
+    /// they overlap in x from 1 to 2.
+    func overlappingCubes() throws -> SignedDistanceMesh {
+        let unit = MeshFixtures.cube
+        let positions = Self.vectors(unit).map { $0 * 2 } + Self.vectors(unit).map { $0 * 2 + Vector3(1, 0, 0) }
+        let indices = unit.triangles + unit.triangles.map { $0 + UInt32(unit.vertexCount) }
+        return try SignedDistanceMesh(positions: positions, indices: indices)
+    }
+
+    @Test func theRobustSignAgreesWithThePseudonormalOnACleanMesh() throws {
+        let cube = try cube()
+        for point in [Vector3(0.5, 0.5, 0.5), Vector3(2, 0.5, 0.5), Vector3(0.99, 0.99, 0.5), Vector3(1.01, 1.01, 1.01),
+                      Vector3(-1, -1, -1), Vector3(0.2, 0.1, 0.05),
+        ] {
+            #expect(near(cube.robustSignedDistance(at: point), cube.signedDistance(at: point)), "at \(point)")
+            #expect(near(cube.unsignedDistance(at: point), abs(cube.signedDistance(at: point))))
+            #expect(cube.isInside(point) == (cube.signedDistance(at: point) < 0))
+        }
+        #expect(abs(cube.windingNumber(at: Vector3(0.5, 0.5, 0.5)) - 1) < 1e-9)
+    }
+
+    @Test func aMeshThatOverlapsItselfStillHasAnInside() throws {
+        let mesh = try overlappingCubes()
+        // Inside the first cube, 0.1 mm from the second cube's face (x = 1): that face is the nearest feature, and the point is on its
+        // outer side. The pseudonormal sign reads outside; this is the misread Check Trapped Volumes must not trust.
+        let inFirstOnly = Vector3(0.9, 1, 1)
+        #expect(mesh.signedDistance(at: inFirstOnly) > 0, "the pseudonormal sign is fooled here")
+        #expect(mesh.isInside(inFirstOnly) && mesh.robustSignedDistance(at: inFirstOnly) < 0)
+        #expect(near(mesh.robustSignedDistance(at: inFirstOnly), -0.1))
+        #expect(abs(mesh.windingNumber(at: inFirstOnly) - 1) < 1e-9)
+        // In both cubes the winding number is 2, and outside both it is 0.
+        #expect(abs(mesh.windingNumber(at: Vector3(1.5, 1, 1)) - 2) < 1e-9 && mesh.isInside(Vector3(1.5, 1, 1)))
+        #expect(!mesh.isInside(Vector3(4, 1, 1)) && mesh.robustSignedDistance(at: Vector3(4, 1, 1)) > 0)
+    }
+
+    @Test func theWindingNumberIsBuiltOnlyWhenAskedFor() throws {
+        let cube = try cube()
+        _ = cube.signedDistance(at: Vector3(0.5, 0.5, 0.5))
+        _ = cube.unsignedDistance(at: Vector3(2, 2, 2))
+        #expect(!cube.hasBuiltWindingNumber, "the bake's questions leave the clusters unbuilt")
+        #expect(cube.isInside(Vector3(0.5, 0.5, 0.5)) && cube.hasBuiltWindingNumber)
+        #expect(!cube.isInside(Vector3(3, 3, 3)), "and a second question reuses them")
+    }
+}
```


- [ ] **Step 2: Run them and see them fail**

Run: `swift build --build-tests 2>&1 | grep "error:" | head -3`
Expected: errors `cannot find 'WindingNumber' in scope` and `value of type 'SignedDistanceMesh' has no member 'isInside'`.

- [ ] **Step 3: Implement**

`Sources/CreatorImplicit/Bake/WindingNumber.swift` (new):

```swift
import Foundation

/// The generalized winding number of a closed triangle mesh (Jacobson, Kavan and Sorkine-Hornung, 2013): the sum of the solid angles
/// the triangles subtend at a point, over 4π. It is 1 inside a closed, consistently wound mesh, 0 outside, and it degrades smoothly where
/// the mesh overlaps itself or folds, which is where a sign taken from the nearest feature's normal flips.
///
/// A mesh with hundreds of thousands of triangles is not summed triangle by triangle. Each node of the BVH holds the vector area and the
/// area-weighted centroid of its triangles, and a node whose box is far from the point (`farRatio` times its radius) counts as one
/// dipole (Barill et al., 2018, the zeroth order): the far part of the sum costs one term per node, and only the triangles near the point
/// are summed exactly. The error of a far node is about (radius ÷ distance)³ of its own solid angle, so the value is within a few
/// hundredths of the exact one; `contains(_:)` sums exactly when the value is within `margin` of ½, so a point is never classified
/// on the far field's error.
struct WindingNumber: Sendable {
    /// A node's far field: the vector area `Σ ½ (b − a) × (c − a)`, the area-weighted centre, the total area and the radius from the
    /// centre to the farthest vertex.
    private struct Cluster: Sendable {
        var centre: SIMD3<Double>
        var vectorArea: SIMD3<Double>
        var area: Double
        var radius: Double
    }

    /// A node is a dipole when the point is farther than this many radii from its centre.
    static let farRatio = 3.0

    /// How near ½ the far field's value may be before `contains(_:)` sums exactly.
    static let margin = 0.15

    private let vertices: [SIMD3<Double>]
    private let triangles: [SIMD3<Int32>]
    private let bvh: TriangleBVH
    private let clusters: [Cluster]

    /// `bvh` must have been built over the same `vertices` and `triangles`.
    init(vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>], bvh: TriangleBVH) {
        self.vertices = vertices
        self.triangles = triangles
        self.bvh = bvh
        var clusters = [Cluster](repeating: Cluster(centre: .zero, vectorArea: .zero, area: 0, radius: 0), count: bvh.nodes.count)
        // A node's children come after it, so walking backwards finishes the children first.
        for index in bvh.nodes.indices.reversed() {
            let node = bvh.nodes[index]
            if node.count > 0 {
                clusters[index] = Self.leaf(slots: Int(node.first)..<Int(node.first + node.count), bvh: bvh, vertices: vertices,
                                            triangles: triangles)
            } else {
                clusters[index] = Self.join(clusters[Int(node.first)], clusters[Int(node.second)])
            }
        }
        self.clusters = clusters
    }

    private static func leaf(slots: Range<Int>, bvh: TriangleBVH, vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>]) -> Cluster {
        var vectorArea = SIMD3<Double>.zero, weighted = SIMD3<Double>.zero, area = 0.0, plain = SIMD3<Double>.zero
        for slot in slots {
            let (a, b, c) = corners(Int(bvh.order[slot]), vertices, triangles)
            let normal = cross(b - a, c - a) * 0.5
            let size = (normal * normal).sum().squareRoot()
            let centroid = (a + b + c) / 3
            vectorArea += normal
            weighted += centroid * size
            plain += centroid
            area += size
        }
        let centre = area > 0 ? weighted / area : plain / Double(max(slots.count, 1))
        var radius = 0.0
        for slot in slots {
            let (a, b, c) = corners(Int(bvh.order[slot]), vertices, triangles)
            for corner in [a, b, c] { radius = max(radius, length(corner - centre)) }
        }
        return Cluster(centre: centre, vectorArea: vectorArea, area: area, radius: radius)
    }

    private static func join(_ left: Cluster, _ right: Cluster) -> Cluster {
        let area = left.area + right.area
        let centre = area > 0 ? (left.centre * left.area + right.centre * right.area) / area : (left.centre + right.centre) / 2
        let radius = max(length(left.centre - centre) + left.radius, length(right.centre - centre) + right.radius)
        return Cluster(centre: centre, vectorArea: left.vectorArea + right.vectorArea, area: area, radius: radius)
    }

    private static func corners(_ index: Int, _ vertices: [SIMD3<Double>],
                                _ triangles: [SIMD3<Int32>]) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
        let triangle = triangles[index]
        return (vertices[Int(triangle.x)], vertices[Int(triangle.y)], vertices[Int(triangle.z)])
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func length(_ a: SIMD3<Double>) -> Double { (a * a).sum().squareRoot() }

    /// The signed solid angle of triangle `abc` seen from the origin (Van Oosterom and Strackee, 1983).
    private static func solidAngle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double {
        let (la, lb, lc) = (length(a), length(b), length(c))
        let numerator = (a * cross(b, c)).sum()
        let denominator = la * lb * lc + (a * b).sum() * lc + (a * c).sum() * lb + (b * c).sum() * la
        return 2 * atan2(numerator, denominator)
    }

    /// The winding number at `point`: about 1 inside a closed mesh and 0 outside. `farRatio` is how far a node must be to count as a
    /// dipole; `.infinity` sums every triangle exactly.
    func value(at point: SIMD3<Double>, farRatio: Double = Self.farRatio) -> Double {
        guard !bvh.nodes.isEmpty else { return 0 }
        var total = 0.0
        var stack = [0]
        stack.reserveCapacity(64)
        while let index = stack.popLast() {
            let cluster = clusters[index]
            let offset = cluster.centre - point
            let squared = (offset * offset).sum()
            let reach = farRatio * cluster.radius
            if squared > reach * reach {
                total += (cluster.vectorArea * offset).sum() / (squared * squared.squareRoot())
                continue
            }
            let node = bvh.nodes[index]
            if node.count > 0 {
                for slot in Int(node.first)..<Int(node.first + node.count) {
                    let (a, b, c) = Self.corners(Int(bvh.order[slot]), vertices, triangles)
                    total += Self.solidAngle(a - point, b - point, c - point)
                }
            } else {
                stack.append(Int(node.first))
                stack.append(Int(node.second))
            }
        }
        return total / (4 * Double.pi)
    }

    /// Whether `point` is inside: the winding number is at least ½. The far field decides unless it is near ½.
    func contains(_ point: SIMD3<Double>) -> Bool {
        let fast = value(at: point)
        if abs(fast - 0.5) > Self.margin { return fast >= 0.5 }
        return value(at: point, farRatio: .infinity) >= 0.5
    }
}
```

`Sources/CreatorImplicit/Bake/LazyWindingNumber.swift` (new):

```swift
import Synchronization

/// A `WindingNumber` that is built on the first question and not before (Errata D18). Its clusters cost build time and about 80 bytes a
/// BVH node, and To Implicit's bake, which only asks for the pseudonormal sign, never needs them.
final class LazyWindingNumber: Sendable {
    private let vertices: [SIMD3<Double>]
    private let triangles: [SIMD3<Int32>]
    private let bvh: TriangleBVH
    private let built = Mutex<WindingNumber?>(nil)

    /// `bvh` must have been built over the same `vertices` and `triangles`.
    init(vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>], bvh: TriangleBVH) {
        self.vertices = vertices
        self.triangles = triangles
        self.bvh = bvh
    }

    /// Whether anyone has asked yet.
    var isBuilt: Bool { built.withLock { $0 != nil } }

    /// The winding number, built by the first caller while the others wait. It is returned by value (arrays are shared), so queries
    /// run outside the lock.
    var number: WindingNumber {
        built.withLock { slot in
            if let made = slot { return made }
            let made = WindingNumber(vertices: vertices, triangles: triangles, bvh: bvh)
            slot = made
            return made
        }
    }
}
```

`Sources/CreatorImplicit/Bake/SignedDistanceMesh.swift`:

```diff
@@ -10,11 +10,18 @@ public enum MeshDistanceError: Error, Equatable, Sendable {
     public var userMessage: String { "This solid isn't closed, so inside and outside are undefined." }
 }
 
-/// The signed distance to a closed triangle mesh (implicit spec §4.4): the unsigned distance is the nearest triangle, found by a BVH;
-/// the sign comes from the angle-weighted pseudonormal of the nearest feature (Bærentzen and Aanæs, 2005), which is exact for any
-/// closed, consistently oriented mesh, with no ray casting and no tolerance. The mesh may be a soup of per-face meshes, as OCCT
-/// makes: vertices closer than `weldTolerance` are one vertex first. Negative is inside. Triangles must be counter-clockwise seen from
-/// outside, as `Kernel.tessellate` gives them.
+/// The signed distance to a closed triangle mesh (implicit spec §4.4): the unsigned distance is the nearest triangle, found by a BVH.
+/// There are two signs (Errata D18):
+/// - `signedDistance(at:)` takes it from the angle-weighted pseudonormal of the nearest feature (Bærentzen and Aanæs, 2005), which is
+///   exact for a closed, consistently oriented mesh that does not overlap itself, with no ray casting and no tolerance. It is kept for the
+///   bake (`DistanceBaker`, To Implicit), whose meshes are the kernel's tessellations, clean and finer than the part's details, and where
+///   a second query per sample would double the cost. Where a mesh folds over itself (a sheet meeting a slab tangentially, meshed coarser
+///   than the wedge between them) the nearest feature's normal can point the wrong way and the sign flips.
+/// - `robustSignedDistance(at:)` and `isInside(_:)` take it from the generalized winding number (`WindingNumber`), inside when it is at
+///   least ½. Check Trapped Volumes decides what is inside with this one (it asks once per region of cells, see `EnclosedVoids`).
+///
+/// The mesh may be a soup of per-face meshes, as OCCT makes: vertices closer than `weldTolerance` are one vertex first. Negative is
+/// inside. Triangles must be counter-clockwise seen from outside, as `Kernel.tessellate` gives them.
 public struct SignedDistanceMesh: Sendable {
     private let vertices: [SIMD3<Double>]
     private let triangles: [SIMD3<Int32>]
@@ -24,6 +31,8 @@ public struct SignedDistanceMesh: Sendable {
     /// For each triangle, the normal of each of its edges (a, b), (b, c), (c, a): the sum of the two faces' normals.
     private let edgeNormals: [SIMD3<Double>]
     private let bvh: TriangleBVH
+    /// Built on the first `windingNumber(at:)` or `isInside(_:)`, so the bake never pays for it.
+    private let winding: LazyWindingNumber
 
     /// The box around the mesh.
     public let bounds: BoundingBox
@@ -42,7 +51,9 @@ public struct SignedDistanceMesh: Sendable {
         self.faceNormals = normals.faces
         self.vertexNormals = normals.vertices
         self.edgeNormals = normals.edges
-        self.bvh = TriangleBVH(vertices: welded, triangles: kept)
+        let bvh = TriangleBVH(vertices: welded, triangles: kept)
+        self.bvh = bvh
+        self.winding = LazyWindingNumber(vertices: welded, triangles: kept, bvh: bvh)
         let low = welded.dropFirst().reduce(welded[0]) { pointwiseMin($0, $1) }
         let high = welded.dropFirst().reduce(welded[0]) { pointwiseMax($0, $1) }
         self.bounds = BoundingBox(min: Vector3(low.x, low.y, low.z), max: Vector3(high.x, high.y, high.z))
@@ -137,9 +148,8 @@ public struct SignedDistanceMesh: Sendable {
     /// How many triangles remain after welding and dropping slivers.
     public var triangleCount: Int { triangles.count }
 
-    /// The signed distance from `point` to the surface: negative inside.
-    public func signedDistance(at point: Vector3) -> Double {
-        let p = SIMD3(point.x, point.y, point.z)
+    /// The nearest point of the surface to `p`, with the squared distance and the normal that gives the pseudonormal sign.
+    private func nearest(to p: SIMD3<Double>) -> (squared: Double, point: SIMD3<Double>, normal: SIMD3<Double>) {
         var best = Double.infinity
         var bestPoint = p
         var bestNormal = SIMD3<Double>.zero
@@ -158,12 +168,45 @@ public struct SignedDistanceMesh: Sendable {
             case .edge(let side): bestNormal = edgeNormals[3 * index + side]
             }
         })
-        guard best.isFinite else { return .infinity }
-        let distance = best.squareRoot()
-        let side = ((p - bestPoint) * bestNormal).sum()
+        return (best, bestPoint, bestNormal)
+    }
+
+    /// The signed distance from `point` to the surface: negative inside, by the nearest feature's pseudonormal.
+    public func signedDistance(at point: Vector3) -> Double {
+        let p = SIMD3(point.x, point.y, point.z)
+        let found = nearest(to: p)
+        guard found.squared.isFinite else { return .infinity }
+        let distance = found.squared.squareRoot()
+        let side = ((p - found.point) * found.normal).sum()
         return side < 0 ? -distance : distance
     }
 
+    /// The distance from `point` to the surface, with no sign.
+    public func unsignedDistance(at point: Vector3) -> Double {
+        let squared = nearest(to: SIMD3(point.x, point.y, point.z)).squared
+        return squared.isFinite ? squared.squareRoot() : .infinity
+    }
+
+    /// Whether the winding number's clusters have been built (the first question builds them).
+    var hasBuiltWindingNumber: Bool { winding.isBuilt }
+
+    /// The generalized winding number at `point`: about 1 inside the mesh, 0 outside.
+    public func windingNumber(at point: Vector3) -> Double {
+        winding.number.value(at: SIMD3(point.x, point.y, point.z))
+    }
+
+    /// Whether `point` is inside: the winding number is at least ½. Unlike the pseudonormal sign this does not depend on which feature
+    /// of the surface happens to be nearest, so a mesh that overlaps itself still has an inside.
+    public func isInside(_ point: Vector3) -> Bool {
+        winding.number.contains(SIMD3(point.x, point.y, point.z))
+    }
+
+    /// The signed distance from `point` to the surface with the sign from the winding number: negative when `isInside`.
+    public func robustSignedDistance(at point: Vector3) -> Double {
+        let distance = unsignedDistance(at: point)
+        return isInside(point) ? -distance : distance
+    }
+
     // MARK: Closest point on a triangle
 
     private enum Feature {
```


- [ ] **Step 4: Build, run the suites the task touches, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"` (expected: no output)
Run: `swift test --filter "SignedDistanceMeshTests|WindingNumberTests|DistanceBakerTests"`
Expected: PASS ("Test run with 23 tests in 3 suites passed" on `CreatorImplicitTests`; the `DistanceBakerTests` run confirms the bake still gets the pseudonormal sign).
Run: `swiftlint lint --strict` (expected: `Found 0 violations`)

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorImplicit/Bake Tests/CreatorImplicitTests
git commit -m "feat(implicit): the generalized winding number, built lazily, and a robust inside test on SignedDistanceMesh (Errata D18)"
```

### Task 3: Check Trapped Volumes decides inside by the winding number; Drain Holes and the check agree

`TrappedVolumeCheck` fills the grid from the **unsigned** distance (a cell is solid within half a cell of the surface), so inside the material is no longer solid in the grid. The flood fill from the corner marks the outside; each pocket it leaves is either the inside of the material or a cavity, and a pocket is wholly on one side of the surface (a path out of it would cross the surface within half a cell of a cell on the path). `EnclosedVoids(_:isInside:)` therefore asks `isInside` about five cell centres spread through each pocket of more than one cell and drops the pocket when most are inside. A pocket is judged as soon as its flood fill has listed `judgedAt` (4,096) cells, from those cells, and a pocket judged material stops being listed: the interior of a thick solid part is one pocket of tens of millions of cells (27 million in a solid 150 mm cube), and listing it all first took the check on that cube to 603 MB resident, past D16's 450 MB (row i-7s). A pocket of fewer cells is judged when it ends, as before. The cell-by-cell alternative is 23 to 35 times slower (Measured facts). Pockets are never told apart cell by cell, which is what the pseudonormal sign misread in the wedge.

Drain Holes Automatic keeps classifying on the implicit itself (`OccupancyGrid.of`: solid where the field is at most half a cell). **This departs from D18's text** ("Drain Holes Automatic classifies the same way as the check") and is user decision 3. The sign of its own field is exact, so it needs no winding number, and a cell is solid by the same definition as in the check (inside, or within half a cell of the surface); but it is not the same grid. Drain Holes' grid is laid over the implicit's bounds (a union's grow by a quarter of the blend radius) and the check's over the mesh's, so the cells fall differently, and a field value is not a distance, so half a cell in field units is not geometric. That grid mismatch (M5's) is **not fixed** here. The task documents it, and adds a test that the two find the same voids of three sheets on a skin (different size, cell size and position of the region) and that drilling the points leaves the check nothing. The agreement is measured, not guaranteed: on a sheet of 6 mm cells each side finds voids the other does not (D18, Task 6). `EnclosedVoids(_:)` with no `isInside` is unchanged, so Drain Holes' grid behaves as before.

**Files:**
- Modify: `Sources/CreatorImplicit/Mesh/Checks/EnclosedVoids.swift`, `TrappedVolumeCheck.swift`, `OccupancyGrid.swift` (doc comment), `DrainHoles.swift` (doc comment)
- Create: `Tests/CreatorImplicitTests/TrappedVolumePhantomTests.swift`
- Test: `Tests/CreatorImplicitTests/OccupancyGridTests.swift`, `DrainHolesTests.swift`

**Interfaces:**
- Consumes: Task 2's `SignedDistanceMesh.unsignedDistance(at:)` and `isInside(_:)`; `OccupancyGrid.fill(lipschitz:from:)` with a distance closure; `ImplicitMesher`, `CPUBatchEvaluator`, `LatticeFixtures.cells(_:)` (existing test fixtures).
- Produces: `EnclosedVoids.init(_ grid: OccupancyGrid, isInside: ((Vector3) -> Bool)? = nil) throws`, `EnclosedVoids.samples` (5), `EnclosedVoids.judgedAt` (4,096), `TrappedVolumeCheck.findVoids(in: SignedDistanceMesh, bounds: BoundingBox) throws -> (grid: OccupancyGrid, found: EnclosedVoids)`, and the test fixture `TrappedVolumePhantomTests.skinnedSheet(half:cell:offset:resolution:)` (by default an 8 mm cube with a 1.5 mm skin and a 1.2 mm gyroid sheet joined by a 1 mm blend, meshed at 0.6 mm, which gives two real voids and, under the old classifier, a third of 110 cells that is solid material; the arguments move and resize the region and change the gyroid's cell for the second and third agreement cases).

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorImplicitTests/OccupancyGridTests.swift`:

```diff
@@ -65,6 +65,57 @@ struct OccupancyGridTests {
         #expect(found.label[grid.index(8, 8, 8)] == 0 && found.label[grid.index(0, 0, 0)] == -1)
     }
 
+    /// A grid of the cells near a surface only, as one made from an unsigned distance is: the block in the shell is then the inside of the
+    /// material or a cavity, and `isInside` says which (Errata D18).
+    @Test func aRegionTheCallerSaysIsInsideIsMaterialAndNotAVoid() throws {
+        let grid = shell()
+        var asked: [Vector3] = []
+        let material = try EnclosedVoids(grid, isInside: { point in asked.append(point); return true })
+        #expect(material.voids.isEmpty && material.label.allSatisfy { $0 == -1 })
+        #expect(asked.count == EnclosedVoids.samples, "once per region, a few cells of it: \(asked.count)")
+        let box = BoundingBox(min: grid.center(of: grid.index(5, 5, 5)), max: grid.center(of: grid.index(12, 12, 12)))
+        #expect(asked.allSatisfy { $0.x >= box.min.x && $0.x <= box.max.x && $0.y >= box.min.y && $0.y <= box.max.y
+            && $0.z >= box.min.z && $0.z <= box.max.z }, "only cells of the pocket")
+        let cavity = try EnclosedVoids(grid, isInside: { _ in false })
+        #expect(cavity.voids.count == 1 && cavity.voids[0].count == 8 * 8 * 8)
+        #expect(try EnclosedVoids(grid).voids.count == 1, "with no test, every pocket is a void, as before")
+    }
+
+    /// A pocket of more than `judgedAt` cells, the inside of a thick part: it is judged from the first cells listed, and when it is material
+    /// it is not listed any further (a solid 150 mm cube has 27 million such cells). A cavity of the same size is still one whole void.
+    @Test func aPocketBiggerThanTheJudgingSizeIsJudgedBeforeItIsListedInFull() throws {
+        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(10, 10, 10)))
+        for index in 0..<grid.cellCount { grid.setSolid(true, at: index) }
+        grid.setSolid(false, at: grid.index(0, 0, 0))
+        var pocket = 0
+        for k in 6..<26 {
+            for j in 6..<26 {
+                for i in 6..<26 {
+                    grid.setSolid(false, at: grid.index(i, j, k))
+                    pocket += 1
+                }
+            }
+        }
+        #expect(pocket > EnclosedVoids.judgedAt)
+        var asked = 0
+        let material = try EnclosedVoids(grid, isInside: { _ in asked += 1; return true })
+        #expect(material.voids.isEmpty && material.label.allSatisfy { $0 == -1 } && asked == EnclosedVoids.samples, "asked \(asked) times")
+        asked = 0
+        let cavity = try EnclosedVoids(grid, isInside: { _ in asked += 1; return false })
+        #expect(cavity.voids.count == 1 && cavity.voids[0].count == pocket && asked == EnclosedVoids.samples)
+        #expect(cavity.label.filter { $0 == 0 }.count == pocket)
+    }
+
+    @Test func theOutsideAndAOneCellPocketAreNeverAsked() throws {
+        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(10, 10, 10)))
+        for index in 0..<grid.cellCount { grid.setSolid(true, at: index) }
+        grid.setSolid(false, at: grid.index(8, 8, 8))
+        grid.setSolid(false, at: grid.index(0, 0, 0))
+        var asked = 0
+        _ = try EnclosedVoids(grid, isInside: { _ in asked += 1; return false })
+        #expect(asked == 0)
+    }
+
     @Test func aHoleInTheShellLetsTheOutsideIn() throws {
         #expect(try EnclosedVoids(shell(openAt: shell().index(8, 8, 13))).voids.isEmpty)
     }
```

`Tests/CreatorImplicitTests/TrappedVolumePhantomTests.swift` (new):

```swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The phantom void of a sheet meeting a slab tangentially (implicit spec Errata M5 and D18).
struct TrappedVolumePhantomTests {
    /// What the lightweight bracket is made of, small: an 8 mm cube with a 1.5 mm skin, a gyroid sheet 1.2 mm thick (cell 10 mm) filling
    /// it and joined to the skin by a 1 mm smooth union, meshed at 0.6 mm. The sheet meets the skin's inner face tangentially in thin
    /// wedges, narrower than the cell, and there the mesh overlaps itself. The skin closes the two gyroid channels, so there are two real
    /// voids; at this size the pseudonormal sign finds a third, of 110 cells, that is solid material.
    static func skinnedSheet(half: Double = 4, cell: Double = 10, offset: Vector3 = .zero,
                             resolution: Double = 0.6) async throws -> (solid: ImplicitSolid, mesh: TriangleMesh) {
        let box = ImplicitSolid.box(halfSize: Vector3(half, half, half), cornerRadius: 0)
        let region = offset == .zero ? box : .moved(box, RigidMove(origin: offset, xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ))
        let lattice = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: LatticeFixtures.cells(cell),
                                                      thickness: .constant(1.2), region: region.bounds))
        let wall = ImplicitSolid.shell(region, thickness: .constant(1.5), side: .inward)
        let inside = ImplicitSolid.offset(region, distance: .constant(-1.5))
        let solid = ImplicitSolid.union([wall, .intersect([lattice, inside], blend: .constant(0))], blend: .constant(1))
        let mesh = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: resolution, quality: .export)
        return (solid, mesh)
    }

    func distances(_ mesh: TriangleMesh) throws -> SignedDistanceMesh {
        try SignedDistanceMesh(positions: (0..<mesh.vertexCount).map { mesh.point($0) }, indices: mesh.triangles)
    }

    /// The sizes of the voids, and the largest `signedDistance` of the part at any cell centre of any void (negative: inside the part).
    func voids(of mesh: TriangleMesh, in solid: ImplicitSolid, robust: Bool) throws -> [(cells: Int, deepestInsidePart: Double)] {
        let measure = try distances(mesh)
        let bounds = try #require(mesh.bounds)
        let found: EnclosedVoids
        let grid: OccupancyGrid
        if robust {
            (grid, found) = try TrappedVolumeCheck.findVoids(in: measure, bounds: bounds)
        } else {
            // The classifier before D18: the pseudonormal sign, every cell asked.
            var plain = OccupancyGrid(bounds: bounds)
            try plain.fill { points in points.map { measure.signedDistance(at: $0) } }
            grid = plain
            found = try EnclosedVoids(plain)
        }
        return found.voids.map { cells in
            (cells.count, cells.map { solid.signedDistance(at: grid.center(of: Int($0))) }.min() ?? 0)
        }
    }

    @Test func aWedgeOfSheetOnSkinIsNotAVoid() async throws {
        let (solid, mesh) = try await Self.skinnedSheet()
        let found = try voids(of: mesh, in: solid, robust: true)
        #expect(found.count == 2, "the two channels the skin closes, and no phantom: \(found.map(\.cells))")
        #expect(found.allSatisfy { $0.cells > 1000 }, "\(found.map(\.cells))")
        #expect(try TrappedVolumeCheck.run(mesh).voidCount == 2)
    }

    @Test func everyVoidItFindsIsAirOutsideThePart() async throws {
        let (solid, mesh) = try await Self.skinnedSheet()
        // The channel's air is outside the part by the field itself: no void cell centre is inside it.
        for void in try voids(of: mesh, in: solid, robust: true) { #expect(void.deepestInsidePart > 0, "\(void)") }
    }

    #if os(macOS)
    /// Pins the fixture: the pseudonormal sign still finds a void here that is solid material (the field is at most 0 at all its cell
    /// centres). If this fails, the mesher changed and the fixture no longer reproduces the phantom; find a size that does. Only that a
    /// phantom exists is pinned, not how many cells or voids: the wedge is narrower than a mesh cell, so its size follows the mesher's
    /// last-bit arithmetic, and the fixture was measured on macOS (arm64) only, so the Linux and Windows jobs do not run this test.
    @Test func thePseudonormalSignFindsAPhantomVoidInTheSameMesh() async throws {
        let (solid, mesh) = try await Self.skinnedSheet()
        let found = try voids(of: mesh, in: solid, robust: false)
        #expect(found.contains { $0.deepestInsidePart <= 0 }, "\(found)")
    }
    #endif
}
```

`Tests/CreatorImplicitTests/DrainHolesTests.swift`:

```diff
@@ -66,4 +66,23 @@ struct DrainHolesTests {
         #expect(!DrainHoles.hasFiniteBounds(unbounded) && DrainHoles.hasFiniteBounds(ball))
         #expect(DrainHoles.drilled(unbounded, at: [.zero], diameter: 1, direction: .unitZ) == unbounded, "no NaN cylinders")
     }
+
+    /// Drain Holes and Check Trapped Volumes see the same voids of these sheets on a skin (Errata D18): the implicit's inside is its own
+    /// field's sign, which is exact, and the mesh's is the winding number, so each finds the channels the skin closes and neither finds the
+    /// wedge where the sheet meets the skin. Drilling the channels leaves nothing for the check to find. Three sizes, cell sizes and
+    /// positions of the region (the lattice's phase and the grids' alignment differ between them). This is not a guarantee: the two grids
+    /// are laid over different bounds (the implicit's loose box, the mesh's), and a sheet of 6 mm cells shows them disagreeing (see D18).
+    @Test(arguments: [
+        (4.0, 10.0, Vector3.zero, 0.6), (6.0, 10.0, Vector3(1.1, 0, 0), 0.7), (5.0, 8.0, Vector3.zero, 0.5),
+    ])
+    func drainHolesAndTheCheckFindTheSameVoidsOfASheetOnASkin(_ half: Double, _ cell: Double, _ offset: Vector3,
+                                                              _ resolution: Double) async throws {
+        let (solid, mesh) = try await TrappedVolumePhantomTests.skinnedSheet(half: half, cell: cell, offset: offset, resolution: resolution)
+        let points = try await DrainHoles.drainPoints(of: solid, direction: Vector3(0, 0, -1), using: CPUBatchEvaluator(solid))
+        let found = try TrappedVolumeCheck.run(mesh).voidCount
+        #expect(points.count == found && found >= 2, "Drain Holes \(points.count), the check \(found)")
+        let drilled = DrainHoles.drilled(solid, at: points, diameter: 2, direction: Vector3(0, 0, -1))
+        let after = try await ImplicitMesher(evaluator: CPUBatchEvaluator(drilled)).mesh(drilled, resolution: resolution, quality: .export)
+        #expect(try TrappedVolumeCheck.run(after).voidCount == 0, "the holes opened every void")
+    }
 }
```


`thePseudonormalSignFindsAPhantomVoidInTheSameMesh` runs the **old classifier** (the pseudonormal sign for every cell) on the fixture and pins that it finds a phantom, and nothing about its size: it is the regression's "fails on the old classifier" half, and fails loudly if the mesher ever changes so the fixture stops reproducing the wedge. The wedge is narrower than a mesh cell, so whether and how big it is follows the mesher's last-bit arithmetic, and the fixture was measured on arm64 macOS only: the test is `#if os(macOS)`, so a different CPU mesher on the Linux (x86_64, aarch64) or Windows job can neither turn xp red nor hide behind its `continue-on-error`. The exact counts (three voids, one phantom) are not pinned anywhere. `aWedgeOfSheetOnSkinIsNotAVoid` is the "passes on the new" half and runs everywhere: its two voids are the large channels the skin closes, which do not depend on the wedge.

- [ ] **Step 2: Run them and see them fail**

Run: `swift build --build-tests 2>&1 | grep "error:" | head -3`
Expected: errors `extra argument 'isInside' in call` and `type 'TrappedVolumeCheck' has no member 'findVoids'`.

- [ ] **Step 3: Implement**

`Sources/CreatorImplicit/Mesh/Checks/EnclosedVoids.swift`:

```diff
@@ -1,25 +1,51 @@
+import CreatorGeometry
+
 /// The empty cells of an `OccupancyGrid` that the outside cannot reach (implicit spec §4.6): flood fill from the corner through
 /// empty cells that share a face; whatever empty is left over is a pocket, and the pockets of more than one cell are voids.
+///
+/// A grid made from a mesh's unsigned distance (Errata D18) marks only the cells near the surface, so a pocket may be the inside of the
+/// material as well as a cavity. Such a region is all on one side of the surface (a path out of it would cross the surface within half
+/// a cell of a cell on the path), so `isInside` is asked about a few of its cell centres, and the region is a void only when most of them
+/// are outside. The region's cells are never told apart one by one, which is what the pseudonormal sign did, and misread in a wedge
+/// narrower than the cells. The inside of a thick part is one region of tens of millions of cells, so a region is judged once `judgedAt`
+/// of its cells are listed, and one judged to be material is not listed any further.
 public struct EnclosedVoids: Sendable {
+    /// How many cell centres of a region `isInside` is asked about.
+    static let samples = 5
+
+    /// How many cells of a region are listed before it is judged: a region that goes on is judged by these, and dropped from the list
+    /// when it is material. Smaller regions are judged when the fill ends.
+    static let judgedAt = 4096
+
     /// The void each cell belongs to, or -1.
     public let label: [Int32]
     /// The flat cell indices of each void, in order of their lowest flat index.
     public let voids: [[Int32]]
 
-    public init(_ grid: OccupancyGrid) throws {
+    /// - Parameter isInside: whether a point is inside the part, for a grid that holds only the cells near the surface. `nil` for a grid
+    ///   that already counts the inside as solid (an implicit solid's, whose inside test is the sign of its own field).
+    public init(_ grid: OccupancyGrid, isInside: ((Vector3) -> Bool)? = nil) throws {
         let counts = grid.counts
         let strides = [1, counts.x, counts.x * counts.y]
         var reached = grid.isSolid
         /// Marks everything reachable from `start`. The cells are listed in `collecting` when it is given; the outside pass gives none,
-        /// so the biggest region of the grid is never stored.
-        func fill(from start: Int, collecting: inout [Int32]?) throws {
+        /// so the biggest region of the grid is never stored. With `judging`, the region is judged when `judgedAt` cells are listed: when
+        /// it is material the list is dropped (`collecting` becomes `nil`) and the fill goes on without it. Returns that verdict, or
+        /// `nil` when the region ended first or there was no judge.
+        @discardableResult
+        func fill(from start: Int, collecting: inout [Int32]?, judging: (([Int32]) -> Bool)? = nil) throws -> Bool? {
             var stack = [Int32(start)]
             var visited = 0
+            var verdict: Bool?
             reached[start] = true
             while let next = stack.popLast() {
                 if visited & 0xFFFF == 0 { try Task.checkCancellation() }
                 visited += 1
                 collecting?.append(next)
+                if verdict == nil, collecting?.count == Self.judgedAt, let judging, let listed = collecting {
+                    verdict = judging(listed)
+                    if verdict == true { collecting = nil }
+                }
                 let c = grid.coordinates(of: Int(next))
                 for axis in 0..<3 {
                     for step in [-1, 1] where c[axis] + step >= 0 && c[axis] + step < counts[axis] {
@@ -31,7 +57,9 @@ public struct EnclosedVoids: Sendable {
                     }
                 }
             }
+            return verdict
         }
+        let judge = isInside.map { isInside in { (cells: [Int32]) in Self.isMaterial(cells, in: grid, isInside) } }
         // The corner is padding, so empty: everything the fill reaches is outside.
         var nothing: [Int32]?
         if !reached[0] { try fill(from: 0, collecting: &nothing) }
@@ -39,14 +67,22 @@ public struct EnclosedVoids: Sendable {
         var voids: [[Int32]] = []
         for start in 0..<grid.cellCount where !reached[start] {
             var listed: [Int32]? = []
-            try fill(from: start, collecting: &listed)
+            let early = try fill(from: start, collecting: &listed, judging: judge)
             let cells = listed ?? []
-            // A pocket of a single cell is below what the grid can tell from the surface.
-            guard cells.count > 1 else { continue }
+            // A pocket of a single cell is below what the grid can tell from the surface; one judged material is not a void.
+            guard cells.count > 1, early != true else { continue }
+            if early == nil, let judge, judge(cells) { continue }
             for cell in cells { label[Int(cell)] = Int32(voids.count) }
             voids.append(cells)
         }
         self.label = label
         self.voids = voids
     }
+
+    /// Whether most of `Self.samples` cell centres, spread through `cells`, are inside the part.
+    private static func isMaterial(_ cells: [Int32], in grid: OccupancyGrid, _ isInside: (Vector3) -> Bool) -> Bool {
+        let picks = Set((0..<samples).map { cells[$0 * (cells.count - 1) / (samples - 1)] })
+        let inside = picks.filter { isInside(grid.center(of: Int($0))) }.count
+        return 2 * inside > picks.count
+    }
 }
```

`Sources/CreatorImplicit/Mesh/Checks/TrappedVolumeCheck.swift`:

```diff
@@ -3,6 +3,11 @@ import CreatorGeometry
 /// Trapped volumes (implicit spec §4.6): a coarse occupancy grid of the mesh (0.5 mm cells, or 1/32 of the longest side if that is
 /// finer), flood filled from outside. Empty cells the fill cannot reach, in pockets of more than one cell, are voids that cannot
 /// drain. A triangle looks into a void when a void cell lies a little way from it along its normal, and is highlighted.
+///
+/// A cell is solid when it is within half a cell of the surface or inside the part. Inside is the mesh's generalized winding number
+/// (at least ½), asked once per region of cells, not the sign of the nearest feature's normal: where a sheet meets a slab tangentially and
+/// the mesh is coarser than the wedge between them, the mesh overlaps itself and that sign reads solid cells as empty, which made 103
+/// phantom voids of the lightweight bracket (spec Errata M5, D18).
 public enum TrappedVolumeCheck {
     public struct Result: Sendable {
         /// The number of enclosed voids.
@@ -19,9 +24,7 @@ public enum TrappedVolumeCheck {
         guard let bounds = mesh.bounds, mesh.triangleCount > 0 else { return Result(voidCount: 0, triangles: []) }
         let positions = (0..<mesh.vertexCount).map { mesh.point($0) }
         let distances = try SignedDistanceMesh(positions: positions, indices: mesh.triangles)
-        var grid = OccupancyGrid(bounds: bounds)
-        try grid.fill { points in points.map { distances.signedDistance(at: $0) } }
-        let found = try EnclosedVoids(grid)
+        let (grid, found) = try findVoids(in: distances, bounds: bounds)
         guard !found.voids.isEmpty else { return Result(voidCount: 0, triangles: [], cell: grid.cell) }
         var facing: [Int] = []
         for index in 0..<mesh.triangleCount {
@@ -37,4 +40,13 @@ public enum TrappedVolumeCheck {
         }
         return Result(voidCount: found.voids.count, triangles: facing, cell: grid.cell)
     }
+
+    /// The occupancy grid of the mesh and its enclosed voids. Only the cells within half a cell of the surface are solid in the grid (the
+    /// distances are unsigned); `EnclosedVoids` decides which of the regions of cells farther away are inside the part, by the winding
+    /// number, which a mesh that folds over itself cannot fool (Errata D18).
+    static func findVoids(in distances: SignedDistanceMesh, bounds: BoundingBox) throws -> (grid: OccupancyGrid, found: EnclosedVoids) {
+        var grid = OccupancyGrid(bounds: bounds)
+        try grid.fill { points in points.map { distances.unsignedDistance(at: $0) } }
+        return (grid, try EnclosedVoids(grid, isInside: { distances.isInside($0) }))
+    }
 }
```

`Sources/CreatorImplicit/Mesh/Checks/OccupancyGrid.swift`:

```diff
@@ -4,6 +4,12 @@ import CreatorGeometry
 /// solid when its centre is inside the part or within half a cell of the surface, so a wall thinner than a cell is never a gap in the
 /// grid, and a void or a channel has to be larger than about a cell to be seen. The grid has two empty cells of padding round the part, so
 /// its corner is always outside.
+///
+/// How "inside" is decided depends on where the grid comes from (Errata D18). A solid's own field says it exactly, by its sign, so
+/// `of(_:using:)` (Drain Holes) marks every cell the field puts at most half a cell out. A mesh has no field: `TrappedVolumeCheck` fills
+/// the cells near the surface from the unsigned distance and `EnclosedVoids(_:isInside:)` asks the mesh's winding number about each
+/// region of cells farther away. Both use the same definition of solid, but not the same grid (the implicit's bounds against the mesh's), so
+/// they may disagree about a pocket a cell or two across.
 public struct OccupancyGrid: Sendable {
     /// The most cells a grid may have, padding included. The flood fill holds `isSolid` and `reached` (a byte each), `label` (4 bytes),
     /// a stack that can reach 4 bytes a cell and the voids' cell lists, 4 more at worst (the outside is not listed): about 450 MB at
```

`Sources/CreatorImplicit/Mesh/Checks/DrainHoles.swift`:

```diff
@@ -5,7 +5,10 @@ import CreatorGeometry
 public enum DrainHoles {
     /// The lowest point of each enclosed void of `solid` along `direction` (the cell centre farthest in that direction, the middle one
     /// of those in the lowest layer), one per void, in the order of the voids. The voids are found on the coarse grid of the
-    /// trapped-volume check, evaluated on the implicit itself.
+    /// trapped-volume check, evaluated on the implicit itself. Its inside test is the field's own sign, which is exact, so it needs no
+    /// winding number: a cell is solid by the same definition as in Check Trapped Volumes (inside, or within half a cell of the surface).
+    /// The grid is not the same one, though: it is laid over the implicit's bounds, not the mesh's, and a field value is not a distance, so
+    /// the two may disagree about a pocket a cell or two across (Errata D18; the mismatch of M5 is not fixed).
     /// - Throws: `ImplicitMeshingError.empty` for a solid with no finite bounds, and `CancellationError`.
     public static func drainPoints(of solid: ImplicitSolid, direction: Vector3,
                                    using evaluator: any ImplicitBatchEvaluator) async throws -> [Vector3] {
```


- [ ] **Step 4: Build, run the suites the task touches, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"` (expected: no output)
Run: `swift test --filter "TrappedVolumeCheckTests|TrappedVolumePhantomTests|OccupancyGridTests|DrainHolesTests|CheckTrappedVolumesNodeTests|DrainHolesNodeTests"`
Expected: PASS, two "Test run with" lines (`CreatorNodesTests`: 10 tests in 2 suites; `CreatorImplicitTests`: 35 tests in 4 suites).
Run: `swiftlint lint --strict` (expected: `Found 0 violations`)

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorImplicit/Mesh/Checks Tests/CreatorImplicitTests
git commit -m "fix(check): Check Trapped Volumes decides inside by the winding number, once per pocket; the wedge fixture (Errata D18)"
```

### Task 4: Check Thin Walls skips hits on the start vertex's own fold

Where the sheet closes on the skin, the mesh folds back on itself within a fraction of a millimetre, and a vertex's inward ray hits a face of its own neighbourhood a few microns away (79 of the 127 places had a ray thickness under 0.05 mm). `ThinWallCheck.wall(behind:limit:)` now skips a hit nearer than `selfHitLimit` (0.05 mm) on a triangle that has a corner in the start vertex's one-ring (the vertex and the vertices it shares a triangle with) and lets the ray go on, so the next face along the ray decides. A hit that is farther, or on a face of vertices outside the one-ring, is still a wall however thin, and a knife edge is still reported a little away from its tip, where the two sides are a hit's distance apart or more. **The accepted limit of the rule** (D18's): a real wall under 0.05 mm whose far face shares a vertex with the start's one-ring cannot be told from the fold and is not reported. It is validated on the bracket and the synthetic wedge only; `aFoldBesideTheVertexIsPassedOverAndTheRayGoesOnToTheWall` pins the behaviour at 0.01 mm and says in its comment that it is this limit, and the doc comment of `ThinWallCheck` names it.

**Files:**
- Modify: `Sources/CreatorImplicit/Mesh/Checks/ThinWallCheck.swift`
- Create: `Tests/CreatorImplicitTests/Support/MeshFixtures+Wedge.swift`
- Test: `Tests/CreatorImplicitTests/ThinWallCheckTests.swift`

**Interfaces:**
- Consumes: `ThinWallCheck.wall(behind:limit:)` (internal), `TriangleBVH.nearestHit(origin:direction:limit:)` with its per-triangle closure, `MeshFixtures` (extended here).
- Produces: `ThinWallCheck.selfHitLimit = 0.05`, `MeshFixtures.wedge(topSteps:bottomSteps:halfAngle:rows:) -> TriangleMesh`.

The existing 0.2 mm wall fixtures (`aWallOfAFifthOfAMillimetreIsFoundWhereverTheCubeHasOne` and its neighbours) stay and must still pass: a wall's far side is on other vertices, so the rule never touches it.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorImplicitTests/Support/MeshFixtures+Wedge.swift` (new):

```swift
import CreatorGeometry
import CreatorImplicit
import Foundation

extension MeshFixtures {
    /// The top and the bottom of a wedge that tapers to a knife edge, as two open sheets sharing the edge's vertices: the edge runs along
    /// y at x = 0, and the faces leave it at `halfAngle` radians above and below the xy plane. `topSteps` and `bottomSteps` are the x
    /// positions of the vertex rows on each face, each starting at 0 (the edge itself); the rows are 1 mm apart along y, `rows` of them.
    /// The faces face outward, so a vertex's inward ray crosses the wedge to the other face.
    static func wedge(topSteps: [Double], bottomSteps: [Double], halfAngle: Double, rows: Int = 4) -> TriangleMesh {
        var positions: [SIMD3<Float>] = []
        func add(_ x: Double, _ y: Double, _ z: Double) -> UInt32 {
            positions.append(SIMD3(Float(x), Float(y), Float(z)))
            return UInt32(positions.count - 1)
        }
        let slope = tan(halfAngle)
        let edge = (0..<rows).map { add(0, Double($0), 0) }
        func face(_ steps: [Double], sign: Double) -> [[UInt32]] {
            [edge] + steps.dropFirst().map { x in (0..<rows).map { add(x, Double($0), sign * x * slope) } }
        }
        let top = face(topSteps, sign: 1), bottom = face(bottomSteps, sign: -1)
        var triangles: [UInt32] = []
        func strips(_ grid: [[UInt32]], flipped: Bool) {
            for i in 0..<grid.count - 1 {
                for j in 0..<rows - 1 {
                    let (a, b, c, d) = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
                    triangles += flipped ? [a, c, b, a, d, c] : [a, b, c, a, c, d]
                }
            }
        }
        strips(top, flipped: false)
        strips(bottom, flipped: true)
        return TriangleMesh(positions: positions, triangles: triangles)
    }
}
```

`Tests/CreatorImplicitTests/ThinWallCheckTests.swift`:

```diff
@@ -1,4 +1,5 @@
 import CreatorGeometry
+import Foundation
 import Testing
 @testable import CreatorImplicit
 
@@ -98,4 +99,51 @@ struct ThinWallCheckTests {
         let wall = ThinWallCheck(mesh).wall(behind: 0, limit: 0.4)
         #expect((wall != nil) == isWall, "plate normal \(normal): \(String(describing: wall))")
     }
+
+    // MARK: Hits on the mesh's own fold (Errata D18)
+
+    /// A vertex at the origin faces up (triangle 0). Triangle 1 shares the vertex's neighbours (1, 0, 0) and (0, 1, 0) and its third
+    /// corner is placed so that the ray (x = y = 0) crosses it `foldDepth` below: the surface folding back on itself. Triangle 2 is a
+    /// plate 0.2 mm down.
+    func foldBesideTheVertex(foldDepth: Float) -> TriangleMesh {
+        let positions: [SIMD3<Float>] = [
+            [0, 0, 0], [1, 0, 0], [0, 1, 0], [-1, -1, -3 * foldDepth], [-1, -1, -0.2], [-1, 1, -0.2], [2, 0, -0.2],
+        ]
+        return TriangleMesh(positions: positions, triangles: [0, 1, 2, 1, 3, 2, 4, 5, 6])
+    }
+
+    /// Also the accepted limit of the rule: a real wall 0.01 mm thick whose far face is this triangle, on the vertex's neighbours, is
+    /// indistinguishable from the fold and is not reported.
+    @Test func aFoldBesideTheVertexIsPassedOverAndTheRayGoesOnToTheWall() throws {
+        let wall = try #require(ThinWallCheck(foldBesideTheVertex(foldDepth: 0.01)).wall(behind: 0, limit: 0.4))
+        #expect(abs(wall.distance - 0.2) < 1e-6 && wall.triangle == 2, "\(wall)")
+    }
+
+    @Test func aFoldBesideTheVertexFartherThanTheLimitIsTheWall() throws {
+        let wall = try #require(ThinWallCheck(foldBesideTheVertex(foldDepth: 0.06)).wall(behind: 0, limit: 0.4))
+        #expect(abs(wall.distance - 0.06) < 1e-6 && wall.triangle == 1, "\(wall)")
+        #expect(ThinWallCheck.selfHitLimit == 0.05)
+    }
+
+    @Test func aPlateOutsideTheNeighbourhoodIsAWallHoweverClose() throws {
+        // The same fold, but on vertices of its own: not the vertex's neighbours, so a real wall 0.01 mm thick.
+        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [-1, -1, -0.01], [-1, 1, -0.01], [2, 0, -0.01]]
+        let wall = try #require(ThinWallCheck(TriangleMesh(positions: positions, triangles: Array(0..<6))).wall(behind: 0, limit: 0.4))
+        #expect(abs(wall.distance - 0.01) < 1e-6 && wall.triangle == 1, "\(wall)")
+    }
+
+    /// A wedge 15 degrees either side of its edge: the faces are `2 x sin(15 degrees)` apart at distance x from the edge. The vertex
+    /// 0.04 mm out on the top face looks across 0.02 mm at the bottom's first strip, which shares the edge's vertices with its
+    /// neighbourhood: that is the mesh closing on the edge. The rows 0.3 and 0.6 mm out see walls of 0.18 and 0.36 mm along their rays,
+    /// which are real and under the 0.4 mm minimum: the knife edge is still reported.
+    @Test func aKnifeEdgeIsStillReportedAwayFromItsTip() throws {
+        let wedge = MeshFixtures.wedge(topSteps: [0, 0.04, 0.3, 0.6, 1.2, 2], bottomSteps: [0, 0.3, 0.6, 1.2, 2], halfAngle: .pi / 12)
+        let result = try ThinWallCheck.run(wedge, minimum: 0.4)
+        #expect(result.places == 1, "one knife edge")
+        let thinnest = try #require(result.thinnest)
+        #expect(thinnest > ThinWallCheck.selfHitLimit, "the tip's own closing is not a wall: \(thinnest)")
+        // 0.3 mm out the faces are 2 × 0.3 × sin 15° = 0.155 mm apart; the ray leaves the top face at 15° to the bottom's normal, 30° in all.
+        #expect(abs(thinnest - 2 * 0.3 * sin(Double.pi / 12) / cos(Double.pi / 6)) < 1e-3, "the wall 0.3 mm out: \(thinnest)")
+        #expect(result.triangles.count > 4, "the faces beside the thin rows are flagged")
+    }
 }
```


- [ ] **Step 2: Run them and see them fail**

Run: `swift build --build-tests 2>&1 | grep "error:" | head -3`
Expected: error `type 'ThinWallCheck' has no member 'selfHitLimit'`.

- [ ] **Step 3: Implement**

`Sources/CreatorImplicit/Mesh/Checks/ThinWallCheck.swift`:

```diff
@@ -2,6 +2,12 @@
 /// back at it is the other side of the wall. A vertex whose wall is thinner than `minimum` is flagged, with its faces. Flagged faces
 /// that touch, and the two sides of one wall, make one place. A surface that meets the ray edge-on (the next face of a sharp corner) is
 /// not the far side of a wall and is passed over, as is any triangle the vertex belongs to.
+///
+/// A hit closer than `selfHitLimit` on a face that touches the vertex's one-ring (the vertex, its neighbours) is the surface folding back
+/// on itself where a sheet closes on a skin, not a wall behind it, and is passed over too: the ray goes on (Errata D18). A knife edge
+/// still shows, a little farther along it, where the two sides are a hit's distance apart or more.
+/// The accepted limit of the rule: a real wall under `selfHitLimit` whose far face shares a vertex with the one-ring is not told from
+/// the fold and is not reported (`aFoldBesideTheVertexIsPassedOverAndTheRayGoesOnToTheWall` pins it).
 public struct ThinWallCheck: Sendable {
     public struct Result: Sendable {
         /// The triangles with a flagged vertex, in order.
@@ -15,11 +21,17 @@ public struct ThinWallCheck: Sendable {
     /// A far side must face back against the vertex normal within 60 degrees.
     static let facingLimit = -0.5
 
+    /// A hit nearer than this (millimetres) on a face that touches the start vertex's one-ring is the mesh folding on itself.
+    static let selfHitLimit = 0.05
+
     private let points: [SIMD3<Double>]
     private let corners: [SIMD3<Int32>]
     private let normals: [SIMD3<Double>]
     private let faceNormals: [SIMD3<Double>]
     private let bvh: TriangleBVH
+    /// The triangles at vertex `v` are `incident[firstIncident[v]..<firstIncident[v + 1]]`.
+    private let firstIncident: [Int32]
+    private let incident: [Int32]
 
     init(_ mesh: TriangleMesh) {
         points = mesh.positions.map { SIMD3<Double>($0) }
@@ -34,6 +46,31 @@ public struct ThinWallCheck: Sendable {
         }
         normals = MeshVertexNormals.of(mesh)
         bvh = TriangleBVH(vertices: points, triangles: corners)
+        var counts = [Int32](repeating: 0, count: points.count + 1)
+        for triangle in corners {
+            for corner in [triangle.x, triangle.y, triangle.z] { counts[Int(corner) + 1] += 1 }
+        }
+        for index in 1..<counts.count { counts[index] += counts[index - 1] }
+        var next = counts
+        var listed = [Int32](repeating: 0, count: Int(counts[counts.count - 1]))
+        for (index, triangle) in corners.enumerated() {
+            for corner in [triangle.x, triangle.y, triangle.z] {
+                listed[Int(next[Int(corner)])] = Int32(index)
+                next[Int(corner)] += 1
+            }
+        }
+        firstIncident = counts
+        incident = listed
+    }
+
+    /// `vertex` and the vertices that share a triangle with it.
+    private func oneRing(of vertex: Int) -> [Int32] {
+        var ring = [Int32(vertex)]
+        for slot in Int(firstIncident[vertex])..<Int(firstIncident[vertex + 1]) {
+            let triangle = corners[Int(incident[slot])]
+            for corner in [triangle.x, triangle.y, triangle.z] where !ring.contains(corner) { ring.append(corner) }
+        }
+        return ring
     }
 
     /// How far the wall behind `vertex` is, and the triangle that is its far side, when it is thinner than `limit`.
@@ -42,12 +79,15 @@ public struct ThinWallCheck: Sendable {
         // The nearest hit this walk has seen: a leaf can hold a nearer triangle before a farther one, and only the nearer is the wall.
         var nearest = Double.infinity
         let direction = -normals[vertex]
+        let ring = oneRing(of: vertex)
         let distance = bvh.nearestHit(origin: points[vertex], direction: direction, limit: limit) { index in
             let triangle = corners[index]
             guard Int(triangle.x) != vertex, Int(triangle.y) != vertex, Int(triangle.z) != vertex,
                   faceNormals[index].dot(normals[vertex]) < Self.facingLimit,
                   let t = Self.hit(points[vertex], direction, points[Int(triangle.x)], points[Int(triangle.y)], points[Int(triangle.z)]),
                   t > 1e-9, t < nearest else { return nil }
+            // Close to the vertex, on a face that touches its neighbourhood: the surface folding back, not a wall. The ray goes on.
+            if t < Self.selfHitLimit, ring.contains(triangle.x) || ring.contains(triangle.y) || ring.contains(triangle.z) { return nil }
             nearest = t
             hitTriangle = index
             return t
```


- [ ] **Step 4: Build, run the suites the task touches, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"` (expected: no output)
Run: `swift test --filter "ThinWallCheckTests|CheckThinWallsNodeTests"`
Expected: PASS ("Test run with 5 tests in 1 suite" for `CheckThinWallsNodeTests` and "14 tests in 1 suite" for `ThinWallCheckTests`).
Run: `swiftlint lint --strict` (expected: `Found 0 violations`)

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorImplicit/Mesh/Checks/ThinWallCheck.swift Tests/CreatorImplicitTests
git commit -m "fix(check): Check Thin Walls passes over a hit on the start vertex's one-ring closer than 0.05 mm (Errata D18)"
```

### Task 5: The bracket acceptance test asserts 0 and 0; bench row i-8

`LightweightBracketAcceptanceTests` drops both `withKnownIssue` blocks and asserts `voids == 0`, `thinPlaces == 0` and no "Walls thinner" in the export summary at the TPMS node's default `blend` (the test sets no `blend`, so the node's own default of 1 mm applies). Measured on the exported 3MF in a release run: **0 voids, 0 thin places, volume fraction 0.7004** (inside 15 to 75 %). So the bracket's blend is not raised and nothing is added to D18 beyond the measurement (Task 6). If a future change leaves a real hit here, raise the bracket graph's `"blend"` in `buildLightweight` (not the node default), and record the measurement in D18.

`ImplicitBenchFixtures.sheet` gains a `skin` parameter (default 0, so the rows i-1 to i-4 are unchanged) and `ImplicitBench` gains row **i-8**: the two checks of a 30 mm cube with a 1.5 mm skin and a 1.2 mm gyroid sheet meshed at 0.3 mm (about 555,000 triangles), timed, no budget. It is the record of the cost the winding number adds. Rows **i-7s** and **i-7h** run `TrappedVolumeCheck.run` (the whole check, including the unsigned-distance fill and the winding number) on a solid and on a hollow 150 mm cube, the largest part that keeps 0.5 mm cells: with the unsigned grid the interior of a thick solid part is one pocket of about 27 million cells that `EnclosedVoids` must not list in full before calling it material (Task 3's judging at 4,096 cells; listing it all peaked at 603 MB), a case i-7 (a hollow cube filled directly) did not cover. Their time and peak resident memory are recorded, each run alone for a peak of its own, and weighed against D16's budget of about 450 MB (Task 6).

**Files:**
- Create: `Tests/CreatorAppTests/Bench/ImplicitBenchChecks.swift`
- Modify: `Tests/CreatorAppTests/LightweightBracketAcceptanceTests.swift`, `Tests/CreatorAppTests/Bench/ImplicitBench.swift`, `ImplicitBenchFixtures.swift`, `ImplicitBenchFixturesTests.swift`

**Interfaces:**
- Consumes: Task 1's `blend` default (through the TPMS node), Tasks 3 and 4's checks, `BenchSamples`, `Bench.requireRelease()`, `MeshTopology` (existing).
- Produces: `ImplicitBenchFixtures.sheet(side:cell:wall:skin:exportResolution:)`; bench rows i-8, i-7s and i-7h.

- [ ] **Step 1: Write the test changes (the acceptance test's known issues come out; with Tasks 1 to 4 in place it is green, and before them it would fail on 103 voids)**

`Tests/CreatorAppTests/LightweightBracketAcceptanceTests.swift`:

```diff
@@ -12,7 +12,8 @@ import Testing
 /// Implicit spec §7's acceptance test, headless on OCCT: a lightweight bracket. The slice's bracket (spec §7.2, as `makeBracketBenchApp` builds
 /// it) → To Implicit → TPMS (Gyroid, Sheet, thickness graded by a distance field, skin 1.5 mm) → Drain Holes (Automatic) → Mesh (0.3 mm) →
 /// Check Thin Walls → Check Trapped Volumes → Output, exported as 3MF. It asserts a closed manifold, no enclosed void, no wall under the
-/// minimum, a volume between 15% and 75% of the solid's (the spec says 40%; see Task 12), and identical bytes on a second run.
+/// minimum, a volume between 15% and 75% of the solid's (the spec says 40%; see Task 12), and identical bytes on a second run. The TPMS
+/// node joins its skin and its sheet with the default `blend` of 1 mm (Errata D18).
 ///
 /// **It needs 7c-2's TPMS node** (`TPMSNode`, `TPMSType`, `TPMSForm`), so it joins the plan only after 7c-2 has merged; whichever of 7c-2 and 7c-3
 /// merges second adds this file.
@@ -87,7 +88,7 @@ struct LightweightBracketAcceptanceTests {
         let first = temporaryURL("lightweight-1.3mf"), second = temporaryURL("lightweight-2.3mf")
         defer { for url in [first, second] { try? FileManager.default.removeItem(at: url) } }
         try await app.export(.threeMF, to: first)
-        // The summary lists the warnings of the nodes the file came from. Measured: Check Thin Walls warns (see the known issue below).
+        // The summary lists the warnings of the nodes the file came from.
         let summary: String
         if case .problem(let problem)? = app.alert { summary = problem.message } else { summary = "" }
         app.alert = nil
@@ -98,20 +99,14 @@ struct LightweightBracketAcceptanceTests {
         #expect(objects.map(\.name) == ["Lightweight Bracket"])
         let mesh = try #require(objects.first?.mesh)
         #expect(MeshTopology(mesh).isClosedManifold, "\(MeshTopology(mesh))")
-        // KNOWN ISSUE (reported, spec §7 asks for 0): measured on the file, the gyroid sheet meeting the 1.5 mm skin leaves about 100
-        // pockets of 2 to 12 cells (about 1 mm wide chambers) that Drain Holes' grid does not see, and some 130 places under 0.4 mm
-        // where the sheet closes on the skin. Drain Holes does drain the 40 or so large chambers. The expectations stay, so the day the
-        // pipeline meets them this test says the issue is fixed.
+        // Spec §7 asks for 0 of each. Errata M5 measured 103 voids and 127 thin places here; Errata D18 found them to be phantoms of the
+        // sharp skin join and of the checks, and the lattice's default 1 mm blend and the robust checks removed them.
         let voids = try TrappedVolumeCheck.run(mesh).voidCount
         let thinPlaces = try ThinWallCheck.run(mesh, minimum: Self.minimumWall).places
         print("LIGHTWEIGHT voids \(voids), thin places \(thinPlaces), volume fraction \(mesh.signedVolume / solidVolume)")
-        withKnownIssue("Drain Holes and Check Trapped Volumes disagree on pockets about a cell across", isIntermittent: false) {
-            #expect(voids == 0, "the drain holes opened every void")
-        }
-        withKnownIssue("the sheet closes on the skin in thin wedges", isIntermittent: false) {
-            #expect(thinPlaces == 0, "no wall under \(Self.minimumWall) mm")
-            #expect(!summary.contains("Walls thinner"), "\(summary)")
-        }
+        #expect(voids == 0, "the drain holes opened every void")
+        #expect(thinPlaces == 0, "no wall under \(Self.minimumWall) mm")
+        #expect(!summary.contains("Walls thinner"), "\(summary)")
         let fraction = mesh.signedVolume / solidVolume
         #expect(fraction > 0.15 && fraction < 0.75, "the part is \(fraction) of the solid's volume")
     }
```

`Tests/CreatorAppTests/Bench/ImplicitBenchFixturesTests.swift`:

```diff
@@ -54,6 +54,22 @@ struct ImplicitBenchFixturesTests {
         #expect(node?.inputValues["cell size"] == .number(100) && node?.inputValues["thickness"] == .number(3))
     }
 
+    @Test func aSkinnedSheetMeshesToAClosedSurfaceTheChecksCanRun() async throws {
+        let part = ImplicitBenchFixtures.sheet(side: 12, cell: 10, wall: 1.2, skin: 1.5, exportResolution: 0.5)
+        let node = part.graph.nodes[part.thickness.id]
+        #expect(node?.inputValues["skin"] == .number(1.5) && node?.inputValues["blend"] == nil, "the node's own default blend")
+        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
+            .evaluate(part.graph, demand: [part.output.id], meshQuality: .export)
+        guard case .mesh(let payload)? = report.results[part.output.id]?.outputs?["mesh"]?.items.first,
+              let mesh = payload as? TriangleMesh else {
+            Issue.record("no mesh: \(String(describing: report.results[part.output.id]?.state))")
+            return
+        }
+        #expect(MeshTopology(mesh).isClosedManifold)
+        _ = try TrappedVolumeCheck.run(mesh)
+        _ = try ThinWallCheck.run(mesh, minimum: 0.4)
+    }
+
     @Test func theSheetIsAnImplicitSolidFillingTheCube() async throws {
         let sheet = ImplicitBenchFixtures.sheet(side: 20, cell: 8, exportResolution: 0.5)
         let solid = try await ImplicitBenchFixtures.solid(of: sheet)
```


- [ ] **Step 2: Run the fixture test and see it fail**

Run: `swift build --build-tests 2>&1 | grep "error:" | head -3`
Expected: error `extra argument 'skin' in call` (from `ImplicitBenchFixturesTests`).

- [ ] **Step 3: Implement the fixture and the bench row**

`Tests/CreatorAppTests/Bench/ImplicitBenchFixtures.swift`:

```diff
@@ -28,11 +28,13 @@ enum ImplicitBenchFixtures {
     static let thickness = 3.0
 
     /// A gyroid sheet through a cube of `side` millimetres, `cell` millimetres per gyroid cell and `wall` thick, meshed at
-    /// `exportResolution` for export.
-    static func sheet(side: Double = 100, cell: Double = cellSize, wall: Double = thickness, exportResolution: Double = 0.1) -> Sheet {
+    /// `exportResolution` for export. With a `skin` the cube keeps a wall of that thickness (joined to the sheet by the node's default
+    /// blend, Errata D18).
+    static func sheet(side: Double = 100, cell: Double = cellSize, wall: Double = thickness, skin: Double = 0,
+                      exportResolution: Double = 0.1) -> Sheet {
         var builder = GraphBuilder()
         let cube = builder.add(ImplicitBoxNode.self, ["size": .vector(Vector3(side, side, side))])
-        let gyroid = builder.add(TPMSNode.self, ["cell size": .number(cell), "thickness": .number(wall)])
+        let gyroid = builder.add(TPMSNode.self, ["cell size": .number(cell), "thickness": .number(wall), "skin": .number(skin)])
         let mesh = builder.add(MeshNode.self, ["export resolution": .number(exportResolution)])
         let output = builder.add(OutputNode.self)
         builder.wire(cube, "implicit", to: gyroid, "region")
```

`Tests/CreatorAppTests/Bench/ImplicitBench.swift`:

```diff
@@ -10,7 +10,7 @@ import Testing
 import CreatorOCCT
 #endif
 
-/// Implicit spec §6, rows i-1 to i-7. Release, idle Mac, `scripts/bench.sh ImplicitBench`; each prints
+/// Implicit spec §6, rows i-1 to i-8. Release, idle Mac, `scripts/bench.sh ImplicitBench`; each prints
 /// `BENCH i-…` lines, with a row's budget judged on the median:
 /// - i-1: the first preview pass of the sheet (a gyroid sheet filling a 100 mm cube; see `ImplicitBenchFixtures`) on a fresh
 ///   evaluator, the GPU's pipelines already compiled: under 1 s. The very first pass of the process, which compiles them, is printed
@@ -31,6 +31,10 @@ import CreatorOCCT
 /// - i-7: the Check Trapped Volumes grid (`OccupancyGrid` and `EnclosedVoids`) of a hollow 150 mm cube, the largest part that keeps 0.5 mm
 ///   cells (32 million cells): the time and the process's peak resident memory, which D16 budgets at about 450 MB for the flood fill.
 /// - i-6: Mesh to Solid of a 100,000-triangle mesh on OCCT (the welding, the faces built on shared vertices, the merge and the check): under 15 s.
+/// - i-7s and i-7h: Check Trapped Volumes (`TrappedVolumeCheck.run`, so the winding number once per pocket) of a solid and of a hollow 150 mm
+///   cube (`ImplicitBenchChecks.swift`): the time and the process's peak resident memory; run each alone for a peak of its own.
+/// - i-8: Check Trapped Volumes and Check Thin Walls of a 30 mm cube with a 1.5 mm skin and a 1.2 mm gyroid sheet, meshed at 0.3 mm (Errata
+///   D18's robust inside test and self-hit rule): the time of each, recorded with no budget.
 @MainActor
 @Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
 struct ImplicitBench {
```

`Tests/CreatorAppTests/Bench/ImplicitBenchChecks.swift` (new):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Row i-8 of `ImplicitBench`: the two checks of a skinned gyroid sheet (implicit spec Errata D18).
extension ImplicitBench {
    @Test func theChecksOfASkinnedSheet() async throws {
        guard Bench.requireRelease() else { return }
        let part = ImplicitBenchFixtures.sheet(side: 30, cell: 10, wall: 1.2, skin: 1.5, exportResolution: 0.3)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(part.graph, demand: [part.output.id], meshQuality: .export)
        guard case .mesh(let payload)? = report.results[part.output.id]?.outputs?["mesh"]?.items.first,
              let mesh = payload as? TriangleMesh else {
            Issue.record("no mesh: \(String(describing: report.results[part.output.id]?.state))")
            return
        }
        let clock = ContinuousClock()
        var traps = BenchSamples("i-8 Check Trapped Volumes of a \(mesh.triangleCount.formatted(.number.grouping(.never))) triangle sheet")
        var thin = BenchSamples("i-8 Check Thin Walls of the same mesh")
        var result = (voids: 0, places: 0)
        for round in 0..<3 {
            let start = clock.now
            result.voids = try TrappedVolumeCheck.run(mesh).voidCount
            let middle = clock.now
            result.places = try ThinWallCheck.run(mesh, minimum: 0.4).places
            if round >= 1 {
                traps.append(from: start, to: middle)
                thin.append(from: middle, to: clock.now)
            }
        }
        print(traps.line())
        print(thin.line())
        print("BENCH i-8 voids \(result.voids), thin places \(result.places)")
        #expect(MeshTopology(mesh).isClosedManifold)
    }

    /// A 150 mm cube, the largest part that keeps 0.5 mm cells, meshed coarsely (its faces are flat), solid or with a 120 mm cavity.
    static func cube(hollow: Bool) async throws -> TriangleMesh {
        let outer = ImplicitSolid.box(halfSize: Vector3(75, 75, 75), cornerRadius: 0)
        let part = hollow ? .subtract([outer, .box(halfSize: Vector3(60, 60, 60), cornerRadius: 0)], blend: .constant(0)) : outer
        return try await ImplicitMesher(evaluator: CPUBatchEvaluator(part)).mesh(part, resolution: 7, quality: .export)
    }

    /// Row i-7s: Check Trapped Volumes on a solid 150 mm cube. The interior is one pocket of about 27 million cells that `EnclosedVoids`
    /// judges material from its first 4,096 listed cells and then stops listing (listing all of it peaked at 603 MB, past D16's 450 MB);
    /// i-7 measured only a hollow cube filled directly. Run it alone (`--filter theChecksOfASolid150mmCube`) for a peak resident size
    /// that is its own.
    @Test func theChecksOfASolid150mmCube() async throws {
        guard Bench.requireRelease() else { return }
        try await Self.measureCube(hollow: false, row: "i-7s", expectedVoids: 0)
    }

    /// Row i-7h: the same on a hollow cube (one real void).
    @Test func theChecksOfAHollow150mmCube() async throws {
        guard Bench.requireRelease() else { return }
        try await Self.measureCube(hollow: true, row: "i-7h", expectedVoids: 1)
    }

    static func measureCube(hollow: Bool, row: String, expectedVoids: Int) async throws {
        let mesh = try await cube(hollow: hollow)
        let before = ImplicitBenchFixtures.peakMemory
        let clock = ContinuousClock()
        let start = clock.now
        let voids = try TrappedVolumeCheck.run(mesh).voidCount
        let elapsed = clock.now - start
        let peak = ImplicitBenchFixtures.peakMemory
        let megabytes = { (bytes: Int) in (Double(bytes) / 1_000_000).formatted(.number.precision(.fractionLength(0))) }
        print("BENCH \(row) \(mesh.triangleCount) triangles, \(voids) void, \(elapsed); peak resident \(megabytes(peak)) MB "
            + "(\(megabytes(before)) MB before the check)")
        #expect(voids == expectedVoids)
    }
}
```


- [ ] **Step 4: Build, run the fixture suite, run the bracket in release, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"` (expected: no output)
Run: `swift test --filter ImplicitBenchFixturesTests` (expected: PASS, "Test run with 6 tests in 1 suite")
Run (the bracket takes about 14 minutes in debug; release builds a second copy but takes about 50 s, and gives the same answer): `swift test -c release --scratch-path <a scratch dir outside the worktree> --filter LightweightBracketAcceptanceTests 2>&1 | grep -E "LIGHTWEIGHT|Test run with|recorded an issue"`
Expected: `LIGHTWEIGHT voids 0, thin places 0, volume fraction 0.70…`, "Test run with 1 test in 1 suite passed".
Run: `swiftlint lint --strict` (expected: `Found 0 violations`)
The bracket also runs in the debug full run of Task 7.

- [ ] **Step 5: Commit**

```bash
git add Tests/CreatorAppTests
git commit -m "test(implicit): the lightweight bracket asserts 0 voids and 0 thin places (Errata D18); bench rows i-8, i-7s and i-7h"
```

### Task 6: The records

No code. Apply each edit below to the file named (the old text is exact, one occurrence each); `git diff --stat` afterwards must show only the five files. The numbers in the performance subsection are from the planning session's release runs; **when the bench is re-run on an idle Mac (`scripts/bench.sh ImplicitBench`), replace the lines and keep the notes**.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` (M5 amended, D18 extended), `docs/roadmap.md`, `CLAUDE.md`, `docs/verification/human-checks.md`, `docs/verification/performance.md`

- [ ] **Step 1: Apply the edits**

`docs/superpowers/specs/2026-10-13-implicit-lattices-design.md`: replace

```text
Fixing it needs Drain Holes and the check to see pockets the same way (a decision for the user).
```

with

```text
Fixing it needs Drain Holes and the check to see pockets the same way (a decision for the user). **Resolved by D18 (7c-3f):** the 103 voids were phantoms of the pseudonormal sign, the 127 thin places knife edges of the sharp skin join, and the bracket now measures 0 voids and 0 thin places at the lattice nodes' default blend.
```

`docs/superpowers/specs/2026-10-13-implicit-lattices-design.md`: replace

```text
  - **The acceptance test asserts 0 voids and no thin walls** at the default blend, and its `withKnownIssue`s come out. If r 1.0 still leaves a real hit after the check is fixed, the plan raises the bracket's blend, not the node default, and records the measurement here.
```

with

```text
  - **The acceptance test asserts 0 voids and no thin walls** at the default blend, and its `withKnownIssue`s come out. If r 1.0 still leaves a real hit after the check is fixed, the plan raises the bracket's blend, not the node default, and records the measurement here.
  - **Measured by 7c-3f.** With the robust checks, the bracket at the default blend of 1 mm gives 0 voids, 0 thin places and 70.0% of the solid's volume, so the bracket's blend is not raised. Check Trapped Volumes asks the winding number once per region of cells, not once per cell (the cells near the surface come from the unsigned distance, and each pocket the flood fill leaves is inside the material or a cavity as a whole): per cell it cost 18.5 s on a 555,000-triangle sheet and 138.6 s on a 2.55-million-triangle one, against 0.8 s and 3.9 s for the pseudonormal sign, and one question per region costs the same as the pseudonormal sign (`docs/verification/performance.md`, row i-8). Drain Holes Automatic keeps the sign of its own field, which is exact, and uses the same definition of a solid cell as the check (inside, or within half a cell of the surface). **That departs from the first sentence of this erratum's Drain Holes line** ("classifies the same way as the check"), and the grid mismatch of M5 is not fixed: Drain Holes' grid is laid over the implicit's bounds and the check's over the mesh, and a field value is not a distance, so half a cell in field units is not geometric. The two agree on the bracket and on three sheets on a skin (`DrainHolesTests`), not by construction: on a sheet of 6 mm cells in an 8 mm box (region moved by (0.2, 0.7, -0.3), meshed at 0.5 mm) Drain Holes finds 2 voids and the check 3, and one void is left after drilling; in a 12 mm box (moved by (0.3, 0.1, 0.2), meshed at 0.6 mm) Drain Holes finds 10 and the check 3. Closing it means either meshing the implicit for Drain Holes (a meshing pass before every drain) or sampling its field on the check's grid; neither is done (user decision 3). `SignedDistanceMesh.signedDistance` keeps the pseudonormal sign for the bake (To Implicit's meshes are the kernel's clean tessellations); `isInside`, `robustSignedDistance` and `windingNumber` are the winding-number sign.
```

`docs/roadmap.md`: replace

```text
7c-3's acceptance has 2 known issues (trapped voids and thin walls, see erratum M5) with a follow-up lane (7c-3f); 7c-4 conformal is next
```

with

```text
7c-3's two known issues (trapped voids and thin walls, erratum M5) are resolved by 7c-3f (erratum D18: a blended skin join and robust checks; code done, human check IL-10 pending); 7c-4 conformal is next
```

`CLAUDE.md`: replace

```text
Linux and Windows.
Implicit lattices, sub-project 7c-2 
```

with

```text
Linux and Windows.
Implicit geometry, sub-project 7c-3f (spec Errata D18, resolving M5: the TPMS, Strut Lattice and Voronoi Lattice nodes gain a `blend` input, default 1 mm, the radius of the smooth union that joins the skin and the lattice, `typeVersion` 2 with a migration that gives a saved graph's node a blend of 0; Check Trapped Volumes decides inside by the mesh's generalized winding number, asked once per region of cells; Check Thin Walls skips a hit under 0.05 mm on a face of the start vertex's one-ring; the lightweight bracket acceptance test asserts 0 voids and 0 thin places, its `withKnownIssue`s gone; plan `docs/superpowers/plans/2026-10-20-7c-3f-skin-blend-and-robust-checks.md`) code is done; its human check IL-10 is pending.
Implicit lattices, sub-project 7c-2 
```

`CLAUDE.md`: replace

```text
`SignedDistanceMesh` (BVH, pseudonormal sign),
```

with

```text
`SignedDistanceMesh` (BVH; `signedDistance(at:)` takes its sign from the pseudonormal, for the bake, and `isInside(_:)`, `robustSignedDistance(at:)` and `windingNumber(at:)` from `WindingNumber`, the generalized winding number summed exactly near the point and as dipoles of BVH clusters far from it, which the checks use; `LazyWindingNumber` builds its clusters on the first such question, so the bake never does),
```

`CLAUDE.md`: replace

```text
face back; the two sides of a wall are one place), `TrappedVolumeCheck` over `OccupancyGrid` (0.5 mm cells within a 32-million-cell
  budget, Errata D16; solid within half a cell of the surface) and `EnclosedVoids` (flood fill from the padded corner), and `DrainHoles`
  (the same test on the implicit; a hole is `subtract` of a moved `cylinder`, so no new `ImplicitSolid` case).
```

with

```text
face back; the two sides of a wall are one place; a hit under 0.05 mm on a face that touches the vertex's one-ring is the mesh folding on itself and is skipped, Errata D18), `TrappedVolumeCheck` over `OccupancyGrid` (0.5 mm cells within a 32-million-cell
  budget, Errata D16; solid within half a cell of the surface, the cells near the surface from `unsignedDistance`) and `EnclosedVoids` (flood fill from the padded corner; with `isInside` it asks the winding number about five cells of each pocket, judged once the pocket has 4,096 cells listed, and drops a pocket that is inside the material, once per pocket and never per cell: per cell it is 23 to 35 times slower, Errata D18), and `DrainHoles`
  (the same test on the implicit, whose inside is the sign of its own field; a hole is `subtract` of a moved `cylinder`, so no new `ImplicitSolid` case).
```

`CLAUDE.md`: replace

```text
(`Implicit/Lattices/`: they share `LatticeSetup` and `LatticeFill`;
```

with

```text
(`Implicit/Lattices/`: they share `LatticeSetup` and `LatticeFill`, which joins the skin and the lattice by a smooth union of the `blend` input, 0 on a graph saved before 7c-3f;
```

`CLAUDE.md`: replace

```text
Regular Polygon is
`typeVersion` 2 (`rotation`).
```

with

```text
Regular Polygon is
`typeVersion` 2 (`rotation`), and so are TPMS, Strut Lattice and Voronoi Lattice (`blend`: their `migrate` stores 0, the sharp join they were saved with, while a new node reads the socket's 1 mm).
```

`docs/verification/human-checks.md`: replace

```text
- [ ] **IL-9 A slicer.** Export an STL of the gyroid at 0.2 mm (IM-9): the part opens in a slicer, the sheet is the thickness set, and no
  hole or non-manifold edge is reported. **Observed:**

```

with

```text
- [ ] **IL-9 A slicer.** Export an STL of the gyroid at 0.2 mm (IM-9): the part opens in a slicer, the sheet is the thickness set, and no
  hole or non-manifold edge is reported. **Observed:**
- [ ] **IL-10 The blended skin join (7c-3f).** In the IL-4 part (skin 1.5) the TPMS inspector shows `blend`, 1 mm on a new node. Orbit to where the gyroid sheet meets the skin's inner face: the join is smooth, a small fillet with no sharp crease or sliver, where `blend` 0 shows the old sharp crease. Drag `blend` from 0 to 3: the fillet grows live and the preview stays responsive. Do the same on a Strut Lattice (its `node blend` rounds the struts' joints, `blend` the skin's) and a Voronoi Lattice. With `skin` 0 `blend` changes nothing. Open a graph saved before 7c-3f that has a lattice with a skin: it looks as it did (its `blend` reads 0). Pinned: `LatticeSkinBlendTests`; the look is human-only. **Observed:**

```

`docs/verification/human-checks.md`: replace

```text
and no warnings in the summary. Pinned:
  `LightweightBracketAcceptanceTests`.
```

with

```text
and no warnings in the summary (7c-3f: 0 voids and 0 thin places, at the TPMS's default `blend`). Pinned:
  `LightweightBracketAcceptanceTests`.
```

`docs/verification/performance.md`: replace

```text
`scripts/bench.sh ImplicitBench` runs rows i-1 to i-7.
```

with

```text
`scripts/bench.sh ImplicitBench` runs rows i-1 to i-8.
```

`docs/verification/performance.md`: replace

```text
| i-7 | the trapped-volume flood fill of a hollow 150 mm cube at the largest grid (28 million cells): time and peak resident memory | recorded |

```

with

```text
| i-7 | the trapped-volume flood fill of a hollow 150 mm cube at the largest grid (28 million cells): time and peak resident memory | recorded |
| i-7s, i-7h | `TrappedVolumeCheck.run` of a solid and of a hollow 150 mm cube: time and peak resident memory against D16's 450 MB (7c-3f) | recorded |
| i-8 | Check Trapped Volumes and Check Thin Walls of a 30 mm cube with a 1.5 mm skin and a 1.2 mm gyroid sheet, meshed at 0.3 mm (7c-3f) | recorded |

```

`docs/verification/performance.md`: replace

```text
the earlier isolated run measured 425 MB peak.

## Raw output
```

with

```text
the earlier isolated run measured 425 MB peak.

### Rows i-5 to i-8 with the robust checks (7c-3f)

Taken 2026-10-20 on a MacBookPro18,2, release build of 7c-3f, on a Mac that was NOT idle (load 3 to 8 on 10 cores, other sessions running): a record, not a verdict. The rows run were i-5, i-6, i-7 and the new i-8 (`scripts/bench.sh ImplicitBench`), and i-7s and i-7h, each alone in its own process (`scripts/bench.sh theChecksOfASolid150mmCube`, then `theChecksOfAHollow150mmCube`). Nothing 7c-3f changed is in i-5 (Decimate) or i-6 (Mesh to Solid), so their budgets are re-checked, not re-argued: both are still met, and i-6 is as close to its budget as in 7c-3.

```text
BENCH i-5 decimate a 2097152 triangle sphere (0.01 mm): median 7039.09 ms, p95 7264.74 ms, max 7264.74 ms (n 3); budget 10000.00 ms: met
BENCH i-5 triangles 2097152 to 290730
BENCH i-7 28094464 cells, 1 void, 3.645953917 seconds; peak resident 738 MB (692 MB before the grid)
BENCH i-6 Mesh to Solid of a 100000 triangle mesh (OCCT): median 14358.38 ms, p95 14416.84 ms, max 14416.84 ms (n 2); budget 15000.00 ms: met
BENCH i-6 faces 100000
BENCH i-8 Check Trapped Volumes of a 554960 triangle sheet: median 2054.87 ms, p95 2061.66 ms, max 2061.66 ms (n 2)
BENCH i-8 Check Thin Walls of the same mesh: median 1267.62 ms, p95 1293.01 ms, max 1293.01 ms (n 2)
BENCH i-8 voids 2, thin places 0
BENCH i-7s 5288 triangles, 0 void, 2.169670875 seconds; peak resident 395 MB (57 MB before the check)
BENCH i-7h 8752 triangles, 1 void, 5.204713291000001 seconds; peak resident 425 MB (57 MB before the check)
```

i-8's two voids are the two gyroid channels the skin closes; the phantom void of Errata M5 is gone. **i-7s and i-7h** (each run alone, so the peak is the check's own on top of the process's 57 MB) put the whole check, the unsigned-distance fill and the winding number included, on a solid and on a hollow 150 mm cube, 28 million cells each: 395 MB and 425 MB resident, inside D16's 450 MB, in 2.2 s and 5.2 s. They exist because the unsigned grid makes the interior of a thick solid part one pocket of 27 million cells: the first version of the check listed all of it before calling it material and peaked at **603 MB** on the solid cube (2.24 s), past the budget. `EnclosedVoids` now judges a pocket from its first 4,096 listed cells and stops listing one judged material (`aPocketBiggerThanTheJudgingSizeIsJudgedBeforeItIsListedInFull`). **The choice of inside test** (Errata D18) was measured on the same sheet and on a larger one, release, with the `SignedDistanceMesh` already built:

| Mesh | Triangles | Grid cells | `SignedDistanceMesh` built | Pseudonormal sign, every cell | Winding number, every cell | Unsigned distance, winding number once per pocket (shipped) |
|---|---|---|---|---|---|---|
| 30 mm cube, skin and sheet | 554,960 | 274,625 | 1.20 s | 0.81 s | 18.5 s | 0.81 s |
| 50 mm cube, skin and sheet | 2,550,048 | 1,157,625 | 7.00 s | 3.92 s | 138.6 s | 3.91 s |

A winding number at every cell is 23 to 35 times the pseudonormal's cost, which the 50 mm cube makes minutes, so Check Trapped Volumes fills the grid from the unsigned distance and asks the winding number about five cells of each pocket the flood fill leaves. All three find the same voids on these two meshes (2 and 8); the phantom shows on the 8 mm fixture of `TrappedVolumePhantomTests`, where the pseudonormal sign finds a third. The winding-number clusters (about 80 bytes a BVH node, plus their build time) are built on the first `isInside` and not with the `SignedDistanceMesh`, so To Implicit's bake, which only asks for the pseudonormal sign, never builds them and row i-3 is unaffected.

## Raw output
```


- [ ] **Step 2: Check the edits applied once each and nothing else moved**

Run: `git diff --stat` (expected: the five files; no source or test file)
Run: `grep -c "IL-10" docs/verification/human-checks.md` (expected: at least 2) and `grep -n "i-8" docs/verification/performance.md | head -3` (expected: the table row, the heading, the bench lines)
Run: `swiftlint lint --strict` (expected: `Found 0 violations`; it ignores Markdown, run it to keep the habit)

- [ ] **Step 3: Commit**

```bash
git add docs CLAUDE.md
git commit -m "docs(7c-3f): D18 measured and M5 resolved; CLAUDE.md, IL-10, roadmap, performance rows i-5 to i-8"
```

### Task 7: One full macOS `swift test`

**Files:** none.

- [ ] **Step 1: Run the whole suite once**

Run (from the worktree; capture the process ID so only your own run can be killed):
```bash
swift test > "$TMPDIR/7c3f-full.log" 2>&1 & echo $!
```
Wait for it to exit (the debug run takes roughly 25 to 30 minutes on an idle Mac; the lightweight bracket alone is about 14 minutes of it). Do not run another `swift test` meanwhile, and never kill by pattern.

- [ ] **Step 2: Judge it by the rule**

```bash
grep -c "Test run with" "$TMPDIR/7c3f-full.log"           # expected: 12
grep -E "recorded an issue|failed after" "$TMPDIR/7c3f-full.log"   # expected: no output
grep -E "Test run with" "$TMPDIR/7c3f-full.log"           # the counts add up to 4620 (the planning-session run measured 4616 before this revision's 4 further tests)
```
The process's exit code must be 0 (`wait <pid>; echo $?`). The "Test run with" count is 12 on macOS; Linux and Windows CI expect 11 (no `CreatorOCCTTests`).

- [ ] **Step 3: Re-check the shared files against master**

Run: `git merge-tree --write-tree HEAD master` (no worktree change). Expected conflicts, if any, only in `CLAUDE.md`, `docs/verification/human-checks.md` or `docs/verification/performance.md`; resolve by keeping both sides (see "Files shared with other tracks"). Then rerun the Task 6 anchor check against master (at `d43f57f` every anchor matched once except the spec's D18 line, which only this branch has):

```bash
python3 - <<'EOF'
import re, subprocess
plan = open("docs/superpowers/plans/2026-10-20-7c-3f-skin-blend-and-robust-checks.md").read()
task6 = plan[plan.index("### Task 6"):plan.index("### Task 7")]
for path, old in re.findall(r"`([^`]+)`: replace\n\n```text\n(.*?)\n```\n\nwith", task6, re.S):
    text = subprocess.check_output(["git", "show", f"master:{path}"], text=True)
    print(text.count(old), path, repr(old[:40]))
EOF
```
Expected: 1 on every line (0 for the spec's D18 line `The acceptance test asserts 0 voids`, which master lacks).

- [ ] **Step 4: Report**

The plan's executor reports the three measured numbers (bracket voids, thin places, fraction), the full-run counts and the bench lines, and does not push (the push to `main` is for after the merge, per the standing rule).

## User decisions

Product behaviour that the spec leaves open or that this plan resolves by a recommendation. The plan is written for the recommended option of each; none blocks it.

1. **How a pocket is judged inside or outside.** D18 says a cell's inside comes from the generalized winding number. Options: (a) once per pocket, from five cells (judged from the first 4,096 cells of a big pocket, which is then not listed in full), with the grid filled from the unsigned distance (recommended: the same voids on every fixture and on the bracket, 0.8 s and 3.9 s on 555 k and 2.55 M triangles); (b) once per cell, to the letter of D18 (23 to 35 times slower: 18.5 s and 138.6 s, minutes on a larger part). The plan departs from the letter for cost, not for the answer.
2. **The sign of To Implicit's bake.** D18 allows the pseudonormal sign to stay if the doc says where. Options: (a) it stays, and the winding number is built lazily so the bake pays nothing for it (recommended: no change to row i-3); (b) the robust sign everywhere (a second query per sample, about double the bake's cost, for kernel tessellations that are already clean).
3. **Drain Holes Automatic.** D18 says it classifies the same way as the check. Options: (a) it keeps the implicit field's own sign, which is exact, with the same definition of a solid cell but not the same grid (recommended: no meshing pass, the bracket and three sheets agree; a sheet of 6 mm cells disagrees, see D18); (b) it meshes the implicit at the check's resolution and drains from the check's own voids (identical voids, a meshing pass of seconds on every edit to Drain Holes); (c) it samples the field on a grid over the mesh's bounds (cheaper than (b), but a field is not a distance, so half a cell is still not geometric). Whichever is chosen, a check after Drain Holes can still report a pocket Drain Holes did not drill; that is what the check is for.
4. **The bracket's volume band.** Spec §7 says 40 %; the acceptance test asserts 15 to 75 % (7c-3's decision) and the bracket measures 70.0 % at the default blend. Options: (a) keep the band (recommended: the fraction is a property of a 1.2 mm gyroid sheet, not of these checks); (b) thin the sheet toward 40 % and tighten the band.

## Risks

- **The self-hit rule** (0.05 mm, one-ring) is validated on the bracket and the synthetic wedge only. A real wall under 0.05 mm whose far face shares a vertex with the one-ring is missed; that is D18's accepted limit, named in `ThinWallCheck`'s doc comment and pinned at 0.01 mm by `aFoldBesideTheVertexIsPassedOverAndTheRayGoesOnToTheWall`.
- **Mesher arithmetic on other platforms.** The phantom wedge is narrower than a mesh cell, so the old-classifier pin runs on macOS only. `DrainHolesTests`' agreement cases compare two counts (equal, and at least 2) on sheets whose channels are several cells wide; if one of them differs on the Linux or Windows job, gate that case the same way (`#if os(macOS)`) rather than loosening the bracket.
- **Drain Holes and the check can disagree** on a pocket a cell or two wide (user decision 3). The bracket and three sheets agree.
- **Memory** of the check on a solid 150 mm cube is measured in row i-7s against D16's 450 MB (Task 6 records it).
- **Debug run length.** The bracket is about 14 minutes of the 25 to 30 of Task 7's debug run; release gives the same answer in about 50 s.
- **The Windows 6.4 compiler** asserts on `async` functions that hold a loop's locals across an `await`: every loop added here is in a non-async function or test, and `LazyWindingNumber` uses `Synchronization.Mutex`, as `GreyImageCache` (built on every platform) already does.

## Self-Review

**Spec coverage (D18, point by point).**
- `blend` on TPMS, Strut and Voronoi, mm, default 1.0, `LatticeFill` smooth union, old files read 0, round-trip and missing-key tests, inspector like other mm inputs, a `.number` socket like `skin` and `node blend`: Task 1.
- Check Trapped Volumes with a robust inside test (generalized winding number, measured against the cost of per-cell use and per-pocket use; i-5 and i-6 untouched and re-measured; the memory of a solid and a hollow 150 mm cube through the whole check, i-7s and i-7h), `SignedDistanceMesh` documents where the pseudonormal sign stays and offers the robust sign (its clusters built lazily, so the bake does not pay), Drain Holes Automatic: Tasks 2 and 3. **Drain Holes is the one departure from D18's text**: it keeps its own field's sign, which is exact, with the same definition of a solid cell as the check but not the same grid, so D18's "classifies the same way" is met only in definition; the grid mismatch of M5 is not fixed, the two agree on the bracket and three sheets and disagree on a sheet of 6 mm cells (user decision 3).
- Check Thin Walls skips self-adjacent hits under 0.05 mm, 0.2 mm wall fixtures kept, a knife-edge test added, the accepted limit of the rule named in the doc comment and a test comment: Task 4.
- Regression fixture for the phantom-void wedge, failing on the old classifier (`thePseudonormalSignFindsAPhantomVoidInTheSameMesh`, macOS only, pins that it still finds a phantom, with no exact counts) and passing on the new; the bracket asserts 0 and 0 at the default blend, fraction in 15 to 75 %: Tasks 3 and 5.
- Records: CLAUDE.md, human check IL-10 (blended join looks smooth in the viewport), performance rows, M5 amended to say D18 resolved it, roadmap: Task 6.
- One full macOS run, 12 "Test run with" lines: Task 7.

**Placeholder scan.** No TBD or "similar to" steps; every code step carries the diff or the file. The bracket's debug run is long and the plan says so and gives the release equivalent.

**Type consistency.** `LatticeSetup.blend` / `blendSocket` / `sharpJoin` and `LatticeFill.fill(...blend:)` (Task 1); `WindingNumber.value(at:farRatio:)` / `contains(_:)` and `SignedDistanceMesh.isInside` / `unsignedDistance` / `robustSignedDistance` / `windingNumber` (Task 2) are the names Task 3 uses; `EnclosedVoids(_:isInside:)`, `EnclosedVoids.samples` and `TrappedVolumeCheck.findVoids(in:bounds:)` (Task 3) are used by Task 3's tests and Task 5's bench; `TrappedVolumePhantomTests.skinnedSheet()` (Task 3) is used by `DrainHolesTests` in the same task; `ThinWallCheck.selfHitLimit` and `MeshFixtures.wedge` (Task 4).

**Review Focus.** Each of the five lines has its test named in the task that owns the code.

## Verification record (planning session)

Each task's code was applied in order in a scratch copy of the worktree (a sibling `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI`), and for each task `swift build --build-tests` finished with no new warnings (the only warnings are the linker's pre-existing "building for macOS-26.0, but linking with dylib …opencascade" lines), the task's suites passed, and `swiftlint lint --strict` reported zero violations. The review revision (the lazy winding number, the macOS-only phantom pin, the three agreement cases, the early judging of a big pocket, the i-7s and i-7h rows, the accepted-limit comments) was applied on top and re-verified the same way: `SignedDistanceMeshTests|WindingNumberTests|DistanceBakerTests` 23 tests, `ThinWallCheckTests|CheckThinWallsNodeTests` 14 and 5, the Task 3 filter 10 (`CreatorNodesTests`) and 35 (`CreatorImplicitTests`), `ImplicitBenchFixturesTests` 6, `swiftlint lint --strict` zero violations. The bracket ran in release (0, 0, 70.04 %). Release bench rows (a Mac that was not idle, so a record and not a verdict): i-7s 395 MB and i-7h 425 MB peak resident (603 MB on the solid cube before the early judging), i-8 2.05 s and 1.27 s. The one full `swift test` on macOS, run on the scratch copy after Task 6 and the revision (debug): exit 0, **12** "Test run with" lines, **4620** tests (303, 91, 187, 205, 193, 1080, 172, 376, 569, 48, 678 and 718), no "recorded an issue", no "failed after", no known issue; the lightweight bracket passed with the `withKnownIssue`s gone and printed `LIGHTWEIGHT voids 0, thin places 0, volume fraction 0.7003955459630002`.
