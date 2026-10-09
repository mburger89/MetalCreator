import CreatorGeometry

extension Sketch {
    /// False when any stored number is NaN or ±∞: the plane, a drawn point, radius or projected
    /// curve, a fix target, a dimension value or a warm start. JSON can't store those, so the graph
    /// refuses such a sketch as a setting (S4).
    public var isFinite: Bool {
        if case .fixed(let plane) = plane, !(plane.origin.isFinite && plane.normal.isFinite && plane.xAxis.isFinite) {
            return false
        }
        return entities.values.allSatisfy { $0.kind.isFinite }
            && constraints.values.allSatisfy { constraint in
                if case .fix(_, let at) = constraint { return at.isFinite }
                return true
            }
            && dimensions.values.allSatisfy(\.value.isFinite)
            && solved.values.allSatisfy { state in
                switch state {
                case .point(let point): point.isFinite
                case .radius(let radius): radius.isFinite
                }
            }
    }
}
