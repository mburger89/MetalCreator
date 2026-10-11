import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Points to Placements (patterns spec §3): points in, planes facing a chosen direction out.
struct PointsToPlacementsNodeTests {
    /// Grid Points in a row of `count`, 10 mm apart from the origin, into Points to Placements.
    func run(count: Int) async throws -> (EvaluationReport, Node) {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(count), "countY": .integer(1), "spacingX": .number(10),
                                               "centred": .bool(false),
        ])
        let node = h.add(PointsToPlacementsNode.self)
        h.wire(grid, "points", to: node, "points")
        return (try await h.run([node]), node)
    }

    @Test func eachPointBecomesAPlaneFacingUpByDefault() async throws {
        let (report, node) = try await run(count: 3)
        let planes = try #require(report.value(node, "placements")?.planes)
        #expect(planes.map(\.origin) == [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)])
        #expect(planes.allSatisfy { $0.normal == .unitZ && $0.xAxis == .unitX })
    }

    @Test func aChosenDirectionIsTheNormalAndTheXAxisIsWorldXProjectedOntoIt() async throws {
        var h = Harness()
        let point = h.add(VectorNode.self, ["x": .number(1), "y": .number(2), "z": .number(3)])
        let node = h.add(PointsToPlacementsNode.self, ["direction": .vector(Vector3(0, 0, -2))])
        h.wire(point, "vector", to: node, "points")
        let plane = try #require(try await h.run([node]).value(node, "placements")?.planes?.first)
        #expect(plane.origin == Vector3(1, 2, 3))
        #expect(plane.normal == Vector3(0, 0, -1))
        #expect(plane.xAxis == .unitX)
    }

    @Test func aDirectionAlongXUsesYForTheXAxisSoItIsStillAFrame() async throws {
        var h = Harness()
        let point = h.add(VectorNode.self)
        let node = h.add(PointsToPlacementsNode.self, ["direction": .vector(.unitX)])
        h.wire(point, "vector", to: node, "points")
        let plane = try #require(try await h.run([node]).value(node, "placements")?.planes?.first)
        #expect(plane.normal == .unitX)
        #expect(abs(plane.xAxis.dot(plane.normal)) < 1e-12 && abs(plane.xAxis.length - 1) < 1e-12)
    }

    @Test func aZeroDirectionNamesItsPlacement() async throws {
        var h = Harness()
        let point = h.add(VectorNode.self)
        let node = h.add(PointsToPlacementsNode.self, ["direction": .vector(.zero)])
        h.wire(point, "vector", to: node, "points")
        #expect(try await h.run([node]).error(node) == "The direction of placement {0} can't be zero.")
    }

    @Test func moreThanTwoThousandPointsAreRefused() async throws {
        let (report, node) = try await run(count: 2001)
        #expect(report.error(node) == "Patterns are limited to 2,000 instances.")
    }

    @Test func noPointsGiveNoPlacements() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(0), "countY": .integer(0)])
        let node = h.add(PointsToPlacementsNode.self)
        h.wire(grid, "points", to: node, "points")
        let report = try await h.run([node])
        #expect(report.isOK(node))
        #expect(report.value(node, "placements")?.planes?.isEmpty == true)
    }
}
