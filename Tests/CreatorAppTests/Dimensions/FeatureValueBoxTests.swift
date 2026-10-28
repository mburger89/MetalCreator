import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
@testable import CreatorViewport
import Testing
@testable import CreatorApp

/// Editing a feature dimension through the viewport's value box (DIM-3 Task 13, spec §3.1, §7).
@MainActor
struct FeatureValueBoxTests {
    func id(_ node: Node, _ key: String) -> OverlayDimensionID {
        OverlayDimensionID("feature/\(node.id.rawValue.uuidString)/input/\(key)/0")
    }

    func select(_ app: AppModel, _ node: Node) async {
        app.editor.selection = [node.id]
        await app.settle()
    }

    /// Three rectangles whose `width` is wired from the parameter "Width" (20), the first selected.
    func parameterApp(uses: Int = 3, min: Double? = nil,
                      max: Double? = nil) async -> (app: AppModel, rectangles: [Node], parameter: GraphParameter) {
        var builder = GraphBuilder()
        let width = GraphParameter(name: "Width", type: .number, value: .number(20), min: min, max: max)
        builder.graph.parameters = [width]
        let reader = builder.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(width.id)])
        var rectangles: [Node] = []
        for index in 0..<uses {
            let rectangle = builder.add(RectangleNode.self, at: Vector2(0, Double(index) * 100))
            builder.graph.nodes[rectangle.id]?.isOutput = true
            builder.wire(reader, "number", to: rectangle, "width")
            rectangles.append(rectangle)
        }
        let app = await makeApp(builder.graph)
        await select(app, rectangles[0])
        return (app, rectangles, width)
    }

    @Test func aDrivingDimensionOpensWithItsExactValue() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        let distance = id(box.extrude, "distance")
        #expect(app.dimensionRouter.valueBoxContent(for: distance) == DimensionValueBoxContent(text: "10", note: nil))
        app.setUnits(.inches)
        await app.settle()
        #expect(app.dimensionRouter.valueBoxContent(for: distance)?.text == "0.3937")
    }

    @Test func aParameterDimensionSaysSoInItsNote() async throws {
        let (app, rectangles, _) = await parameterApp()
        #expect(app.dimensionRouter.valueBoxContent(for: id(rectangles[0], "width"))
            == DimensionValueBoxContent(text: "20", note: "Width (parameter, used by 3 features)"))
        let (single, ones, _) = await parameterApp(uses: 1)
        #expect(single.dimensionRouter.valueBoxContent(for: id(ones[0], "width"))?.note == "Width (parameter, used by 1 feature)")
    }

    @Test func aReferenceOpensNoBox() async throws {
        var builder = GraphBuilder()
        let number = builder.add(NumberNode.self, ["value": .number(10)])
        let rectangle = builder.add(RectangleNode.self)
        builder.graph.nodes[rectangle.id]?.isOutput = true
        builder.wire(number, "value", to: rectangle, "width")
        let app = await makeApp(builder.graph)
        await select(app, rectangle)
        #expect(app.featureDimensions[id(rectangle, "width")] != nil)
        #expect(app.dimensionRouter.valueBoxContent(for: id(rectangle, "width")) == nil)
        #expect(!app.viewport.openValueBox(for: id(rectangle, "width")))
    }

    @Test func aParameterEditChangesEveryFeatureUsingIt() async throws {
        let (app, rectangles, parameter) = await parameterApp()
        let outcome = await app.dimensionRouter.commitValue("30", to: id(rectangles[0], "width"))
        #expect(outcome == .accepted)
        await app.settle()
        #expect(app.document.undoName == UndoName.changeParameter)
        #expect(app.document.graph.parameters.first { $0.id == parameter.id }?.value == .number(30))
        for rectangle in rectangles {
            #expect(app.document.results[rectangle.id]?.dimensions.first { $0.target == .input("width") }?.value == 30)
        }
    }

    @Test func aParameterOutsideItsRangeIsRefused() async throws {
        let (app, rectangles, parameter) = await parameterApp(min: 10, max: 100)
        let outcome = await app.dimensionRouter.commitValue("200", to: id(rectangles[0], "width"))
        #expect(outcome == .refused("Width must be between 10 mm and 100 mm."))
        #expect(app.document.graph.parameters.first { $0.id == parameter.id }?.value == .number(20))
        #expect(!app.document.canUndo)
    }

    @Test func aRefusedParseLeavesNoHold() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        let outcome = await app.dimensionRouter.commitValue("abc", to: id(box.extrude, "distance"))
        #expect(outcome == .refused("“abc” isn't a number."))
        #expect(!app.document.isHoldingResults)
        let zero = await app.dimensionRouter.commitValue("0", to: id(box.extrude, "distance"))
        #expect(zero == .refused("A length must be more than 0 mm."))
        #expect(!app.document.isHoldingResults && !app.document.canUndo)
        let next = await app.dimensionRouter.commitValue("12", to: id(box.extrude, "distance"))
        #expect(next == .accepted)
        await app.settle()
        #expect(app.document.results[box.extrude.id]?.dimensions.first?.value == 12)
    }

    @Test func theSameValueIsAcceptedWithNoStep() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        #expect(await app.dimensionRouter.commitValue("10", to: id(box.extrude, "distance")) == .accepted)
        #expect(!app.document.canUndo)
    }

    @Test func aCountEditsAnIntegerInput() async throws {
        var builder = GraphBuilder()
        let pattern = builder.add(LinearPatternNode.self)
        builder.graph.nodes[pattern.id]?.isOutput = true
        let app = await makeApp(builder.graph)
        await select(app, pattern)
        let count = id(pattern, "count")
        #expect(app.featureDimensions[count] != nil)
        #expect(await app.dimensionRouter.commitValue("6.5", to: count) == .refused("A count must be a whole number of 1 or more."))
        #expect(await app.dimensionRouter.commitValue("0", to: count) == .refused("A count must be a whole number of 1 or more."))
        #expect(await app.dimensionRouter.commitValue("99999999999999999999999", to: count) == .refused("That number is too big."))
        #expect(!app.document.canUndo)
        #expect(await app.dimensionRouter.commitValue("6", to: count) == .accepted)
        #expect(app.document.graph.nodes[pattern.id]?.inputValues["count"] == .integer(6))
    }

    @Test func anAngleOutsideItsRangeIsRefused() throws {
        let units = DocumentUnits.millimetres
        let spec = DimensionSpec(.input("angle"), .angular(vertex: .zero, first: .unitX, second: .unitY, normal: .unitZ,
                                                           placement: .standoff), .angle, value: 90)
        let dimension = FeatureDimension(id: OverlayDimensionID("x"), node: NodeID(), spec: spec, editing: .driving, isPinned: false,
                                         overlay: OverlayDimension(id: OverlayDimensionID("x"), geometry: spec.geometry, text: "90°",
                                                                   tint: .dimensionDriving, isPinned: false))
        #expect(FeatureDimensionEditing.value(from: "400", for: dimension, units: units)
            == .failure(FeatureEditRefusal(message: "An angle must be more than 0° and at most 360°.")))
        #expect(FeatureDimensionEditing.value(from: "360", for: dimension, units: units) == .success(360))
    }

    @Test func aBoxSideEditsOneComponent() async throws {
        var builder = GraphBuilder()
        let box = builder.add(ImplicitBoxNode.self, ["size": .vector(Vector3(20, 30, 40))])
        builder.graph.nodes[box.id]?.isOutput = true
        let app = await makeApp(builder.graph)
        await select(app, box)
        let side = OverlayDimensionID("feature/\(box.id.rawValue.uuidString)/input/size.1/0")
        #expect(app.featureDimensions[side] != nil)
        #expect(await app.dimensionRouter.commitValue("35", to: side) == .accepted)
        #expect(app.document.graph.nodes[box.id]?.inputValues["size"] == .vector(Vector3(20, 35, 40)))
    }

    @Test func aCylinderDiameterWritesItsRadius() async throws {
        var builder = GraphBuilder()
        let cylinder = builder.add(ImplicitCylinderNode.self)
        builder.graph.nodes[cylinder.id]?.isOutput = true
        let app = await makeApp(builder.graph)
        await select(app, cylinder)
        let diameter = id(cylinder, "radius")
        #expect(app.dimensionRouter.valueBoxContent(for: diameter)?.text == "10")
        #expect(await app.dimensionRouter.commitValue("12", to: diameter) == .accepted)
        #expect(app.document.graph.nodes[cylinder.id]?.inputValues["radius"] == .number(6))
    }

    func sketchID(_ sketch: Sketch, named name: String) throws -> DimensionID {
        try #require(sketch.dimensions.first { $0.value.name == name }?.key)
    }

    func storedSketch(_ app: AppModel, _ node: Node) throws -> Sketch {
        guard case .sketch(let sketch)? = app.document.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] else {
            throw FeatureEditRefusal(message: "no sketch stored")
        }
        return sketch
    }

    @Test func anUnexposedSketchDimensionIsStoredSolved() async throws {
        var builder = GraphBuilder()
        let sketch = rectangleSketch()
        let box = builder.sketchedBox(sketch)
        let width = try sketchID(sketch, named: "width")
        let app = await makeApp(builder.graph)
        await select(app, box.sketch)
        let dimension = FeatureDimension.overlayID(node: box.sketch.id, target: .sketchDimension(width))
        #expect(app.dimensionRouter.valueBoxContent(for: dimension)?.text == "60")
        #expect(await app.dimensionRouter.commitValue("70", to: dimension) == .accepted)
        await app.settle()
        let stored = try storedSketch(app, box.sketch)
        #expect(stored.dimensions[width]?.value == 70)
        #expect(app.document.undoName == UndoName.changeDimension)
        let points = stored.entityIDs.compactMap { id -> Double? in
            if case .point(let position)? = stored.solved[id] { position.x } else { nil }
        }
        #expect(points.max() == 70, "the stored warm start is the solved geometry")
        app.document.undo()
        #expect(!app.document.canUndo)
        #expect(try storedSketch(app, box.sketch).dimensions[width]?.value == 60)
    }

    @Test func anExposedUnwiredSketchDimensionEditsItsSocket() async throws {
        var builder = GraphBuilder()
        let sketch = rectangleSketch(exposed: true)
        let box = builder.sketchedBox(sketch)
        let width = try sketchID(sketch, named: "width")
        let app = await makeApp(builder.graph)
        await select(app, box.sketch)
        let dimension = FeatureDimension.overlayID(node: box.sketch.id, target: .sketchDimension(width))
        #expect(await app.dimensionRouter.commitValue("70", to: dimension) == .accepted)
        #expect(app.document.graph.nodes[box.sketch.id]?.inputValues["width"] == .number(70))
        #expect(app.document.undoName == UndoName.changeDimension)
    }

    @Test func anOverConstrainingSketchValueIsRefusedUnchanged() async throws {
        var builder = GraphBuilder()
        var sketch = Sketch(plane: .fixed(.xy))
        let corners = [Vector2(0, 0), Vector2(60, 0), Vector2(30, 40)].map { sketch.addPoint($0) }
        let lines = (0..<3).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 3]) }
        sketch.add(.horizontal(lines[0]))
        sketch.add(.fix(corners[0], at: .zero))
        let base = sketch.addDimension(.length(lines[0]), value: 60)
        sketch.renameDimension(base, to: "base")
        sketch.addDimension(.length(lines[1]), value: 50)
        sketch.addDimension(.length(lines[2]), value: 50)
        let box = builder.sketchedBox(sketch)
        let app = await makeApp(builder.graph)
        await select(app, box.sketch)
        let dimension = FeatureDimension.overlayID(node: box.sketch.id, target: .sketchDimension(base))
        let before = app.document.content
        // 50 + 50 < 200: no triangle has those sides.
        let outcome = await app.dimensionRouter.commitValue("200", to: dimension)
        guard case .refused(let message) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(app.document.content == before)
        #expect(!app.document.canUndo && !app.document.isHoldingResults)
    }

    @Test func typingChangesNoDocument() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        let before = app.document.content
        #expect(app.viewport.openValueBox(for: id(box.extrude, "distance")))
        app.viewport.valueBoxDraftChanged("7")
        #expect(app.viewport.valueBox?.draft == "7")
        #expect(app.document.content == before)
        #expect(!app.document.isEvaluating && !app.document.canUndo)
    }

    @Test func returnCommitsThroughTheBoxAndClosesIt() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        await select(app, box.extrude)
        #expect(app.viewport.openValueBox(for: id(box.extrude, "distance")))
        app.viewport.valueBoxDraftChanged("500000000000x")
        await app.viewport.submitValueBox()
        #expect(app.viewport.valueBox?.message == "“500000000000x” isn't a number.")
        app.viewport.valueBoxDraftChanged("15")
        await app.viewport.submitValueBox()
        #expect(app.viewport.valueBox == nil)
        #expect(app.document.graph.nodes[box.extrude.id]?.inputValues["distance"] == .number(15))
    }
}
