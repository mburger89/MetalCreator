import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

struct ValueNodeTests {
    @Test func numberAndIntegerPassTheirValues() async throws {
        var h = Harness()
        let number = h.add(NumberNode.self, ["value": .number(2.5)])
        let integer = h.add(IntegerNode.self, ["value": .integer(7)])
        let report = try await h.run([number, integer])
        #expect(report.value(number, "value")?.numbers == [2.5])
        #expect(report.value(integer, "value")?.integers == [7])
        #expect(report.isOK(number) && report.isOK(integer))
    }

    @Test func vectorCombinesThreeNumbers() async throws {
        var h = Harness()
        let vector = h.add(VectorNode.self, ["x": .number(1), "y": .number(-2), "z": .number(3)])
        let report = try await h.run([vector])
        #expect(report.value(vector, "vector")?.vectors == [Vector3(1, -2, 3)])
    }

    @Test func numbersCanBeWiredIntoAVector() async throws {
        var h = Harness()
        let number = h.add(NumberNode.self, ["value": .number(4)])
        let vector = h.add(VectorNode.self)
        h.wire(number, "value", to: vector, "z")
        let report = try await h.run([vector])
        #expect(report.value(vector, "vector")?.vectors == [Vector3(0, 0, 4)])
    }

    @Test func planeOffsetsAlongItsNormal() async throws {
        var h = Harness()
        let xy = h.add(PlaneNode.self, ["offset": .number(5)])
        let xz = h.add(PlaneNode.self, ["orientation": .integer(1), "offset": .number(-20)])
        let yz = h.add(PlaneNode.self, ["orientation": .integer(2)])
        let report = try await h.run([xy, xz, yz])
        #expect(report.value(xy, "plane")?.planes == [Plane.xy.offset(by: 5)])
        #expect(report.value(xz, "plane")?.planes?.first?.origin == Vector3(0, 20, 0))
        #expect(report.value(xz, "plane")?.planes?.first?.normal == -.unitY)
        #expect(report.value(yz, "plane")?.planes == [Plane.yz])
    }

    @Test func anOutOfRangeChoiceNamesTheOptions() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["orientation": .integer(7)])
        let report = try await h.run([plane])
        let message = try #require(report.error(plane))
        #expect(message.contains("XZ"))
        #expect(message.contains("“orientation”"))
    }

    @Test func aWiredIntegerWidensToANumber() async throws {
        var h = Harness()
        let integer = h.add(IntegerNode.self, ["value": .integer(3)])
        let vector = h.add(VectorNode.self)
        h.wire(integer, "value", to: vector, "x")
        let report = try await h.run([vector])
        #expect(report.value(vector, "vector")?.vectors == [Vector3(3, 0, 0)])
    }
}
