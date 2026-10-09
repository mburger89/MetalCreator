import CreatorGeometry
import CreatorSketch

/// The pointer readout while a point is dragged (user, 2026-10-09): the solved values, so it reads what the release
/// keeps (a dimensioned line's length stays put however far the pointer goes), updated every drag step.
/// - The end of exactly one line, which nothing else shares: that line's length and angle, start to end.
/// - The start or end of exactly one arc, which nothing else shares: the arc's radius and sweep.
/// - Anything else (a circle's or arc's centre, a free point, a corner): its position.
///
/// A point is shared (a corner) when more than one curve is built on it, or a coincident constraint joins it to
/// another point, so a point that ends both an arc and a line reads its position: neither curve's values describe
/// the corner, and its position is what both have in common. Other constraints on the point (on a curve, a midpoint,
/// fixed) don't make it shared: they hold it, and its curve's values still read what the drag changes.
extension SketchEditorModel {
    func dragReadout(_ point: SketchEntityID) -> String? {
        guard let position = sketch.position(of: point) else { return nil }
        let curves = sketch.entityIDs.filter { sketch.entities[$0]?.kind.referencedPoints.contains(point) == true }
        let joined = sketch.constraints.values.contains {
            if case .coincident(let a, let b) = $0 { return a == point || b == point }
            return false
        }
        guard curves.count == 1, !joined, let kind = sketch.entities[curves[0]]?.kind else {
            return ReadoutText.position(position)
        }
        switch kind {
        case .line(let start, let end):
            guard let from = sketch.position(of: start), let to = sketch.position(of: end) else { break }
            return ReadoutText.line(from: from, to: to)
        case .arc(let center, let start, let end) where point != center:
            guard let c = sketch.position(of: center), let s = sketch.position(of: start),
                  let e = sketch.position(of: end) else { break }
            return ReadoutText.arc(center: c, start: s, end: e)
        default:
            break
        }
        return ReadoutText.position(position)
    }
}
