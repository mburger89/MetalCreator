extension SketchEntityKind {
    /// False when the drawn position, radius or projected curve holds NaN or ±∞.
    var isFinite: Bool {
        switch self {
        case .point(let position): position.isFinite
        case .line, .arc: true
        case .circle(_, let radius): radius.isFinite
        case .projected(let source):
            switch source.curve {
            case .line(let a, let b): a.isFinite && b.isFinite
            case .arc(let center, let radius, let start, let end):
                center.isFinite && radius.isFinite && start.radians.isFinite && end.radians.isFinite
            case .circle(let center, let radius): center.isFinite && radius.isFinite
            }
        }
    }
}
