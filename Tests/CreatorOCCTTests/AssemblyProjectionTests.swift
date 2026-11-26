#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorDrawing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// An assembly's parts in one hidden-line run (drawings DR-5, R2): the compound keeps each part's face order, parts hide each other
/// and copies of one part stay apart.
struct AssemblyProjectionTests {
    let kernel = OCCTKernel()
    static let front = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))

    func cube(_ size: Double, at offset: Vector3 = .zero, tag: NodeTag = NodeTag(node: NodeID(), item: 0)) async throws -> Solid {
        let box = try await kernel.extrude(
            .rectangle(width: size, height: size, plane: .xy), distance: size, mode: .oneSided, tag: tag)
        guard offset != .zero else { return box }
        return try await kernel.transform(box, by: Transform(translation: offset), tag: tag)
    }

    func length(_ curve: ProjectedCurve) -> Double {
        switch curve {
        case .line(let a, let b): (b - a).length
        default: 0
        }
    }

    @Test func partsHideEachOther() async throws {
        // A 20 mm cube in front of a 40 mm one, covering part of the big cube's right-hand edge.
        let big = try await cube(40)
        let small = try await cube(20, at: Vector3(20, -40, 5))
        let layout = PartSpan.layoutForTests([big, small])
        let compound = try await kernel.compound([big, small], tag: NodeTag(node: NodeID(), item: 0))
        let projection = try await kernel.projection(
            of: compound, curves: [], frame: Self.front, options: ProjectionOptions())
        let bigEdges = Set(compound.topology.restricted(toFaces: layout[0]).edges.map(\.id))
        let smallEdges = Set(compound.topology.restricted(toFaces: layout[1]).edges.map(\.id))
        func total(_ ids: Set<EdgeID>, _ visibility: LineVisibility) -> Double {
            projection.lines.filter { line in
                guard case .edge(let id)? = line.source else { return false }
                return ids.contains(id) && line.visibility == visibility && line.lineClass == .sharp
            }.reduce(0) { $0 + length($1.curve) }
        }
        // The small cube's front outline (4 x 20 mm) is whole; the big cube's (4 x 40 mm) loses the 20 mm its edge runs behind it.
        #expect(abs(total(smallEdges, .visible) - 80) < 1e-6)
        #expect(abs(total(bigEdges, .visible) - 140) < 1e-6)
    }

    @Test func compoundKeepsPartFaceOrder() async throws {
        let tags = (0..<3).map { _ in NodeTag(node: NodeID(), item: 0) }
        var solids: [Solid] = []
        for (index, tag) in tags.enumerated() {
            solids.append(try await cube(10, at: Vector3(Double(index) * 30, 0, 0), tag: tag))
        }
        let compound = try await kernel.compound(solids, tag: NodeTag(node: NodeID(), item: 0))
        var start = 0
        for (index, solid) in solids.enumerated() {
            let count = solid.topology.faces.count
            let nodes = compound.topology.faces[start..<(start + count)].map { Set($0.tags.map(\.node)) }
            #expect(nodes.allSatisfy { $0 == [tags[index].node] })
            start += count
        }
        #expect(start == compound.topology.faces.count)
    }

    @Test func twinCopiesProjectApart() async throws {
        let tag = NodeTag(node: NodeID(), item: 0)
        let box = try await cube(10, tag: tag)
        let one = try await kernel.transform(box, by: Transform(translation: Vector3(-20, 0, 0)), tag: tag)
        let two = try await kernel.transform(box, by: Transform(translation: Vector3(20, 0, 0)), tag: tag)
        let spans = PartSpan.layoutForTests([one, two])
        let compound = try await kernel.compound([one, two], tag: NodeTag(node: NodeID(), item: 0))
        #expect(spans[0] == 0..<one.topology.faces.count)
        #expect(spans[1] == one.topology.faces.count..<compound.topology.faces.count)
        let projection = try await kernel.projection(
            of: compound, curves: [], frame: Self.front, options: ProjectionOptions())
        for (index, range) in spans.enumerated() {
            let ids = Set(compound.topology.restricted(toFaces: range).edges.map(\.id))
            let own = projection.lines.filter { line in
                guard case .edge(let id)? = line.source else { return false }
                return ids.contains(id)
            }
            #expect(!own.isEmpty)
            for line in own {
                let bounds = line.curve.bounds
                #expect(index == 0 ? bounds.max.x < 0 : bounds.min.x > 0)
            }
        }
    }
}

private extension PartSpan {
    /// The face ranges `layout` gives one part per solid.
    static func layoutForTests(_ solids: [Solid]) -> [Range<Int>] {
        PartSpan.layout(solids.map { PartSolids(output: NodeID(), solids: [$0], curves: []) }).spans.map(\.faces)
    }
}
#endif
