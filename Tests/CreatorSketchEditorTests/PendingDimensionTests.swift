import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The D tool's pending dimension (spec §4.2, §4.4): the second pick opens the value box and commits nothing; the click that
/// places the dimension is the one "Add Dimension" step, and where it is placed chooses the orientation.
@MainActor
struct PendingDimensionTests {
    let pendingID = SketchDimensionDrawing.pendingID

    @Test func twoPicksOpenTheBoxAndCommitNothing() {
        let (model, _, host) = pickedDiagonal()
        #expect(host.openedBoxes == ["sketch/new"])
        #expect(host.commits.isEmpty)
        #expect(model.valueBoxContent(for: pendingID)?.text == "72.111")
        #expect(model.dimensions.first { $0.id == pendingID }?.tint == .selected)
    }

    @Test func escapeInTheBoxAddsNothing() {
        let (model, _, host) = pickedDiagonal()
        let before = model.sketch
        model.valueBoxClosed(pendingID, by: .cancelled)
        #expect(model.pending == nil)
        #expect(host.commits.isEmpty && model.sketch == before)
        #expect(!model.dimensions.contains { $0.id == pendingID })
    }

    @Test func anUntouchedReturnThenAClickAddsOneStep() throws {
        let (model, rectangle, host) = pickedDiagonal()
        let before = model.solution
        acceptAndPlace(model, at: Vector2(30, 60))
        #expect(host.commits.map(\.name) == ["Add Dimension"])
        let dimension = try #require(model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] })
        #expect(dimension.kind == .horizontalDistance(rectangle.corners[0], rectangle.corners[2]))
        #expect(abs(dimension.value - 60) < 1e-9 && dimension.labelPoint == Vector2(30, 60))
        #expect(model.solution.points == before.points, "nothing moved")
        #expect(model.pending == nil)
    }

    @Test(arguments: [
        (Vector2(30, 60), 60.0, "horizontal"), (Vector2(80, 20), 40.0, "vertical"), (Vector2(30, 20), 72.1110255, "distance"),
    ])
    func placementChoosesTheOrientation(label: Vector2, value: Double, name: String) throws {
        let (model, rectangle, host) = pickedDiagonal()
        model.valueBoxClosed(pendingID, by: .unchanged)
        hover(model, label.x, label.y)
        click(model, label.x, label.y)
        let dimension = try #require(model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] })
        let (a, b) = (rectangle.corners[0], rectangle.corners[2])
        let expected: DimensionKind = switch name {
        case "horizontal": .horizontalDistance(a, b)
        case "vertical": .verticalDistance(a, b)
        default: .distance(a, b)
        }
        #expect(dimension.kind == expected)
        #expect(abs(dimension.value - value) < 1e-6)
        #expect(host.commits.count == 1)
    }

    @Test func aTypedValueSolvesOnReturnButCommitsOnTheClick() async throws {
        let (model, rectangle, host) = pickedDiagonal()
        let outcome = await model.commitValue("80", to: pendingID)
        #expect(outcome == .accepted)
        #expect(host.commits.isEmpty)
        let c0 = try #require(model.solution.points[rectangle.corners[0]])
        let c2 = try #require(model.solution.points[rectangle.corners[2]])
        #expect(abs((c2 - c0).length - 80) < 1e-6)
        click(model, 30, 20)
        #expect(host.commits.map(\.name) == ["Add Dimension"])
        let dimension = try #require(model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] })
        #expect(dimension.value == 80 && dimension.isDriving)
        let end = try #require(model.sketch.position(of: rectangle.corners[2]))
        #expect(abs(end.length - 80) < 1e-6, "the committed sketch holds the typed distance")
    }

    @Test func aTypedValueLocksTheOrientation() async throws {
        let (model, rectangle, _) = pickedDiagonal()
        _ = await model.commitValue("80", to: pendingID)
        let solved = model.solution.points
        let kind = DimensionKind.distance(rectangle.corners[0], rectangle.corners[2])
        for label in [Vector2(30, 60), Vector2(80, 20), Vector2(30, 20)] {
            hover(model, label.x, label.y)
            #expect(model.pending?.kind == kind)
            #expect(model.pending?.labelPoint == label)
            #expect(model.solution.points == solved)
        }
        click(model, 80, 20)
        let dimension = try #require(model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] })
        #expect(dimension.kind == kind && dimension.value == 80)
    }

    @Test func aFlippingValueIsRefusedInTheBox() async {
        let (model, _, host) = pickedDiagonal()
        model.flipCheck = { _, _, _ in true }
        let before = model.sketch
        let outcome = await model.commitValue("80", to: pendingID)
        #expect(outcome == .refused("This value would flip the sketch."))
        #expect(model.sketch == before && host.commits.isEmpty)
        #expect(model.pending?.phase == .entering)
    }

    @Test func nonsenseAndZeroAreRefusedInTheBoxWithTheInspectorsWords() async {
        let (model, _, _) = pickedDiagonal()
        #expect(await model.commitValue("wide", to: pendingID) == .refused("“wide” isn't a number."))
        #expect(await model.commitValue("0", to: pendingID) == .refused("A distance must be more than 0 mm."))
        #expect(model.pending?.phase == .entering)
    }

    @Test func anOverDefiningDimensionIsAReference() throws {
        let (model, _, host) = pickedDiagonal(dimensioned: true)
        #expect(host.openedBoxes.isEmpty)
        #expect(model.pending?.phase == .placing && model.pending?.isDriving == false)
        click(model, 30, 20)
        let dimension = try #require(model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] })
        #expect(!dimension.isDriving && abs(dimension.value - 72.1110255) < 1e-6)
        #expect(host.commits.count == 1)
    }

    @Test func parallelLinesAreALineDistance() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, _) = makeModel(rectangle.sketch)
        click(model, 30, 0.3)
        click(model, 30, 40.2)
        #expect(model.pending?.aligned == .lineDistance(rectangle.lines[0], rectangle.lines[2]))
        #expect(abs((model.pending?.value ?? 0) - 40) < 1e-9)
        let (other, _) = makeModel(rectangle.sketch)
        click(other, 30, 0.3)
        click(other, 60.2, 20)
        #expect(other.pending?.aligned == .angle(rectangle.lines[0], rectangle.lines[1]))
        #expect(abs((other.pending?.value ?? 0) - 90) < 1e-6)
    }

    @Test func aCirclePickShowsItsDiameterAtOnce() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(0, 0), radius: 5)
        let (model, host) = makeModel(sketch)
        click(model, 5.2, 0)
        #expect(model.pending?.kind == .diameter(circle) && model.pending?.value == 10 && model.pending?.phase == .picked)
        #expect(model.dimensions.contains { $0.id == pendingID })
        #expect(host.openedBoxes.isEmpty && host.commits.isEmpty)
        hover(model, 12, 3)
        #expect(model.pending?.labelPoint == Vector2(12, 3))
        click(model, 20, 20)
        #expect(model.pending?.phase == .entering && model.pending?.kind == .diameter(circle) && model.pending?.value == 10)
        #expect(host.openedBoxes == ["sketch/new"])

        var arcSketch = Sketch()
        let center = arcSketch.addPoint(Vector2(0, 0))
        let arc = arcSketch.addArc(center: center, start: arcSketch.addPoint(Vector2(5, 0)), end: arcSketch.addPoint(Vector2(0, 5)))
        let (other, otherHost) = makeModel(arcSketch)
        click(other, 3.6, 3.6)
        #expect(other.pending?.kind == .radius(arc) && other.pending?.phase == .picked)
        click(other, 20, 20)
        #expect(other.pending?.kind == .radius(arc) && otherHost.openedBoxes == ["sketch/new"])
    }

    @Test func aSecondCircleOrPointMakesACentreDistance() throws {
        var sketch = Sketch()
        let first = sketch.addCircle(center: Vector2(0, 0), radius: 2)
        let second = sketch.addCircle(center: Vector2(30, 40), radius: 3)
        let point = sketch.addPoint(Vector2(6, 8))
        let line = sketch.addLine(Vector2(8, -20), Vector2(8, -10))
        let (circles, circlesHost) = makeModel(sketch)
        click(circles, 2.1, 0)
        click(circles, 32.1213, 42.1213)
        #expect(circles.pending?.aligned == .centreDistance(first, second))
        #expect(abs((circles.pending?.value ?? 0) - 50) < 1e-6 && circlesHost.openedBoxes == ["sketch/new"])

        let (withPoint, _) = makeModel(sketch)
        click(withPoint, 2.1, 0)
        click(withPoint, 6, 8)
        #expect(withPoint.pending?.aligned == .centreDistance(first, point))
        #expect(abs((withPoint.pending?.value ?? 0) - 10) < 1e-6)

        let (withLine, lineHost) = makeModel(sketch)
        click(withLine, 2.1, 0)
        click(withLine, 8, -15)
        let centre = try #require(withLine.sketch.entities[first]).kind
        guard case .circle(let centrePoint, _) = centre else {
            Issue.record("not a circle")
            return
        }
        #expect(withLine.pending?.aligned == .distance(centrePoint, line))
        #expect(abs((withLine.pending?.value ?? 0) - 8) < 1e-6 && lineHost.openedBoxes == ["sketch/new"])
    }

    @Test func aProjectedCircleHasNoCentreToMeasureFrom() {
        var sketch = Sketch()
        let projected = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .circle(center: .zero, radius: 5)))))
        sketch.addLine(Vector2(8, 0), Vector2(8, 10))
        let (model, host) = makeModel(sketch)
        click(model, 5.2, 0)
        #expect(model.pending?.kind == .diameter(projected))
        click(model, 8, 5)
        #expect(model.refusal == "That can't be measured.")
        #expect(model.pending == nil && host.openedBoxes.isEmpty && host.commits.isEmpty)
    }

    @Test func axisAlignedPointsStayAligned() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, _) = makeModel(rectangle.sketch)
        click(model, 0.2, 0.2)
        click(model, 60.2, 0.2)
        acceptAndPlace(model, at: Vector2(30, 30))
        let dimension = try #require(model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] })
        #expect(dimension.kind == .distance(rectangle.corners[0], rectangle.corners[1]) && abs(dimension.value - 60) < 1e-9)
    }

    @Test func concentricCirclesHaveNoCentreDistance() {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(0, 0), radius: 5)
        sketch.addCircle(center: Vector2(0, 0), radius: 8)
        let (model, host) = makeModel(sketch)
        click(model, 5.2, 0)
        click(model, 8.1, 0)
        #expect(model.refusal == "Those are in the same place: there is nothing to dimension.")
        #expect(model.pending == nil && host.openedBoxes.isEmpty)
    }

    @Test func abandoningAPendingDimensionAddsNothing() async throws {
        var other = RectangleSketch(dimensioned: false).sketch
        other.addPoint(Vector2(5, 5))
        let abandons: [(String, @MainActor (SketchEditorModel) -> Void)] = [
            ("escape", { $0.escape() }),
            ("choose", { $0.choose(.line) }),
            ("finish", { $0.finish() }),
            ("reload", { $0.reload(other, plane: .xy) }),
        ]
        for (name, abandon) in abandons {
            let (model, rectangle, host) = pickedDiagonal()
            _ = await model.commitValue("80", to: pendingID)
            #expect(model.pending?.phase == .placing, "\(name)")
            abandon(model)
            #expect(model.pending == nil, "\(name)")
            #expect(host.commits.isEmpty, "\(name)")
            let c2 = try #require(model.solution.points[rectangle.corners[2]])
            #expect(abs(c2.x - 60) < 1e-9 && abs(c2.y - 40) < 1e-9, "\(name): the geometry is back")
            #expect(!model.dimensions.contains { $0.id == pendingID }, "\(name)")
        }
    }

    @Test func theCommitAsksTheHostOnlyAfterATypedValue() async {
        let (typed, _, _) = pickedDiagonal()
        var asked = 0
        typed.events.checkValueCommit = {
            asked += 1
            return "Extrude: the profile is open."
        }
        _ = await typed.commitValue("80", to: pendingID)
        click(typed, 30, 20)
        await typed.commitCheck?.value
        #expect(asked == 1)
        #expect(typed.refusal == "Extrude: the profile is open.")

        let (untouched, _, _) = pickedDiagonal()
        untouched.events.checkValueCommit = {
            asked += 1
            return "never"
        }
        acceptAndPlace(untouched, at: Vector2(30, 20))
        await untouched.commitCheck?.value
        #expect(asked == 1 && untouched.refusal == nil)
    }
}

extension PendingDimensionTests {
    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.dimension)
        return (model, RecordingHost(model))
    }

    func click(_ model: SketchEditorModel, _ x: Double, _ y: Double) {
        model.click(at: Vector2(x, y), tolerance: 1, modifiers: [])
    }

    func hover(_ model: SketchEditorModel, _ x: Double, _ y: Double) {
        model.hover(at: Vector2(x, y), tolerance: 1, modifiers: [])
    }

    /// The rectangle's corners 0 and 2 picked (60, 40 apart), the box open on the aligned distance.
    func pickedDiagonal(dimensioned: Bool = false) -> (SketchEditorModel, RectangleSketch, RecordingHost) {
        let rectangle = RectangleSketch(dimensioned: dimensioned)
        let (model, host) = makeModel(rectangle.sketch)
        click(model, 0.2, 0.2)
        click(model, 60.2, 40.2)
        return (model, rectangle, host)
    }
}
