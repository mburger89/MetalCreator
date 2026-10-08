import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

struct ProfileNodeTests {
    func profile(_ report: EvaluationReport, _ node: Node) throws -> Profile2D {
        try #require(report.value(node, "profile")?.profiles?.first)
    }

    @Test(arguments: [
        (0, Vector3(0, -10, 0), Vector3(20, 0, 0)), (4, Vector3(-10, -5, 0), Vector3(10, 5, 0)),
        (6, Vector3(0, 0, 0), Vector3(20, 10, 0)), (8, Vector3(-20, 0, 0), Vector3(0, 10, 0)),
    ])
    func rectangleAnchorsPlaceTheChosenPointOnTheOrigin(anchor: Int, low: Vector3, high: Vector3) async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self, ["anchor": .integer(anchor)])
        let result = try profile(try await h.run([rectangle]), rectangle)
        #expect(result.segments.count == 4)
        #expect(result.isClosed)
        #expect(result.bounds == BoundingBox(min: low, max: high))
    }

    @Test func rectangleOnXZStandsUp() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["orientation": .integer(1)])
        let rectangle = h.add(RectangleNode.self, ["width": .number(60), "height": .number(30), "anchor": .integer(7)])
        h.wire(plane, "plane", to: rectangle, "plane")
        let result = try profile(try await h.run([rectangle]), rectangle)
        #expect(result.bounds == BoundingBox(min: Vector3(-30, 0, 0), max: Vector3(30, 0, 30)))
    }

    @Test func badSizesAreExplained() async throws {
        var h = Harness()
        let flat = h.add(RectangleNode.self, ["height": .number(0)])
        let anchor = h.add(RectangleNode.self, ["anchor": .integer(9)])
        let report = try await h.run([flat, anchor])
        #expect(report.error(flat) == "“height” must be greater than 0 mm.")
        #expect(report.error(anchor) == "“anchor” must be 0 to 8 (top-left to bottom-right).")
    }

    @Test func roundedRectangleHasEightSegmentsAndZeroRadiusGivesFour() async throws {
        var h = Harness()
        let rounded = h.add(RoundedRectangleNode.self)
        let square = h.add(RoundedRectangleNode.self, ["cornerRadius": .number(0)])
        let report = try await h.run([rounded, square])
        #expect(try profile(report, rounded).segments.count == 8)
        #expect(try profile(report, rounded).isClosed)
        #expect(try profile(report, square).segments.count == 4)
    }

    @Test func tooLargeACornerRadiusNamesTheLimit() async throws {
        var h = Harness()
        let rounded = h.add(RoundedRectangleNode.self, ["width": .number(20), "height": .number(10), "cornerRadius": .number(5)])
        let report = try await h.run([rounded])
        #expect(report.error(rounded) == "Corner radius 5 mm is too large for a 20 × 10 mm rectangle (it must be less than 5 mm).")
    }

    @Test func circlesBroadcastOverWiredPoints() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["spacingX": .number(20), "spacingY": .number(16)])
        let circle = h.add(CircleNode.self, ["diameter": .number(5)])
        h.wire(grid, "points", to: circle, "plane")
        let report = try await h.run([circle])
        let circles = try #require(report.value(circle, "profile")?.profiles)
        #expect(circles.count == 4)
        #expect(circles.map(\.plane.origin) == [Vector3(-10, -8, 0), Vector3(10, -8, 0), Vector3(-10, 8, 0), Vector3(10, 8, 0)])
        guard case .arc(_, let radius, _, _)? = circles.first?.segments.first else { Issue.record("expected an arc"); return }
        #expect(radius == 2.5)
    }

    @Test func polygonSidesAreChecked() async throws {
        var h = Harness()
        let hexagon = h.add(RegularPolygonNode.self)
        let line = h.add(RegularPolygonNode.self, ["sides": .integer(2)])
        let report = try await h.run([hexagon, line])
        #expect(try profile(report, hexagon).segments.count == 6)
        // Exact text is safe on any host: message numbers use `Locale.messages` (Task 3).
        #expect(report.error(line) == "A polygon needs 3 to 1,000 sides.")
    }

    @Test func polylineFromWiredPoints() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1), "centred": .bool(false)])
        let open = h.add(PolylineNode.self, ["closed": .bool(false)])
        h.wire(grid, "points", to: open, "points")
        let report = try await h.run([open])
        #expect(try profile(report, open).segments.count == 2)
        #expect(try !profile(report, open).isClosed)
        #expect(report.isOK(open))
    }

    @Test func polylineProblemsAreExplained() async throws {
        var h = Harness()
        let points = h.add(GridPointsNode.self, ["countX": .integer(2), "countY": .integer(1)])
        let closed = h.add(PolylineNode.self)
        h.wire(points, "points", to: closed, "points")
        let same = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1), "spacingX": .number(0)])
        let repeated = h.add(PolylineNode.self, ["closed": .bool(false)])
        h.wire(same, "points", to: repeated, "points")
        let report = try await h.run([closed, repeated])
        #expect(report.error(closed) == "A closed polyline needs at least 3 points.")
        #expect(report.error(repeated) == "Points 1 and 2 are in the same place.")
    }

    @Test func polylineWarnsThatZIsIgnored() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(3)])
        let points = h.add(VectorNode.self)
        h.wire(series, "values", to: points, "x")
        h.wire(series, "values", to: points, "z")
        let polyline = h.add(PolylineNode.self, ["closed": .bool(false)])
        h.wire(points, "vector", to: polyline, "points")
        let report = try await h.run([polyline])
        #expect(report.warning(polyline) == "Point z values are ignored: points are placed on the plane by their x and y.")
        #expect(try profile(report, polyline).segments.count == 2)
    }
}
