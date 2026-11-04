import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

struct ConvertUnitsNodeTests {
    static let lengthFactors: [Double] = [1, 10, 1000, 25.4, 304.8]

    func length(_ value: Double, from: Int, to: Int) -> [SocketName: ConstantValue] {
        ["value": .number(value), "quantity": .integer(0), "fromLength": .integer(from), "toLength": .integer(to)]
    }

    @Test func twoInchesIsFiftyPointEightMillimetres() async throws {
        var h = Harness()
        let node = h.add(ConvertUnitsNode.self, ["value": .number(2)])
        let report = try await h.run([node])
        #expect(report.value(node, "value")?.numbers == [50.8])
        #expect(report.isOK(node))
    }

    @Test func defaultsReadTwentyFivePointFourForOne() async throws {
        var h = Harness()
        let node = h.add(ConvertUnitsNode.self)
        let report = try await h.run([node])
        #expect(report.value(node, "value")?.numbers == [25.4])
    }

    @Test func everyLengthPairRoundTrips() async throws {
        for from in 0..<5 {
            for to in 0..<5 {
                var h = Harness()
                let there = h.add(ConvertUnitsNode.self, length(37.25, from: from, to: to))
                let back = h.add(ConvertUnitsNode.self, length(0, from: to, to: from))
                h.wire(there, "value", to: back, "value")
                let report = try await h.run([there, back])
                let expected = 37.25 * Self.lengthFactors[from] / Self.lengthFactors[to]
                let converted = try #require(report.value(there, "value")?.numbers?.first)
                #expect(isClose(converted, expected, relative: 1e-12), "\(from) to \(to)")
                let returned = try #require(report.value(back, "value")?.numbers?.first)
                #expect(isClose(returned, 37.25, relative: 1e-12), "\(from) to \(to) and back")
            }
        }
    }

    @Test func aFootIs304Point8Millimetres() async throws {
        var h = Harness()
        let node = h.add(ConvertUnitsNode.self, length(1, from: 4, to: 0))
        let report = try await h.run([node])
        #expect(report.value(node, "value")?.numbers == [304.8])
    }

    @Test func degreesToRadiansAndBack() async throws {
        var h = Harness()
        let toRad = h.add(ConvertUnitsNode.self, ["value": .number(180), "quantity": .integer(1)])
        let toDeg = h.add(ConvertUnitsNode.self, ["quantity": .integer(1), "fromAngle": .integer(1), "toAngle": .integer(0)])
        h.wire(toRad, "value", to: toDeg, "value")
        let report = try await h.run([toRad, toDeg])
        #expect(report.value(toRad, "value")?.numbers == [Double.pi])
        let back = try #require(report.value(toDeg, "value")?.numbers?.first)
        #expect(isClose(back, 180, relative: 1e-12))
    }

    @Test func theSameUnitIsExact() async throws {
        // 0.1 * 25.4 / 25.4 is not 0.1 in floating point; the same unit must not multiply and divide.
        #expect(13.311 * 25.4 / 25.4 != 13.311)
        var h = Harness()
        let values: [Double] = [13.311, 44.505, 42.85, 1e-300, 123_456.789_012_345]
        var nodes: [Node] = []
        for value in values {
            nodes.append(h.add(ConvertUnitsNode.self, length(value, from: 3, to: 3)))
            nodes.append(h.add(ConvertUnitsNode.self, ["value": .number(value), "quantity": .integer(1),
                                                       "fromAngle": .integer(1), "toAngle": .integer(1),
                                                       ]))
        }
        let report = try await h.run(nodes)
        for (index, node) in nodes.enumerated() {
            #expect(report.value(node, "value")?.numbers == [values[index / 2]])
        }
    }

    @Test func aHiddenQuantitysUnitsDoNotMatter() async throws {
        var h = Harness()
        let node = h.add(ConvertUnitsNode.self, ["value": .number(2), "fromAngle": .integer(99), "toAngle": .integer(-4)])
        let report = try await h.run([node])
        #expect(report.value(node, "value")?.numbers == [50.8])
    }

    @Test func anOutOfRangeOptionRefuses() async throws {
        var h = Harness()
        let node = h.add(ConvertUnitsNode.self, ["toLength": .integer(5)])
        let quantity = h.add(ConvertUnitsNode.self, ["quantity": .integer(2)])
        let report = try await h.run([node, quantity])
        #expect(report.error(node)?.hasPrefix("Choose") == true)
        #expect(report.error(quantity)?.hasPrefix("Choose") == true)
    }

    @Test func aListBroadcasts() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(1), "step": .number(1), "count": .integer(3)])
        let node = h.add(ConvertUnitsNode.self)
        h.wire(series, "values", to: node, "value")
        let report = try await h.run([node])
        let value = try #require(report.value(node, "value"))
        #expect(value.isList)
        #expect(value.numbers == [25.4, 50.8, 25.4 * 3])
    }

    @Test func aTreeKeepsItsShape() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(0), "step": .number(1), "count": .integer(4)])
        let partition = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(series, "values", to: partition, "tree")
        let node = h.add(ConvertUnitsNode.self, length(0, from: 2, to: 0))
        h.wire(partition, "tree", to: node, "value")
        let report = try await h.run([node])
        #expect(report.value(node, "value")?.outline == "[[0,1000],[2000,3000]]")
    }

    @Test func aNonFiniteValueRefuses() async throws {
        var h = Harness()
        let nan = h.add(ConvertUnitsNode.self, ["value": .number(.nan)])
        let infinite = h.add(ConvertUnitsNode.self, ["value": .number(.infinity), "quantity": .integer(1)])
        let overflow = h.add(ConvertUnitsNode.self, length(1e308, from: 2, to: 0))
        let report = try await h.run([nan, infinite, overflow])
        #expect(report.error(nan) == "“value” must be a finite number.")
        #expect(report.error(infinite) == "“value” must be a finite number.")
        #expect(report.error(overflow) == "“value” must be a finite number.")
    }

    @Test func theInspectorShowsOnlyTheActiveQuantity() {
        func names(_ node: Node) -> [SocketName] {
            ConvertUnitsNode.inspector(for: node).flatMap(\.controls).compactMap { control in
                switch control {
                case .number(let name), .segmented(let name, _): name
                default: nil
                }
            }
        }
        var h = Harness()
        let lengthNode = h.add(ConvertUnitsNode.self)
        let angleNode = h.add(ConvertUnitsNode.self, ["quantity": .integer(1)])
        #expect(names(lengthNode) == ["value", "quantity", "fromLength", "toLength"])
        #expect(names(angleNode) == ["value", "quantity", "fromAngle", "toAngle"])
        let notes = ConvertUnitsNode.inspector(for: lengthNode).flatMap(\.controls).filter { if case .note = $0 { true } else { false } }
        #expect(notes == [.note("Length inputs elsewhere read millimetres, so convert to mm before wiring into one.")])
    }

    @Test func theDocumentsUnitsDoNotTouchIt() async throws {
        var h = Harness()
        let node = h.add(ConvertUnitsNode.self, ["value": .number(2)])
        var graph = h.graph
        graph.units = DocumentUnits(length: .inches)
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(graph, demand: [node.id])
        #expect(report.value(node, "value")?.numbers == [50.8])
        #expect(ConvertUnitsNode.inputs.first { $0.name == "value" }?.unit == ValueUnit.none)
    }

    @Test func aSavedNodeRoundTrips() throws {
        var h = Harness()
        let node = h.add(ConvertUnitsNode.self, ["value": .number(3), "quantity": .integer(1),
                                                 "fromLength": .integer(4), "toAngle": .integer(0),
                                                 ])
        let file = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: h.graph)), registry: BuiltInNodes.registry)
        let loaded = try #require(file.graph.nodes[node.id])
        #expect(loaded.typeID == ConvertUnitsNode.typeID)
        #expect(loaded.inputValues == node.inputValues)
        #expect(loaded.inputValues["fromLength"] == .integer(4))
    }
}
