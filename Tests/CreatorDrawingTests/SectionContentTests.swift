import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Section content")
struct SectionContentTests {
    let output = NodeID()
    let parent = ProjectionCacheTests.front

    /// A horizontal cutting line through the middle of a 10 mm box, looking up (+z of the parent's plane).
    var cutter: SectionCutter {
        SectionCutter(frame: parent, points: [Vector2(-10, 5), Vector2(10, 5)], viewing: Vector2(0, 1))
    }

    func sectionView(_ cutter: SectionCutter) -> DrawingView {
        DrawingView(
            kind: .section, source: output, orientation: .custom(SectionFrame.frame(for: cutter)), center: .zero,
            derivation: .section(SectionLine(parent: ViewID(), cutter: cutter)), letter: "A")
    }

    func source(_ solids: [Solid], curves: [Curve] = []) -> DrawingSourceContent {
        DrawingSourceContent(output: output, name: "Output", state: .ready(solids: solids, curves: curves, meshCount: 0))
    }

    @Test func theRemainderIsProjected() async throws {
        let kernel = FakeKernel()
        let solid = try await ProjectionCacheTests.box(kernel, 10)
        let smaller = try await ProjectionCacheTests.box(kernel, 6)
        await kernel.setSectionCutHook { _, _, _ in smaller }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(for: sectionView(cutter), scale: 1, source: source([solid]), previous: nil)
        #expect(content.problem == nil)
        let bounds = try #require(content.projection?.bounds)
        #expect(bounds.width == 6)
        #expect(content.topology == smaller.topology)
    }

    @Test func hatchComesFromTheSection() async throws {
        let kernel = FakeKernel()
        let solid = try await ProjectionCacheTests.box(kernel, 10)
        let smaller = try await ProjectionCacheTests.box(kernel, 6)
        await kernel.setSectionCutHook { _, _, _ in smaller }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(for: sectionView(cutter), scale: 1, source: source([solid]), previous: nil)
        #expect(content.hatch.count == 1)
        let region = try #require(content.hatch.first)
        #expect(region.part == 0)
        #expect(region.band == HatchBand.bands(for: cutter)[0])
        #expect(region.edges.count == 1)
        #expect(region.edges[0].count >= 4)
        #expect(content.warnings.isEmpty)
    }

    @Test func everythingCutAwayIsAProblem() async throws {
        let kernel = FakeKernel()
        let solids = [try await ProjectionCacheTests.box(kernel), try await ProjectionCacheTests.box(kernel)]
        await kernel.setSectionCutHook { _, _, _ in nil }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(for: sectionView(cutter), scale: 1, source: source(solids), previous: nil)
        #expect(content.problem == DrawingProjector.cutAwaySentence)
        #expect(DrawingProjector.cutAwaySentence == "The cutting line leaves nothing of the part on the side it looks toward.")
        #expect(content.projection == nil)
        #expect(content.hatch.isEmpty)
    }

    @Test func curvesAreLeftOutWithAWarning() async throws {
        let kernel = FakeKernel()
        let solid = try await ProjectionCacheTests.box(kernel)
        let curve = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(5, 0, 0))], tag: ProjectionCacheTests.tag)
        await kernel.setSectionCutHook { part, _, _ in part }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(
            for: sectionView(cutter), scale: 1, source: source([solid], curves: [curve]), previous: nil)
        #expect(content.warnings.contains(DrawingProjector.curvesLeftOutSentence))
        #expect(
            DrawingProjector.curvesLeftOutSentence
                == "This section leaves out the Output's curves; a section shows what the cut leaves of solids and sheets.")
        #expect(content.projection != nil)
    }

    @Test func anOutputOfOnlyCurvesSaysSo() async throws {
        let kernel = FakeKernel()
        let curve = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(5, 0, 0))], tag: ProjectionCacheTests.tag)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(
            for: sectionView(cutter), scale: 1, source: source([], curves: [curve]), previous: nil)
        #expect(content.problem == DrawingProjector.noSolidsToCutSentence)
        #expect(content.problem != DrawingProjector.cutAwaySentence)
        #expect(content.warnings.contains(DrawingProjector.curvesLeftOutSentence))
    }

    @Test func aRefusedCutKeepsThePreviousContent() async throws {
        let kernel = FakeKernel()
        let solid = try await ProjectionCacheTests.box(kernel)
        await kernel.setSectionCutHook { part, _, _ in part }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let view = sectionView(cutter)
        let first = await projector.content(for: view, scale: 1, source: source([solid]), previous: nil)
        #expect(first.projection != nil && !first.hatch.isEmpty)
        let other = try await ProjectionCacheTests.box(kernel)
        await kernel.setSectionCutHook { _, _, _ in throw KernelError.invalidInput("No cut today.") }
        let second = await projector.content(for: view, scale: 1, source: source([other]), previous: first)
        #expect(second.projection == first.projection)
        #expect(second.topology == first.topology)
        #expect(second.hatch == first.hatch)
        #expect(second.problem == KernelError.invalidInput("No cut today.").userMessage)
    }

    @Test func stepLinesAreDropped() {
        let node = SectionCutter.toolNode
        let step = FaceInfo(
            id: FaceID(1), kind: .plane, normal: nil, area: 1, centroid: .zero,
            tags: [TopoTag(node: node, item: 0, role: .side(loop: 0, segment: 1))])
        let cut = FaceInfo(
            id: FaceID(2), kind: .plane, normal: nil, area: 1, centroid: .zero,
            tags: [TopoTag(node: node, item: 0, role: .side(loop: 0, segment: 0))])
        let other = FaceInfo(id: FaceID(3), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [])
        func edge(_ id: Int, _ a: FaceID, _ b: FaceID) -> EdgeInfo {
            EdgeInfo(
                id: EdgeID(id), kind: .line, direction: Vector3(1, 0, 0), length: 1, midpoint: .zero, convexity: .convex,
                faces: [a, b])
        }
        let topology = Topology(faces: [step, cut, other], edges: [edge(1, step.id, other.id), edge(2, cut.id, other.id)])
        func line(_ id: Int) -> ProjectedLine {
            ProjectedLine(
                visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(Double(id), 0)),
                source: .edge(EdgeID(id)))
        }
        let projection = Projection2D(lines: [line(1), line(2)])
        let kept = SectionLines.droppingSteps(projection, topology: topology)
        #expect(kept.lines.map(\.source) == [.edge(EdgeID(2))])
    }

    @Test func aDetailFramingCentresOnTheCircle() throws {
        let projection = Projection2D(lines: [
            ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(100, 40)), source: nil),
        ])
        let circle = Rect2D(min: Vector2(10, 10), max: Vector2(20, 20))
        let content = ViewContent(projection: projection, framing: circle)
        let mapping = try #require(ViewMapping.of(content: content, center: Vector2(200, 100), scale: 5))
        let placed = mapping.sheet(Vector2(15, 15))
        #expect(abs(placed.x - 200) < 1e-9 && abs(placed.y - 100) < 1e-9)
        let frame = try #require(ViewLinework.frame(for: content, center: Vector2(200, 100), scale: 5))
        #expect(frame == Rect2D(min: Vector2(175, 75), max: Vector2(225, 125)))
        let plain = ViewContent(projection: projection)
        let unframed = try #require(ViewMapping.of(content: plain, center: Vector2(200, 100), scale: 1))
        #expect(unframed == ViewMapping.of(projection: projection, center: Vector2(200, 100), scale: 1))
    }

    @Test func aSheetIsNeverSectioned() async throws {
        let kernel = FakeKernel()
        let box = try await ProjectionCacheTests.box(kernel)
        var topology = box.topology
        topology.faces = topology.faces.map { face in
            var face = face
            face.isOnOpenShell = true
            return face
        }
        let sheet = Solid(topology: topology, bounds: box.bounds, storage: box.storage)
        await kernel.setSectionCutHook { _, _, _ in sheet }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(for: sectionView(cutter), scale: 1, source: source([sheet]), previous: nil)
        #expect(content.hatch.isEmpty)
        #expect(content.projection != nil)
        #expect(content.warnings.isEmpty)
        #expect(await kernel.operationLog.filter { $0 == "section" }.isEmpty)
    }

    @Test func aFailedSectionLeavesThePartUnhatched() async throws {
        let kernel = FakeKernel()
        let solid = try await ProjectionCacheTests.box(kernel)
        await kernel.setSectionCutHook { part, _, _ in part }
        await kernel.setSectionHook { throw KernelError.invalidInput("No section.") }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(for: sectionView(cutter), scale: 1, source: source([solid]), previous: nil)
        #expect(content.projection != nil)
        #expect(content.hatch.isEmpty)
        #expect(content.problem == nil)
        #expect(content.warnings == [DrawingProjector.hatchFailedSentence])
        #expect(DrawingProjector.hatchFailedSentence == "The cut faces of a part couldn't be hatched.")
    }

    /// A box with `open` of its faces marked as a bare shell's: the value holds a closed solid and an open shell (R5).
    func mixed(_ box: Solid, openFaces open: Set<FaceID>) -> Solid {
        var topology = box.topology
        topology.faces = topology.faces.map { face in
            var face = face
            face.isOnOpenShell = open.contains(face.id)
            return face
        }
        return Solid(topology: topology, bounds: box.bounds, storage: box.storage)
    }

    func hatch(of solid: Solid, kernel: FakeKernel) async -> [HatchRegion] {
        await kernel.setSectionCutHook { part, _, _ in part }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        return await projector.content(for: sectionView(cutter), scale: 1, source: source([solid]), previous: nil).hatch
    }

    @Test func aRegionBoundedByAnOpenShellIsNotHatched() async throws {
        let kernel = FakeKernel()
        let box = try await ProjectionCacheTests.box(kernel, 10)
        let section = try await kernel.section(box, by: Plane(origin: box.bounds.center, normal: Vector3(0, 0, 1), xAxis: Vector3(1, 0, 0)),
                                               tolerance: 1e-4)
        let pieceFaces = Set(section.regions.flatMap(\.boundary).compactMap(\.sourceFace))
        let cut = try #require(pieceFaces.sorted { $0.rawValue < $1.rawValue }.first)
        let other = try #require(box.topology.faces.map(\.id).first { !pieceFaces.contains($0) })
        let dropped = mixed(box, openFaces: [cut])
        #expect(dropped.holdsClosedSolid && dropped.hasOpenShell)
        #expect(await hatch(of: dropped, kernel: kernel).isEmpty)
        // A face the cut doesn't touch being open leaves the region hatched.
        let kept = mixed(box, openFaces: [other])
        #expect(kept.holdsClosedSolid && kept.hasOpenShell)
        #expect(await hatch(of: kept, kernel: kernel).count == 1)
    }
}
