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
/// NS-3 Task 8, fix round 1: the drag keys, failed and list reads, demand, and the ways the mode ends.
extension ControlNetModeTests {
    @Test func aNoChangeDragCancelledKeepsAnEarlierDragsStep() async throws {
        let fixture = await open()
        let first = try await enter(fixture)
        try drag(first, pole: PoleIndex(i: 2, j: 3), by: Vector3(0.5, 0, 0))
        await fixture.app.settle()
        first.done()
        #expect(fixture.app.controlNet == nil)
        let second = try await enter(fixture)
        second.selection = [PoleIndex(i: 2, j: 3)]
        second.toggleLock(.z)
        try drag(second, pole: PoleIndex(i: 2, j: 3), by: Vector3(0.5, 0, 0), finish: false)
        second.cancel()
        #expect(fixture.app.controlNet === second)
        #expect(fixture.app.document.undoName == "Move Control Points")
        #expect(moves(fixture).count == 1)
        fixture.app.document.undo()
        #expect(moves(fixture).isEmpty)
    }

    @Test func aFailedReadClearsTheNetAndSaysWhy() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        try fixture.app.document.perform(.setInput(fixture.source.id, "kind", .integer(1)), name: UndoName.changeParameter)
        await fixture.app.settle()
        #expect(session.net.uCount == 0 && fixture.app.viewport.overlay.points.isEmpty)
        #expect(fixture.app.controlNetProblem != nil)
    }

    @Test func aSourceNobodyDemandsIsEvaluatedForTheNet() async throws {
        var source = Self.registry.makeNode(NetSheetNode.typeID, at: .zero)
        source.inputValues["hold"] = .integer(0)
        let edit = Self.registry.makeNode(EditSurfaceNode.typeID, at: Vector2(240, 0))
        let graph = Graph(nodes: [source.id: source, edit.id: edit], links: [
            Link(from: Endpoint(node: source.id, socket: "surface"), to: Endpoint(node: edit.id, socket: "surface")),
        ])
        let app = AppModel(kernel: NetSheetNode.kernel, registry: Self.registry, file: GraphFile(graph: graph))
        await app.settle()
        app.editor.selection = [edit.id]
        await app.settle()
        #expect(app.viewport.overlay.points.count == 48)
        app.editor.selection = []
        app.editControlPoints(of: edit.id)
        await app.settle()
        #expect(app.controlNet?.net.uCount == 6)
    }

    @Test func enteringWhileTheInputLoadsChecksTheListWhenItLands() async throws {
        let fixture = await open()
        let gate = NetSheetNode.gate
        defer { gate.open() }
        try fixture.app.document.perform(.batch([.setInput(fixture.source.id, "count", .integer(3)),
                                                 .setInput(fixture.source.id, "hold", .integer(1)),
        ]), name: UndoName.changeParameter)
        #expect(await gate.waitUntilEntered())
        fixture.app.editControlPoints(of: fixture.edit.id)
        let session = try #require(fixture.app.controlNet)
        gate.open()
        await fixture.app.settle()
        #expect(session.net.uCount == 0)
        #expect(fixture.app.controlNetProblem == "Edit Control Points works on one surface; this node gets 3.")
    }

    @Test func aPickEndsWhenEditingStarts() async throws {
        let fixture = await open()
        let solid = try #require(solids(fixture.app, fixture.source, "surface").first)
        fixture.app.pick = PickSession(solid: solid, source: Endpoint(node: fixture.source.id, socket: "surface"), rule: nil,
                                       consumer: nil, picked: [], level: fixture.app.editor.levelPath)
        fixture.app.editControlPoints(of: fixture.edit.id)
        #expect(fixture.app.pick == nil && fixture.app.controlNet != nil)
    }

    @Test func aCurveListIsRefusedInTheCurveSentence() async throws {
        let source = Self.registry.makeNode(CurveListNode.typeID, at: .zero)
        let edit = Self.registry.makeNode(EditCurveNode.typeID, at: Vector2(240, 0))
        let output = Self.registry.makeNode(OutputNode.typeID, at: Vector2(480, 0))
        let graph = Graph(nodes: [source.id: source, edit.id: edit, output.id: output], links: [
            Link(from: Endpoint(node: source.id, socket: "curve"), to: Endpoint(node: edit.id, socket: "curve")),
            Link(from: Endpoint(node: edit.id, socket: "curve"), to: Endpoint(node: output.id, socket: "curve")),
        ])
        let app = AppModel(kernel: NetSheetNode.kernel, registry: Self.registry, file: GraphFile(graph: graph))
        await app.settle()
        app.editControlPoints(of: edit.id)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.message == "Edit Control Points works on one curve; this node gets 3.")
    }

    @Test func anUndoThatRemovesTheNodeEndsTheMode() async throws {
        let fixture = await open()
        let extra = Self.registry.makeNode(EditSurfaceNode.typeID, at: Vector2(240, 200))
        try fixture.app.document.perform(.addNode(extra), name: UndoName.addNode(extra))
        fixture.app.editControlPoints(of: extra.id)
        #expect(fixture.app.controlNet?.node == extra.id)
        fixture.app.document.undo()
        await fixture.app.settle()
        #expect(fixture.app.controlNet == nil && fixture.app.viewport.tool == nil)
    }

    @Test func openingAFileEndsTheMode() async throws {
        let fixture = await open()
        _ = try await enter(fixture)
        let url = temporaryURL("net.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture.app.document.fileData().write(to: url)
        try fixture.app.open(url)
        #expect(fixture.app.controlNet == nil)
    }

    @Test func escapeCancelsADragFirstThenEndsTheMode() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        try drag(session, pole: PoleIndex(i: 2, j: 3), by: Vector3(0.5, 0, 0), finish: false)
        session.cancel()
        #expect(fixture.app.controlNet === session)
        session.cancel()
        #expect(fixture.app.controlNet == nil)
    }

    @Test func aLateReadOfAnOlderNetNeverReplacesTheNewer() async throws {
        let fixture = await open()
        let session = try await enter(fixture)
        let feed = try #require(fixture.app.controlNetFeed)
        let older = feed.token - 1
        let stale = ControlNetGrid(poles: [.zero], uCount: 1, vCount: 1, normals: [])
        fixture.app.controlNetLanded(feed, token: older, result: .success(stale))
        #expect(session.net.uCount == 6 && session.net.vCount == 8)
    }
}
#endif
