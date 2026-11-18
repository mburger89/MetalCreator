#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// NS-1 Task 6: each curve and surface node through the real Evaluator and OCCT, against the kernel tests' numbers.
struct SurfaceNodeTests {
    let kernel = OCCTKernel()

    func area(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).surfaceArea }

    func rectangle(_ h: inout Harness, _ width: Double, _ height: Double, at origin: Vector3 = .zero) -> Node {
        h.add(RectangleNode.self, ["width": .number(width), "height": .number(height), "plane": .plane(.through(origin))])
    }

    /// `count` points `step` mm apart along x (or z), through a Series and a Vector broadcast.
    func points(_ h: inout Harness, count: Int, step: Double, along z: Bool = false) -> Node {
        let series = h.add(SeriesNode.self, ["step": .number(step), "count": .integer(count)])
        let vector = h.add(VectorNode.self)
        h.wire(series, "values", to: vector, z ? "z" : "x")
        return vector
    }

    @Test func curveThroughPointsMakesACurveThroughThePoints() async throws {
        var h = Harness()
        let node = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 4, step: 10)
        h.wire(source, "vector", to: node, "points")
        let report = try await h.run([node], kernel: kernel)
        let curve = try #require(report.value(node, "curve")?.curves?.first)
        #expect(!curve.isClosed && curve.length > 29.9)
        #expect(isClose(curve.bounds.max.x, 30, relative: 1e-6))
    }

    @Test func degreeFiveNeedsSixPointsAndSaysSo() async throws {
        var h = Harness()
        let node = h.add(CurveThroughPointsNode.self, ["degree": .integer(1)])
        let source = points(&h, count: 3, step: 10)
        h.wire(source, "vector", to: node, "points")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == "A degree-5 curve needs at least six points.")
    }

    @Test(arguments: [0.0, -5, 400]) func revolveCurveRefusesAnAngleOutsideZeroTo360(angle: Double) async throws {
        var h = Harness()
        let rect = rectangle(&h, 4, 6, at: Vector3(10, 0, 0))
        let node = h.add(RevolveCurveNode.self, ["angle": .number(angle)])
        h.wire(rect, "profile", to: node, "curve")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == "The angle must be more than 0° and at most 360°.")
    }

    @Test func sweepShowsItsBinormalForFixedOrientationOnly() {
        func controls(_ orientation: Int) -> [InspectorControl] {
            var node = BuiltInNodes.registry.makeNode(SweepNode.typeID)
            node.inputValues["orientation"] = .integer(orientation)
            return SweepNode.inspector(for: node).flatMap(\.controls)
        }
        #expect(!controls(0).contains(.vector("binormal")))
        #expect(controls(1).contains(.vector("binormal")))
    }

    @Test func sweepShowsItsTwistForFrenetAndFixedOnly() {
        func controls(_ orientation: Int) -> [InspectorControl] {
            var node = BuiltInNodes.registry.makeNode(SweepNode.typeID)
            node.inputValues["orientation"] = .integer(orientation)
            return SweepNode.inspector(for: node).flatMap(\.controls)
        }
        #expect(controls(0).contains(.slider("twist")) && controls(1).contains(.slider("twist")))
        #expect(!controls(2).contains(.slider("twist")) && !controls(3).contains(.slider("twist")))
        let names = SweepNode.inputs.map(\.name)
        #expect(names.contains("rail") && names.contains("guide"))
    }

    @Test(arguments: [(2, "Wire a rail curve."), (3, "Wire a guide surface.")])
    func aRailOrGuideSweepNeedsItsInput(orientation: Int, sentence: String) async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let path = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 3, step: 10, along: true)
        h.wire(source, "vector", to: path, "points")
        let node = h.add(SweepNode.self, ["orientation": .integer(orientation)])
        h.wire(circle, "profile", to: node, "profiles")
        h.wire(path, "curve", to: node, "path")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == sentence)
    }

    @Test(arguments: [2, 3]) func aTwistWithARailOrGuideIsRefused(orientation: Int) async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let path = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 3, step: 10, along: true)
        h.wire(source, "vector", to: path, "points")
        let node = h.add(SweepNode.self, ["orientation": .integer(orientation), "twist": .number(30)])
        h.wire(circle, "profile", to: node, "profiles")
        h.wire(path, "curve", to: node, "path")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == "Twist can't be combined with a rail or a guide surface.")
    }

    @Test func severalRailsAreRefused() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let path = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 3, step: 10, along: true)
        h.wire(source, "vector", to: path, "points")
        let box = h.box(10, 20, 5)
        let edges = h.add(AllEdgesNode.self)
        h.wire(box, "solid", to: edges, "solid")
        let rails = h.add(CurveFromEdgesNode.self)
        h.wire(edges, "edges", to: rails, "edges")
        let node = h.add(SweepNode.self, ["orientation": .integer(2)])
        h.wire(circle, "profile", to: node, "profiles")
        h.wire(path, "curve", to: node, "path")
        h.wire(rails, "curves", to: node, "rail")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == "Sweep takes one rail curve.")
    }

    @Test(arguments: [0, 1]) func aWiredRailIsIgnoredAndSaysSo(orientation: Int) async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let path = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 3, step: 10, along: true)
        h.wire(source, "vector", to: path, "points")
        let box = h.box(10, 20, 5)
        let edges = h.add(AllEdgesNode.self)
        h.wire(box, "solid", to: edges, "solid")
        let rails = h.add(CurveFromEdgesNode.self)
        h.wire(edges, "edges", to: rails, "edges")
        let node = h.add(SweepNode.self, ["orientation": .integer(orientation)])
        h.wire(circle, "profile", to: node, "profiles")
        h.wire(path, "curve", to: node, "path")
        h.wire(rails, "curves", to: node, "rail")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.warning(node) == "The rail and guide are used only when the orientation is Rail or Guide.")
    }

    @Test func aWiredGuideIsIgnoredAndSaysSo() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let path = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 3, step: 10, along: true)
        h.wire(source, "vector", to: path, "points")
        let node = h.add(SweepNode.self)
        h.wire(circle, "profile", to: node, "profiles")
        h.wire(path, "curve", to: node, "path")
        h.wire(h.box(10, 20, 5), "solid", to: node, "guide")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.warning(node) == "The rail and guide are used only when the orientation is Rail or Guide.")
    }

    @Test func aSweepWithNothingIgnoredHasNoWarning() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let path = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 3, step: 10, along: true)
        h.wire(source, "vector", to: path, "points")
        let node = h.add(SweepNode.self)
        h.wire(circle, "profile", to: node, "profiles")
        h.wire(path, "curve", to: node, "path")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.warning(node) == nil)
    }

    @Test func theTwistIsInDegrees() throws {
        #expect(try #require(SweepNode.inputs.first { $0.name == "twist" }).unit == .degrees)
    }

    @Test func extrudeCurveHasADistanceHandle() {
        #expect(ExtrudeCurveNode.handles == [HandleSpec.linear("distance")])
    }

    @Test func profileToCurvesGivesOneCurvePerLoop() async throws {
        var h = Harness()
        let rect = rectangle(&h, 10, 20)
        let node = h.add(ProfileToCurvesNode.self)
        h.wire(rect, "profile", to: node, "profile")
        let report = try await h.run([node], kernel: kernel)
        let curves = try #require(report.value(node, "curves")?.curves)
        #expect(curves.count == 1 && curves[0].isClosed && isClose(curves[0].length, 60))
    }

    @Test func curveFromEdgesGivesCurvesCoveringAllTwelveBoxEdges() async throws {
        var h = Harness()
        let box = h.box(10, 20, 5)
        let edges = h.add(AllEdgesNode.self)
        h.wire(box, "solid", to: edges, "solid")
        let node = h.add(CurveFromEdgesNode.self)
        h.wire(edges, "edges", to: node, "edges")
        let report = try await h.run([node], kernel: kernel)
        let curves = try #require(report.value(node, "curves")?.curves)
        #expect(!curves.isEmpty)
        #expect(isClose(curves.reduce(0) { $0 + $1.length }, 4 * (10 + 20 + 5)))
    }

    @Test func planarSurfaceFillsARectangle() async throws {
        var h = Harness()
        let rect = rectangle(&h, 10, 20)
        let node = h.add(PlanarSurfaceNode.self)
        h.wire(rect, "profile", to: node, "curves")
        let report = try await h.run([node], kernel: kernel)
        #expect(isClose(try await area(try onlySolid(report, node, "surface")), 200))
    }

    @Test func extrudeCurveSweepsARectangleIntoAWall() async throws {
        var h = Harness()
        let rect = rectangle(&h, 10, 20)
        let node = h.add(ExtrudeCurveNode.self, ["distance": .number(5)])
        h.wire(rect, "profile", to: node, "curve")
        let report = try await h.run([node], kernel: kernel)
        #expect(isClose(try await area(try onlySolid(report, node, "surface")), 60 * 5))
    }

    @Test func symmetricExtrudeCurveDoublesTheArea() async throws {
        var h = Harness()
        let rect = rectangle(&h, 10, 20)
        let node = h.add(ExtrudeCurveNode.self, ["distance": .number(5), "symmetric": .bool(true)])
        h.wire(rect, "profile", to: node, "curve")
        let report = try await h.run([node], kernel: kernel)
        #expect(isClose(try await area(try onlySolid(report, node, "surface")), 60 * 5 * 2))
    }

    @Test func revolveCurveTurnsARectangleAboutTheYAxis() async throws {
        var h = Harness()
        // x 8...12, y -3...3 about Y: two walls and two annuli.
        let rect = rectangle(&h, 4, 6, at: Vector3(10, 0, 0))
        let node = h.add(RevolveCurveNode.self)
        h.wire(rect, "profile", to: node, "curve")
        let report = try await h.run([node], kernel: kernel)
        #expect(isClose(try await area(try onlySolid(report, node, "surface")), 400 * .pi, relative: 1e-5))
    }

    @Test func loftSurfaceJoinsTwoRectangles() async throws {
        var h = Harness()
        let bottom = rectangle(&h, 10, 20), top = rectangle(&h, 10, 20, at: Vector3(0, 0, 10))
        let merge = h.add(MergeNode.self)
        h.wire(bottom, "profile", to: merge, "a")
        h.wire(top, "profile", to: merge, "b")
        let node = h.add(LoftSurfaceNode.self, ["ruled": .bool(true)])
        h.wire(merge, "list", to: node, "sections")
        let report = try await h.run([node], kernel: kernel)
        #expect(isClose(try await area(try onlySolid(report, node, "surface")), 60 * 10, relative: 1e-5))
    }

    @Test func sweepMakesASolidTube() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let path = h.add(CurveThroughPointsNode.self)
        let source = points(&h, count: 3, step: 10, along: true)
        h.wire(source, "vector", to: path, "points")
        let node = h.add(SweepNode.self)
        h.wire(circle, "profile", to: node, "profiles")
        h.wire(path, "curve", to: node, "path")
        let report = try await h.run([node], kernel: kernel)
        let solid = try onlySolid(report, node, "surface")
        let measured = try await volume(solid, kernel)
        #expect(isClose(measured, .pi * 4 * 20, relative: 1e-4), "volume \(measured)")
    }

    /// Ruling R-A: a boundary edge of a Planar Surface picked with Edges by Tag is found again when the rectangle changes.
    @Test func aPickedBoundaryEdgeSurvivesAChangeOfWidth() async throws {
        var h = Harness()
        let rect = rectangle(&h, 10, 20)
        let surface = h.add(PlanarSurfaceNode.self)
        h.wire(rect, "profile", to: surface, "curves")
        let byTag = h.add(EdgesByTagNode.self)
        h.wire(surface, "surface", to: byTag, "solid")
        let first = try await h.run([surface], kernel: kernel)
        let sheet = try onlySolid(first, surface, "surface")
        let right = try #require(sheet.topology.edges.first { $0.midpoint.x > 4.9 && abs($0.midpoint.y) < 1e-6 })
        h.set(byTag, NodeSetting.picks, .edgePicks(sheet.topology.picks(for: [right.id])))
        h.set(rect, "width", .number(14))
        let report = try await h.run([byTag], kernel: kernel)
        let set = try #require(report.value(byTag, "edges")?.edgeSets?.first)
        #expect(report.isOK(byTag))
        let edge = try #require(set.solid.topology.edges.first { $0.id == set.edges.first })
        #expect(set.edges.count == 1 && abs(edge.midpoint.x - 7) < 1e-6)
    }
}
#endif
