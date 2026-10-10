import CreatorGeometry
import CreatorGraph

/// Comment geometry computed, never measured (like `NodeLayout`), so drawing, hit testing and resizing agree. All
/// values are canvas points at zoom 1 (canvas comments spec 2026-10-09 §7).
public enum CommentLayout {
    /// A new note's size.
    public static let noteSize = Vector2(160, 100)
    /// The strip at the top of a frame that drags it and shows its title.
    public static let titleBarHeight = 22.0
    /// Slack between a framed selection's bounds and the frame around it.
    public static let framePadding = 24.0
    /// How far inside a frame's edge a press still grabs the frame; further in belongs to the nodes and the box.
    public static let borderWidth = 6.0
    /// The smallest a comment can be resized to.
    public static let minimumSize = Vector2(80, 40)
    /// The side of the bottom-right resize handle of a selected comment.
    public static let handleSize = 12.0
    /// A note's text padding.
    public static let notePadding = 8.0

    /// The frame that holds `bounds` (display canvas points): padded `framePadding` on every side, with the title bar
    /// added above.
    public static func framing(_ bounds: CanvasRect) -> CanvasRect {
        CanvasRect(origin: bounds.origin - Vector2(framePadding, framePadding + titleBarHeight),
                   size: bounds.size + Vector2(2 * framePadding, 2 * framePadding + titleBarHeight))
    }

    /// The title bar of a frame drawn at `rect`.
    public static func titleBar(of rect: CanvasRect) -> CanvasRect {
        CanvasRect(origin: rect.origin, size: Vector2(rect.size.x, min(titleBarHeight, rect.size.y)))
    }

    /// The part of a frame drawn at `rect` that is not its chrome: inside the title bar and the edge band. Nil when
    /// the frame is so small that all of it is chrome.
    public static func interior(of rect: CanvasRect) -> CanvasRect? {
        let size = Vector2(rect.size.x - 2 * borderWidth, rect.size.y - titleBarHeight - borderWidth)
        guard size.x > 0, size.y > 0 else { return nil }
        return CanvasRect(origin: rect.origin + Vector2(borderWidth, titleBarHeight), size: size)
    }

    /// Whether a press at `point` is on the chrome of a frame drawn at `rect`: its title bar or its edge band.
    public static func chromeContains(_ rect: CanvasRect, _ point: Vector2) -> Bool {
        guard rect.contains(point) else { return false }
        guard let interior = interior(of: rect) else { return true }
        return !interior.contains(point)
    }

    /// Whether a box meets the chrome of a frame drawn at `rect`: it overlaps the frame without lying wholly inside
    /// its interior, so a box drawn among the nodes inside a frame doesn't select the frame.
    public static func chromeIntersects(_ rect: CanvasRect, _ box: CanvasRect) -> Bool {
        guard rect.intersects(box) else { return false }
        guard let interior = interior(of: rect) else { return true }
        let inside = box.origin.x >= interior.origin.x && box.origin.y >= interior.origin.y
            && box.maxX <= interior.maxX && box.maxY <= interior.maxY
        return !inside
    }

    /// The resize handle of a comment drawn at `rect`: its bottom-right corner.
    public static func handle(of rect: CanvasRect) -> CanvasRect {
        CanvasRect(origin: Vector2(rect.maxX - handleSize, rect.maxY - handleSize), size: Vector2(handleSize, handleSize))
    }

    /// `size` raised to `minimumSize` (display points).
    public static func clamped(_ size: Vector2) -> Vector2 {
        Vector2(max(size.x, minimumSize.x), max(size.y, minimumSize.y))
    }
}
