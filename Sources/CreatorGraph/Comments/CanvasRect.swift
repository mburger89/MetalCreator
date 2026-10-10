import CreatorGeometry

/// An axis-aligned rectangle in canvas or screen points, y down. Lives in `CreatorGraph`, with the comments it frames
/// (`StickyNote.frame`, `CommentFrame.frame`; canvas comments spec 2026-10-09 §7), and is saved with them.
public struct CanvasRect: Equatable, Sendable, Codable {
    public var origin: Vector2
    public var size: Vector2

    public init(origin: Vector2, size: Vector2) {
        self.origin = origin
        self.size = size
    }

    /// The rectangle spanned by two corners in any order (a box-select drag).
    public init(corner a: Vector2, _ b: Vector2) {
        origin = Vector2(min(a.x, b.x), min(a.y, b.y))
        size = Vector2(abs(a.x - b.x), abs(a.y - b.y))
    }

    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }
    public var centre: Vector2 { origin + size * 0.5 }

    public func contains(_ point: Vector2) -> Bool {
        point.x >= origin.x && point.x <= maxX && point.y >= origin.y && point.y <= maxY
    }

    public func intersects(_ other: CanvasRect) -> Bool {
        origin.x <= other.maxX && other.origin.x <= maxX && origin.y <= other.maxY && other.origin.y <= maxY
    }

    /// This rectangle shifted by `delta`.
    public func moved(by delta: Vector2) -> CanvasRect {
        CanvasRect(origin: origin + delta, size: size)
    }

    /// The smallest rectangle holding both.
    public func union(_ other: CanvasRect) -> CanvasRect {
        CanvasRect(corner: Vector2(min(origin.x, other.origin.x), min(origin.y, other.origin.y)),
                   Vector2(max(maxX, other.maxX), max(maxY, other.maxY)))
    }
}
