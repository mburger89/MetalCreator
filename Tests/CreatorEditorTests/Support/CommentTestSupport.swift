// Test fixture file: comments for the editor tests.
import CreatorGeometry
import CreatorGraph
import Foundation
@testable import CreatorEditor

/// A comment ID whose sort order is `n`, so tests control the draw order.
func commentID(_ n: Int) -> CommentID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return CommentID(rawValue: UUID(uuidString: "00000000-0000-0000-0001-" + suffix) ?? UUID())
}

/// A 160 × 100 note at `origin` (stored coordinates).
func note(_ n: Int, _ text: String = "Note", at origin: Vector2 = .zero, size: Vector2 = Vector2(160, 100)) -> StickyNote {
    StickyNote(id: commentID(n), text: text, frame: CanvasRect(origin: origin, size: size))
}

/// A frame at `origin` (stored coordinates), 400 × 300 unless given.
func box(_ n: Int, _ title: String = "Frame", at origin: Vector2 = .zero, size: Vector2 = Vector2(400, 300)) -> CommentFrame {
    CommentFrame(id: commentID(n), title: title, frame: CanvasRect(origin: origin, size: size))
}

@MainActor
extension EditorModel {
    /// The screen point `inset` canvas points inside a comment's drawn top-left corner.
    func screenPoint(inComment id: CommentID, inset: Vector2) -> Vector2 {
        guard let rect = frame(ofComment: id) else { return .zero }
        return transform.toScreen(rect.origin + inset)
    }
}
