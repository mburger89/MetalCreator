import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Linear Pattern (patterns spec §3): placements along a line, one branch.
struct LinearPatternNodeTests {
    func run(_ settings: [SocketName: ConstantValue] = [:]) async throws -> (report: EvaluationReport, node: Node) {
        var h = Harness()
        let node = h.add(LinearPatternNode.self, settings)
        return (try await h.run([node]), node)
    }

    func planes(_ settings: [SocketName: ConstantValue]) async throws -> [Plane] {
        let (report, node) = try await run(settings)
        return try #require(report.value(node, "placements")?.planes, "\(String(describing: report.state(node)))")
    }

    @Test func fourPlacementsTenApartFromTheStartAlongTheDirection() async throws {
        let planes = try await planes(["start": .vector(Vector3(1, 2, 3)), "direction": .vector(.unitY), "count": .integer(4),
                                       "spacing": .number(10),
        ])
        #expect(planes.map(\.origin) == [Vector3(1, 2, 3), Vector3(1, 12, 3), Vector3(1, 22, 3), Vector3(1, 32, 3)])
        #expect(planes.allSatisfy { $0.normal == .unitZ && $0.xAxis == .unitX })
    }

    @Test func theOutputIsAFlatListSoPlacesNameItsInstancesByIndex() async throws {
        let (report, node) = try await run()
        #expect(report.value(node, "placements")?.isList == true)
        #expect(report.isOK(node))
    }

    @Test func aTotalLengthSpreadsThePlacementsOverIt() async throws {
        let planes = try await planes(["count": .integer(4), "length": .number(30), "spacing": .number(99)])
        #expect(planes.map(\.origin.x) == [0, 10, 20, 30])
    }

    @Test func aSinglePlacementStaysAtTheStartWhateverTheLength() async throws {
        let planes = try await planes(["count": .integer(1), "length": .number(30)])
        #expect(planes.map(\.origin) == [.zero])
    }

    @Test func aSlantedDirectionIsNormalisedSoSpacingIsTheRealDistance() async throws {
        let planes = try await planes(["direction": .vector(Vector3(3, 4, 0)), "count": .integer(2), "spacing": .number(10)])
        #expect(isClose(planes[1].origin, Vector3(6, 8, 0)))
    }

    @Test func facingTurnsEveryPlacementAndGivesItsXAxisThePlaneFromFaceWay() async throws {
        let planes = try await planes(["facing": .vector(.unitX), "count": .integer(2)])
        #expect(planes.allSatisfy { $0.normal == .unitX && isClose($0.xAxis, .unitY) })
        let up = try await self.planes(["facing": .vector(Vector3(0, 0, 5)), "count": .integer(1)])
        #expect(up[0].normal == .unitZ, "a facing is a direction, so only its way matters")
    }

    @Test func noCountMeansNoPlacements() async throws {
        let (report, node) = try await run(["count": .integer(0)])
        #expect(report.isOK(node))
        #expect(report.value(node, "placements")?.items.isEmpty == true)
    }

    @Test(arguments: [
        (["count": .integer(-1)], "“count” can't be negative."),
        (["direction": .vector(.zero)], "“direction” can't be zero."),
        (["facing": .vector(.zero)], "“facing” can't be zero."),
        (["spacing": .number(-1)], "“spacing” must be 0 or more."),
        (["count": .integer(2), "length": .number(-5)], "“length” must be 0 or more."),
        (["count": .integer(2_001)], "Patterns are limited to 2,000 instances."),
        (["count": .integer(Int.max)], "Patterns are limited to 2,000 instances."),
    ] as [([SocketName: ConstantValue], String)])
    func aBadInputIsRefusedInPlainWords(settings: [SocketName: ConstantValue], message: String) async throws {
        let (report, node) = try await run(settings)
        #expect(report.error(node) == message)
    }
}
