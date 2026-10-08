import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// `HandleSpec` → `ViewportHandle` (spec §6.5) for the selected nodes, and dragging one as one undo step.
@MainActor
struct HandleTests {
    @Test func aSelectedExtrudeHasADistanceArrowFromItsProfile() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        #expect(app.viewport.handles.isEmpty, "nothing is selected")
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first)
        #expect(app.viewport.handles.count == 1)
        #expect(handle.anchor == .zero && handle.direction == .unitZ && handle.value == 10)
        #expect(handle.style == .linear && handle.tint == .solid)
        #expect(handle.range == 0.1...200, "the socket's slider range")

        try app.document.perform(.setInput(box.extrude.id, "reversed", .bool(true)))
        await app.settle()
        #expect(app.viewport.handles.first?.direction == -.unitZ)
        try app.document.perform(.setInput(box.extrude.id, "mode", .integer(1)))
        await app.settle()
        #expect(app.viewport.handles.first?.anchor == Vector3(0, 0, -5), "symmetric: the knob sits on the far cap")
        #expect(app.viewport.handles.first?.direction == .unitZ)
    }

    @Test func aWiredDistanceHasNoHandle() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let number = builder.add(NumberNode.self, ["value": .number(12)], at: Vector2(0, 200))
        builder.wire(number, "value", to: box.extrude, "distance")
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        #expect(app.viewport.handles.isEmpty)
    }

    @Test func aFilletsRadiusHandleSitsOnItsFirstEdgeAndHidesWithItsToggle() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let edges = builder.add(AllEdgesNode.self)
        let fillet = builder.add(FilletNode.self, ["radius": .number(2)])
        let output = builder.add(OutputNode.self)
        builder.wire(box.extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        // Upstream of an Output, so it's evaluated (the demand set, spec §4.4).
        builder.wire(fillet, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [fillet.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first)
        #expect(handle.style == .radial && handle.tint == .feature && handle.value == 2)
        let solid = try #require(solids(app, box.extrude).first)
        #expect(handle.anchor == solid.topology.edges[0].midpoint)
        #expect(handle.direction == -.unitZ, "FakeKernel's first edge borders the start cap, whose normal is −z")
        try app.document.perform(.setInput(fillet.id, NodeSetting.showHandle, .bool(false)))
        await app.settle()
        #expect(app.viewport.handles.isEmpty, "“Show handle in view” off")
    }

    @Test func noHandlesWhilePicking() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let rule = builder.add(EdgesByTagNode.self)
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        app.beginPick(for: rule.id)
        await app.settle()
        #expect(app.viewport.handles.isEmpty)
    }
}
