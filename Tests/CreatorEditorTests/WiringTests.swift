import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct WiringTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let other = testNode(RectangleTestNode.self, id: 2, at: Vector2(0, 300))
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(300, 0))
    let number = testNode(NumberTestNode.self, id: 4, at: Vector2(300, 300))

    @Test func draggingFromAnOutputToAnInputConnects() {
        let editor = makeEditor([rect, extrude])
        editor.drag(editor.screenPoint(of: rect.id, "profile", input: false),
                    editor.screenPoint(of: extrude.id, "profile", input: true))
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
        #expect(editor.refusal == nil)
    }

    @Test func draggingFromAnInputBackToAnOutputConnects() {
        let editor = makeEditor([rect, extrude])
        editor.drag(editor.screenPoint(of: extrude.id, "profile", input: true),
                    editor.screenPoint(of: rect.id, "profile", input: false))
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
    }

    @Test func theWireFollowsThePointerWhileDragging() {
        let editor = makeEditor([rect, extrude])
        let start = editor.screenPoint(of: rect.id, "profile", input: false)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: Vector2(250, 200))
        #expect(editor.interaction == .connecting(WireDrag(
            from: SocketRef(Endpoint(node: rect.id, socket: "profile"), isInput: false), current: Vector2(250, 200))))
    }

    @Test func droppingOnAnOccupiedInputReplacesItsWireInOneUndoStep() {
        let editor = makeEditor([rect, other, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.drag(editor.screenPoint(of: other.id, "profile", input: false),
                    editor.screenPoint(of: extrude.id, "profile", input: true))
        #expect(editor.graph.links == [wire(other, "profile", extrude, "profile")])
        editor.document.undo()
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
    }

    @Test func aTypeMismatchIsRefusedWithAPlainMessage() {
        let editor = makeEditor([number, extrude])
        editor.drag(editor.screenPoint(of: number.id, "value", input: false),
                    editor.screenPoint(of: extrude.id, "profile", input: true))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal?.message == "A number can't connect to a profile input.")
        #expect(editor.refusal?.node == extrude.id)
        #expect(editor.shakeCount(of: extrude.id) == 1)
        #expect(!editor.document.canUndo)
    }

    @Test func outputToOutputIsRefused() {
        let editor = makeEditor([rect, other])
        editor.drag(editor.screenPoint(of: rect.id, "profile", input: false),
                    editor.screenPoint(of: other.id, "profile", input: false))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal?.message == "Connect an output to an input.")
    }

    @Test func aCycleIsRefused() {
        let a = testNode(NumberTestNode.self, id: 5, at: .zero)
        let b = testNode(NumberTestNode.self, id: 6, at: Vector2(300, 0))
        let editor = makeEditor([a, b], [wire(a, "value", b, "value")])
        editor.drag(editor.screenPoint(of: b.id, "value", input: false),
                    editor.screenPoint(of: a.id, "value", input: true))
        #expect(editor.graph.links == [wire(a, "value", b, "value")])
        #expect(editor.refusal?.message == "That wire would make a loop.")
    }

    @Test func droppingOnEmptyCanvasDoesNothing() {
        let editor = makeEditor([rect, extrude])
        editor.drag(editor.screenPoint(of: rect.id, "profile", input: false), Vector2(900, 900))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal == nil)
        #expect(editor.interaction == nil)
    }

    @Test func draggingAWiredInputOntoEmptyCanvasDisconnectsIt() {
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.drag(editor.screenPoint(of: extrude.id, "profile", input: true), Vector2(900, 900))
        #expect(editor.graph.links.isEmpty)
        editor.document.undo()
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
        #expect(!editor.document.canUndo)
    }
}
