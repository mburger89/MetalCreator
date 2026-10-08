extension SketchEntityKind {
    /// The same entity with every reference to point `old` changed to `new`.
    func replacingPoint(_ old: SketchEntityID, with new: SketchEntityID) -> SketchEntityKind {
        func swap(_ id: SketchEntityID) -> SketchEntityID { id == old ? new : id }
        return switch self {
        case .point, .projected: self
        case .line(let start, let end): .line(start: swap(start), end: swap(end))
        case .arc(let center, let start, let end): .arc(center: swap(center), start: swap(start), end: swap(end))
        case .circle(let center, let radius): .circle(center: swap(center), radius: radius)
        }
    }
}
