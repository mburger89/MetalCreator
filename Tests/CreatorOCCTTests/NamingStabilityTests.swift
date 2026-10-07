import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Builds the acceptance bracket's plate (spec §7.2) directly through the kernel, the way the
/// M3 nodes will: plate → holes (one broadcast item each) → subtract → fillet the convex
/// vertical outer edges → chamfer the top-cap edges. Node identities are fixed across rebuilds,
/// exactly as in a document whose parameters change.
struct NamingStabilityTests {
    struct Nodes {
        let plate = NodeID()
        let holes = NodeID()
        let cut = NodeID()
        let fillet = NodeID()
        let chamfer = NodeID()
    }

    struct Built {
        let cut: Solid
        let filletEdges: [EdgeInfo]
        let filleted: Solid
        let chamferEdges: [EdgeInfo]
        let chamfered: Solid
    }

    func isVerticalConvexLine(_ edge: EdgeInfo) -> Bool {
        edge.kind == .line && edge.convexity == .convex && !edge.isSeam && abs((edge.direction ?? .zero).dot(.unitZ)) > 0.999
    }

    func build(_ kernel: any Kernel, nodes: Nodes, outline: Profile2D, holeCenters: [Vector2]) async throws -> Built {
        let plateTag = NodeTag(node: nodes.plate, item: 0)
        let plate = try await kernel.extrude(outline, distance: 6, mode: .oneSided, tag: plateTag)
        var tools: [Solid] = []
        for (item, center) in holeCenters.enumerated() {
            tools.append(try await kernel.extrude(.circle(radius: 2.5, center: center, plane: Plane.xy.offset(by: -1)),
                                                  distance: 8, mode: .oneSided, tag: NodeTag(node: nodes.holes, item: item)))
        }
        let cut = try await kernel.boolean(.subtract, plate, tools, tag: NodeTag(node: nodes.cut, item: 0))
        let filletEdges = cut.topology.edges.filter(isVerticalConvexLine)
        let filleted = try await kernel.fillet(cut, edges: filletEdges.map(\.id), radius: 3, tag: NodeTag(node: nodes.fillet, item: 0))
        let top: (FaceInfo) -> Bool = { hasTag($0, .endCap, of: plateTag) }
        let outer: (FaceInfo) -> Bool = { face in
            face.tags.contains { tag in
                (tag.node == nodes.plate && { if case .side = tag.role { true } else { false } }())
                    || (tag.node == nodes.fillet && { if case .blend = tag.role { true } else { false } }())
            }
        }
        let chamferEdges = edges(filleted, between: top, and: outer)
        let chamfered = try await kernel.chamfer(filleted, edges: chamferEdges.map(\.id), distance: 0.5,
                                                 tag: NodeTag(node: nodes.chamfer, item: 0))
        return Built(cut: cut, filletEdges: filletEdges, filleted: filleted, chamferEdges: chamferEdges, chamfered: chamfered)
    }

    func grid(columns: Int, rows: Int, spacingX: Double, spacingY: Double) -> [Vector2] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                Vector2((Double(column) - Double(columns - 1) / 2) * spacingX, (Double(row) - Double(rows - 1) / 2) * spacingY)
            }
        }
    }

    func keys(_ edges: [EdgeInfo], in solid: Solid) -> Set<EdgeKey> {
        Set(edges.compactMap { solid.topology.key(of: $0) })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func widthChangeKeepsFilletAndChamferEdgeMeanings(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let nodes = Nodes()
        let holes = grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20)
        let narrow = try await build(kernel, nodes: nodes, outline: .rectangle(width: 60, height: 40, plane: .xy), holeCenters: holes)
        let wide = try await build(kernel, nodes: nodes, outline: .rectangle(width: 90, height: 40, plane: .xy), holeCenters: holes)
        #expect(narrow.filletEdges.count == 4)
        #expect(wide.filletEdges.count == 4)
        #expect(keys(narrow.filletEdges, in: narrow.cut) == keys(wide.filletEdges, in: wide.cut))
        #expect(narrow.chamferEdges.count == 8)
        #expect(wide.chamferEdges.count == 8)
        #expect(keys(narrow.chamferEdges, in: narrow.filleted) == keys(wide.chamferEdges, in: wide.filleted))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func holeCountChangeLeavesThePlateEdgesAlone(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let nodes = Nodes()
        let outline = Profile2D.rectangle(width: 90, height: 40, plane: .xy)
        let four = try await build(kernel, nodes: nodes, outline: outline, holeCenters: grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20))
        let six = try await build(kernel, nodes: nodes, outline: outline, holeCenters: grid(columns: 3, rows: 2, spacingX: 30, spacingY: 20))
        #expect(keys(four.filletEdges, in: four.cut) == keys(six.filletEdges, in: six.cut))
        #expect(keys(four.chamferEdges, in: four.filleted) == keys(six.chamferEdges, in: six.filleted))
        for item in 0..<6 {
            #expect(faces(six.cut, role: .side(segment: 0), of: NodeTag(node: nodes.holes, item: item)).count == 1)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func hexagonOutlineStillFilletsEveryOuterCorner(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let corners = (0..<6).map { k in Vector2(40 * cos(Double(k) * .pi / 3), 40 * sin(Double(k) * .pi / 3)) }
        let hexagon = Profile2D(plane: .xy, segments: corners.indices.map { .line(corners[$0], corners[($0 + 1) % 6]) })
        let built = try await build(kernel, nodes: Nodes(), outline: hexagon, holeCenters: grid(columns: 2, rows: 2, spacingX: 30, spacingY: 20))
        #expect(built.filletEdges.count == 6)
        #expect(built.chamferEdges.count == 12)
        let plateSides = built.filletEdges.compactMap { built.cut.topology.key(of: $0) }
        #expect(plateSides.count == 6)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func noFaceIsUntaggedOrUnnamedInTheBracket(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let built = try await build(kernel, nodes: Nodes(), outline: .rectangle(width: 60, height: 40, plane: .xy),
                                    holeCenters: grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20))
        for solid in [built.cut, built.filleted, built.chamfered] {
            #expect(solid.topology.faces.allSatisfy { !$0.tags.isEmpty })
            #expect(solid.topology.faces.allSatisfy { face in
                !face.tags.contains { if case .unnamed = $0.role { true } else { false } }
            })
        }
        #expect(try await kernel.properties(of: built.chamfered).volume < (try await kernel.properties(of: built.cut).volume))
    }
}
