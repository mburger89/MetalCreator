// Test fixture file: comment fixtures shared by the comment tests.
import Foundation
import CreatorGeometry
@testable import CreatorGraph

/// A comment ID whose sort order is `n`, so tests control the order comments are written in.
func commentID(_ n: Int) -> CommentID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return CommentID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID())
}

func note(_ n: Int, _ text: String = "Note", at origin: Vector2 = .zero, accent: AccentRole = .muted) -> StickyNote {
    StickyNote(id: commentID(n), text: text, frame: CanvasRect(origin: origin, size: Vector2(160, 100)), accent: accent)
}

func box(_ n: Int, _ title: String = "Frame", at origin: Vector2 = .zero, accent: AccentRole = .muted) -> CommentFrame {
    CommentFrame(id: commentID(n), title: title, frame: CanvasRect(origin: origin, size: Vector2(300, 200)), accent: accent)
}
