import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// The bracket's holes (spec §7.2) cut two ways on OCCT: by moving the tool with Transform, which keeps working, and
/// by placing it with Place. Same part, and the new path names each hole by its instance.
struct PlaceBracketTests {
    struct Bracket {
        var h = Harness()
        let plate: Node, holes: Node, grid: Node

        init() {
            plate = h.box(60, 40, 6)
            grid = h.add(GridPointsNode.self, ["spacingX": .number(40), "spacingY": .number(20)])
            let circle = h.add(CircleNode.self, ["diameter": .number(5), "plane": .plane(Plane.xy.offset(by: -1))])
            holes = h.add(ExtrudeNode.self, ["distance": .number(8)])
            h.wire(circle, "profile", to: holes, "profile")
        }
    }

    static let expectedVolume = 60.0 * 40 * 6 - 4 * Double.pi * 6.25 * 6

    @Test func theTransformPathStillCutsTheBracketsHoles() async throws {
        let kernel = OCCTKernel()
        var b = Bracket()
        let moved = b.h.add(TransformNode.self)
        b.h.wire(b.holes, "solid", to: moved, "solid")
        b.h.wire(b.grid, "points", to: moved, "move")
        let cut = b.h.add(BooleanNode.self, ["operation": .integer(1)])
        b.h.wire(b.plate, "solid", to: cut, "target")
        b.h.wire(moved, "solid", to: cut, "tools")
        let report = try await b.h.run([cut], kernel: kernel)
        #expect(report.isOK(cut))
        #expect(isClose(try await volume(try onlySolid(report, cut), kernel), Self.expectedVolume))
    }

    @Test func thePlacePathCutsTheSamePartAndNamesEachHoleByInstance() async throws {
        let kernel = OCCTKernel()
        var b = Bracket()
        let placements = b.h.add(PointsToPlacementsNode.self)
        let place = b.h.add(PlaceNode.self)
        b.h.wire(b.grid, "points", to: placements, "points")
        b.h.wire(b.holes, "solid", to: place, "tool")
        b.h.wire(placements, "placements", to: place, "placements")
        let cut = b.h.add(BooleanNode.self, ["operation": .integer(1)])
        b.h.wire(b.plate, "solid", to: cut, "target")
        b.h.wire(place, "solids", to: cut, "tools")
        let report = try await b.h.run([cut], kernel: kernel)
        #expect(report.isOK(cut))
        let solid = try onlySolid(report, cut)
        #expect(isClose(try await volume(solid, kernel), Self.expectedVolume))
        let qualifier = NodeID.instanceScoped([place.id, b.holes.id])
        for index in 0..<4 {
            let wall = TopoTag(node: qualifier, item: index, role: .side(segment: 0))
            #expect(solid.topology.faces.filter { $0.tags.contains(wall) }.count == 1)
        }
    }
}
