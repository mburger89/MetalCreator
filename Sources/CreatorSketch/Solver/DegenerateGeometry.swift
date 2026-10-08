import CreatorGeometry

/// Geometry a solve may reach that meets every residual but is no longer a usable curve: a
/// circle or arc whose radius shrank to nothing or went negative, or an arc that turned inside
/// out (its sweep jumped across a full turn). Such a solution is never accepted (final review).
struct DegenerateGeometry {
    /// A radius at or below this (mm) has shrunk to nothing.
    static let radiusTolerance = 1e-6

    let sketch: Sketch
    let layout: UnknownLayout
    /// The warm start, the arcs' sweeps are compared against.
    let x0: [Double]

    /// A plain sentence for the first degenerate curve the component's `columns` move at `x`
    /// (global unknowns), or `nil` when every curve is sound.
    func reason(at x: [Double], columns: Set<Int>) -> String? {
        func point(_ id: SketchEntityID, _ values: [Double]) -> Vector2? {
            layout.pointColumns[id].map { Vector2(values[$0], values[$0 + 1]) }
        }
        func moves(_ ids: [SketchEntityID]) -> Bool {
            ids.contains { id in layout.pointColumns[id].map { columns.contains($0) || columns.contains($0 + 1) } ?? false }
        }
        for id in sketch.entityIDs {
            switch sketch.entities[id]?.kind {
            case .circle:
                guard let column = layout.radiusColumns[id], columns.contains(column) else { continue }
                if x[column] <= Self.radiusTolerance { return "\(sketch.label(of: id)) would shrink to nothing." }
            case .arc(let center, let start, let end):
                guard moves([center, start, end]), let c = point(center, x), let s = point(start, x), let e = point(end, x),
                      let c0 = point(center, x0), let s0 = point(start, x0), let e0 = point(end, x0) else { continue }
                if (s - c).length <= Self.radiusTolerance || (e - c).length <= Self.radiusTolerance {
                    return "\(sketch.label(of: id)) would shrink to nothing."
                }
                if abs(Self.sweep(c, s, e) - Self.sweep(c0, s0, e0)) > .pi {
                    return "\(sketch.label(of: id)) would turn inside out."
                }
            default:
                continue
            }
        }
        return nil
    }

    /// The counter-clockwise sweep from start to end around the centre, in [0, 2π).
    static func sweep(_ center: Vector2, _ start: Vector2, _ end: Vector2) -> Double {
        SketchMath.wrapped(SketchMath.angle(end - center) - SketchMath.angle(start - center))
    }
}
