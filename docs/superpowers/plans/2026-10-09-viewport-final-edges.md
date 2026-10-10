# Viewport: a Selected Rule's Edges Over the Final Part — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In Final preview, the edges of a selected selection-rule node (Edges by Tag, All Edges, Edge Set Op and the other rules) whose solid isn't shown glow pink over the Final part where they lie on it, and show as an overlay where they don't, so the user sees what the rule selects.

**Architecture:** The app shell (`SceneBuilder`) adds one **guide** `ViewportItem` (`isGuide: true`) per solid that a selected rule is on and no shown, non-ghost part holds, carrying the rule's edges. The viewport (`CreatorViewport`, which stays free of `CreatorGraph`) draws only a guide's selected edges, in the selection colour, after the solids and ghosts, depth-tested with the same bias B-rep edges get: edges on the part cover its white edge, edges in free space float over it, and edges the part hides are redrawn faded. A guide has no surfaces and is no part of the scene: it never widens `sceneBounds`, the orbit pivot, the ID pass, hover or the face menu. No geometric "do these coincide" test exists anywhere: the depth test decides.

**Tech Stack:** Swift 6.2 strict concurrency, Swift Testing, Metal (MSL source in `ViewportShaders.swift` is **not** changed), MetalUI (no new gaps), OCCT via `CreatorOCCT` in the GPU tests.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` §6.3 (Viewport: "Faces and edges selected by the active rule glow **pink**"; the Edge pass; the ID pass) and §6.1 (Preview modes), with all its Errata, above all **Errata (M6)**: "§6.3's 'edges selected by the active rule glow pink' holds in Selected-node preview and in pick mode, and in Final only when the rule's own solid is shown ... Owner: roadmap row 'Viewport: a selected rule's edges over the Final part'", and the M6 plan's Decision 10 ("in Final it waits for the viewport to draw a non-shown solid's edges over the part"). This plan is that owner. Task 5 writes the new Errata.

**Worktree:** `/Users/maxburger/Developer/MetalCreator-finaledges`, branch `viewport-final-edges`, off master `4e4be6e` (1643 tests). Run every command from the worktree. Never edit `Package.swift`'s MetalUI path, never modify `../MetalUI`, never take screenshots.

## Files shared with other tracks (what the side that merges second must keep)

| File | Shared with | The second merger keeps |
|---|---|---|
| `Sources/CreatorApp/AppModel+Scene.swift` | groups-editor (Preview "Selected node" per level; `refreshScene`/`applyPreview`) | the `showsGuides: previewMode == .final && sketch == nil` argument on the `SceneBuilder.scene` call. If groups-editor changes which nodes are `shown` or adds a level, guides still belong to Final preview at the level shown, with no guide in a "Selected node" preview. |
| `Sources/CreatorApp/SceneBuilder.swift` | groups-editor | `showsGuides`, `guides(for:notShownIn:)`, the `selectedSets` local. A per-level `scene` signature must keep a way to say "no guides". |
| `Sources/CreatorApp/ViewportItem+Comparison.swift` | none likely | `isGuide == other.isGuide` in `drawsTheSame` (without it a guide appearing doesn't re-show the scene). |
| `Sources/CreatorViewport/Render/ViewportRenderer.swift` | sketcher-s5c (overlay and picking) | `drawGuides` between the ghost pass and `drawOverlay`; `!$0.isGuide` in `drawSolids`' filter and in `drawEdges`; `where !item.isGuide` in **both** ID-pass loops; `meshes` as `private(set)` and `edgeDepthBias` internal (the guide extension reads them). Any new loop s5c adds over `frame.items` (new picking, an overlay that follows items) must skip guides. |
| `Sources/CreatorViewport/Render/ViewportPipelines.swift` | sketcher-s5c (new overlay pipelines) | the `depthBehind` state (additive: keep both sets of pipelines). |
| `Sources/CreatorViewport/Render/FrameItem.swift`, `Model/ViewportModel+Frame.swift` | sketcher-s5c | `isGuide` (last field, defaulted) and passing it from `ViewportItem`. |
| `Sources/CreatorViewport/Model/ViewportModel.swift` (`sceneBounds`), `ViewportModel+Input.swift` (`pivotPoint`) | sketcher-s5c (`framingBounds`, picking) | the `!$0.isGuide` filters. A tool's `framingBounds` is unaffected. |
| `Sources/CreatorViewport/Model/ViewportItem.swift` | none likely | `isGuide` and its trailing, defaulted init parameter. |
| `Sources/CreatorViewport/Render/EdgeInstanceKey.swift`, `GPUGeometry.swift`, `GPUMesh.swift` | sketcher-s5c only if it changes edge instances | the defaulted `hidden` parameter and field. |
| `Tests/CreatorViewportTests/Support/TestFrames.swift`, `OffscreenRenderTests.swift` | sketcher-s5c | nothing changes in them here (`FrameItem.isGuide` is defaulted), but `GuideRenderTests` reads `OffscreenRenderTests.front` and `.size`: keep those two statics. |
| `Tests/CreatorAppTests/SceneTests.swift` | groups-editor | the renamed `aRuleSelectedInFinalPreviewGlowsOnItsOwnShownSolidAndAddsNoGuide` and its `allSatisfy { !$0.isGuide }` line. |
| `Tests/CreatorAppTests/AppAcceptanceTests.swift`, `Bench/BracketBenchApp.swift` | naming-face-picks (bracket tests), kernel-blend-max (possibly) | in the acceptance test, filter guides before counting parts; in `makeBracketBenchApp`, the `selection = []` that keeps the benchmarks measuring the bracket alone. |
| `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/verification/human-checks.md`, the parent spec's trailing Errata | every track | both sides' text. Each track appends its own Errata section at the end of the spec and its own rows: resolve the conflict by keeping both. This plan's roadmap edit changes one row in place (the "Viewport: a selected rule's edges over the Final part" row); human check **M6-15** is appended after M6-14 (if another track took M6-15, renumber ours, nothing else refers to the number but the spec Errata, the roadmap row and `human-checks.md`). |

`docs/metalui-gaps.md`: **no change and no new gap.** Everything here is MetalCreator's own viewport code.

## Global Constraints

- Swift 6 strict concurrency; Swift Testing (`@Test`, `#expect`), no XCTest. Target macOS 26, MetalUI as the UI framework (spec §3.1).
- `@MainActor @Observable` models; behaviour in models, views thin; one type per Swift file; no force unwraps, no GCD, `FormatStyle` for formatting (this plan adds none).
- `CreatorViewport` depends on Kernel, Geometry, CreatorStyle and MetalUI only, **never `CreatorGraph`** (CLAUDE.md). A guide is a plain `ViewportItem` flag, so this holds.
- Colour only through theme roles (`CreatorStyle`): the guide's colour is `ViewportPalette.selection`, faded for hidden parts; no new hex values.
- `swiftlint lint --strict` reports zero violations (type bodies <= 250 lines: `ViewportRenderer` is at the limit, which is why Task 3 moves `drawGuides` into an extension, and `ViewportModelTests` is at it, which is why guide tests get their own suite).
- A full `swift test` passes only if its exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear. Master has 1643 tests.
- The MSL structs in `ViewportShaders.swift` and the Swift structs mirror each other byte for byte (`GPUDataTests` pins the strides): this plan changes neither.
- Pixel colours are compared in tests only where the colours are far apart (the pink #ff79c6 against the dark background, the part's white edge and shaded faces), as the view cube's label test already does.

## User decisions (defaults written into this plan)

1. **Hidden parts of a guide's edges.** Default: drawn faded (35% of the selection colour) where the part hides them, so an edge inside the material is still seen (Task 3). Alternative: drawn only where visible. To take the alternative, skip Task 3 entirely (Task 2 is the visible-only behaviour; Task 2's last test then stays as it is).
2. **A rule whose solid another Output shows.** Default: its edges glow on that item and no guide is added (the old test's box case). Alternative: always add a guide too (the same lines drawn twice, plus the finished part's overlay). To take it, drop the `notShownIn` condition from `SceneBuilder.guides`.
3. **Selected-node preview with several nodes selected, sketch mode, pick mode.** Default: no guides (Errata (M6) says the viewport is empty with several selected; the sketch scene is dimmed; pick mode shows only the solid being picked on).
4. **Style.** Default: the same pink and the same 2.5 pt width as a glow. Alternative: a dashed or thicker line to tell guide from glow.
5. **Several rules selected in Final.** Default: every selected rule gets a guide, so a multi-selection of rules draws all their edges (matching the existing glow on a shown solid, and the spec's "the active rule" read as "the selected rules"). Alternative: draw guides only when exactly one rule is selected (the selection of one is "the active rule"). To take it, `SceneBuilder.scene` makes guides only when `selection.count == 1`; the glow on a shown solid is unchanged.
6. **Face rules.** Not covered: nothing previews a selected set of faces in any mode today.

Noted, not a decision: in every Final view a guide is made for a rule whose solid is a pre-feature intermediate, even when all its edges coincide with the part's (a rule whose edges the fillet leaves alone). They then simply recolour the part's edges pink, which is the glow the spec asks for.

## Review Focus

Inputs the spec implies and no happy-path test would exercise, most likely first. Each has its test in the task named.

1. A selected rule in error, blocked, or still holding an old result must not draw edges from its stale solid (a lie, as ghosts' highlights are): `SceneGuideTests.aRuleInErrorOrBlockedDrawsNoGuide` (the part still shows, as a ghost, and nothing is a guide) and `anUnsuccessfulResultHasNoEdgeSetsToMakeGuidesFrom` (the guide builder fed an unsuccessful result gives none) (Task 4).
2. Two selected rules on one hidden solid draw one guide with both rules' edges; a rule with no edges, or whose solid is shown, makes none; a solid shown only as a stale ghost still gets a guide: `rulesOnTheSameHiddenSolidShareOneGuide` (Task 4).
3. A guide must never move the camera or take input: the first framing, F, and the orbit pivot ignore its surfaces (F with a rule selected frames its edges), and the ID pass never returns it: `ViewportGuideTests` (Task 1), `GuideRenderTests.aGuideIsNeverPicked` (Task 2).
4. Where the scene is meant to be empty or dimmed there is no guide: Selected-node preview with several nodes selected, sketch mode: `guidesAppearOnlyInFinalPreview`, `sketchModeShowsNoGuides` (Task 4). The pick-mode scene bypasses `SceneBuilder`.
5. Edges on the part's own edges must not shimmer or double up: the guide shares the edge bias, and the faded redraw passes only where the part is strictly nearer: `aGuideEdgeOnThePartCoversThePartsEdgeInTheSelectionColour`, `anEdgeBehindThePartShowsFaintlyThroughIt` (Tasks 2, 3), human check M6-15.

## Risks

- **Orbit cost.** A guide's edges are drawn twice per frame (solid and faded passes) with the part's depth, so a selected rule adds two small line draws per frame. Edge instances are cached per key, so nothing is rebuilt while orbiting.
- **Extra tessellation on every selection change.** A guide's solid is the pre-feature solid, and the viewport's mesh cache tessellates it as well (extra mesh and edge buffers per selected rule) the first time it is shown. The cache keeps it while the selection stays on that rule. The benchmark fixture is protected only by `selection = []` in `makeBracketBenchApp`. Optional, after the task: record one release bench of the bracket with a rule selected in `docs/verification/performance.md` (`scripts/bench.sh`); not a gate.
- **Scene diffing.** A guide appearing must re-show the scene: `drawsTheSame` compares `isGuide` (Task 4, `aGuideDrawsDifferentlyFromThePartItShadows`).

## File structure

Create:
- `Sources/CreatorViewport/Render/ViewportRenderer+Guides.swift` — `drawGuides` (Task 3 moves it here).
- `Sources/CreatorViewport/Render/ViewportPalette+Guides.swift` — `hiddenGuideOpacity`, `hiddenSelection`.
- `Tests/CreatorViewportTests/ViewportGuideTests.swift` — model behaviour of guides.
- `Tests/CreatorViewportTests/GuideRenderTests.swift` — offscreen pixel and ID-pass tests.
- `Tests/CreatorAppTests/SceneGuideTests.swift` — scene building, preview modes, sketch mode.

Modify:
- `Sources/CreatorViewport/Model/ViewportItem.swift`, `ViewportModel.swift`, `ViewportModel+Input.swift`, `ViewportModel+Frame.swift`, `Render/FrameItem.swift`
- `Sources/CreatorViewport/Render/ViewportRenderer.swift`, `EdgeInstanceKey.swift`, `GPUGeometry.swift`, `GPUMesh.swift`, `ViewportPipelines.swift`
- `Sources/CreatorApp/SceneBuilder.swift`, `AppModel+Scene.swift`, `ViewportItem+Comparison.swift`
- `Tests/CreatorViewportTests/GPUDataTests.swift`, `Tests/CreatorAppTests/SceneTests.swift`, `AppAcceptanceTests.swift`, `Bench/BracketBenchApp.swift`
- `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `docs/superpowers/roadmap.md`, `docs/verification/human-checks.md`, `CLAUDE.md`

Test counts (each measured by a full `swift test` after the task): Task 1 master + 4 (1647), Task 2 master + 8 (1651), Task 3 master + 9 (1652), Task 4 master + 16 (1659), Task 5 master + 16 (1659, docs only).

For every task, "verify" means all of: `swift build --build-tests` with no new warnings (the baseline has two, plus the Homebrew OCCT `ld: warning: ... built for newer version 27.0` lines, which are environmental), a full `swift test` that passes by the rule above, and `swiftlint lint --strict` with zero violations.

---

### Task 1: `ViewportItem.isGuide` and the model rules

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportItem.swift`, `Sources/CreatorViewport/Render/FrameItem.swift`, `Sources/CreatorViewport/Model/ViewportModel+Frame.swift`, `Sources/CreatorViewport/Model/ViewportModel.swift`, `Sources/CreatorViewport/Model/ViewportModel+Input.swift`
- Create: `Tests/CreatorViewportTests/ViewportGuideTests.swift`

**Interfaces:**
- Consumes: `ViewportModel.show(_:)`, `sceneBounds`, `pivotPoint(under:)`, `selectionBounds()`, `frame(at:)`; test helpers `fakeBox`, `StubMeshKernel`, `ManualClock`, `isClose` (all existing).
- Produces: `ViewportItem.init(solid:isGhost:selectedFaces:selectedEdges:isGuide:)` with `isGuide: Bool = false` last; `ViewportItem.isGuide`; `FrameItem.isGuide` (`var isGuide = false`, last).

- [ ] **Step 1: Write the failing tests**

```swift
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// Guides (spec §6.3, Errata (M6)): the selected edges of a solid the scene doesn't show, drawn over the part. A guide
/// is no part of the scene: it never frames, orbits or picks. (How they draw: `GuideRenderTests`.)
@MainActor
struct ViewportGuideTests {
    func makeModel(pose: CameraPose? = nil) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        return model
    }

    func show(_ model: ViewportModel, _ items: [ViewportItem]) async {
        model.show(items)
        await model.waitForMeshes()
    }

    @Test func aGuideNeverWidensTheFramedScene() async throws {
        let model = makeModel()
        let part = try await fakeBox()
        let faraway = try await fakeBox(width: 400, depth: 400, height: 400)
        await show(model, [ViewportItem(solid: part),
                           ViewportItem(solid: faraway, selectedEdges: [EdgeID(1)], isGuide: true),
        ])
        #expect(model.items.count == 2)
        #expect(model.sceneBounds == part.bounds)
        #expect(isClose(model.pose.target, part.bounds.center), "the first framing ignores the guide")
    }

    @Test func aGuideAloneIsNotASceneAndHasNothingToOrbitAbout() async throws {
        let model = makeModel()
        let guide = try await fakeBox(width: 400, depth: 400, height: 400)
        await show(model, [ViewportItem(solid: guide, selectedEdges: [EdgeID(1)], isGuide: true)])
        #expect(model.sceneBounds == nil)
        #expect(model.pivotPoint(under: ScreenPoint(200, 150)) == nil, "a ray through a guide's surface isn't a hit")
        let part = try await fakeBox()
        await show(model, [ViewportItem(solid: part)])
        #expect(isClose(model.pose.target, part.bounds.center), "a guide-only scene didn't use up the first framing")
    }

    @Test func aGuidesSelectedEdgesAreWhatFramingTheSelectionFrames() async throws {
        let model = makeModel(pose: CameraPose())
        let part = try await fakeBox()
        let guide = try await fakeBox(width: 100, depth: 100, height: 100)
        await show(model, [ViewportItem(solid: part), ViewportItem(solid: guide, selectedEdges: [EdgeID(1)], isGuide: true)])
        let bounds = try #require(model.selectionBounds())
        #expect(isClose(bounds.size.x, guide.bounds.size.x), "edge 1 spans the guide's width, not the part's")
    }

    @Test func theFrameCarriesTheGuideFlag() async throws {
        let model = makeModel(pose: CameraPose())
        await show(model, [ViewportItem(solid: try await fakeBox()),
                           ViewportItem(solid: try await fakeBox(width: 3), selectedEdges: [EdgeID(1)], isGuide: true),
        ])
        let frame = model.frame(at: 0)
        #expect(frame.items.map(\.isGuide) == [false, true])
        #expect(frame.items[1].selectedEdges == [EdgeID(1)])
        #expect(frame.sceneBounds == model.sceneBounds)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error | head -3`
Expected: errors that `extra argument 'isGuide' in call` / `value of type 'FrameItem' has no member 'isGuide'`.

- [ ] **Step 3: Add the flag to `ViewportItem`**

In `Sources/CreatorViewport/Model/ViewportItem.swift`, add a line to the type's doc list, the property, and the init parameter, so the type reads:

```swift
import CreatorKernel

/// One solid the viewport shows (spec §6.3). The host builds these from the document:
/// - output solids, and last-good results drawn as ghosts while their node is in error (spec §4.4)
/// - the faces and edges the active selection rule picks, which glow pink
/// - guides: the edges a selected rule picks on a solid the scene doesn't show, drawn over the part (`isGuide`)
public struct ViewportItem: Sendable {
    public var solid: Solid
    public var isGhost: Bool
    public var selectedFaces: Set<FaceID>
    public var selectedEdges: Set<EdgeID>
    /// A guide is not part of the scene (spec §6.3, Errata (M6)): it carries a solid the host doesn't show, and only
    /// its `selectedEdges` are drawn, in the selection colour, over the shown scene. They glow where they lie on a
    /// shown part and float free where they don't. A guide's surfaces and edges are otherwise never drawn, picked,
    /// hovered or offered in the face menu, and it never widens `sceneBounds` or the point the camera orbits about.
    public var isGuide: Bool

    public init(solid: Solid, isGhost: Bool = false, selectedFaces: Set<FaceID> = [], selectedEdges: Set<EdgeID> = [],
                isGuide: Bool = false) {
        self.solid = solid
        self.isGhost = isGhost
        self.selectedFaces = selectedFaces
        self.selectedEdges = selectedEdges
        self.isGuide = isGuide
    }
}
```

- [ ] **Step 4: Carry it to the frame**

`Sources/CreatorViewport/Render/FrameItem.swift`: replace the last field and brace

```swift
    var selectedEdges: Set<EdgeID>
}
```

with

```swift
    var selectedEdges: Set<EdgeID>
    /// Only the selected edges are drawn, over everything else (`ViewportItem.isGuide`).
    var isGuide = false
}
```

`Sources/CreatorViewport/Model/ViewportModel+Frame.swift`: replace

```swift
                                        selectedFaces: item.selectedFaces, selectedEdges: item.selectedEdges))
```

with

```swift
                                        selectedFaces: item.selectedFaces, selectedEdges: item.selectedEdges,
                                        isGuide: item.isGuide))
```

- [ ] **Step 5: Keep guides out of the scene's bounds and the orbit pivot**

`Sources/CreatorViewport/Model/ViewportModel.swift`: replace

```swift
    /// The union of every shown solid's bounds, ghosts included.
    public var sceneBounds: BoundingBox? {
        items.reduce(BoundingBox?.none) { bounds, item in bounds?.union(item.solid.bounds) ?? item.solid.bounds }
    }
```

with

```swift
    /// The union of every shown solid's bounds, ghosts included and guides left out.
    public var sceneBounds: BoundingBox? {
        items.filter { !$0.isGuide }.reduce(BoundingBox?.none) { bounds, item in
            bounds?.union(item.solid.bounds) ?? item.solid.bounds
        }
    }
```

`Sources/CreatorViewport/Model/ViewportModel+Input.swift` (`pivotPoint(under:)`): replace

```swift
        let meshes = items.enumerated().compactMap { index, item in
            cache.mesh(for: item.solid).map { (solidIndex: index, mesh: $0.mesh) }
        }
```

with

```swift
        let meshes = items.enumerated().compactMap { index, item in
            item.isGuide ? nil : cache.mesh(for: item.solid).map { (solidIndex: index, mesh: $0.mesh) }
        }
```

(`selectionBounds()` is deliberately unchanged: F with a rule selected frames the guide's selected edges.)

- [ ] **Step 6: Verify**

Run: `swift test --filter ViewportGuideTests` — Expected: 4 tests pass. Then the full verify (see above). Expected: 1647 tests (master + 4), 11 "Test run with" lines, 0 new warnings, 0 lint violations.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests/ViewportGuideTests.swift
git commit -m "feat(viewport): guide items — selected edges of a solid the scene doesn't show"
```

---

### Task 2: Draw a guide's edges over the scene, never its surfaces, never in the ID pass

**Files:**
- Modify: `Sources/CreatorViewport/Render/ViewportRenderer.swift`
- Create: `Tests/CreatorViewportTests/GuideRenderTests.swift`

**Interfaces:**
- Consumes: `FrameItem.isGuide` (Task 1); `EdgeInstanceKey`, `GPUMesh.edges(_:palette:device:)`, `drawLines(...)`, `pipelines.depthTest`, `edgeDepthBias(_:)` (all existing); `OffscreenRenderTests.front` and `.size`, `TestFrames.frame`, `OCCTKernel`.
- Produces: `ViewportRenderer.drawGuides(_:_:scale:_:)` (private for now); the guide ordering: solids, grid, edges, ghosts, **guides**, overlay, handles.

- [ ] **Step 1: Write the failing tests**

The pixel tests render one frame at 2 pixels per point and read a few pixels. The fixture: the 10 x 20 x 30 part of `OffscreenRenderTests` seen from the front, orthographic, 5 points per mm, and a wide guide box (30 x 20 x 30) whose left edges are at view x = 25, clear of the part (x 75...125), and whose top front edge runs along the part's own top front edge (view y = 25).

```swift
import CreatorGeometry
import CreatorKernel
import CreatorOCCT
import Metal
import Testing
@testable import CreatorViewport

/// Guides (spec §6.3, Errata (M6)): a guide's selected edges are drawn over the scene, its surfaces and ID-pass pixels
/// never. These read a few pixels back, like the view cube's label test. The colours are far apart: the selection
/// pink (#ff79c6), the edge white (#f8f8f2) and the dark background.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct GuideRenderTests {
    /// A box standing on z = 0, centred on x = 0 and y = 0 (as `OffscreenRenderTests.box()` builds one).
    func box(width: Double, depth: Double, height: Double) async throws -> (solid: Solid, mesh: DisplayMesh) {
        let kernel = OCCTKernel()
        let solid = try await kernel.extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height,
                                             mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        return (solid, try await kernel.tessellate(solid, tolerance: 0.05))
    }

    /// `OffscreenRenderTests`' view (front, orthographic, 5 points per mm) of a 10 × 20 × 30 part, with `guide`'s
    /// every edge selected on a guide item when there is one.
    func frame(guide: DisplayMesh?) async throws -> ViewportFrame {
        let part = try await box(width: 10, depth: 20, height: 30)
        var frame = TestFrames.frame(mesh: part.mesh, pose: OffscreenRenderTests.front, size: OffscreenRenderTests.size,
                                     bounds: part.solid.bounds)
        if let guide {
            frame.items.append(FrameItem(meshSerial: 2, mesh: guide, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                         selectedFaces: [], selectedEdges: Set(guide.edgePolylines.keys), isGuide: true))
        }
        return frame
    }

    /// The main pass at 2 pixels per point, as BGRA bytes of a 400 × 400 target.
    func render(_ frame: ViewportFrame) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try ViewportRenderer(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400,
                                                                  mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        renderer.encode(frame, into: target, scale: 2, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: 400 * 400 * 4)
        target.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
        return bytes
    }

    /// The colour at view point (`x`, `y`).
    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func aGuidesEdgesDrawInTheSelectionColourOverEmptySpaceAndItsSurfacesDoNot() async throws {
        let wide = try await box(width: 30, depth: 20, height: 30)
        let with = try render(try await frame(guide: wide.mesh))
        let without = try render(try await frame(guide: nil))
        // The guide spans x -15…15 mm: its left edges are at view x = 25, clear of the part (x 75…125).
        let edge = color(with, 25, 100)
        #expect(edge[0] > 200 && edge[2] > 150 && edge[1] < 170, "pink: \(edge)")
        #expect(color(without, 25, 100)[0] < 100, "the dark background")
        #expect(color(with, 40, 100) == color(without, 40, 100), "inside the guide, off its edges: no surface is drawn")
    }

    @Test func aGuideEdgeOnThePartCoversThePartsEdgeInTheSelectionColour() async throws {
        let wide = try await box(width: 30, depth: 20, height: 30)
        let with = try render(try await frame(guide: wide.mesh))
        let without = try render(try await frame(guide: nil))
        // The guide's top front edge runs along the part's, at view y = 25, between x = 75 and 125.
        #expect(color(without, 100, 25)[1] > 230, "the part's own edge is white")
        let covered = color(with, 100, 25)
        #expect(covered[0] > 200 && covered[1] < 170, "and the guide's edge glows over it: \(covered)")
    }

    @Test func aGuideIsNeverPicked() async throws {
        let wide = try await box(width: 30, depth: 20, height: 30)
        let with = try await frame(guide: wide.mesh)
        let without = try await frame(guide: nil)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        let reference = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        #expect(picker.pick(at: ScreenPoint(25, 100), in: with) == nil, "on the guide's edge")
        #expect(picker.pick(at: ScreenPoint(40, 100), in: with) == nil, "where the guide's face would be")
        #expect(picker.pick(at: ScreenPoint(100, 100), in: with) == reference.pick(at: ScreenPoint(100, 100), in: without),
                "the part is picked as before")
    }

    @Test func anEdgeBehindThePartStaysHidden() async throws {
        let inside = try await box(width: 4, depth: 4, height: 10)
        let with = try render(try await frame(guide: inside.mesh))
        let without = try render(try await frame(guide: nil))
        // The guide's left edges are at view x = 90, 8 mm behind the part's front face.
        #expect(color(with, 90, 150) == color(without, 90, 150))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter GuideRenderTests 2>&1 | grep -E "Expectation|Test run"`
Expected: `aGuideIsNeverPicked` and `aGuidesEdgesDraw...AndItsSurfacesDoNot` fail (the guide is still drawn as an ordinary part: its surface changes the pixel at (40, 100) and its ID pixels pick).

- [ ] **Step 3: Draw guides last, skip them everywhere else**

In `Sources/CreatorViewport/Render/ViewportRenderer.swift`:

1. In the class doc, change `///   ghosts, handles, the view cube (its face names painted on from a label atlas) and the triad. It renders` to `///   ghosts, guides' selected edges, handles, the view cube (its face names painted on from a label atlas) and the triad. It renders`.

2. In `encode`, replace

```swift
        drawSolids(frame, ghosts: true, uniforms, encoder)
        drawOverlay(frame, uniforms, scale: pixelScale, encoder)
```

with

```swift
        drawSolids(frame, ghosts: true, uniforms, encoder)
        drawGuides(frame, uniforms, scale: pixelScale, encoder)
        drawOverlay(frame, uniforms, scale: pixelScale, encoder)
```

3. In `drawSolids`, replace `let items = frame.items.filter { $0.isGhost == ghosts }` with `let items = frame.items.filter { $0.isGhost == ghosts && !$0.isGuide }`.

4. In `drawEdges`, replace `for item in frame.items where !item.isGhost && (!selectedOnly || !item.selectedEdges.isEmpty) {` with `for item in frame.items where !item.isGhost && !item.isGuide && (!selectedOnly || !item.selectedEdges.isEmpty) {`.

5. In `encodeIDs`, change **both** `for item in frame.items {` loops (the face loop starting `guard let gpu = meshes[item.meshSerial], let vertices = gpu.vertexBuffer,` and the edge loop starting `let key = EdgeInstanceKey(solid: item.solidIndex, selected: [], selectedOnly: false, scale: 1)`) to `for item in frame.items where !item.isGuide {`.

6. Add, just before `func drawLines(`:

```swift
    /// A guide's selected edges (spec §6.3, Errata (M6)), after the solids and ghosts so they lie over them. They're
    /// depth-tested with the bias B-rep edges get: where they lie on the part they cover its edge in the selection
    /// colour, and where they float clear of it they show as an overlay. The guide's own surfaces aren't drawn.
    private func drawGuides(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float,
                            _ encoder: any MTLRenderCommandEncoder) {
        let style = LineUniforms(widthOverride: 0, depthBias: Float(edgeDepthBias(frame)), padding0: 0, padding1: 0)
        for item in frame.items where item.isGuide && !item.selectedEdges.isEmpty {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true, scale: scale)
            guard let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, device: device) else { continue }
            drawLines(edges.buffer, count: edges.count, uniforms, depth: pipelines.depthTest, style: style, encoder)
        }
    }

```

(`prepareMeshes` already uploads every frame item's mesh, guides included, which `edges(...)` needs.)

- [ ] **Step 4: Verify**

Run: `swift test --filter GuideRenderTests` — Expected: 4 tests pass. Full verify. Expected: 1651 tests (master + 8), 11 "Test run with" lines, no new warnings, lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorViewport/Render/ViewportRenderer.swift Tests/CreatorViewportTests/GuideRenderTests.swift
git commit -m "feat(viewport): draw a guide's selected edges over the scene, never its surfaces or ID pixels"
```

---

### Task 3: Show the part-hidden pieces faded (user decision 1; skip this task for "visible only")

**Files:**
- Create: `Sources/CreatorViewport/Render/ViewportPalette+Guides.swift`, `Sources/CreatorViewport/Render/ViewportRenderer+Guides.swift`
- Modify: `Sources/CreatorViewport/Render/ViewportRenderer.swift`, `EdgeInstanceKey.swift`, `GPUGeometry.swift`, `GPUMesh.swift`, `ViewportPipelines.swift`, `Tests/CreatorViewportTests/GPUDataTests.swift`, `Tests/CreatorViewportTests/GuideRenderTests.swift`

**Interfaces:**
- Consumes: Task 2's `drawGuides`.
- Produces: `ViewportPalette.hiddenGuideOpacity: Float` (0.35), `ViewportPalette.hiddenSelection: SIMD4<Float>`; `EdgeInstanceKey.hidden: Bool = false`; `GPUGeometry.edgeInstances(..., hidden: Bool = false)`; `ViewportPipelines.depthBehind` (`.greater`, no write); `ViewportRenderer.drawGuides` now internal, in `ViewportRenderer+Guides.swift`; `ViewportRenderer.meshes` is `private(set)`, `edgeDepthBias(_:)` internal.

The faded redraw uses the line pipeline (premultiplied blend) with the **same** biased lines and a `.greater` depth test: a guide pixel passes only where the part (or a ghost) is strictly nearer than the line pulled toward the camera by the edge bias, so edges lying *on* the part never double up.

- [ ] **Step 1: Write the failing tests**

In `Tests/CreatorViewportTests/GPUDataTests.swift`, add before `@Test func faceFlagsMarkHoverAndSelection()`:

```swift
    @Test func hiddenEdgesTakeTheFadedSelectionColour() {
        let mesh = TestMeshes.box(bounds)
        let palette = ViewportPalette.dracula
        let hidden = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 1, selected: [EdgeID(1)], selectedOnly: true, scale: 1,
                                               hidden: true)
        #expect(hidden.count == 1)
        #expect(hidden[0].color == palette.hiddenSelection)
        #expect(SIMD3(hidden[0].color.x, hidden[0].color.y, hidden[0].color.z)
            == SIMD3(palette.selection.x, palette.selection.y, palette.selection.z), "the same hue")
        #expect(abs(hidden[0].color.w - palette.selection.w * ViewportPalette.hiddenGuideOpacity) < 1e-6)
        #expect(hidden[0].color.w < palette.selection.w)
        let shown = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 1, selected: [EdgeID(1)], selectedOnly: true, scale: 1)
        #expect(shown[0].color == palette.selection, "not hidden: unchanged")
    }

```

In `Tests/CreatorViewportTests/GuideRenderTests.swift`, replace the last test `anEdgeBehindThePartStaysHidden` with:

```swift
    @Test func anEdgeBehindThePartShowsFaintlyThroughIt() async throws {
        let inside = try await box(width: 4, depth: 4, height: 10)
        let with = try render(try await frame(guide: inside.mesh))
        let without = try render(try await frame(guide: nil))
        // The guide's left edges are at view x = 90, 8 mm behind the part's front face.
        let seen = color(with, 90, 150)
        let plain = color(without, 90, 150)
        #expect(seen[1] < plain[1] - 10, "pinker than the part's face: \(seen) against \(plain)")
        #expect(seen[1] > 121, "but fainter than the selection pink (green 121): \(seen)")
        #expect(color(with, 100, 100) == color(without, 100, 100), "the part's face between the edges is as before")
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error | head -3` — Expected: `extra argument 'hidden'` / `no member 'hiddenSelection'`.

- [ ] **Step 3: The faded colour**

Create `Sources/CreatorViewport/Render/ViewportPalette+Guides.swift`:

```swift
extension ViewportPalette {
    /// How much of the selection colour shows in a guide's edges where the part hides them (spec §6.3, Errata (M6)).
    static let hiddenGuideOpacity: Float = 0.35

    /// The selection colour, faded: a guide's edges seen through the part in front of them.
    var hiddenSelection: SIMD4<Float> {
        var faded = selection
        faded.w *= Self.hiddenGuideOpacity
        return faded
    }
}
```

- [ ] **Step 4: Thread `hidden` through the edge instances**

`Sources/CreatorViewport/Render/EdgeInstanceKey.swift`: replace the doc line and add the field:

```swift
/// What a mesh's edge instances depend on: the solid index (inside the pick IDs), the selection, the mode, the
/// pixel scale and whether the selection is drawn faded (a guide's edges behind the part).
struct EdgeInstanceKey: Hashable {
    var solid: Int
    var selected: Set<EdgeID>
    var selectedOnly: Bool
    var scale: Float
    var hidden = false
}
```

`Sources/CreatorViewport/Render/GPUGeometry.swift` (`edgeInstances`): replace

```swift
                              selectedOnly: Bool, scale: Float, palette: ViewportPalette = .dracula) -> [LineInstance] {
        var instances: [LineInstance] = []
        for edge in polylines.keys
```

with

```swift
                              selectedOnly: Bool, scale: Float, palette: ViewportPalette = .dracula,
                              hidden: Bool = false) -> [LineInstance] {
        var instances: [LineInstance] = []
        let selectionColor = hidden ? palette.hiddenSelection : palette.selection
        for edge in polylines.keys
```

and replace `let color = isSelected ? palette.selection : palette.edge` with `let color = isSelected ? selectionColor : palette.edge`.

`Sources/CreatorViewport/Render/GPUMesh.swift` (`edges(_:palette:device:)`): replace

```swift
                                                  selectedOnly: key.selectedOnly, scale: key.scale, palette: palette)
```

with

```swift
                                                  selectedOnly: key.selectedOnly, scale: key.scale, palette: palette,
                                                  hidden: key.hidden)
```

- [ ] **Step 5: The depth state**

`Sources/CreatorViewport/Render/ViewportPipelines.swift`: after `let depthTest: any MTLDepthStencilState` add

```swift
    /// A guide's edges behind the part: pass only where something nearer already wrote depth, without writing.
    let depthBehind: any MTLDepthStencilState
```

and after `depthTest = try depth(.lessEqual, write: false)` add `depthBehind = try depth(.greater, write: false)`.

- [ ] **Step 6: Move `drawGuides` into an extension and add the faded draw**

`ViewportRenderer` is at the 250-line type-body limit, so remove `drawGuides` (Task 2's version, with its doc comment) from `ViewportRenderer.swift`, change `private var meshes: [Int: GPUMesh] = [:]` to `private(set) var meshes: [Int: GPUMesh] = [:]` and `private func edgeDepthBias(` to `func edgeDepthBias(`, then create `Sources/CreatorViewport/Render/ViewportRenderer+Guides.swift`:

```swift
import Metal

extension ViewportRenderer {
    /// A guide's selected edges (spec §6.3, Errata (M6)), after the solids and ghosts so they lie over them. They're
    /// depth-tested with the bias B-rep edges get: where they lie on the part they cover its edge in the selection
    /// colour, and where they float clear of it they show as an overlay. Where the part hides them, a second draw
    /// shows them faded (`ViewportPalette.hiddenSelection`), so a rule's edges inside the material can still be seen.
    /// The guide's own surfaces aren't drawn.
    func drawGuides(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float,
                    _ encoder: any MTLRenderCommandEncoder) {
        let style = LineUniforms(widthOverride: 0, depthBias: Float(edgeDepthBias(frame)), padding0: 0, padding1: 0)
        for item in frame.items where item.isGuide && !item.selectedEdges.isEmpty {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true, scale: scale)
            guard let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, device: device) else { continue }
            drawLines(edges.buffer, count: edges.count, uniforms, depth: pipelines.depthTest, style: style, encoder)
            let hiddenKey = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true,
                                            scale: scale, hidden: true)
            guard let faded = meshes[item.meshSerial]?.edges(hiddenKey, palette: frame.palette, device: device) else { continue }
            drawLines(faded.buffer, count: faded.count, uniforms, depth: pipelines.depthBehind, style: style, encoder)
        }
    }
}
```

- [ ] **Step 7: Verify**

Run: `swift test --filter "GuideRenderTests|GPUDataTests"` — Expected: all pass. Full verify. Expected: 1652 tests (master + 9: one new data test; the render test was replaced), 11 "Test run with" lines, no new warnings, lint clean.

- [ ] **Step 8: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): a guide's edges show faded where the part hides them"
```

---

### Task 4: The scene builder makes guides in Final preview

**Files:**
- Modify: `Sources/CreatorApp/SceneBuilder.swift`, `Sources/CreatorApp/AppModel+Scene.swift`, `Sources/CreatorApp/ViewportItem+Comparison.swift`, `Tests/CreatorAppTests/SceneTests.swift`, `Tests/CreatorAppTests/AppAcceptanceTests.swift`, `Tests/CreatorAppTests/Bench/BracketBenchApp.swift`
- Create: `Tests/CreatorAppTests/SceneGuideTests.swift`

**Interfaces:**
- Consumes: `ViewportItem.init(...isGuide:)` (Task 1); `EdgeSet(solid:edges:)`, `SceneBuilder.edgeSets(_:)`, `SceneBuilder.highlighting`, `AppModel.sources`, `makeApp`, `solids(_:_:)`, `GraphBuilder` (`solid()`, `add`, `wire`), `rectangleSketch()`.
- Produces: `SceneBuilder.scene(shown:graph:results:lastGood:selection:showsGuides: Bool = false)`; `SceneBuilder.guides(for sets: [EdgeSet], notShownIn scene: [SceneItem]) -> [SceneItem]`.

- [ ] **Step 1: Rewrite the old test and add the new suite**

`Tests/CreatorAppTests/SceneTests.swift`: the old test pins the behaviour that changes. Replace its doc comment and name, and add one expectation. Replace

```swift
    /// Spec §6.3's glow in Final preview: a selected rule's edges glow on a shown solid only when it is the rule's
    /// own. A rule feeding a Fillet is on the solid before the fillet, which Final shows only if another Output shows
    /// it; on the filleted part nothing glows (spec Errata (M6)). Preview ▸ Selected node shows the rule on its solid.
    @Test func aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid() async throws {
```

with

```swift
    /// Spec §6.3's glow in Final preview: a selected rule's edges glow on a shown solid that is the rule's own. A
    /// rule feeding a Fillet is on the solid before the fillet; where another Output shows that solid it glows there
    /// and nothing else is added, and where none does the rule's edges come as a guide
    /// (`SceneGuideTests.aRuleWhoseSolidIsNotShownDrawsItsEdgesAsAGuideOverTheFinalPart`, Errata (M6)).
    @Test func aRuleSelectedInFinalPreviewGlowsOnItsOwnShownSolidAndAddsNoGuide() async throws {
```

and replace

```swift
        #expect(app.viewport.items.count == 2)
        #expect(app.viewport.items.first { $0.solid === filleted }?.selectedEdges.isEmpty == true,
                "the filleted part isn't the rule's solid, so nothing glows on it")
```

with

```swift
        #expect(app.viewport.items.count == 2, "the rule's solid is shown, so its edges need no guide")
        #expect(app.viewport.items.allSatisfy { !$0.isGuide })
        #expect(app.viewport.items.first { $0.solid === filleted }?.selectedEdges.isEmpty == true,
                "the filleted part isn't the rule's solid, so nothing glows on it")
```

Create `Tests/CreatorAppTests/SceneGuideTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A selected rule's edges over the Final part (spec §6.3, Errata (M6)): when the rule's solid isn't shown, they come
/// as guide items, which the viewport draws over the part.
@MainActor
struct SceneGuideTests {
    /// Rectangle → Extrude → All Edges → Fillet → Output: the Output shows the filleted part, so the box the rule
    /// is on (the Extrude's solid) is shown by no Output.
    struct HiddenRule {
        var graph: Graph
        var extrude: Node
        var edges: Node
        var fillet: Node
    }

    func hiddenRule() -> HiddenRule {
        var builder = GraphBuilder()
        let box = builder.solid()
        let edges = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, at: Vector2(720, 200))
        let output = builder.add(OutputNode.self, at: Vector2(960, 200))
        builder.wire(box.extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        return HiddenRule(graph: builder.graph, extrude: box.extrude, edges: edges, fillet: fillet)
    }

    @Test func aRuleWhoseSolidIsNotShownDrawsItsEdgesAsAGuideOverTheFinalPart() async throws {
        let rule = hiddenRule()
        let app = await makeApp(rule.graph)
        #expect(app.viewport.items.count == 1, "nothing selected: just the part")
        app.editor.selection = [rule.edges.id]
        await app.settle()
        let part = try #require(solids(app, rule.fillet).first)
        let ruleSolid = try #require(solids(app, rule.extrude).first)
        #expect(app.viewport.items.count == 2)
        let shown = try #require(app.viewport.items.first { $0.solid === part })
        #expect(!shown.isGuide && !shown.isGhost && shown.selectedEdges.isEmpty, "the part itself is drawn as before")
        let guide = try #require(app.viewport.items.first { $0.isGuide })
        #expect(guide.solid === ruleSolid)
        #expect(guide.selectedEdges.count == 12, "a box's twelve edges")
        #expect(!guide.isGhost)
        #expect(app.sources[ObjectIdentifier(ruleSolid)] == nil, "a guide is no target for the face menu")
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.items.count == 1, "deselecting the rule takes its guide away")
    }

    @Test func guidesAppearOnlyInFinalPreview() async throws {
        let rule = hiddenRule()
        let app = await makeApp(rule.graph)
        app.editor.selection = [rule.edges.id]
        await app.settle()
        #expect(app.viewport.items.count == 2)
        app.previewMode = .selectedNode
        await app.settle()
        #expect(app.viewport.items.count == 1, "the rule on its own solid, with its edges selected")
        #expect(app.viewport.items.first?.isGuide == false)
        #expect(app.viewport.items.first?.selectedEdges.count == 12)
        app.editor.selection = [rule.edges.id, rule.fillet.id]
        await app.settle()
        #expect(app.viewport.items.isEmpty, "several selected: the viewport is empty, guides included")
        app.previewMode = .final
        app.editor.selection = [rule.edges.id]
        await app.settle()
        #expect(app.viewport.items.count == 2)
    }

    @Test func aRuleInErrorOrBlockedDrawsNoGuide() async throws {
        let rule = hiddenRule()
        let app = await makeApp(rule.graph)
        try app.document.perform(.setInput(rule.extrude.id, "distance", .number(-1)))
        app.editor.selection = [rule.edges.id]
        await app.settle()
        #expect(app.document.results[rule.edges.id]?.state.isSuccess == false)
        #expect(!app.viewport.items.isEmpty, "the part is still shown, as a ghost")
        #expect(app.viewport.items.allSatisfy { $0.isGhost && !$0.isGuide }, "its last result is stale, so no edges are drawn from it")
    }

    @Test func anUnsuccessfulResultHasNoEdgeSetsToMakeGuidesFrom() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10,
                                                   mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let outputs: [SocketName: Value] = ["edges": .one(.edgeSet(EdgeSet(solid: solid, edges: [EdgeID(1)])))]
        #expect(SceneBuilder.edgeSets(NodeResult(state: .ok(duration: .zero), outputs: outputs)).count == 1)
        #expect(SceneBuilder.edgeSets(NodeResult(state: .error("boom"), outputs: outputs)).isEmpty)
        #expect(SceneBuilder.edgeSets(NodeResult(state: .idle("missing input"), outputs: outputs)).isEmpty)
        #expect(SceneBuilder.guides(for: SceneBuilder.edgeSets(NodeResult(state: .error("boom"), outputs: outputs)),
                                    notShownIn: []).isEmpty)
    }

    @Test func sketchModeShowsNoGuides() async throws {
        var builder = GraphBuilder()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(rectangleSketch())])
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)], at: Vector2(240, 0))
        let edges = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, at: Vector2(720, 200))
        let output = builder.add(OutputNode.self, at: Vector2(960, 200))
        builder.wire(sketch, "profiles", to: extrude, "profile")
        builder.wire(extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [edges.id]
        await app.settle()
        #expect(app.viewport.items.contains { $0.isGuide }, "in Final preview the rule's edges are a guide")
        app.editor.selection = [sketch.id]
        app.editor.press(.editSketch, on: sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        await app.viewport.waitForAnimation()
        #expect(app.sketch != nil)
        app.editor.selection = [sketch.id, edges.id]
        await app.settle()
        #expect(app.sketch != nil)
        #expect(app.viewport.items.allSatisfy { $0.isGhost && !$0.isGuide }, "the dimmed scene, with no guide over it")
    }

    @Test func rulesOnTheSameHiddenSolidShareOneGuide() async throws {
        let kernel = FakeKernel()
        func solid() async throws -> Solid {
            try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                     tag: NodeTag(node: NodeID(), item: 0))
        }
        let (hidden, other, shownSolid, ghosted) = (try await solid(), try await solid(), try await solid(), try await solid())
        let scene = [SceneItem(item: ViewportItem(solid: shownSolid), source: nil),
                     SceneItem(item: ViewportItem(solid: ghosted, isGhost: true), source: nil),
        ]
        let sets = [EdgeSet(solid: hidden, edges: [EdgeID(0), EdgeID(1)]),
                    EdgeSet(solid: shownSolid, edges: [EdgeID(2)]),
                    EdgeSet(solid: other, edges: []),
                    EdgeSet(solid: ghosted, edges: [EdgeID(3)]),
                    EdgeSet(solid: hidden, edges: [EdgeID(1), EdgeID(5)]),
        ]
        let guides = SceneBuilder.guides(for: sets, notShownIn: scene)
        #expect(guides.count == 2, "one for the hidden solid, one for the stale ghost's; none for a shown solid or no edges")
        #expect(guides[0].item.solid === hidden)
        #expect(guides[0].item.selectedEdges == [EdgeID(0), EdgeID(1), EdgeID(5)], "both rules' edges, once")
        #expect(guides[1].item.solid === ghosted)
        #expect(guides.allSatisfy { $0.item.isGuide && $0.source == nil })
    }

    @Test func aGuideDrawsDifferentlyFromThePartItShadows() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10,
                                                   mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let part = ViewportItem(solid: solid, selectedEdges: [EdgeID(1)])
        let guide = ViewportItem(solid: solid, selectedEdges: [EdgeID(1)], isGuide: true)
        #expect(!part.drawsTheSame(as: guide))
        #expect(ViewportItem.sameScene([part, guide], [part, guide]))
        #expect(!ViewportItem.sameScene([part], [guide]), "so a guide appearing re-shows the scene")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error | head -3` — Expected: compile errors `extra argument 'showsGuides' in call` and `type 'SceneBuilder' has no member 'guides'`.

- [ ] **Step 3: `SceneBuilder`**

In `Sources/CreatorApp/SceneBuilder.swift`, replace the doc bullet and signature

```swift
    /// - Edges picked by a selected rule glow on whichever shown solid is the rule's own (spec §6.3). In Final
    ///   preview a rule feeding a Fillet or Chamfer is on a solid that isn't shown, so nothing glows (Errata (M6)).
    public static func scene(shown: [NodeID], graph: Graph, results: [NodeID: NodeResult],
                             lastGood: [NodeID: [SocketName: Value]], selection: Set<NodeID>) -> [SceneItem] {
```

with

```swift
    /// - Edges picked by a selected rule glow on whichever shown solid is the rule's own (spec §6.3).
    /// - With `showsGuides` (Final preview), the edges of a selected rule whose solid no shown part holds come as
    ///   guide items (`ViewportItem.isGuide`), which the viewport draws over the part. A rule feeding a Fillet or
    ///   Chamfer is on the solid before the feature, which Final doesn't show (Errata (M6)): its edges glow where they
    ///   lie on the finished part and show as an overlay where they don't.
    public static func scene(shown: [NodeID], graph: Graph, results: [NodeID: NodeResult],
                             lastGood: [NodeID: [SocketName: Value]], selection: Set<NodeID>,
                             showsGuides: Bool = false) -> [SceneItem] {
```

replace the end of `scene`

```swift
        return highlighting(scene, selectedSets: selection.sorted().flatMap { edgeSets(results[$0]) })
    }
```

with

```swift
        let selectedSets = selection.sorted().flatMap { edgeSets(results[$0]) }
        let highlighted = highlighting(scene, selectedSets: selectedSets)
        return showsGuides ? highlighted + guides(for: selectedSets, notShownIn: highlighted) : highlighted
    }
```

and add, just before the doc comment of `highlighting`:

```swift
    /// One guide per solid the sets are on that no shown part holds, in the sets' order, holding all their edges. A
    /// solid shown only as a ghost is stale, so it doesn't count as shown. A set with no edges makes no guide.
    static func guides(for sets: [EdgeSet], notShownIn scene: [SceneItem]) -> [SceneItem] {
        var order: [Solid] = []
        var edges: [ObjectIdentifier: Set<EdgeID>] = [:]
        for set in sets where !set.edges.isEmpty && !scene.contains(where: { !$0.item.isGhost && $0.item.solid === set.solid }) {
            let key = ObjectIdentifier(set.solid)
            if edges[key] == nil { order.append(set.solid) }
            edges[key, default: []].formUnion(set.edges)
        }
        return order.map { solid in
            SceneItem(item: ViewportItem(solid: solid, selectedEdges: edges[ObjectIdentifier(solid)] ?? [], isGuide: true),
                      source: nil)
        }
    }

```

(`source: nil` keeps a guide out of `AppModel.sources`, so it is never a face-menu target.)

- [ ] **Step 4: `AppModel` and the comparison**

`Sources/CreatorApp/AppModel+Scene.swift`: replace

```swift
            scene = SceneBuilder.scene(shown: shown, graph: document.graph, results: document.results,
                                       lastGood: document.lastGoodOutputs, selection: editor.selection)
```

with

```swift
            scene = SceneBuilder.scene(shown: shown, graph: document.graph, results: document.results,
                                       lastGood: document.lastGoodOutputs, selection: editor.selection,
                                       showsGuides: previewMode == .final && sketch == nil)
```

and extend the doc comment of `refreshScene`: replace `/// Shows the scene and the selected nodes' handles. While picking,` with

```swift
    /// Shows the scene and the selected nodes' handles. In Final preview the scene also carries the selected rules'
    /// edges on solids it doesn't show, as guides (not while sketching). While picking,
```

(The observation list already reads `previewMode`, `sketch`, `editor.selection` and `document.results`.)

`Sources/CreatorApp/ViewportItem+Comparison.swift`: replace `solid === other.solid && isGhost == other.isGhost && selectedFaces == other.selectedFaces` with `solid === other.solid && isGhost == other.isGhost && isGuide == other.isGuide && selectedFaces == other.selectedFaces`, and its doc's `the very same solid, ghosted alike, with the same faces` with `the very same solid, ghosted alike, a guide alike, with the same faces`.

- [ ] **Step 5: The two tests that count parts**

Picking an edge set leaves the picked rule selected, which now draws its edges as a guide. `Tests/CreatorAppTests/AppAcceptanceTests.swift`: replace

```swift
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.isGhost == false)
        #expect(app.exportName == "Bracket")
```

with

```swift
        let parts = app.viewport.items.filter { !$0.isGuide }
        #expect(parts.count == 1 && parts.first?.isGhost == false)
        let guides = app.viewport.items.filter(\.isGuide)
        #expect(guides.count == 1 && guides.first?.selectedEdges.isEmpty == false,
                "the picked rule stays selected, so its edges on the pre-chamfer solid are drawn over the part")
        #expect(app.exportName == "Bracket")
```

`Tests/CreatorAppTests/Bench/BracketBenchApp.swift` (`makeBracketBenchApp`): the benchmarks measure the bracket alone (spec §7.3), as the performance record did; add after `expectAllOK(app, "the benchmark's bracket")`:

```swift
    // The pick leaves the Chamfer's rule selected, and a selected rule's edges are drawn over the part as a guide
    // (Errata (M6)). The benchmarks measure the bracket alone, as spec §7.3 words it, as the performance record did.
    app.editor.selection = []
    await app.settle()
```

(`BracketBenchAppTests.theBracketIsReadyToMeasure` asserts one item and needs no change.)

- [ ] **Step 6: Verify**

Run: `swift test --filter "SceneGuideTests|SceneTests|AppAcceptanceTests|BracketBenchAppTests"` — Expected: pass. Full verify. Expected: 1659 tests (master + 16), 11 "Test run with" lines, no new warnings, lint clean.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorApp Tests/CreatorAppTests
git commit -m "feat(app): Final preview draws a selected rule's edges over the part as a guide"
```

---

### Task 5: Spec Errata, roadmap, CLAUDE.md and the human check

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `docs/superpowers/roadmap.md`, `docs/verification/human-checks.md`, `CLAUDE.md`

**Interfaces:** none (documentation). Consumes the test names from Tasks 1 to 4.

- [ ] **Step 1: Spec**

In Errata (M6), replace the end of the §6.3 bullet

```
  doesn't show). Pinned: `SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid`. Owner: roadmap row
  "Viewport: a selected rule's edges over the Final part".
```

with

```
  doesn't show). Superseded for Final preview by Errata (Viewport: a rule's edges over the Final part), below.
```

and append at the end of the file:

```markdown
## Errata (Viewport: a rule's edges over the Final part)

- §6.3's "faces and edges selected by the active rule glow pink" now holds in Final preview for every selected rule,
  which ends Errata (M6)'s exception. The edges a selected rule picks on a solid no shown part holds (a rule feeding a
  Fillet or Chamfer is on the solid before the feature) reach the viewport as a **guide** (`ViewportItem.isGuide`):
  only its selected edges are drawn, in the selection colour at the width a glow has, after the solids and the ghosts,
  depth-tested with the bias B-rep edges get. Where they lie on the finished part they cover its white edge in pink;
  where they don't (an edge the fillet rounded away) they show as an overlay in free space; where the part hides them
  they show faded, at 35% of the selection colour (`ViewportPalette.hiddenGuideOpacity`). A guide has no surfaces and
  is no part of the scene: it never widens the framed bounds or the point the camera orbits about, and is never
  hovered, picked or offered the face menu. F with a rule selected frames its edges.
- It appears in Final preview only, for a selected rule that succeeded and picked at least one edge (a rule in error or
  blocked has only a stale result and makes none). Selected-node preview keeps Errata (M6)'s behaviour (the rule's own
  solid with its edges selected; several selected shows nothing), and neither pick mode nor sketch mode shows guides.
  A rule whose solid another Output shows glows on that item and makes no guide; rules on the same hidden solid share
  one guide. Pinned: `SceneGuideTests`, `ViewportGuideTests`, `GuideRenderTests`, `GPUDataTests.hiddenEdgesTakeTheFadedSelectionColour`
  and human check M6-15.
- Every selected rule gets a guide (a multi-selection of rules draws all their edges, as the glow on a shown solid
  does); in Final a rule whose solid is a pre-feature intermediate always makes one, and where its edges coincide with
  the part's they simply recolour them pink.
- Not covered: face rules (nothing previews a selected set of faces yet, in any mode) and a rule selected inside a
  group (the groups editor's viewport per level).
```

- [ ] **Step 2: Roadmap**

In `docs/superpowers/roadmap.md`, the row "Viewport: a selected rule's edges over the Final part": replace `| ⏳ after M6 | \`SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid\` |` with

```
| ✅ code done (plan `2026-10-09-viewport-final-edges.md`, Errata (Viewport: a rule's edges over the Final part)); human check M6-15 pending | `SceneGuideTests`, `ViewportGuideTests`, `GuideRenderTests` (was `SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid`) |
```

- [ ] **Step 3: Human checks (group M6)**

In `docs/verification/human-checks.md`, M6-8: replace

```
Still in Final, select the fillet's Edge Set Op and the
  chamfer's Edges by Tag: nothing glows on the finished part (known, Errata (M6); the rule's solid isn't shown).
  Orbit, pan the graph canvas and drag the panel edge: the part doesn't flicker or reload. Pinned: `SceneTests`,
  `aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid`, `panningTheCanvasOrSettlingTheCameraDoesntRebuildTheScene`.
```

with

```
Still in Final, select the fillet's Edge Set Op and the
  chamfer's Edges by Tag: their edges are drawn over the finished part (M6-15). Orbit, pan the graph canvas and drag
  the panel edge: the part doesn't flicker or reload. Pinned: `SceneTests`,
  `aRuleSelectedInFinalPreviewGlowsOnItsOwnShownSolidAndAddsNoGuide`,
  `panningTheCanvasOrSettlingTheCameraDoesntRebuildTheScene`.
```

and add after M6-14 (before `## Group EP`):

```markdown
- [ ] **M6-15 A selected rule's edges over the Final part.** With the bracket open in Preview ▸ Final, select the
  fillet's Edge Set Op: its four edges (the flange's vertical corners, as in M6-8) show pink, as thick as a selection
  glow, over the finished part. R3 rounds those corners away, so the pink lines float just outside the rounded corners
  (the part has no edge of its own there to cover). Select the chamfer's Edges by Tag too: the plate's top outline is
  pink over the chamfered part. Orbit: the pink lines stay on their edges, with no flicker or shimmer, and any piece
  the part hides in front of it shows as a faint pink line through the part. Shaded (View menu) keeps them. Click and
  right-click on a pink line in free space: nothing is selected and no face menu opens. Press F with a rule selected:
  the view frames that rule's edges. Deselect: the lines go. Preview ▸ Selected node with one rule selected: the
  bracket before the feature, edges pink, with no extra lines. View ▸ Theme ▸ Alucard: the lines take its selection
  colour. Pinned: `SceneGuideTests`, `ViewportGuideTests`, `GuideRenderTests`. **Observed:**
```

- [ ] **Step 4: CLAUDE.md**

In the `CreatorViewport` bullet, after `    MetalUI glue.` (the end of the `ViewportModel` item) insert:

```
 A `ViewportItem` with `isGuide` is no part of the scene: only its selected edges are drawn, after the
    solids and ghosts (faded where the part hides them), and it never frames, orbits, picks or opens the face menu
    (`ViewportRenderer+Guides`).
```

so the item reads `... \`ViewportView\` is the\n    MetalUI glue. A \`ViewportItem\` with ...`. In the `CreatorApp` bullet replace `turns results into \`ViewportItem\`s (\`SceneBuilder\`) and \`HandleSpec\`s into` with

```
turns results into `ViewportItem`s (`SceneBuilder`; in Final preview a selected rule's edges on a solid no shown
  part holds come as guide items, Errata (Viewport: a rule's edges over the Final part)) and `HandleSpec`s into
```

- [ ] **Step 5: Verify**

Run the full verify. Expected: 1659 tests (master + 16, unchanged), 11 "Test run with" lines, lint clean.

- [ ] **Step 6: Commit**

```bash
git add docs CLAUDE.md
git commit -m "docs: Errata for a selected rule's edges over the Final part, human check M6-15"
```

---

## Self-review

**Spec coverage.** §6.3 "faces and edges selected by the active rule glow pink": Tasks 2 and 4 (guides drawn in the selection colour; Selected-node and pick behaviour unchanged). §6.3 edge pass / ID pass: the guide shares the edge bias; the ID pass skips guides (Task 2). §6.1 preview modes: guides in Final only (Task 4, `guidesAppearOnlyInFinalPreview`), Errata (M6)'s "several selected shows nothing" kept. Errata (M6) owner row: closed by Task 5. §4.4 ghosts: a ghost never counts as a shown solid and never receives a highlight (`rulesOnTheSameHiddenSolidShareOneGuide`). `CreatorViewport` free of `CreatorGraph`: the only new viewport API is a Bool on `ViewportItem`.

**Placeholder scan.** No TBD or "similar to" steps; every code step has complete code or a replace-this-with-that block with the exact text.

**Type consistency.** `isGuide` (Task 1) is used by Tasks 2 to 4 under that name; `hidden`/`hiddenSelection`/`hiddenGuideOpacity`/`depthBehind` are defined in Task 3 and used only there; `SceneBuilder.guides(for:notShownIn:)` and `showsGuides` are defined in Task 4 and used by the Task 4 tests and `AppModel`.

**Review Focus.** Each of the five lines has its test in the named task (see the list above).

**Verification record.** Each task was applied in turn to a scratch copy of the worktree (with a sibling `MetalUI` symlink): Task 1 master + 4 = 1647, Task 2 = 1651, Task 3 = 1652, Task 4 = 1659, Task 5 = 1659; every full `swift test` had exit 0, 11 "Test run with" lines and no "recorded an issue" or "failed after" line; builds added no warnings; `swiftlint lint --strict` reported 0 violations. After the review revision (the stronger error-rule test and one new unit test), Task 4 and Task 5 were re-run in the scratch copy: 1659 tests, exit 0, 11 "Test run with" lines, no new warnings, 0 lint violations. Master's 1643 was measured the same way (190 + 65 + 184 + 139 + 122 + 151 + 83 + 222 + 31 + 304 + 152). Red checks were run for the pivot, the ID-pass and surface tests (reverting the renderer or model change makes them fail), for the sketch-mode and preview-mode tests (removing the `previewMode == .final` or `sketch == nil` clause makes them fail).
