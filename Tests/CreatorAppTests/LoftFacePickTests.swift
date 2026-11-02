import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// "Pick Start Face in View…", "Pick End Face in View…" and the Clear buttons on a Loft: each pick and each clear is one undo step.
@MainActor
struct LoftFacePickTests {
    struct Setup {
        var app: AppModel
        var loft: Node
        var extrude: Node
    }

    /// A box on xy (its top is face 1) and a rectangle at z = 20, both wired into a Loft whose `solid` is the box.
    func open() async -> Setup {
        var builder = GraphBuilder()
        let (_, extrude) = builder.solid()
        let rectangle = builder.add(RectangleNode.self, ["plane": .plane(.through(Vector3(0, 0, 20)))])
        let loft = builder.add(LoftNode.self)
        builder.wire(rectangle, "profile", to: loft, "sections")
        builder.wire(extrude, "solid", to: loft, "solid")
        let output = builder.add(OutputNode.self)
        builder.wire(extrude, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        return Setup(app: app, loft: loft, extrude: extrude)
    }

    @Test func theButtonsBeginAPickOnTheWiredPart() async throws {
        let setup = await open()
        for start in [true, false] {
            setup.app.editor.press(start ? .pickLoftStartFace : .pickLoftEndFace, on: setup.loft.id)
            setup.app.handle(try #require(setup.app.editor.inspectorRequest))
            await setup.app.settle()
            let session = try #require(setup.app.pick)
            #expect(session.loftEnd == PickSession.LoftEndTarget(loft: setup.loft.id, isStart: start))
            #expect(session.picksFace && session.lattice == nil && session.picked.isEmpty)
            let part = try #require(setup.app.solid(at: Endpoint(node: setup.extrude.id, socket: "solid")))
            #expect(session.solid === part)
            setup.app.cancelPick()
        }
        #expect(setup.app.document.canUndo == false)
    }

    @Test func aClickOnAFaceSetsTheEndAsOneNamedStepAndUndoClearsIt() async throws {
        let setup = await open()
        let app = setup.app
        app.beginLoftFacePick(for: setup.loft.id, start: true)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(nil)
        #expect(app.pick != nil && app.document.canUndo == false, "an edge or empty space does nothing")
        app.viewportClicked(.face(solid: 0, FaceID(1)))
        #expect(app.pick == nil)
        let part = try #require(app.solid(at: Endpoint(node: setup.extrude.id, socket: "solid")))
        let node = try #require(app.document.graph.nodes[setup.loft.id])
        #expect(node.inputValues[NodeSetting.startFace] == .facePick(try #require(part.topology.facePick(for: FaceID(1)))))
        #expect(node.inputValues[NodeSetting.endFace] == nil)
        #expect(app.editor.selection == [setup.loft.id])
        #expect(app.document.undoName == "Pick Loft Face")
        app.document.undo()
        await app.settle()
        #expect(app.document.graph.nodes[setup.loft.id]?.inputValues[NodeSetting.startFace] == nil)
        #expect(app.document.canUndo == false)
    }

    @Test func theEndFaceIsPickedAndClearedSeparately() async throws {
        let setup = await open()
        let app = setup.app
        app.beginLoftFacePick(for: setup.loft.id, start: false)
        await app.settle()
        app.viewportClicked(.face(solid: 0, FaceID(1)))
        #expect(app.document.graph.nodes[setup.loft.id]?.inputValues[NodeSetting.endFace] != nil)
        #expect(app.document.graph.nodes[setup.loft.id]?.inputValues[NodeSetting.startFace] == nil)

        app.editor.press(.clearLoftEndFace, on: setup.loft.id)
        app.handle(try #require(app.editor.inspectorRequest))
        #expect(app.document.graph.nodes[setup.loft.id]?.inputValues[NodeSetting.endFace] == nil)
        #expect(app.document.undoName == "Clear Loft Face")
        app.document.undo()
        #expect(app.document.graph.nodes[setup.loft.id]?.inputValues[NodeSetting.endFace] != nil, "one step brings it back")
        app.document.undo()
        #expect(app.document.canUndo == false)
    }

    @Test func clearingAnEndWithNoFaceMakesNoStep() async throws {
        let setup = await open()
        setup.app.clearLoftFace(of: setup.loft.id, start: true)
        #expect(setup.app.document.canUndo == false)
    }

    @Test func aLoftWithNoPartWiredSaysToWireOne() async throws {
        var builder = GraphBuilder()
        let loft = builder.add(LoftNode.self)
        let app = await makeApp(builder.graph)
        app.beginLoftFacePick(for: loft.id, start: true)
        #expect(app.pick == nil)
        #expect(app.alert != nil)
    }
}
