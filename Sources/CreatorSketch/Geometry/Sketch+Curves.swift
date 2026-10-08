import CreatorGeometry

extension Sketch {
    /// The current shape of a line, arc, circle or projected edge (from `solved`, else drawn),
    /// or `nil` for points, suspended projections and degenerate curves.
    func shape(of id: SketchEntityID) -> CurveShape? {
        switch entities[id]?.kind {
        case .line(let start, let end):
            guard let a = position(of: start), let b = position(of: end), (b - a).length > CurveIntersection.tolerance else { return nil }
            return .line(a, b)
        case .arc(let center, let start, let end):
            guard let c = position(of: center), let s = position(of: start), let e = position(of: end) else { return nil }
            let radius = (s - c).length
            let from = SketchMath.angle(s - c)
            let sweep = SketchMath.wrapped(SketchMath.angle(e - c) - from)
            guard radius > CurveIntersection.tolerance, sweep * radius > CurveIntersection.tolerance else { return nil }
            return .arc(center: c, radius: radius, start: from, sweep: sweep)
        case .circle(let center, _):
            guard let c = position(of: center), let radius = radius(of: id), radius > CurveIntersection.tolerance else { return nil }
            return .arc(center: c, radius: radius, start: 0, sweep: CurveShape.fullTurn)
        case .projected(let source):
            guard !source.isSuspended else { return nil }
            switch source.curve {
            case .line(let a, let b):
                return (b - a).length > CurveIntersection.tolerance ? .line(a, b) : nil
            case .arc(let center, let radius, let start, let end):
                let sweep = end.radians - start.radians
                guard radius > 0, sweep > 0 else { return nil }
                return .arc(center: center, radius: radius, start: start.radians, sweep: min(sweep, CurveShape.fullTurn))
            case .circle(let center, let radius):
                return radius > 0 ? .arc(center: center, radius: radius, start: 0, sweep: CurveShape.fullTurn) : nil
            }
        default:
            return nil
        }
    }

    /// Every curve in ID order, optionally leaving out construction geometry.
    func curves(includingConstruction: Bool) -> [SketchCurve] {
        entityIDs.compactMap { id in
            guard let entity = entities[id], includingConstruction || !entity.isConstruction,
                  let shape = shape(of: id) else { return nil }
            return SketchCurve(source: id, shape: shape)
        }
    }
}
