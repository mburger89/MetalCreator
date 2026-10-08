extension SketchEntityKind {
    /// The point entities this entity is built on, in declaration order.
    public var referencedPoints: [SketchEntityID] {
        switch self {
        case .point, .projected: []
        case .line(let start, let end): [start, end]
        case .arc(let center, let start, let end): [center, start, end]
        case .circle(let center, _): [center]
        }
    }

    var isPoint: Bool {
        if case .point = self { return true }
        return false
    }
}
