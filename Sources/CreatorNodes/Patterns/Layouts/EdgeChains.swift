import CreatorGeometry
import CreatorKernel
import Foundation

/// Joins straight and circular curves into chains (Curve Pattern, patterns spec §3): curves that meet at an end, within
/// `tolerance`, belong to one chain, which runs from one end to the other. Deterministic: the curves are taken in the order
/// given, a chain starts at the first curve with a free end (else the first of all), and at a junction the first curve
/// that continues wins, so a branching set falls into several chains rather than failing.
enum EdgeChains {
    /// How close two ends must be to meet, in millimetres.
    static let tolerance = 1e-4

    static func chains(of curves: [EdgeCurve]) -> [CurveChain] {
        // How many curve ends touch each curve's start and end: 1 (itself) means the end is free.
        let touching: [(start: Int, end: Int)] = curves.map { curve in
            guard !curve.isFullCircle else { return (0, 0) }
            let others = curves.filter { !$0.isFullCircle }
            let count = { (point: Vector3) in
                others.reduce(0) { $0 + (meets($1.startPoint, point) ? 1 : 0) + (meets($1.endPoint, point) ? 1 : 0) }
            }
            return (count(curve.startPoint), count(curve.endPoint))
        }
        var used: Set<Int> = []
        var chains: [CurveChain] = []
        while let first = curves.indices.first(where: { !used.contains($0) }) {
            let free = curves.indices.first { index in
                !used.contains(index) && !curves[index].isFullCircle && (touching[index].start == 1 || touching[index].end == 1)
            }
            let begin = free ?? first
            used.insert(begin)
            guard !curves[begin].isFullCircle else {
                chains.append(CurveChain([curves[begin]], isClosed: true))
                continue
            }
            var pieces = [touching[begin].end == 1 && touching[begin].start != 1 ? curves[begin].reversed : curves[begin]]
            while let tail = pieces.last?.endPoint,
                  let next = curves.indices.first(where: { index in
                      !used.contains(index) && !curves[index].isFullCircle
                          && (meets(curves[index].startPoint, tail) || meets(curves[index].endPoint, tail))
                  }) {
                used.insert(next)
                pieces.append(meets(curves[next].startPoint, tail) ? curves[next] : curves[next].reversed)
            }
            let closes = pieces.count > 1 && pieces.first.map { meets($0.startPoint, pieces[pieces.count - 1].endPoint) } == true
            chains.append(CurveChain(pieces, isClosed: closes))
        }
        return chains
    }

    /// The chains of a profile's loops, outline first and then each hole: a loop is a chain already, closed when its last
    /// segment ends where its first begins.
    static func chains(of profile: Profile2D) -> [CurveChain] {
        profile.loops.filter { !$0.isEmpty }.map { loop in
            let pieces = loop.map { segment -> EdgeCurve in
                switch segment {
                case .line(let a, let b):
                    return .line(start: profile.plane.point(a), end: profile.plane.point(b))
                case .arc(let center, let radius, let start, let end):
                    let startPoint = center + Vector2(cos(start.radians), sin(start.radians)) * radius
                    return .circle(center: profile.plane.point(center), axis: profile.plane.normal, radius: radius,
                                   start: profile.plane.point(startPoint), sweep: end.radians - start.radians)
                }
            }
            let closes = pieces.first.map { meets($0.startPoint, pieces[pieces.count - 1].endPoint) } == true
            return CurveChain(pieces, isClosed: closes)
        }
    }

    private static func meets(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= tolerance }
}
