import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

struct GeneratorNodeTests {
    @Test func seriesSteps() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["start": .number(2), "step": .number(0.5), "count": .integer(4)])
        let report = try await h.run([series])
        let values = try #require(report.value(series, "values"))
        #expect(values.isList)
        #expect(values.numbers == [2, 2.5, 3, 3.5])
    }

    @Test func aOneItemSeriesIsStillAList() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(1)])
        let report = try await h.run([series])
        #expect(report.value(series, "values")?.isList == true)
        #expect(report.value(series, "values")?.numbers == [0])
    }

    @Test func rangeIncludesBothEnds() async throws {
        var h = Harness()
        let range = h.add(RangeNode.self, ["start": .number(0), "end": .number(10), "count": .integer(5)])
        let single = h.add(RangeNode.self, ["start": .number(3), "end": .number(10), "count": .integer(1)])
        let empty = h.add(RangeNode.self, ["count": .integer(0)])
        let report = try await h.run([range, single, empty])
        #expect(report.value(range, "values")?.numbers == [0, 2.5, 5, 7.5, 10])
        #expect(report.value(single, "values")?.numbers == [3])
        #expect(report.value(empty, "values")?.numbers == [])
    }

    @Test func negativeAndHugeCountsAreRefused() async throws {
        var h = Harness()
        let negative = h.add(SeriesNode.self, ["count": .integer(-1)])
        let huge = h.add(RangeNode.self, ["count": .integer(1_000_000)])
        let report = try await h.run([negative, huge])
        #expect(report.error(negative) == "“count” can't be negative.")
        #expect(report.error(huge)?.contains("at most") == true)
    }

    @Test func gridPointsAreCentredRowByRow() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["spacingX": .number(20), "spacingY": .number(16)])
        let report = try await h.run([grid])
        #expect(report.value(grid, "points")?.vectors == [
            Vector3(-10, -8, 0), Vector3(10, -8, 0), Vector3(-10, 8, 0), Vector3(10, 8, 0),
        ])
    }

    @Test func uncentredGridStartsAtTheOrigin() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1), "centred": .bool(false)])
        let report = try await h.run([grid])
        #expect(report.value(grid, "points")?.vectors == [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)])
    }

    @Test(arguments: [(4, 2), (6, 3)])
    func totalDrivesTheColumnCount(total: Int, columns: Int) async throws {
        var h = Harness()
        let count = h.add(IntegerNode.self, ["value": .integer(total)])
        let grid = h.add(GridPointsNode.self, ["countX": .integer(99), "spacingX": .number(20), "spacingY": .number(16)])
        h.wire(count, "value", to: grid, "total")
        let report = try await h.run([grid])
        let points = try #require(report.value(grid, "points")?.vectors)
        #expect(points.count == total)
        #expect(Set(points.map(\.x)).count == columns)
        #expect(Set(points.map(\.y)) == [-8, 8])
    }

    @Test func aShortLastRowKeepsTheFullGridCentre() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["total": .integer(3)])
        let report = try await h.run([grid])
        #expect(report.value(grid, "points")?.vectors == [Vector3(-5, -5, 0), Vector3(5, -5, 0), Vector3(-5, 5, 0)])
    }

    @Test func aTotalWithNoRowsIsExplained() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countY": .integer(0), "total": .integer(4)])
        let report = try await h.run([grid])
        #expect(report.error(grid) == "Set “countY” to at least 1 to lay out “total” points.")
    }

    @Test func pointsBroadcastIntoDownstreamNodes() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self)
        let plane = h.add(PlaneNode.self)
        let series = h.add(SeriesNode.self, ["count": .integer(3)])
        h.wire(series, "values", to: plane, "offset")
        let report = try await h.run([grid, plane])
        #expect(report.value(grid, "points")?.vectors?.count == 4)
        #expect(report.value(plane, "plane")?.planes?.map(\.origin.z) == [0, 1, 2])
    }
}
