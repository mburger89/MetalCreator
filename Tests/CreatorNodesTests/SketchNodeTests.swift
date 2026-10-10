import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorSketch
import Testing

/// Sketcher spec §7, the Sketch node: solve, regions, exposed dimensions, measurements and states.
struct SketchNodeTests {
    func near(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length <= 1e-6 }

    func sketchNode(_ h: inout Harness, _ sketch: Sketch) -> Node {
        h.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
    }

    @Test func aNewSketchHoldsAnEmptySketchOnXYAndAsksForAShape() async throws {
        #expect(BuiltInNodes.registry.makeNode(SketchNode.typeID).inputValues[NodeSetting.sketch] == .sketch(Sketch()))
        var h = Harness()
        let node = h.add(SketchNode.self)
        let report = try await h.run([node])
        #expect(report.warning(node) == SketchSolve.nothingDrawn)
        #expect(report.value(node, "profiles")?.profiles?.isEmpty == true)
        #expect(report.value(node, "profiles")?.isList == true)
    }

    @Test func aFullyConstrainedRectangleIsOneProfileOnTheSketchPlane() async throws {
        var h = Harness()
        let node = sketchNode(&h, RectangleSketch(width: 60, height: 40, plane: .fixed(.xz)).sketch)
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let profiles = try #require(report.value(node, "profiles")?.profiles)
        try #require(profiles.count == 1)
        #expect(profiles[0].plane == .xz)
        #expect(profiles[0].isClosed)
        let expected = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)]
        #expect(zip(profiles[0].corners, expected).allSatisfy(near) && profiles[0].corners.count == 4)
    }

    @Test func regionsComeOutLargestFirstWithTheirHoles() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.addHole(center: Vector2(15, 20), radius: 5)
        rectangle.addHole(center: Vector2(100, 0), radius: 3)
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let profiles = try #require(report.value(node, "profiles")?.profiles)
        #expect(profiles.map(\.holes.count) == [1, 0])
        #expect(profiles.map(\.outer.count) == [4, 1])
    }

    /// A projected edge is refreshed from the model on every evaluation, so a line a fillet turned into an arc arrives as an
    /// arc: what was said about it as a line can't hold, and the person is told which constraint is left out.
    @Test func aConstraintOnAProjectedEdgeThatChangedKindIsIgnoredAndSaid() throws {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "e", curve: .arc(center: .zero, radius: 5, start: .degrees(0), end: .degrees(90)))
        let arc = sketch.add(SketchEntity(.projected(source)))
        sketch.add(.horizontal(arc))
        let output = try SketchSolve.run(sketch, on: .xy)
        #expect(output.warnings.contains("Horizontal on Projected edge 1 is ignored: its projected edge is a different kind of curve now."))
    }

    @Test func aSuspendedProjectionIsNotSaidTwice() throws {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "e", curve: .arc(center: .zero, radius: 5, start: .degrees(0), end: .degrees(90)),
                                      isSuspended: true)
        sketch.add(.horizontal(sketch.add(SketchEntity(.projected(source)))))
        let output = try SketchSolve.run(sketch, on: .xy)
        #expect(!output.warnings.contains { $0.contains("different kind of curve") }, "SketchProjections already names it")
    }

    @Test func anUnderConstrainedSketchWarnsAndStillOutputs() async throws {
        var sketch = Sketch()
        let corners = [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)].map { sketch.addPoint($0) }
        for k in 0..<4 { sketch.addLine(from: corners[k], to: corners[(k + 1) % 4]) }
        var h = Harness()
        let node = sketchNode(&h, sketch)
        let report = try await h.run([node])
        #expect(report.warning(node) == "The sketch has 8 degrees of freedom left, so it isn't fully constrained.")
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
    }

    @Test func anOverConstrainedSketchIsAnErrorNamingTheConflict() async throws {
        var rectangle = RectangleSketch()
        rectangle.sketch.add(.horizontal(rectangle.lines[1]))
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let error = try #require(try await h.run([node]).error(node))
        #expect(error == SketchSolver.solve(rectangle.sketch).conflictMessages.joined(separator: "\n"))
        #expect(error.contains("Horizontal on Line 2"))
    }

    @Test func anImpossibleValueIsAPlainError() async throws {
        var rectangle = RectangleSketch()
        rectangle.sketch.dimensions[rectangle.width]?.value = -5
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let error = try #require(try await h.run([node]).error(node))
        guard case .failed(let reason) = SketchSolver.solve(rectangle.sketch).status else {
            Issue.record("expected the solver to refuse a negative length")
            return
        }
        #expect(error == reason)
    }

    @Test func openCurvesWarn() async throws {
        var rectangle = RectangleSketch()
        let a = rectangle.sketch.addPoint(Vector2(80, 0)), b = rectangle.sketch.addPoint(Vector2(90, 0))
        rectangle.sketch.addLine(from: a, to: b)
        rectangle.sketch.add(.fix(a, at: Vector2(80, 0)))
        rectangle.sketch.add(.fix(b, at: Vector2(90, 0)))
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.warning(node) == "1 curve doesn't form a closed region.")
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
    }

    @Test func anExposedDimensionIsANumberInputNamedAfterIt() {
        var rectangle = RectangleSketch(width: 60)
        rectangle.expose(rectangle.width)
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID)
        node.inputValues[NodeSetting.sketch] = .sketch(rectangle.sketch)
        let exposed = SketchNode.inputs(for: node).dropFirst(SketchNode.inputs.count)
        #expect(exposed.map(\.name) == ["d1"])
        #expect(exposed.first?.type == .number && exposed.first?.unit == .millimetres)
        #expect(exposed.first?.defaultValue == .number(60))
    }

    @Test func aWiredValueDrivesItsExposedDimension() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(80)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(width, "value", to: node, "d1")
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let profile = try #require(report.value(node, "profiles")?.profiles?.first)
        #expect(near(profile.corners[1], Vector2(80, 0)))
    }

    @Test func aListIntoAnExposedDimensionBroadcastsOneProfilePerValue() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let widths = h.add(SeriesNode.self, ["start": .number(20), "step": .number(10), "count": .integer(3)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(widths, "values", to: node, "d1")
        let profiles = try #require(try await h.run([node]).value(node, "profiles")?.profiles)
        #expect(profiles.map { $0.corners[1].x.rounded() } == [20, 30, 40])
    }

    @Test func aDimensionNamedLikeAnInputOrSettingIsNotExposedAndWarns() async throws {
        var rectangle = RectangleSketch()
        rectangle.expose(rectangle.width)
        rectangle.sketch.renameDimension(rectangle.width, to: "plane")
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        #expect(SketchNode.inputs(for: h.graph.nodes[node.id] ?? node).map(\.name) == ["plane", "references"])
        let report = try await h.run([node])
        #expect(report.warning(node) == "Dimension “plane” can't be an input: the node already has an input or setting "
            + "with that name. Rename it.")
        #expect(SketchSockets.isReserved("sketch") && SketchSockets.isReserved("projection.p1") && !SketchSockets.isReserved("d1"))
    }

    @Test func referenceDimensionsComeOutAsMeasurementsInNameOrder() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        let diagonal = rectangle.sketch.addDimension(.distance(rectangle.corners[0], rectangle.corners[2]), value: 1,
                                                     isDriving: false)
        let top = rectangle.sketch.addDimension(.length(rectangle.lines[2]), value: 1, isDriving: false)
        rectangle.sketch.renameDimension(diagonal, to: "b")
        rectangle.sketch.renameDimension(top, to: "a")
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.isOK(node))
        let measured = try #require(report.value(node, "measurements")?.numbers)
        #expect(measured.count == 2)
        #expect(isClose(measured[0], 60) && isClose(measured[1], 5200.squareRoot()))
    }

    @Test func aReferenceDimensionThatCantBeMeasuredEmptiesMeasurementsAndSaysWhich() async throws {
        // Dropping "a" would move "b" up to position 0, so a wired consumer of position 0 would read b.
        var rectangle = RectangleSketch(width: 60, height: 40)
        let hole = rectangle.addHole(center: Vector2(15, 20), radius: 5)
        guard case .radius(let circle)? = rectangle.sketch.dimensions[hole]?.kind else {
            Issue.record("expected a radius dimension")
            return
        }
        let wrong = rectangle.sketch.addDimension(.length(circle), value: 1, isDriving: false)
        let top = rectangle.sketch.addDimension(.length(rectangle.lines[2]), value: 1, isDriving: false)
        rectangle.sketch.renameDimension(wrong, to: "a")
        rectangle.sketch.renameDimension(top, to: "b")
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(report.warning(node) == SketchSolve.unmeasured("a", because: SketchSolve.wrongGeometry))
        #expect(report.value(node, "measurements")?.numbers == [])
        #expect(report.value(node, "profiles")?.profiles?.count == 1)
    }

    @Test func aWiredPlaneSketchIsDrawnOnTheWiredPlane() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["orientation": .integer(1), "offset": .number(5)])
        let node = sketchNode(&h, RectangleSketch(plane: .wired).sketch)
        #expect(try await h.run([node]).error(node) == SketchNode.wiredPlaneMissing)
        h.wire(plane, "plane", to: node, "plane")
        let report = try await h.run([node])
        #expect(report.isOK(node))
        #expect(report.value(node, "profiles")?.profiles?.first?.plane == Plane.xz.offset(by: 5))
    }

    @Test func aWireIntoTheOwnPlaneOfASketchWarns() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["orientation": .integer(1)])
        let node = sketchNode(&h, RectangleSketch(plane: .fixed(.xy)).sketch)
        h.wire(plane, "plane", to: node, "plane")
        let report = try await h.run([node])
        #expect(report.warning(node) == SketchNode.ignoredPlane)
        #expect(report.value(node, "profiles")?.profiles?.first?.plane == .xy)
    }

    @Test func aMissingOrUnreadableSketchIsAPlainError() async throws {
        var h = Harness()
        let node = h.add(SketchNode.self)
        h.set(node, NodeSetting.sketch, nil)
        #expect(try await h.run([node]).error(node) == SketchNode.missingSketch)
        h.set(node, NodeSetting.sketch, .text("square"))
        #expect(try await h.run([node]).error(node) == SketchNode.unreadableSketch)
    }

    @Test func sketchProfilesExtrudeWithTheirHoleWallsNamed() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.addHole(center: Vector2(15, 20), radius: 5)
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(node, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude])
        let solid = try onlySolid(report, extrude)
        #expect(solid.topology.faces.contains { $0.tags.contains(TopoTag(node: extrude.id, item: 0, role: .side(loop: 1, segment: 0))) })
    }

    @Test func aWireLeftOnAnUnexposedDimensionIsIgnored() async throws {
        var rectangle = RectangleSketch(width: 60, height: 40)
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(80)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(width, "value", to: node, "d1")
        rectangle.sketch.dimensions[rectangle.width]?.isExposed = false
        h.set(node, NodeSetting.sketch, .sketch(rectangle.sketch))
        let report = try await h.run([node])
        #expect(report.isOK(node))
        #expect(near(try #require(report.value(node, "profiles")?.profiles?.first).corners[1], Vector2(60, 0)))
    }

    @Test func anEmptySketchIntoAnExtrudeMakesNoSolidAndNoError() async throws {
        var h = Harness()
        let node = h.add(SketchNode.self)
        let extrude = h.add(ExtrudeNode.self)
        h.wire(node, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude])
        #expect(report.isOK(extrude))
        #expect(report.value(extrude, "solid")?.solids?.isEmpty == true)
    }

    @Test func aNonFiniteWiredValueIsAPlainError() async throws {
        var rectangle = RectangleSketch()
        rectangle.expose(rectangle.width)
        var h = Harness()
        let width = h.add(NumberNode.self, ["value": .number(.nan)])
        let node = sketchNode(&h, rectangle.sketch)
        h.wire(width, "value", to: node, "d1")
        let report = try await h.run([node])
        #expect(report.error(node) == "Length d1 is not a number.")
    }
}
