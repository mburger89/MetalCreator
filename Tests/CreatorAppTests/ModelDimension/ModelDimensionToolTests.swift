import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorApp
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// DIM-4 Task 5: the model dimension tool adds a sketch dimension from two picks (spec §3.5), on OCCT's holed plate.
@MainActor
struct ModelDimensionToolTests {
    #if canImport(CreatorOCCT)
    @Test func theToolWaitsForBothPicksBeforeTouchingTheDocument() async throws {
        let part = try await plate()
        let app = part.app
        let graph = app.document.graph
        #expect(app.beginModelDimension())
        app.viewportClicked(try part.rim(0))
        #expect(app.modelDimension?.pickedCount == 1)
        #expect(app.document.graph == graph)
        #expect(app.document.undoName == nil)
        #expect(ModelDimensionText.prompt(picked: 1) == "Click two edges or holes to dimension · 1 picked")
    }

    @Test func twoHoleRimsAddACentreToCentreDimensionAndOpenItsBox() async throws {
        let part = try await plate()
        let app = part.app
        let before = part.stored
        let centres = part.rimCentres()
        let pose = app.viewport.pose
        app.beginModelDimension()
        app.viewportClicked(try part.rim(0))
        app.viewportClicked(try part.rim(1))
        await app.settle()
        let added = try #require(part.newDimension(after: before))
        #expect(added.kind == .centreDistance(part.plate.circles[0], part.plate.circles[1]))
        #expect(abs(added.value - 30) < 1e-6)
        #expect(added.isDriving)
        #expect(app.undoTitle == "Undo Add Dimension")
        #expect(app.modelDimension == nil)
        #expect(app.editor.selection.isEmpty)
        #expect(app.viewport.valueBox?.draft == "30")
        let after = part.rimCentres()
        #expect(after.count == centres.count)
        for (a, b) in zip(after, centres) { #expect((a - b).length < 1e-6) }
        #expect(app.viewport.pose == pose)
    }

    @Test func oneUndoTakesItAway() async throws {
        let part = try await plate()
        let app = part.app
        let before = part.stored
        app.beginModelDimension()
        app.viewportClicked(try part.rim(0))
        app.viewportClicked(try part.rim(1))
        await app.settle()
        app.undo()
        await app.settle()
        #expect(part.stored == before)
        #expect(app.heldModelDimension == nil)
    }

    @Test func returnWithANewValueIsASecondStep() async throws {
        let part = try await plate()
        let app = part.app
        let before = part.stored
        app.beginModelDimension()
        app.viewportClicked(try part.rim(0))
        app.viewportClicked(try part.rim(1))
        await app.settle()
        app.viewport.valueBoxDraftChanged("35")
        await app.viewport.submitValueBox()
        await app.settle()
        #expect(abs(try #require(part.newDimension(after: before)).value - 35) < 1e-6)
        #expect(app.undoTitle == "Undo Change Dimension")
        app.undo()
        await app.settle()
        #expect(abs(try #require(part.newDimension(after: before)).value - 30) < 1e-6)
        app.undo()
        await app.settle()
        #expect(part.newDimension(after: before) == nil)
        #expect(part.stored == before)
    }

    @Test func escapeOnTheBoxKeepsTheMeasuredDimension() async throws {
        let part = try await plate()
        let app = part.app
        let before = part.stored
        app.beginModelDimension()
        app.viewportClicked(try part.rim(0))
        app.viewportClicked(try part.rim(1))
        await app.settle()
        try #require(app.viewport.valueBox != nil)
        app.viewport.cancelValueBox()
        await app.settle()
        #expect(abs(try #require(part.newDimension(after: before)).value - 30) < 1e-6)
        #expect(app.undoTitle == "Undo Add Dimension")
        #expect(app.heldModelDimension == nil)
    }

    @Test func theNewDimensionShowsWhileItsBoxIsOpenThenByTheChainRule() async throws {
        for selecting in [false, true] {
            let part = try await plate()
            let app = part.app
            let before = part.stored
            if selecting {
                app.editor.selection = [part.extrude.id]
                await app.settle()
            }
            app.beginModelDimension()
            app.viewportClicked(try part.rim(0))
            app.viewportClicked(try part.rim(1))
            await app.settle()
            let added = try #require(Set(part.stored.dimensions.keys).subtracting(before.dimensions.keys).first)
            let id = FeatureDimension.overlayID(node: part.sketch.id, target: .sketchDimension(added))
            #expect(app.viewport.dimensions.contains { $0.id == id }, "shown while its box is open")
            app.viewport.cancelValueBox()
            await app.settle()
            #expect(app.viewport.dimensions.contains { $0.id == id } == selecting)
            #expect(app.editor.selection == (selecting ? [part.extrude.id] : []))
        }
    }

    @Test func anOverDefiningPairIsAddedAsAReferenceWithNoBox() async throws {
        let part = try await plate()
        let app = part.app
        let before = part.stored
        app.beginModelDimension()
        app.viewportClicked(try part.topEdge(0))
        app.viewportClicked(try part.topEdge(2))
        await app.settle()
        let added = try #require(part.newDimension(after: before))
        #expect(added.kind == .lineDistance(part.plate.lines[0], part.plate.lines[2]))
        #expect(!added.isDriving)
        #expect(abs(added.value - 40) < 1e-6)
        #expect(app.viewport.valueBox == nil)
        #expect(app.heldModelDimension == nil)
    }

    @Test func aWallAndAHoleGiveTheDistanceFromItsCentre() async throws {
        let part = try await plate()
        let app = part.app
        let before = part.stored
        app.beginModelDimension()
        app.viewportClicked(try part.wall(3))
        app.viewportClicked(try part.rim(0))
        await app.settle()
        let added = try #require(part.newDimension(after: before))
        let centre = try part.centre(part.plate.circles[0])
        #expect(added.kind == .distance(centre, part.plate.lines[3]))
        #expect(abs(added.value - 15) < 1e-6)
    }

    @Test func differentFeaturesSayWhyAndAddNothing() async throws {
        let part = try await plate { builder in _ = builder.box(at: Vector2(0, 400)) }
        let app = part.app
        let other = try #require(app.viewport.items.indices.first { $0 != part.index && !app.viewport.items[$0].isGhost })
        let face = try #require(app.viewport.items[other].solid.topology.faces.first)
        let graph = app.document.graph
        app.beginModelDimension()
        app.viewportClicked(try part.wall(0))
        app.viewportClicked(.face(solid: other, face.id))
        #expect(app.modelDimension?.message == "These come from different features: a measurement tool is planned")
        #expect(app.modelDimension?.first == nil)
        #expect(app.document.graph == graph)
        app.viewportClicked(try part.wall(0))
        #expect(app.modelDimension?.message == nil)
        #expect(app.modelDimension?.pickedCount == 1)
    }

    @Test func theSameItemTwiceIsIgnored() async throws {
        let part = try await plate()
        let app = part.app
        let graph = app.document.graph
        app.beginModelDimension()
        app.viewportClicked(try part.rim(0, top: true))
        app.viewportClicked(try part.rim(0, top: false))
        #expect(app.modelDimension?.pickedCount == 1)
        #expect(app.modelDimension?.message == nil)
        #expect(app.document.graph == graph)
    }

    @Test func aPickThatWentStaleAddsNothing() async throws {
        // Before the part is evaluated again: the stored sketch no longer has the entity.
        let (before, unsettledGraph) = try await staleApp(settling: false)
        before.app.viewportClicked(try before.rim(1))
        #expect(before.app.modelDimension?.message == ModelDimensionText.differentFeatures)
        #expect(before.app.document.graph == unsettledGraph)
        // After it: the evaluated sketch no longer has it.
        let (after, settledGraph) = try await staleApp(settling: true)
        after.app.viewportClicked(try after.wall(0))
        #expect(after.app.modelDimension?.message == ModelDimensionText.differentFeatures)
        #expect(after.app.modelDimension?.first == nil)
        #expect(after.app.document.graph == settledGraph)
    }

    @Test func aWiredSketchIsMeasuredAsEvaluated() async throws {
        var builder = GraphBuilder()
        let holed = holedPlateSketch()
        var sketch = holed.sketch
        let width = try #require(sketch.dimensions.first { $0.value.name == "width" }?.key)
        sketch.dimensions[width]?.isExposed = true
        let (node, extrude) = builder.sketchedBox(sketch)
        let number = builder.add(NumberNode.self, ["value": .number(80)], at: Vector2(0, 300))
        builder.wire(number, "value", to: node, "width")
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        let part = ModelDimensionPlate(app: app, plate: holed, sketch: node, extrude: extrude)
        let before = part.stored
        app.beginModelDimension()
        app.viewportClicked(try part.wall(3))
        app.viewportClicked(try part.wall(1))
        await app.settle()
        let added = try #require(part.newDimension(after: before))
        #expect(added.kind == .lineDistance(holed.lines[3], holed.lines[1]))
        #expect(abs(added.value - 80) < 1e-6)
        #expect(!added.isDriving)
    }

    @Test func ghostsAndGuidesArentPicked() async throws {
        let part = try await plate()
        let app = part.app
        var ghost = app.viewport.items[part.index]
        ghost.isGhost = true
        let face = try #require(ghost.solid.topology.faces.first)
        app.viewport.show([ghost])
        await app.viewport.waitForMeshes()
        app.beginModelDimension()
        app.viewportClicked(.face(solid: 0, face.id))
        #expect(app.modelDimension?.pickedCount == 0)
        app.viewportClicked(nil)
        #expect(app.modelDimension?.pickedCount == 0)
    }

    @Test func theToolEndsWithEscapeSketchModeOrALevelChange() async throws {
        let part = try await plate()
        let app = part.app
        app.beginModelDimension()
        app.cancelModelDimension()
        #expect(app.modelDimension == nil)
        app.beginModelDimension()
        app.beginSketch(for: part.sketch.id)
        #expect(app.modelDimension == nil)
        app.finishSketch()
        #expect(app.beginModelDimension())
        app.editor.selection = [part.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        await app.settle()
        #expect(app.modelDimension == nil)
    }

    @Test func itCantStartWhileSketchingOrPicking() async throws {
        let part = try await plate()
        let app = part.app
        app.beginSketch(for: part.sketch.id)
        #expect(!app.beginModelDimension())
        #expect(app.modelDimension == nil)
        app.finishSketch()
        app.pick = PickSession(solid: part.solid, source: Endpoint(node: part.extrude.id, socket: "solid"), rule: nil,
                               consumer: nil, picked: [], level: app.editor.levelPath)
        #expect(!app.beginModelDimension())
        #expect(app.modelDimension == nil)
    }
    #endif
}
