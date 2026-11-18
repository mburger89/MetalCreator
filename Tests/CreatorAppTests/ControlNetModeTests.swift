import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorViewport
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

#if canImport(CreatorOCCT)
/// A one-face B-spline sheet with a `u` x `v` net (the kernel's test helper) at 1 mm spacing; `count` copies make a list, and a
/// `hold` of 1 holds the evaluation at `ControlNetModeTests.gate` until the test lets it through.
enum NetSheetNode: NodeDefinition {
    static let typeID = "test.netSheet"
    static let displayName = "Net Sheet"
    static let category = NodeCategory.surface
    static let inputs = [SocketSpec("u", .integer, defaultValue: .integer(6)), SocketSpec("v", .integer, defaultValue: .integer(8)),
                         SocketSpec("count", .integer, defaultValue: .integer(1)), SocketSpec("hold", .integer, defaultValue: .integer(0)),
                         SocketSpec("kind", .integer, defaultValue: .integer(0)),
    ]
    static let outputs = [SocketSpec("surface", .solid)]
    static let kernel = OCCTKernel()
    static let gate = HookGate()

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        if try inputs.integer("hold") == 1 { await gate.hold() }
        if try inputs.integer("kind") == 1 {
            // A closed solid, which has no control net to edit.
            let box = try await Self.kernel.extrude(Profile2D.rectangle(width: 10, height: 10, plane: .xy), distance: 5, mode: .oneSided,
                                                    tag: context.tag)
            return NodeOutputs(["surface": .solid(box)])
        }
        let sheet = try await Self.kernel.bsplineSheet(uCount: try inputs.integer("u"), vCount: try inputs.integer("v"), degree: 1,
                                                       tag: context.tag)
        return NodeOutputs(lists: ["surface": Array(repeating: Scalar.solid(sheet), count: try inputs.integer("count"))])
    }
}

/// `count` straight curves, for an Edit Curve node that gets a list.
enum CurveListNode: NodeDefinition {
    static let typeID = "test.curveList"
    static let displayName = "Curve List"
    static let category = NodeCategory.surface
    static let inputs = [SocketSpec("count", .integer, defaultValue: .integer(3))]
    static let outputs = [SocketSpec("curve", .curve)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let curve = try await NetSheetNode.kernel.makeCurve([.line(.zero, Vector3(10, 0, 0))], tag: context.tag)
        return NodeOutputs(lists: ["curve": Array(repeating: Scalar.curve(curve), count: try inputs.integer("count"))])
    }
}

/// NS-3 Task 8: the control-point mode in the app.
@MainActor
struct ControlNetModeTests {
    struct Fixture {
        let app: AppModel
        let source: Node
        let edit: Node
        let output: Node
    }

    static let registry = NodeRegistry(BuiltInNodes.all + [NetSheetNode.self, CurveListNode.self])

    func open(_ settings: [SocketName: ConstantValue] = [:]) async -> Fixture {
        var source = Self.registry.makeNode(NetSheetNode.typeID, at: .zero)
        source.inputValues.merge(settings) { _, given in given }
        let edit = Self.registry.makeNode(EditSurfaceNode.typeID, at: Vector2(240, 0))
        let output = Self.registry.makeNode(OutputNode.typeID, at: Vector2(480, 0))
        let graph = Graph(nodes: [source.id: source, edit.id: edit, output.id: output], links: [
            Link(from: Endpoint(node: source.id, socket: "surface"), to: Endpoint(node: edit.id, socket: "surface")),
            Link(from: Endpoint(node: edit.id, socket: "surface"), to: Endpoint(node: output.id, socket: "solid")),
        ])
        let app = AppModel(kernel: NetSheetNode.kernel, registry: Self.registry, file: GraphFile(graph: graph))
        app.viewport.recordViewSize(ViewportSize(width: 200, height: 200))
        await app.settle()
        return Fixture(app: app, source: source, edit: edit, output: output)
    }

    /// An orthographic camera 200 points square showing 20 mm, so a millimetre is ten points. Looks down -Z.
    static func projector() -> ViewportProjector {
        let distance = 10 / tan(CameraPose.fieldOfView / 2)
        return ViewportProjector(pose: CameraPose(target: .zero, distance: distance, yaw: 0, pitch: .pi / 2, projection: .orthographic),
                                 size: ViewportSize(width: 200, height: 200))
    }

    func enter(_ fixture: Fixture) async throws -> ControlNetSession {
        fixture.app.editControlPoints(of: fixture.edit.id)
        await fixture.app.settle()
        return try #require(fixture.app.controlNet)
    }

    func moves(_ fixture: Fixture) -> [PoleMove] {
        fixture.app.document.graph.nodes[fixture.edit.id]?.inputValues[NodeSetting.poleMoves]?.poleMoves ?? []
    }

    func drag(_ session: ControlNetSession, pole: PoleIndex, by delta: Vector3, steps: Int = 3, finish: Bool = true) throws {
        let projector = Self.projector()
        let world = try #require(session.position(of: pole))
        let start = try #require(projector.screenPoint(of: world))
        #expect(session.dragBegan(at: start, modifiers: [], projector: projector))
        for step in 1...steps {
            let fraction = Double(step) / Double(steps)
            let target = try #require(projector.screenPoint(of: world + delta * fraction))
            session.dragMoved(to: target, modifiers: [], projector: projector)
        }
        if finish {
            let end = try #require(projector.screenPoint(of: world + delta))
            session.dragEnded(at: end, modifiers: [], projector: projector)
        }
    }

    @Test func enteringInstallsTheTool() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        #expect(fixture.app.viewport.tool === session)
        #expect(session.net.uCount == 6 && session.net.vCount == 8)
        #expect(fixture.app.viewport.overlay.points.count == 48)
        fixture.app.endControlPoints()
        #expect(fixture.app.controlNet == nil && fixture.app.viewport.tool == nil)
    }

    @Test func insideAGroupIsRefused() async throws {
        let fixture = await open()
        let app = fixture.app
        app.editor.selection = [fixture.source.id, fixture.edit.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        app.editControlPoints(of: fixture.edit.id)
        #expect(app.controlNet == nil)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.message
            == "Control points inside a group can't be edited yet. Edit them before grouping, or from the top level.")
    }

    @Test func aListIsRefused() async throws {
        let fixture = await open(["count": .integer(3)])
        fixture.app.editControlPoints(of: fixture.edit.id)
        #expect(fixture.app.controlNet == nil)
        guard case .problem(let problem)? = fixture.app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.message == "Edit Control Points works on one surface; this node gets 3.")
    }

    @Test func aDragIsOneUndoStep() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        try drag(session, pole: PoleIndex(i: 2, j: 3), by: Vector3(0.5, 0, 0))
        await fixture.app.settle()
        #expect(fixture.app.document.undoName == "Move Control Points")
        let stored = moves(fixture)
        #expect(stored.count == 1 && stored[0].index == PoleIndex(i: 2, j: 3))
        try #require(stored.count == 1)
        #expect(abs(stored[0].offset.x - 0.5) < 1e-6)
        fixture.app.document.undo()
        #expect(moves(fixture).isEmpty)
        #expect(fixture.app.document.undoName != "Move Control Points")
    }

    @Test func scrubbingHoldsDuringADrag() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        try drag(session, pole: PoleIndex(i: 1, j: 1), by: Vector3(0.5, 0, 0), finish: false)
        #expect(fixture.app.document.isScrubbing)
        let projector = Self.projector()
        session.dragEnded(at: try #require(projector.screenPoint(of: Vector3(1.5, 1, 0))), modifiers: [], projector: projector)
        #expect(!fixture.app.document.isScrubbing)
    }

    @Test func typingIsOneStepNamedChangeControlPoint() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        session.selection = [PoleIndex(i: 1, j: 2)]
        session.setOffset(0, to: 2)
        #expect(fixture.app.document.undoName == "Change Control Point")
        #expect(moves(fixture) == [PoleMove(index: PoleIndex(i: 1, j: 2), offset: Vector3(2, 0, 0))])
        session.setOffset(0, to: 0)
        #expect(moves(fixture).isEmpty)
    }

    @Test func aCancelledDragLeavesNoStepAndTheRestoredNet() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        let before = fixture.app.document.content
        let nameBefore = fixture.app.document.undoName
        try drag(session, pole: PoleIndex(i: 2, j: 3), by: Vector3(0.5, 0, 0), finish: false)
        await fixture.app.settle()
        // The net is shown again mid-drag (an evaluation landed): it waits for the drag's end.
        session.showNet(session.net, moves: [PoleMove(index: PoleIndex(i: 2, j: 3), offset: Vector3(0.25, 0, 0))])
        session.cancel()
        #expect(fixture.app.document.isScrubbing == false)
        #expect(fixture.app.controlNet === session)
        #expect(fixture.app.document.content == before)
        #expect(fixture.app.document.undoName == nameBefore)
        #expect(fixture.app.document.undoName != "Move Control Points")
        #expect(session.offsets.values.allSatisfy { $0 == .zero })
        await fixture.app.settle()
        #expect(session.offsets.values.allSatisfy { $0 == .zero } && fixture.app.document.canRedo == false)
    }

    @Test func enteringEndsMeasure() async throws {
        let fixture = await open()
        fixture.app.setMeasure(true)
        #expect(fixture.app.measure != nil)
        _ = try await enter(fixture)
        #expect(fixture.app.measure == nil)
    }

    @Test func measureIsRefusedWhileEditing() async throws {
        let fixture = await open()
        _ = try await enter(fixture)
        fixture.app.setMeasure(true)
        #expect(fixture.app.measure == nil)
        #expect(!fixture.app.beginModelDimension())
        #expect(fixture.app.modelDimension == nil)
        fixture.app.beginSketch(for: fixture.edit.id)
        #expect(fixture.app.sketch == nil)
    }

    @Test func mcpIsRefusedWhileEditing() async throws {
        let fixture = await open()
        let session = AppDocumentSession(model: fixture.app)
        #expect(session.editRefusal() == nil)
        _ = try await enter(fixture)
        #expect(session.editRefusal() == "MetalCreator is editing control points. Click Done, then try again.")
    }

    @Test func deletingTheNodeEndsTheMode() async throws {
        let fixture = await open()
        _ = try await enter(fixture)
        try fixture.app.document.perform(.removeNode(fixture.edit.id), name: UndoName.delete)
        await fixture.app.settle()
        #expect(fixture.app.controlNet == nil && fixture.app.viewport.tool == nil)
        #expect(fixture.app.viewport.overlay.points.isEmpty)
    }

    @Test func newEndsTheMode() async throws {
        let fixture = await open()
        _ = try await enter(fixture)
        fixture.app.load(GraphFile(), from: nil)
        #expect(fixture.app.controlNet == nil && fixture.app.controlNetPreview == nil)
    }

    @Test func aSelectedNodeShowsItsNetReadOnly() async throws {
        let fixture = await open()
        let app = fixture.app
        app.editor.selection = [fixture.edit.id]
        await app.settle()
        #expect(app.controlNet == nil && app.viewport.tool == nil)
        #expect(app.viewport.overlay.points.count == 48)
        app.editor.selection = [fixture.source.id]
        await app.settle()
        #expect(app.viewport.overlay.points.isEmpty)
    }

    @Test func aStaleNetIsNeverMixed() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        let gate = NetSheetNode.gate
        defer { gate.open() }
        try fixture.app.document.perform(.batch([.setInput(fixture.source.id, "u", .integer(7)),
                                                 .setInput(fixture.source.id, "hold", .integer(1)),
        ]), name: UndoName.changeParameter)
        #expect(await gate.waitUntilEntered())
        // The evaluation is held: the overlay still shows the whole old net, never a mix.
        #expect(session.net.uCount == 6 && fixture.app.viewport.overlay.points.count == 48)
        gate.open()
        await fixture.app.settle()
        #expect(session.net.uCount == 7 && session.net.vCount == 8)
        #expect(fixture.app.viewport.overlay.points.count == 56)
    }
}
#endif
