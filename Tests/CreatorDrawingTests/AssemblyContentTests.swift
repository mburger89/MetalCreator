import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Assembly content")
struct AssemblyContentTests {
    let nodeA = NodeID(), nodeB = NodeID(), nodeC = NodeID()

    /// A solid of `count` faces in a chain of edges, with the box's bounds and storage.
    func solid(_ count: Int, size: Double = 10, from base: Solid) -> Solid {
        let faces = (0..<count).map { index in
            FaceInfo(
                id: FaceID(index), kind: .plane, normal: Vector3(0, 0, 1), area: 1, centroid: .zero,
                tags: [TopoTag(node: NodeID(), item: 0, role: .side(segment: index))])
        }
        let edges = (1..<max(count, 1)).map { index in
            EdgeInfo(
                id: EdgeID(index), kind: .line, direction: Vector3(1, 0, 0), length: 1, midpoint: .zero, convexity: .convex,
                faces: [FaceID(index - 1), FaceID(index)])
        }
        return Solid(topology: Topology(faces: faces, edges: edges), bounds: base.bounds, storage: base.storage)
    }

    static func concatenate(_ solids: [Solid]) -> Solid {
        var faces: [FaceInfo] = [], edges: [EdgeInfo] = []
        var bounds = solids[0].bounds
        for solid in solids {
            let (faceOffset, edgeOffset) = (faces.count, edges.count)
            faces += solid.topology.faces.map { var f = $0; f.id = FaceID(f.id.rawValue + faceOffset); return f }
            edges += solid.topology.edges.map {
                var e = $0
                e.id = EdgeID(e.id.rawValue + edgeOffset)
                e.faces = e.faces.map { FaceID($0.rawValue + faceOffset) }
                return e
            }
            bounds = bounds.union(solid.bounds)
        }
        return Solid(topology: Topology(faces: faces, edges: edges), bounds: bounds, storage: solids[0].storage)
    }

    func kernel() async -> FakeKernel {
        let kernel = FakeKernel()
        await kernel.setCompoundHook { Self.concatenate($0) }
        return kernel
    }

    func base(_ kernel: FakeKernel) async throws -> Solid { try await ProjectionCacheTests.box(kernel) }

    func part(_ id: NodeID, _ name: String, _ solids: [Solid], curves: [Curve] = [], meshes: Int = 0) -> DrawingSourceContent {
        DrawingSourceContent(output: id, name: name, state: .ready(solids: solids, curves: curves, meshCount: meshes))
    }

    func view(_ outputs: [NodeID], derivation: ViewDerivation? = nil, cutter: SectionCutter? = nil) -> DrawingView {
        if let cutter {
            return DrawingView(
                kind: .section, source: outputs[0], orientation: .custom(SectionFrame.frame(for: cutter)), center: .zero,
                derivation: .section(SectionLine(parent: ViewID(), cutter: cutter)), letter: "A", assembly: outputs)
        }
        return DrawingView(
            kind: .base, source: outputs[0], orientation: .standard(.front), center: .zero, assembly: outputs)
    }

    var cutter: SectionCutter {
        SectionCutter(frame: ProjectionCacheTests.front, points: [Vector2(-10, 5), Vector2(10, 5)], viewing: Vector2(0, 1))
    }

    @Test func spansFollowFaceCounts() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let parts = [
            PartSolids(output: nodeA, solids: [solid(6, from: box)], curves: []),
            PartSolids(output: nodeB, solids: [solid(7, from: box)], curves: []),
            PartSolids(output: nodeC, solids: [solid(6, from: box)], curves: []),
        ]
        let layout = PartSpan.layout(parts)
        #expect(layout.spans.map(\.faces) == [0..<6, 6..<13, 13..<19])
        #expect(layout.spans.map(\.curves) == [0..<0, 0..<0, 0..<0])
        let curve = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(5, 0, 0))], tag: ProjectionCacheTests.tag)
        let curved = PartSpan.layout([
            PartSolids(output: nodeA, solids: [], curves: [curve, curve]),
            PartSolids(output: nodeB, solids: [], curves: []),
            PartSolids(output: nodeC, solids: [], curves: [curve]),
        ])
        #expect(curved.spans.map(\.curves) == [0..<2, 2..<2, 2..<3])
        #expect(layout.spans.span(containingFace: 6)?.output == nodeB)
        #expect(layout.spans.span(containingFace: 19) == nil)
        #expect(curved.spans.span(containingCurve: 2)?.output == nodeC)
    }

    @Test func aSharedSolidsSpanIsEmptyAtTheRunningCount() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let s1 = solid(6, from: box), s2 = solid(6, from: box)
        let layout = PartSpan.layout([
            PartSolids(output: nodeA, solids: [s1], curves: []), PartSolids(output: nodeB, solids: [s1, s2], curves: []),
        ])
        #expect(layout.solids.count == 2)
        #expect(layout.spans.map(\.faces) == [0..<6, 6..<12])
        #expect(layout.shared.count == 1 && layout.shared[0].part == nodeB && layout.shared[0].other == nodeA)
        let same = PartSpan.layout([
            PartSolids(output: nodeA, solids: [s1], curves: []), PartSolids(output: nodeB, solids: [s1], curves: []),
        ])
        #expect(same.spans.map(\.faces) == [0..<6, 6..<6])
    }

    @Test func layoutIsTheProjectorsSpans() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let s1 = solid(6, from: box), s2 = solid(7, from: box), s3 = solid(6, from: box)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let outputs = [nodeA, nodeB, nodeC]
        let plain = await projector.content(
            for: view(outputs), scale: 1,
            parts: [part(nodeA, "A", [s1]), part(nodeB, "B", [s2]), part(nodeC, "C", [s3])], previous: nil)
        let expected = PartSpan.layout([
            PartSolids(output: nodeA, solids: [s1], curves: []), PartSolids(output: nodeB, solids: [s2], curves: []),
            PartSolids(output: nodeC, solids: [s3], curves: []),
        ])
        #expect(plain.parts == expected.spans)
        let shared = await projector.content(
            for: view(outputs), scale: 1,
            parts: [part(nodeA, "A", [s1]), part(nodeB, "B", [s1, s2]), part(nodeC, "C", [s3])], previous: nil)
        let sharedExpected = PartSpan.layout([
            PartSolids(output: nodeA, solids: [s1], curves: []), PartSolids(output: nodeB, solids: [s1, s2], curves: []),
            PartSolids(output: nodeC, solids: [s3], curves: []),
        ])
        #expect(shared.parts == sharedExpected.spans)
        // A section: every solid's remainder is the one the hook returns.
        let r1 = solid(6, from: box), r2 = solid(6, from: box)
        await kernel.setSectionCutHook { solid, _, _ in solid === s1 ? r1 : r2 }
        let section = await projector.content(
            for: view([nodeA, nodeB], cutter: cutter), scale: 1,
            parts: [part(nodeA, "A", [s1]), part(nodeB, "B", [s2])], previous: nil)
        let sectionExpected = PartSpan.layout([
            PartSolids(output: nodeA, solids: [r1], curves: []), PartSolids(output: nodeB, solids: [r2], curves: []),
        ])
        #expect(section.parts == sectionExpected.spans)
    }

    @Test func hatchesGoByPart() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let smaller = try await ProjectionCacheTests.box(kernel, 6)
        await kernel.setSectionCutHook { _, _, _ in smaller }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let (a1, a2, b1) = (solid(6, from: box), solid(6, from: box), solid(6, from: box))
        let assembly = await projector.content(
            for: view([nodeA, nodeB], cutter: cutter), scale: 1,
            parts: [part(nodeA, "A", [a1, a2]), part(nodeB, "B", [b1])], previous: nil)
        #expect(assembly.hatch.map(\.part) == [0, 0, 1])
        // A single-Output view keeps the solid's index.
        let single = DrawingView(
            kind: .section, source: nodeA, orientation: .custom(SectionFrame.frame(for: cutter)), center: .zero,
            derivation: .section(SectionLine(parent: ViewID(), cutter: cutter)), letter: "A")
        let content = await projector.content(
            for: single, scale: 1, source: part(nodeA, "A", [a1, a2]), previous: nil)
        #expect(content.hatch.map(\.part) == [0, 1])
        #expect(content.parts.isEmpty)
    }

    @Test func restrictedKeepsOnlyThePart() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let compound = Self.concatenate([solid(6, from: box), solid(7, from: box), solid(6, from: box)])
        let restricted = compound.topology.restricted(toFaces: 6..<13)
        #expect(restricted.faces.count == 7)
        #expect(restricted.faces.map(\.id.rawValue) == Array(6..<13))
        let ids = Set(restricted.faces.map(\.id))
        #expect(restricted.edges.count == 6)
        #expect(restricted.edges.allSatisfy { $0.faces.allSatisfy(ids.contains) })
        #expect(restricted.edges.map(\.id) == compound.topology.edges.filter { $0.faces.allSatisfy(ids.contains) }.map(\.id))
        #expect(compound.topology.restricted(toFaces: 19..<19).faces.isEmpty)
    }

    @Test func aSectionOfAnAssemblyHasSpansOverTheRemainders() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let (a, b) = (solid(6, from: box), solid(7, from: box))
        let remainder = solid(5, from: box)
        await kernel.setSectionCutHook { solid, _, _ in solid === a ? remainder : nil }
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(
            for: view([nodeA, nodeB], cutter: cutter), scale: 1, parts: [part(nodeA, "A", [a]), part(nodeB, "B", [b])],
            previous: nil)
        #expect(content.problem == nil)
        #expect(content.parts.map(\.faces) == [0..<5, 5..<5])
    }

    @Test func aDetailCopiesItsParentsSpans() {
        let spans = [PartSpan(output: nodeA, faces: 0..<6, curves: 0..<0)]
        let parent = ViewContent(projection: Projection2D(lines: []), parts: spans)
        let detail = DetailClip.content(of: parent, circle: DetailCircle(parent: ViewID(), center: .zero, radius: 5))
        #expect(detail.parts == spans)
    }

    @Test func aSingleOutputViewHasNoSpans() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let single = DrawingView(kind: .base, source: nodeA, orientation: .standard(.front), center: .zero)
        let content = await projector.content(
            for: single, scale: 1,
            source: part(nodeA, "A", [solid(6, from: box), solid(6, from: box)]), previous: nil)
        #expect(content.parts == [])
        #expect(content.problem == nil)
    }
}
