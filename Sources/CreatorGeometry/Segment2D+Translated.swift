extension Segment2D {
    /// The same segment moved by `offset` in plane coordinates.
    public func translated(by offset: Vector2) -> Segment2D {
        switch self {
        case .line(let a, let b): .line(a + offset, b + offset)
        case .arc(let center, let radius, let start, let end): .arc(center: center + offset, radius: radius, start: start, end: end)
        }
    }
}
