import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// A sketch drawn on a plane wired into its node follows that plane (sketcher spec §8): when the plane moves the
/// camera looks at it again, and when the plane loses its result the sketch stays open on the last plane and says so.
@MainActor
struct SketchPlaneFollowTests {
    /// A rectangle sketch on the wired XY Plane node, open in a 1400 × 900 viewport.
    func openOnWiredPlane() async throws -> (app: AppModel, plane: Node) {
        var sketch = rectangleSketch()
        sketch.plane = .wired
        var builder = GraphBuilder()
        let plane = builder.add(PlaneNode.self)
        let box = builder.sketchedBox(sketch)
        builder.wire(plane, "plane", to: box.sketch, "plane")
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        try #require(app.sketch != nil)
        return (app, plane)
    }

    @Test func theCameraLooksAtTheWiredPlaneAgainWhenItMoves() async throws {
        let (app, plane) = try await openOnWiredPlane()
        let before = app.viewport.pose
        #expect(app.sketch?.editor.plane == .xy)
        try app.document.perform(.setInput(plane.id, "orientation", .integer(1)))   // XZ
        await app.settle()
        await app.viewport.waitForAnimation()
        #expect(app.sketch?.editor.plane == .xz)
        #expect(abs(app.viewport.pose.pitch - before.pitch) > 0.5, "the camera turned to face the new plane")
        #expect(app.viewport.pose.projection == .orthographic)
        #expect(app.alert == nil)
    }

    @Test func aPlaneThatDoesNotMoveLeavesTheCameraAlone() async throws {
        let (app, plane) = try await openOnWiredPlane()
        let before = app.viewport.pose
        try app.document.perform(.setInput(plane.id, "offset", .number(0)))
        await app.settle()
        #expect(app.viewport.pose == before && !app.viewport.isAnimating)
    }

    @Test func aPlaneThatLosesItsResultKeepsTheSketchOpenOnTheLastPlaneAndSaysSo() async throws {
        let (app, plane) = try await openOnWiredPlane()
        try app.document.perform(.setInput(plane.id, "orientation", .integer(7)))   // not one of XY, XZ, YZ
        await app.settle()
        #expect(app.sketch?.editor.plane == .xy, "the last plane stays")
        #expect(app.alert == .problem(AppProblem("The plane lost its result", AppModel.planeFailed)))
        app.alert = nil
        try app.document.perform(.setInput(plane.id, "offset", .number(5)))
        await app.settle()
        #expect(app.alert == nil, "said once, not on every refresh")
        try app.document.perform(.setInput(plane.id, "orientation", .integer(0)))
        await app.settle()
        #expect(app.sketch?.editor.plane == Plane.xy.offset(by: 5), "it follows the plane again once it evaluates")
    }

    /// The wire itself is deleted: no node is wired in, so the alert must not say a node has no result.
    @Test func aPlaneWhoseWireIsRemovedKeepsTheSketchOpenOnTheLastPlaneAndSaysSoOnce() async throws {
        let (app, plane) = try await openOnWiredPlane()
        let link = try #require(app.document.graph.links.first { $0.to.node == app.sketch?.node && $0.to.socket == "plane" })
        try app.document.perform(.disconnect(link))
        await app.settle()
        #expect(app.sketch?.editor.plane == .xy, "the last plane stays")
        #expect(app.alert == .problem(AppProblem("The plane lost its result", AppModel.planeUnwired)))
        app.alert = nil
        try app.document.perform(.setInput(plane.id, "offset", .number(5)))
        await app.settle()
        #expect(app.alert == nil, "said once")
    }

    /// A question already on screen (here Discard Changes) is never replaced: the loss is said once it is answered.
    @Test func aLostPlaneWaitsForTheAlertAlreadyShowing() async throws {
        let (app, _) = try await openOnWiredPlane()
        app.alert = .discardChanges
        let link = try #require(app.document.graph.links.first { $0.to.node == app.sketch?.node && $0.to.socket == "plane" })
        try app.document.perform(.disconnect(link))
        await app.settle()
        #expect(app.alert == .discardChanges, "the question stays")
        app.alert = nil
        app.refreshScene()
        #expect(app.alert == .problem(AppProblem("The plane lost its result", AppModel.planeUnwired)), "then the loss is said")
    }
}
