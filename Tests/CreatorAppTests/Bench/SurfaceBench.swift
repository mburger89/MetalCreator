#if canImport(Metal) && canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Row `surface-3` (NS-3, control points): one drag step of a control point on a 30 × 30 net, from the pointer move to the
/// preview. A Rectangle becomes a Planar Surface, Rebuild Surface gives it 30 × 30 poles (degree 3, 27 spans each way), Edit Surface
/// takes the drag, and the drag runs through `ControlNetSession` as the viewport's tool does: every step is a coalesced
/// `poleMoves` edit while `DocumentModel.isScrubbing` holds. The §7.2 bracket sits in the same document with its Fillet at
/// Curvature (G2), so the scrubbing flag is on a node that reads it and the fillet builds at G1 for the steps; it is a second branch
/// of the graph, not downstream of the surface, since a fillet refuses a sheet. Release; prints `BENCH surface-3 …`. Recorded, not gated.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct SurfaceBench {
    @Test func draggingOneControlPointOfA30By30Net() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
        try app.document.perform(.setInput(bracket.fillet.id, "continuity", .integer(1)))
        let rectangle = try add(app, RectangleNode.self, ["width": .number(60), "height": .number(40)])
        let curves = try add(app, ProfileToCurvesNode.self)
        let planar = try add(app, PlanarSurfaceNode.self)
        let rebuild = try add(app, RebuildSurfaceNode.self, ["spansU": .integer(27), "spansV": .integer(27)])
        let edit = try add(app, EditSurfaceNode.self)
        let output = try add(app, OutputNode.self)
        try wire(app, rectangle, "profile", curves, "profile")
        try wire(app, curves, "curves", planar, "curves")
        try wire(app, planar, "surface", rebuild, "surface")
        try wire(app, rebuild, "surface", edit, "surface")
        try wire(app, edit, "surface", output, "solid")
        await app.settle()
        app.editControlPoints(of: edit.id)
        await app.settle()
        let session = try #require(app.controlNet, "the mode started")
        #expect(session.net.uCount == 30 && session.net.vCount == 30, "a 30 x 30 net")

        let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 10 / tan(CameraPose.fieldOfView / 2), yaw: 0,
                                                           pitch: .pi / 2, projection: .orthographic),
                                          size: ViewportSize(width: 200, height: 200))
        let pole = PoleIndex(i: 15, j: 15)
        let world = try #require(session.position(of: pole))
        let start = try #require(projector.screenPoint(of: world))
        #expect(session.dragBegan(at: start, modifiers: [], projector: projector))
        var steps = BenchSamples("surface-3 30x30 net, one drag step to the preview")
        let clock = ContinuousClock()
        for step in 1...40 {
            let target = try #require(projector.screenPoint(of: world + Vector3(0.03 * Double(step), 0, 0)))
            let begin = clock.now
            session.dragMoved(to: target, modifiers: [], projector: projector)
            await app.settle()
            if step > 5 { steps.append(from: begin, to: clock.now) }
        }
        let end = try #require(projector.screenPoint(of: world + Vector3(1.2, 0, 0)))
        let releaseBegin = clock.now
        session.dragEnded(at: end, modifiers: [], projector: projector)
        await app.settle()
        var release = BenchSamples("surface-3 release (the G2 fillet built), to the preview")
        release.append(from: releaseBegin, to: clock.now)
        #expect(!app.document.isScrubbing)
        let stored = app.document.graph.nodes[edit.id]?.inputValues[NodeSetting.poleMoves]?.poleMoves ?? []
        #expect(stored.count == 1, "the drag moved the point")
        expectAllOK(app, "after the drag")
        print(steps.line(budget: Bench.frameBudget))
        print(release.line())
    }

    private func add(_ app: AppModel, _ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) throws -> Node {
        var node = app.registry.makeNode(definition.typeID, at: Vector2(Double(app.document.graph.nodes.count) * 40, 200))
        node.inputValues.merge(values) { _, given in given }
        try app.document.perform(.addNode(node))
        return node
    }

    private func wire(_ app: AppModel, _ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) throws {
        try app.document.perform(.connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))))
    }
}
#endif
