// Test fixture file: a graph with two notes, a frame and a node, for typing on the canvas through the app's window.
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Foundation

/// A note, a second note, a frame and a Rectangle node, at fixed places well apart on the canvas.
struct TypingFixture {
    let note = StickyNote(id: Self.id(1), text: "Line one", frame: CanvasRect(origin: Vector2(40, 40), size: Vector2(160, 100)))
    let otherNote = StickyNote(id: Self.id(2), text: "Second", frame: CanvasRect(origin: Vector2(40, 150), size: Vector2(160, 60)))
    let box = CommentFrame(id: Self.id(3), title: "Bracket", frame: CanvasRect(origin: Vector2(260, 40), size: Vector2(300, 160)))
    let rectangle: Node
    let graph: Graph

    init() {
        var builder = GraphBuilder()
        rectangle = builder.add(RectangleNode.self, at: Vector2(620, 60))
        var graph = builder.graph
        graph.stickies = [note.id: note, otherNote.id: otherNote]
        graph.frames = [box.id: box]
        self.graph = graph
    }

    static func id(_ n: Int) -> CommentID {
        CommentID(rawValue: UUID(uuidString: "00000000-0000-0000-0001-" + String(repeating: "0", count: 11) + String(n)) ?? UUID())
    }
}
