import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Place (patterns spec §3): a tool built at the origin facing +Z, and a copy of it for every placement.
struct PlaceNodeTests {
    /// A 10 mm box tool (centred on XY, z 0…10) and Grid Points → Points to Placements → Place.
    struct Fixture {
        var h = Harness()
        let tool: Node, grid: Node, placements: Node, place: Node

        init(columns: Int = 2, rows: Int = 2, direction: Vector3 = .unitZ) {
            tool = h.box(10, 10, 10)
            grid = h.add(GridPointsNode.self, ["countX": .integer(columns), "countY": .integer(rows), "spacingX": .number(20),
                                               "spacingY": .number(20),
            ])
            placements = h.add(PointsToPlacementsNode.self, ["direction": .vector(direction)])
            place = h.add(PlaceNode.self)
            h.wire(grid, "points", to: placements, "points")
            h.wire(placements, "placements", to: place, "placements")
            h.wire(tool, "solid", to: place, "tool")
        }
    }

    @Test func aToolAndAGridMakeACopyPerPlacementInOneKernelCall() async throws {
        let f = Fixture()
        let kernel = FakeKernel()
        await kernel.clearLog()
        let report = try await f.h.run([f.place], kernel: kernel)
        #expect(report.isOK(f.place))
        #expect(report.value(f.place, "solids")?.solids?.count == 4)
        #expect(await kernel.operationLog.filter { $0 == "place" }.count == 1)
        #expect(await kernel.operationLog.contains("transform") == false)
    }

    @Test func copiesSitAtTheirPlacementsInGridOrder() async throws {
        let f = Fixture()
        let report = try await f.h.run([f.place])
        let copies = try #require(report.value(f.place, "solids")?.solids)
        let centres = copies.map { ($0.bounds.min + $0.bounds.max) * 0.5 }
        #expect(centres.map(\.x) == [-10, 10, -10, 10])
        #expect(centres.map(\.y) == [-10, -10, 10, 10])
        #expect(copies.allSatisfy { $0.bounds.min.z == 0 && $0.bounds.max.z == 10 })
    }

    @Test func aPlacementFacingAwayTurnsTheToolToFaceIt() async throws {
        let f = Fixture(columns: 1, rows: 1, direction: .unitX)
        let report = try await f.h.run([f.place])
        let copy = try #require(report.value(f.place, "solids")?.solids?.first)
        // Standing on +Z becomes standing on +X: 0…10 along X, ±5 on Y and Z.
        #expect(isClose(copy.bounds.min, Vector3(0, -5, -5)))
        #expect(isClose(copy.bounds.max, Vector3(10, 5, 5)))
    }

    @Test func eachCopysTagsAreTheToolsQualifiedByTheInstance() async throws {
        let f = Fixture()
        let report = try await f.h.run([f.place])
        let copies = try #require(report.value(f.place, "solids")?.solids)
        let qualifier = NodeID.instanceScoped([f.place.id, f.tool.id])
        for (index, copy) in copies.enumerated() {
            let tags = Set(copy.topology.faces.flatMap(\.tags))
            #expect(tags.contains(TopoTag(node: qualifier, item: index, role: .endCap)))
            #expect(tags.allSatisfy { $0.node == qualifier && $0.item == index })
        }
    }

    @Test func aListOfToolsMeetsAListOfPlacementsAndTheShorterRepeatsItsLast() async throws {
        var f = Fixture(columns: 3, rows: 1)
        let heights = f.h.add(SeriesNode.self, ["start": .number(5), "step": .number(5), "count": .integer(2)])
        f.h.wire(heights, "values", to: f.tool, "distance")
        let report = try await f.h.run([f.place])
        let copies = try #require(report.value(f.place, "solids")?.solids)
        #expect(copies.map(\.bounds.max.z) == [5, 10, 10])
    }

    @Test func moreToolsThanPlacementsStillPlacesEveryTool() async throws {
        var f = Fixture(columns: 1, rows: 1)
        let heights = f.h.add(SeriesNode.self, ["start": .number(5), "step": .number(5), "count": .integer(3)])
        f.h.wire(heights, "values", to: f.tool, "distance")
        let report = try await f.h.run([f.place])
        let copies = try #require(report.value(f.place, "solids")?.solids)
        #expect(copies.map(\.bounds.max.z) == [5, 10, 15])
        #expect(Set(copies.map { ($0.bounds.min + $0.bounds.max).x }).count == 1)
    }

    @Test func noPlacementsIsAnEmptyListNotAnError() async throws {
        var f = Fixture(columns: 1, rows: 1)
        f.h.set(f.grid, "total", .integer(0))
        let report = try await f.h.run([f.place])
        #expect(report.isOK(f.place))
        #expect(report.value(f.place, "solids")?.solids?.isEmpty == true)
    }

    @Test func moreThanTwoThousandInstancesAreRefused() async throws {
        // 2,001 tools meeting one placement: Place's own limit, past Points to Placements'.
        var f = Fixture(columns: 1, rows: 1)
        let heights = f.h.add(SeriesNode.self, ["start": .number(1), "step": .number(1), "count": .integer(2001)])
        f.h.wire(heights, "values", to: f.tool, "distance")
        #expect(try await f.h.run([f.place]).error(f.place) == "Patterns are limited to 2,000 instances.")
        let atTheLimit = Fixture(columns: 2000, rows: 1)
        #expect(try await atTheLimit.h.run([atTheLimit.place]).value(atTheLimit.place, "solids")?.solids?.count == 2000)
    }

    @Test func aPlacementWithNoDirectionNamesItsPath() async throws {
        var h = Harness()
        let tool = h.box(10, 10, 10)
        let place = h.add(PlaceNode.self)
        h.wire(tool, "solid", to: place, "tool")
        h.set(place, "placements", .plane(Plane(origin: .zero, normal: .zero, xAxis: .unitX)))
        let report = try await h.run([place])
        #expect(report.error(place) == "Placement {0} has no usable direction: its normal and x axis must not be zero or along each other.")
    }

    @Test func aWiredPlaneAndAPointBothWorkAsAPlacement() async throws {
        var h = Harness()
        let tool = h.box(10, 10, 10)
        let plane = h.add(PlaneNode.self, ["orientation": .integer(1), "offset": .number(0)])
        let place = h.add(PlaceNode.self)
        h.wire(tool, "solid", to: place, "tool")
        h.wire(plane, "plane", to: place, "placements")
        let copy = try onlySolid(try await h.run([place]), place, "solids")
        // The XZ plane faces −Y: the box lies along −Y.
        #expect(isClose(copy.bounds.min, Vector3(-5, -10, -5)))
        #expect(isClose(copy.bounds.max, Vector3(5, 0, 5)))
    }

    /// Group instances rename the copies a pattern node placed (`GroupScopes.lifting`), so the nodes that place copies say so.
    @Test func onlyTheNodesThatPlaceCopiesAreFlaggedAsPlacers() {
        let flagged = BuiltInNodes.all.filter { $0.placesInstances }.map { $0.typeID }  // A key path on a metatype crashes Swift 6.4.
        #expect(Set(flagged) == [PlaceNode.typeID, HolePatternNode.typeID, BossPatternNode.typeID, SlotPatternNode.typeID,
                                 PatternFeatureNode.typeID,
        ])
    }
}
