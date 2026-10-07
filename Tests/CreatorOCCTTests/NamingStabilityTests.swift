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

    /// True when every edge has a key and no two edges share one, so a key-set comparison is not vacuous.
    func keysAreDistinctAndNamed(_ edges: [EdgeInfo], in solid: Solid) -> Bool {
        keys(edges, in: solid).count == edges.count
    }

    /// The plate side segment index of a key side that is exactly one plate `.side` tag, else nil.
    func plateSideSegment(_ side: Set<TopoTag>, plate: NodeID) -> Int? {
        guard side.count == 1, let tag = side.first, tag.node == plate, case .side(let segment) = tag.role else { return nil }
        return segment
    }

    func isPlateSideOrFilletBlend(_ tag: TopoTag, nodes: Nodes) -> Bool {
        switch tag.role {
        case .side: tag.node == nodes.plate
        case .blend: tag.node == nodes.fillet
        default: false
        }
    }

    /// Every face of the cut, filleted and chamfered solids carries at least one tag, and none is `.unnamed`.
    func assertFullyNamed(_ built: Built, sourceLocation: SourceLocation = #_sourceLocation) {
        for solid in [built.cut, built.filleted, built.chamfered] {
            #expect(solid.topology.faces.allSatisfy { !$0.tags.isEmpty }, sourceLocation: sourceLocation)
            #expect(solid.topology.faces.allSatisfy { face in
                !face.tags.contains { if case .unnamed = $0.role { true } else { false } }
            }, sourceLocation: sourceLocation)
        }
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
        #expect(keysAreDistinctAndNamed(narrow.filletEdges, in: narrow.cut))
        #expect(keysAreDistinctAndNamed(wide.filletEdges, in: wide.cut))
        #expect(keysAreDistinctAndNamed(narrow.chamferEdges, in: narrow.filleted))
        #expect(keysAreDistinctAndNamed(wide.chamferEdges, in: wide.filleted))

        // Absolute anchor: each fillet edge joins two adjacent plate sides of the rectangle.
        for key in keys(narrow.filletEdges, in: narrow.cut) {
            let first = plateSideSegment(key.first, plate: nodes.plate)
            let second = plateSideSegment(key.second, plate: nodes.plate)
            #expect(first != nil && second != nil, "fillet key \(key) is not two plate sides")
            if let first, let second {
                let gap = (first - second + 4) % 4
                #expect(gap == 1 || gap == 3, "plate sides \(first) and \(second) are not adjacent")
            }
        }
        // Each chamfer edge joins the plate's top cap to a plate side or a fillet blend.
        let topCap: Set<TopoTag> = [TopoTag(NodeTag(node: nodes.plate, item: 0), .endCap)]
        for key in keys(narrow.chamferEdges, in: narrow.filleted) {
            let other = key.first == topCap ? key.second : (key.second == topCap ? key.first : nil)
            #expect(other != nil, "chamfer key \(key) has no plate end-cap side")
            if let other {
                #expect(other.contains { isPlateSideOrFilletBlend($0, nodes: nodes) }, "chamfer key \(key) has no outer side")
            }
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func holeCountChangeLeavesThePlateEdgesAlone(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let nodes = Nodes()
        let outline = Profile2D.rectangle(width: 90, height: 40, plane: .xy)
        let four = try await build(kernel, nodes: nodes, outline: outline, holeCenters: grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20))
        let six = try await build(kernel, nodes: nodes, outline: outline, holeCenters: grid(columns: 3, rows: 2, spacingX: 30, spacingY: 20))
        #expect(four.filletEdges.count == 4)
        #expect(six.filletEdges.count == 4)
        #expect(four.chamferEdges.count == 8)
        #expect(six.chamferEdges.count == 8)
        #expect(keysAreDistinctAndNamed(four.filletEdges, in: four.cut))
        #expect(keysAreDistinctAndNamed(six.filletEdges, in: six.cut))
        #expect(keysAreDistinctAndNamed(four.chamferEdges, in: four.filleted))
        #expect(keysAreDistinctAndNamed(six.chamferEdges, in: six.filleted))
        #expect(keys(four.filletEdges, in: four.cut) == keys(six.filletEdges, in: six.cut))
        #expect(keys(four.chamferEdges, in: four.filleted) == keys(six.chamferEdges, in: six.filleted))
        for item in 0..<6 {
            #expect(faces(six.cut, role: .side(segment: 0), of: NodeTag(node: nodes.holes, item: item)).count == 1)
        }
        assertFullyNamed(six)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func hexagonOutlineStillFilletsEveryOuterCorner(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let corners = (0..<6).map { k in Vector2(40 * cos(Double(k) * .pi / 3), 40 * sin(Double(k) * .pi / 3)) }
        let hexagon = Profile2D(plane: .xy, segments: corners.indices.map { .line(corners[$0], corners[($0 + 1) % 6]) })
        let built = try await build(kernel, nodes: Nodes(), outline: hexagon, holeCenters: grid(columns: 2, rows: 2, spacingX: 30, spacingY: 20))
        #expect(built.filletEdges.count == 6)
        #expect(built.chamferEdges.count == 12)
        let filletKeys = built.filletEdges.compactMap { built.cut.topology.key(of: $0) }
        #expect(filletKeys.count == 6)
        #expect(Set(filletKeys).count == 6)
        #expect(keysAreDistinctAndNamed(built.chamferEdges, in: built.filleted))
        assertFullyNamed(built)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func noFaceIsUntaggedOrUnnamedInTheBracket(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let built = try await build(kernel, nodes: Nodes(), outline: .rectangle(width: 60, height: 40, plane: .xy),
                                    holeCenters: grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20))
        assertFullyNamed(built)
        #expect(try await kernel.properties(of: built.chamfered).volume < (try await kernel.properties(of: built.cut).volume))
    }
}
