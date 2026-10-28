import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorViewport
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// DIM-4's acceptance (spec §3.1, §3.3, §3.5, §7): on a sketched bracket, the Hole Pattern's spacing is edited on the part
/// (in mm and in inches) with one undo step, nothing else re-evaluated and the camera still; and the model tool adds the
/// plate's edge-to-edge distance as a reference.
@MainActor
struct DimensionAcceptanceTests {
    #if canImport(CreatorOCCT)
    /// What the bracket's dimensions read in a unit, and what the person types.
    struct Texts {
        var spacingBefore: String, spacingAfter: String, holes: String, plate: String
        var typed: String, typedSpacing: Double, editText: String
        var holeCentres: [Double]
        var units: DocumentUnits
    }

    static func texts(_ unit: LengthUnit) -> Texts {
        switch unit {
        case .millimetres:
            Texts(spacingBefore: "60", spacingAfter: "70", holes: "2X Ø8", plate: "100", typed: "70", typedSpacing: 70,
                  editText: "60", holeCentres: [20, 90], units: .millimetres)
        case .inches:
            Texts(spacingBefore: "2.36", spacingAfter: "2.75", holes: "2X Ø.31", plate: "3.94", typed: "2.75", typedSpacing: 69.85,
                  editText: "2.3622", holeCentres: [20, 89.85], units: DocumentUnits(length: .inches))
        }
    }

    @Test(arguments: [LengthUnit.millimetres, .inches])
    func theHolePatternsSpacingIsEditedOnThePart(_ unit: LengthUnit) async throws {
        let expected = Self.texts(unit)
        let app = AppModel(kernel: OCCTKernel())
        let part = try AppSketchBracket(in: app)
        await app.settle()
        expectAllOK(app, "the bracket")
        if unit == .inches {
            app.setUnits(.inches)
            await app.settle()
        }

        try await pinThePlatesLength(part, app, expected)

        // Click a hole wall: the Hole Pattern is selected, the layout's spacing and the holes' size show.
        let wall = try part.holeWall(app)
        app.viewportClicked(wall)
        await app.settle()
        #expect(app.editor.selection == [part.holes.id])
        let spacing = try #require(part.shown(app, expected.spacingBefore), "the layout's spacing")
        #expect(part.shown(app, expected.holes) != nil, "the holes' size")
        #expect(part.shown(app, expected.plate)?.isPinned == true, "the pin")

        // Opening the box and typing change nothing.
        let graph = app.document.graph
        let extrudeSolid = try #require(part.solid(app, of: part.extrude))
        let pose = app.viewport.pose
        #expect(app.viewport.openValueBox(for: spacing.id))
        #expect(app.viewport.valueBox?.draft == expected.editText)
        app.viewport.valueBoxDraftChanged(expected.typed)
        #expect(app.document.graph == graph)
        #expect(app.viewport.pose == pose)
        #expect(!app.document.isEvaluating, "typing starts no evaluation")

        // Return commits one step, and only the layout's spacing.
        await app.viewport.submitValueBox()
        await app.settle()
        let layout = try #require(app.document.graph.nodes[part.layout.id])
        guard case .number(let value)? = layout.inputValues["spacing"] else {
            Issue.record("spacing is not a number: \(String(describing: layout.inputValues["spacing"]))")
            return
        }
        #expect(abs(value - expected.typedSpacing) < 1e-9)
        for (id, node) in app.document.graph.nodes where id != part.layout.id {
            #expect(node.inputValues == graph.nodes[id]?.inputValues, "\(node.name) is unchanged")
        }
        #expect(part.solid(app, of: part.extrude) === extrudeSolid, "the plate was not evaluated again")
        #expect(app.viewport.pose == pose, "the camera did not move")
        let centres = try part.holeCentresX(app)
        #expect(centres.count == 2 && zip(centres, expected.holeCentres).allSatisfy { abs($0 - $1) < 1e-6 }, "\(centres)")
        #expect(app.undoTitle == "Undo Change Dimension")
        expectAllOK(app, "spacing edited")

        // The pin is still there and shows; the spacing reads its new value.
        #expect(part.shown(app, expected.plate)?.isPinned == true)
        #expect(part.shown(app, expected.spacingAfter) != nil)

        try await undoAndRedo(part, app, redone: layout.inputValues["spacing"])
        try await saveAndReopen(part, app, expected)
    }

    private func pinThePlatesLength(_ part: AppSketchBracket, _ app: AppModel, _ expected: Texts) async throws {
        // Pin the plate's length from the sketch's dimension.
        app.editor.selection = [part.sketch.id]
        app.refreshDimensions()
        let length = try #require(part.shown(app, expected.plate))
        let pinAction = try #require(app.dimensionRouter.menuActions(for: length.id).first { $0.title == "Pin Dimension" })
        app.dimensionRouter.performMenuAction(pinAction, for: length.id)
        await app.settle()
        let pin = DimensionPin(node: part.sketch.id, target: .sketchDimension(part.lengthID))
        #expect(app.document.graph.dimensionPins == [pin])
    }

    private func undoAndRedo(_ part: AppSketchBracket, _ app: AppModel, redone: ConstantValue?) async throws {
        // One undo restores the spacing, redo makes it again.
        app.undo()
        await app.settle()
        #expect(app.document.graph.nodes[part.layout.id]?.inputValues["spacing"] == .number(60))
        let undone = try part.holeCentresX(app)
        #expect(undone.count == 2 && abs(undone[0] - 20) < 1e-6 && abs(undone[1] - 80) < 1e-6, "\(undone)")
        app.redo()
        await app.settle()
        #expect(app.document.graph.nodes[part.layout.id]?.inputValues["spacing"] == redone)
    }

    private func saveAndReopen(_ part: AppSketchBracket, _ app: AppModel, _ expected: Texts) async throws {
        // Save, reopen: the units, the pin and the dimensions come back.
        let file = temporaryURL("dimension-bracket.mcgraph")
        defer { try? FileManager.default.removeItem(at: file) }
        try app.save(to: file)
        let pins = app.document.graph.dimensionPins
        try app.open(file)
        await app.settle()
        #expect(app.document.units == expected.units)
        #expect(app.document.graph.dimensionPins == pins)
        #expect(!app.isEdited)
        app.editor.selection = [part.holes.id]
        await app.settle()
        #expect(part.shown(app, expected.plate)?.isPinned == true)
        #expect(part.shown(app, expected.spacingAfter) != nil)
    }

    @Test func theToolAddsThePlatesEdgeToEdgeAsAReference() async throws {
        let app = AppModel(kernel: OCCTKernel())
        let part = try AppSketchBracket(in: app)
        await app.settle()
        let before = try #require(part.storedSketch(app))
        app.beginModelDimension()
        app.viewportClicked(try part.plateTopEdge(app, segment: 3))
        app.viewportClicked(try part.plateTopEdge(app, segment: 1))
        await app.settle()
        let stored = try #require(part.storedSketch(app))
        let added = Set(stored.dimensions.keys).subtracting(before.dimensions.keys)
        #expect(added.count == 1)
        let dimension = try #require(added.first.flatMap { stored.dimensions[$0] })
        let lines = part.lines
        #expect(dimension.kind == .lineDistance(lines[3], lines[1]))
        #expect(!dimension.isDriving, "the length dimension already defines it")
        #expect(abs(dimension.value - 100) < 1e-6)
        #expect(app.undoTitle == "Undo Add Dimension")
        #expect(app.viewport.valueBox == nil)

        // A hole's rim and the plate's wall are different features: the chip, nothing added.
        let graph = app.document.graph
        app.beginModelDimension()
        app.viewportClicked(try part.holeRim(app))
        app.viewportClicked(try part.plateTopEdge(app, segment: 0))
        #expect(app.modelDimension?.message == "These come from different features: a measurement tool is planned")
        #expect(app.document.graph == graph)
    }

    @Test func aSharedLayoutBelongsToNeitherFeature() async throws {
        let app = AppModel(kernel: OCCTKernel())
        let part = try AppSketchBracket(in: app)
        // A second Hole Pattern (Ø4) on the first's solid, placed by the same layout.
        var second = app.registry.makeNode(HolePatternNode.typeID, at: Vector2(900, 0))
        second.inputValues["diameter"] = .number(4)
        second.inputValues["throughAll"] = .bool(true)
        try app.document.perform(.addNode(second))
        try app.document.perform(.connect(Link(from: Endpoint(node: part.holes.id, socket: "solid"),
                                               to: Endpoint(node: second.id, socket: "part"))))
        try app.document.perform(.connect(Link(from: Endpoint(node: part.layout.id, socket: "placements"),
                                               to: Endpoint(node: second.id, socket: "placements"))))
        await app.settle()
        app.editor.selection = [part.holes.id]
        await app.settle()
        #expect(part.shown(app, "2X Ø8") != nil, "\(app.viewport.dimensions.map(\.text))")
        #expect(part.shown(app, "60") == nil, "the shared layout's spacing belongs to neither pattern")
    }
    #endif
}
