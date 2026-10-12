import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Grid Pattern (patterns spec §3): placements on a grid in a plane, one branch per row.
struct GridPatternNodeTests {
    func rows(_ settings: [SocketName: ConstantValue]) async throws -> [[Plane]] {
        var h = Harness()
        let node = h.add(GridPatternNode.self, settings)
        let report = try await h.run([node])
        let tree = try #require(report.value(node, "placements")?.asTree, "\(String(describing: report.state(node)))")
        return tree.leaves.map { leaf in leaf.items.compactMap { if case .plane(let plane) = $0 { plane } else { nil } } }
    }

    func error(_ settings: [SocketName: ConstantValue]) async throws -> String? {
        var h = Harness()
        let node = h.add(GridPatternNode.self, settings)
        return try await h.run([node]).error(node)
    }

    @Test func aCentredGridHasOneBranchPerRowWithItsMiddleOnTheOrigin() async throws {
        let rows = try await rows(["countX": .integer(3), "countY": .integer(2), "spacingX": .number(10), "spacingY": .number(20)])
        #expect(rows.map(\.count) == [3, 3])
        #expect(rows.map { $0.map(\.origin.x) } == [[-10, 0, 10], [-10, 0, 10]])
        #expect(rows.map { $0.map(\.origin.y) } == [[-10, -10, -10], [10, 10, 10]])
        #expect(rows.flatMap { $0 }.allSatisfy { $0.normal == .unitZ && $0.xAxis == .unitX })
    }

    @Test func aGridThatIsNotCentredStartsOnThePlanesOrigin() async throws {
        let rows = try await rows(["countX": .integer(3), "countY": .integer(2), "centred": .bool(false)])
        #expect(rows.map { $0.map(\.origin.x) } == [[0, 10, 20], [0, 10, 20]])
        #expect(rows.map { $0.map(\.origin.y) } == [[0, 0, 0], [10, 10, 10]])
    }

    @Test func staggerMovesEverySecondRowHalfAPitchAndTheGridIsCentredWithIt() async throws {
        let rows = try await rows(["countX": .integer(3), "countY": .integer(3), "stagger": .bool(true)])
        #expect(rows.map { $0.map(\.origin.x) } == [[-12.5, -2.5, 7.5], [-7.5, 2.5, 12.5], [-12.5, -2.5, 7.5]])
        let single = try await self.rows(["countX": .integer(3), "countY": .integer(1), "stagger": .bool(true)])
        #expect(single.map { $0.map(\.origin.x) } == [[-10, 0, 10]], "one row has nothing to shift against")
    }

    @Test func theGridLiesInTheGivenPlaneAndFacesAlongItsNormal() async throws {
        let rows = try await rows(["plane": .plane(Plane.yz.offset(by: 5)), "countX": .integer(2), "countY": .integer(2),
                                   "centred": .bool(false),
        ])
        // The YZ plane's x axis is world Y and its y axis world Z, at x = 5.
        #expect(rows.map { $0.map(\.origin) } == [[Vector3(5, 0, 0), Vector3(5, 10, 0)], [Vector3(5, 0, 10), Vector3(5, 10, 10)]])
        #expect(rows.flatMap { $0 }.allSatisfy { $0.normal == .unitX && $0.xAxis == .unitY })
    }

    @Test func oneRowIsStillATreeSoAnotherRowAddedLaterRenamesNoPath() async throws {
        var h = Harness()
        let node = h.add(GridPatternNode.self, ["countY": .integer(1)])
        let report = try await h.run([node])
        #expect(report.value(node, "placements")?.depth == 2)
    }

    @Test func noRowsOrNoColumnsMakeAnEmptyTree() async throws {
        #expect(try await rows(["countY": .integer(0)]).isEmpty)
        #expect(try await rows(["countX": .integer(0), "countY": .integer(2)]).map(\.count) == [0, 0])
    }

    @Test(arguments: [
        (["countX": .integer(-1)], "“countX” can't be negative."),
        (["countY": .integer(-1)], "“countY” can't be negative."),
        (["spacingX": .number(-1)], "“spacingX” must be 0 or more."),
        (["countX": .integer(51), "countY": .integer(40)], "Patterns are limited to 2,000 instances."),
        (["countX": .integer(Int.max), "countY": .integer(3)], "Patterns are limited to 2,000 instances."),
        (["plane": .plane(Plane(origin: .zero, normal: .zero, xAxis: .unitX))], "The grid's plane has no usable direction."),
    ] as [([SocketName: ConstantValue], String)])
    func aBadInputIsRefusedInPlainWords(settings: [SocketName: ConstantValue], message: String) async throws {
        #expect(try await error(settings) == message)
    }

    @Test func aGridOfExactlyTheLimitIsAccepted() async throws {
        #expect(try await rows(["countX": .integer(50), "countY": .integer(40)]).map(\.count).reduce(0, +) == 2_000)
    }
}
