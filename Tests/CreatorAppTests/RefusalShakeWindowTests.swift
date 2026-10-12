import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The refusal shake running in the app's window (gap M5-i, used again by the C10 adoption): the window's clock moves by
/// hand, and the frames drawn at those times show the node out, across and home (`RefusalShake`'s keyframes).
@MainActor
struct RefusalShakeWindowTests {
    /// A Rectangle and an Extrude, apart, and the link the editor refuses (a profile into a number input).
    func refusedLink() async throws -> (app: AppWindow, extrude: Node, link: Link) {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let extrude = builder.add(ExtrudeNode.self, at: Vector2(300, 40))
        let app = try await AppWindow.open(builder.graph)
        let link = Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: extrude.id, socket: "distance"))
        return (app, extrude, link)
    }

    /// The x of every rect in the last frame, in draw order.
    func xs(_ app: AppWindow) -> [Float] {
        app.window.scene.rects.map(\.bounds.origin.x)
    }

    /// How far each rect of the last frame is from where it was `rest`.
    func shifts(_ app: AppWindow, from rest: [Float]) -> [Float] {
        zip(rest, xs(app)).map { $1 - $0 }
    }

    @Test func aRefusedConnectionShakesTheTargetNodeOutAcrossAndHome() async throws {
        let (app, extrude, link) = try await refusedLink()
        let rest = xs(app)
        app.editor.connect(link)
        #expect(app.editor.shakeCount(of: extrude.id) == 1)
        app.redraw()
        app.window.advance(by: 0.05)
        let distance: Float = 6   // the keyframes' reach, in points (`RefusalShake.distance`), written out so a change shows here
        let out = shifts(app, from: rest)
        #expect(out.contains(distance) && !out.contains { $0 != 0 && $0 != distance },
                "after 0.05 s the node is 6 points out, and only the node moved")
        #expect(out.filter { $0 == 0 }.count > 0, "the rest of the window stayed put")
        app.window.advance(by: 0.1)
        #expect(shifts(app, from: rest).filter { $0 != 0 }.allSatisfy { $0 == -distance }, "then 6 across")
        app.window.advance(by: 0.1)
        #expect(shifts(app, from: rest).allSatisfy { $0 == 0 }, "and home: the shake lasts a fifth of a second")
    }

    @Test func eachNewRefusalShakesAgain() async throws {
        let (app, extrude, link) = try await refusedLink()
        let rest = xs(app)
        app.editor.connect(link)
        app.redraw()
        app.window.advance(by: 0.3)
        #expect(shifts(app, from: rest).allSatisfy { $0 == 0 })
        app.editor.connect(link)
        #expect(app.editor.shakeCount(of: extrude.id) == 2)
        app.redraw()
        app.window.advance(by: 0.05)
        #expect(shifts(app, from: rest).contains { $0 != 0 }, "the second refusal moved the node again")
    }
}
