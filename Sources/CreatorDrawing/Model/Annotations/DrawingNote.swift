import CreatorGeometry

/// A leader's far end: what it points at, and where it pointed last (a point on the view's model plane, mm).
public struct LeaderEnd: Hashable, Codable, Sendable {
    public var target: AnchorTarget
    public var hint: Vector2

    public init(target: AnchorTarget, hint: Vector2) {
        self.target = target
        self.hint = hint
    }
}

/// A text note; `position` is the block's top-left, relative to its view's centre or absolute on the sheet (plan R7).
public struct DrawingNote: Hashable, Codable, Sendable {
    public var text: String
    public var position: Vector2
    public var leaders: [LeaderEnd]

    public init(text: String, position: Vector2, leaders: [LeaderEnd] = []) {
        self.text = text
        self.position = position
        self.leaders = leaders
    }
}
