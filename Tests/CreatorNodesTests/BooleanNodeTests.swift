import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

struct BooleanNodeTests {
    @Test func broadcastHolesAreSubtractedInOneBoolean() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let plate = h.box(60, 40, 6)
        let grid = h.add(GridPointsNode.self, ["spacingX": .number(20), "spacingY": .number(16)])
        let circle = h.add(CircleNode.self, ["diameter": .number(5)])
        let holes = h.add(ExtrudeNode.self, ["distance": .number(20), "mode": .integer(1)])
        h.wire(grid, "points", to: circle, "plane")
        h.wire(circle, "profile", to: holes, "profile")
        let cut = h.add(BooleanNode.self, ["operation": .integer(1)])
        h.wire(plate, "solid", to: cut, "target")
        h.wire(holes, "solid", to: cut, "tools")
        let report = try await h.run([cut], kernel: kernel)
        let solid = try onlySolid(report, cut)
        #expect(isClose(try await volume(solid, kernel), 60 * 40 * 6 - 4 * Double.pi * 6.25 * 6))
        #expect(report.isOK(cut))
        for item in 0..<4 {
            #expect(solid.topology.faces.contains { $0.tags.contains(TopoTag(node: holes.id, item: item, role: .side(segment: 0))) })
        }
    }

    @Test func unionAndIntersectOfOverlappingBoxes() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let a = h.box(10, 10, 10)
        let b = h.box(10, 10, 10, at: Vector3(5, 0, 0))
        let union = h.add(BooleanNode.self)
        let intersect = h.add(BooleanNode.self, ["operation": .integer(2)])
        for node in [union, intersect] {
            h.wire(a, "solid", to: node, "target")
            h.wire(b, "solid", to: node, "tools")
        }
        let report = try await h.run([union, intersect], kernel: kernel)
        #expect(isClose(try await volume(try onlySolid(report, union), kernel), 1500))
        #expect(isClose(try await volume(try onlySolid(report, intersect), kernel), 500))
    }

    @Test func aCutThatSplitsThePartWarns() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let bar = h.box(30, 10, 10)
        let slot = h.box(2, 20, 20, at: Vector3(0, 0, -5))
        let cut = h.add(BooleanNode.self, ["operation": .integer(1)])
        h.wire(bar, "solid", to: cut, "target")
        h.wire(slot, "solid", to: cut, "tools")
        let report = try await h.run([cut], kernel: kernel)
        #expect(report.warning(cut) == "The result is 2 separate pieces. They stay together as one solid, because parts with several bodies aren't supported yet.")
        #expect(isClose(try await volume(try onlySolid(report, cut), kernel), 2800))
    }

    @Test func anEmptyIntersectionIsAPlainError() async throws {
        var h = Harness()
        let a = h.box(10, 10, 10)
        let b = h.box(10, 10, 10, at: Vector3(50, 0, 0))
        let intersect = h.add(BooleanNode.self, ["operation": .integer(2)])
        h.wire(a, "solid", to: intersect, "target")
        h.wire(b, "solid", to: intersect, "tools")
        let report = try await h.run([intersect], kernel: OCCTKernel())
        #expect(report.error(intersect) != nil)
        #expect(report.error(intersect)?.contains("occt") == false)
    }

    /// Hole count 0: Grid Points, Circle and Extrude broadcast to empty lists, and the kernel
    /// refuses an empty tool list, so the node passes the target through.
    @Test func anEmptyToolListLeavesTheTargetUnchanged() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let plate = h.box(60, 40, 6)
        let grid = h.add(GridPointsNode.self, ["total": .integer(0)])
        let circle = h.add(CircleNode.self, ["diameter": .number(5)])
        let holes = h.add(ExtrudeNode.self, ["distance": .number(20), "mode": .integer(1)])
        h.wire(grid, "points", to: circle, "plane")
        h.wire(circle, "profile", to: holes, "profile")
        let cut = h.add(BooleanNode.self, ["operation": .integer(1)])
        let join = h.add(BooleanNode.self)
        let intersect = h.add(BooleanNode.self, ["operation": .integer(2)])
        for node in [cut, join, intersect] {
            h.wire(plate, "solid", to: node, "target")
            h.wire(holes, "solid", to: node, "tools")
        }
        let report = try await h.run([cut, join, intersect], kernel: kernel)
        #expect(report.value(holes, "solid")?.solids?.isEmpty == true)
        #expect(report.isOK(cut))
        #expect(report.isOK(join))
        #expect(isClose(try await volume(try onlySolid(report, cut), kernel), 60 * 40 * 6))
        #expect(report.error(intersect) == "Connect at least one tool solid.")
    }

    @Test func pieceCountFollowsSharedEdges() {
        let tag = TopoTag(node: NodeID(), item: 0, role: .startCap)
        let faces = (0..<4).map { FaceInfo(id: FaceID($0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [tag]) }
        func edge(_ id: Int, _ a: Int, _ b: Int) -> EdgeInfo {
            EdgeInfo(id: EdgeID(id), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .convex,
                     faces: [FaceID(a), FaceID(b)])
        }
        #expect(Topology(faces: faces, edges: [edge(0, 0, 1), edge(1, 2, 3)]).pieceCount == 2)
        #expect(Topology(faces: faces, edges: [edge(0, 0, 1), edge(1, 1, 2), edge(2, 2, 3)]).pieceCount == 1)
    }
}
