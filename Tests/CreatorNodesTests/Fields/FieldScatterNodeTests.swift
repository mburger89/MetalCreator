import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Field Scatter on a profile (fields spec §3.3): the region, the spacing from the field, determinism and the refusals.
struct FieldScatterNodeTests {
    /// A Rectangle on the XY plane wired into a Field Scatter's `profile`.
    struct Fixture {
        var h = Harness()
        let rectangle: Node
        let scatter: Node

        init(_ settings: [SocketName: ConstantValue] = [:], width: Double = 60, height: Double = 40) {
            rectangle = h.add(RectangleNode.self, ["width": .number(width), "height": .number(height), "plane": .plane(.xy)])
            scatter = h.add(FieldScatterNode.self, settings)
            h.wire(rectangle, "profile", to: scatter, "profile")
        }

        func run(kernel: any Kernel = FakeKernel()) async throws -> EvaluationReport {
            try await h.run([scatter], kernel: kernel)
        }

        func planes(_ report: EvaluationReport) throws -> [Plane] {
            try #require(report.value(scatter, "placements")?.planes, "\(String(describing: report.state(scatter)))")
        }

        func points(_ report: EvaluationReport) throws -> [Vector3] { try planes(report).map(\.origin) }
    }

    static func nearestPair(_ points: [Vector3]) -> Double {
        var nearest = Double.infinity
        for (index, a) in points.enumerated() {
            for b in points[(index + 1)...] { nearest = min(nearest, (a - b).length) }
        }
        return nearest
    }

    @Test func itMakesAFlatListOfPlacementsFacingTheProfilesNormal() async throws {
        let f = Fixture(["minSpacing": .number(6), "maxSpacing": .number(6), "margin": .number(3)])
        let report = try await f.run()
        let value = try #require(report.value(f.scatter, "placements"))
        #expect(value.isList && report.isOK(f.scatter))
        let planes = try f.planes(report)
        #expect(planes.count >= 20)
        #expect(planes.allSatisfy { $0.normal == .unitZ && $0.xAxis == .unitX && $0.origin.z == 0 })
        #expect(planes.allSatisfy { abs($0.origin.x) <= 27 + 1e-9 && abs($0.origin.y) <= 17 + 1e-9 }, "inside the 3 mm margin")
        #expect(Self.nearestPair(planes.map(\.origin)) >= 6 - 1e-9)
    }

    @Test func theSpacingIsTheMinimumPlusTheClampedFieldTimesTheRange() async throws {
        // A constant field of 0.5 is spacing 8 between 6 and 10; 5 clamps to 1 (spacing 10); -3 clamps to 0 (spacing 6).
        var spacings: [Double: [Vector3]] = [:]
        for (field, spacing) in [(0.5, 8.0), (5.0, 10.0), (-3.0, 6.0)] {
            let f = Fixture(["minSpacing": .number(6), "maxSpacing": .number(10), "field": .number(field), "margin": .number(0)])
            let points = try f.points(try await f.run())
            spacings[spacing] = points
            #expect(Self.nearestPair(points) >= spacing - 1e-9, "field \(field)")
        }
        let counts = [6.0, 8.0, 10.0].map { spacings[$0]?.count ?? 0 }
        #expect(counts[0] > counts[1] && counts[1] > counts[2], "a smaller spacing places more points: \(counts)")
    }

    @Test func theSameInputsGiveTheSamePointsAndAnotherSeedOthers() async throws {
        var f = Fixture(["minSpacing": .number(5), "maxSpacing": .number(8), "seed": .integer(3)])
        let first = try f.points(try await f.run())
        let again = try f.points(try await f.run())
        #expect(again == first)
        f.h.set(f.scatter, "seed", .integer(4))
        let other = try f.points(try await f.run())
        #expect(other != first)
    }

    @Test func pointsAreDenserWhereTheFieldIsLow() async throws {
        // A linear gradient along +X from x = -30 (0) to x = 30 (1): spacing 4 at the left edge, 10 at the right.
        var f = Fixture(["minSpacing": .number(4), "maxSpacing": .number(10), "margin": .number(0)], width: 60, height: 40)
        let gradient = f.h.add(LinearGradientNode.self, [
            "plane": .plane(Plane(origin: Vector3(-30, 0, 0), normal: .unitX, xAxis: .unitY)), "length": .number(60),
        ])
        f.h.wire(gradient, "field", to: f.scatter, "field")
        let points = try f.points(try await f.run())
        let left = points.filter { $0.x < 0 }.count
        let right = points.count - left
        #expect(left > 2 * right && right > 5, "left \(left), right \(right)")
        #expect(Self.nearestPair(points) >= 4 - 1e-9)
    }

    // MARK: refusals

    @Test func withNoRegionOrTwoItSaysSo() async throws {
        var f = Fixture()
        f.h.set(f.scatter, "minSpacing", .number(5))
        var bare = Harness()
        let lone = bare.add(FieldScatterNode.self)
        let lonely = try await bare.run([lone])
        #expect(lonely.error(lone) == FieldScatterNode.noRegion)
        let plate = f.h.box(60, 40, 6)
        f.h.wire(plate, "solid", to: f.scatter, "solid")
        let both = try await f.run()
        #expect(both.error(f.scatter) == FieldScatterNode.bothRegions)
    }

    @Test(arguments: [
        ("minSpacing", ConstantValue.number(0), "“minSpacing” must be greater than 0 mm."),
        ("minSpacing", .number(-2), "“minSpacing” must be greater than 0 mm."),
        ("margin", .number(-1), "“margin” must be 0 or more."),
    ])
    func aBadNumberIsRefusedInWords(_ socket: String, _ value: ConstantValue, _ message: String) async throws {
        let f = Fixture([SocketName(socket): value])
        let report = try await f.run()
        #expect(report.error(f.scatter) == message)
    }

    @Test func aMaximumBelowTheMinimumIsRefused() async throws {
        let f = Fixture(["minSpacing": .number(8), "maxSpacing": .number(5)])
        let report = try await f.run()
        #expect(report.error(f.scatter) == "“maxSpacing” can't be less than “minSpacing” (8 mm).")
    }

    @Test func aMarginThatEatsTheRegionLeavesNoRoom() async throws {
        let f = Fixture(["margin": .number(25)])
        let report = try await f.run()
        #expect(report.error(f.scatter) == FieldScatterNode.noRoom)
    }

    @Test func moreThanTwoThousandPointsSaysHowManyWouldHaveBeenPlaced() async throws {
        let f = Fixture(["minSpacing": .number(1.5), "maxSpacing": .number(1.5), "margin": .number(0)], width: 100, height: 100)
        let message = try #require(try await f.run().error(f.scatter))
        #expect(message.hasPrefix("Field Scatter would place ") && !message.contains("more than"), "\(message)")
        #expect(message.hasSuffix(" points; patterns are limited to 2,000 instances."), "\(message)")
    }

    @Test func farMoreThanThatSaysMoreThanTheCeiling() async throws {
        let f = Fixture(["minSpacing": .number(2), "maxSpacing": .number(2), "margin": .number(0)], width: 400, height: 400)
        let report = try await f.run()
        #expect(report.error(f.scatter)
            == "Field Scatter would place more than 8,000 points; patterns are limited to 2,000 instances.")
    }

    @Test func aListWiredIntoASingleValuedInputIsRefusedInTheLayoutsWords() async throws {
        var f = Fixture()
        let series = f.h.add(SeriesNode.self, ["count": .integer(3)])
        f.h.wire(series, "values", to: f.scatter, "minSpacing")
        let report = try await f.run()
        #expect(report.error(f.scatter) == "Field Scatter takes single values, not lists: wire one value into each input, "
            + "or pick one out of the list first with List Item.")
    }

    @Test func anOpenProfileIsRefused() async throws {
        var h = Harness()
        let points = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1), "spacingX": .number(10)])
        let line = h.add(PolylineNode.self, ["closed": .bool(false)])
        let scatter = h.add(FieldScatterNode.self)
        h.wire(points, "points", to: line, "points")
        h.wire(line, "profile", to: scatter, "profile")
        let message = try #require(try await h.run([scatter]).error(scatter))
        #expect(message == "“profile” isn't a closed outline.")
    }

    @Test func aFieldThatIsNotANumberSomewhereIsRefusedNotTreatedAsZero() async throws {
        let inputs = NodeInputs(item: 0, slots: [
            "profile": .item(.profile(.rectangle(width: 20, height: 20, plane: .xy))), "field": .item(.field(.constant(.nan))),
            "minSpacing": .item(.number(4)), "maxSpacing": .item(.number(8)), "margin": .item(.number(1)), "seed": .item(.integer(0)),
        ])
        let context = EvalContext(node: BuiltInNodes.registry.makeNode(FieldScatterNode.typeID), item: 0, parameters: [:])
        await #expect(throws: NodeError.invalidValue(FieldScatterNode.notANumber)) {
            try await FieldScatterNode.evaluate(inputs, kernel: FakeKernel(), context: context)
        }
    }

    // MARK: the node's place in the catalogue

    @Test func theNodeIsDeclaredAsASingleValuedFieldsLayoutWithAHelpNote() {
        #expect(FieldScatterNode.category == .fields && FieldScatterNode.outputs.map(\.type) == [.plane])
        #expect(FieldScatterNode.inputs.map(\.name) == ["solid", "profile", "field", "minSpacing", "maxSpacing", "margin", "seed"])
        #expect(FieldScatterNode.inputs.prefix(2).allSatisfy { $0.isOptional })
        #expect(FieldScatterNode.inspector.last?.controls == [.note(FieldScatterNode.help)])
        #expect(FieldScatterNode.help
            == "Points renumber when the field or region changes; a pick on a scattered instance may stop matching.")
    }
}
