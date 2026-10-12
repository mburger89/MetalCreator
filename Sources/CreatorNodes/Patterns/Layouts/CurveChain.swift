import CreatorGeometry
import CreatorKernel
import Foundation

/// A run of straight and circular pieces joined end to end, to place things along (Curve Pattern, patterns spec §3). Each
/// piece runs the way the chain does; a closed chain ends where it began.
struct CurveChain {
    let pieces: [EdgeCurve]
    let isClosed: Bool
    let length: Double

    init(_ pieces: [EdgeCurve], isClosed: Bool) {
        self.pieces = pieces
        self.isClosed = isClosed
        length = pieces.reduce(0) { $0 + $1.pathLength }
    }

    /// The point `distance` along the chain (held to its ends) and the unit direction the chain runs in there. A point where
    /// two pieces meet runs the way the next one does; the end of an open chain, the way its last piece does. `nil` for a
    /// chain with no pieces.
    func sample(at distance: Double) -> (point: Vector3, tangent: Vector3)? {
        var remaining = min(max(distance, 0), length)
        for (index, piece) in pieces.enumerated() {
            if remaining < piece.pathLength || index == pieces.count - 1 {
                return piece.sample(at: min(remaining, piece.pathLength))
            }
            remaining -= piece.pathLength
        }
        return nil
    }

    /// `count` placements spaced evenly: a closed chain gets them all round without repeating its start; an open one puts the
    /// first at its start and the last at its end (a single one stays at the start).
    func distances(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        if isClosed { return (0..<count).map { length * Double($0) / Double(count) } }
        guard count > 1 else { return [0] }
        return (0..<count).map { length * Double($0) / Double(count - 1) }
    }

    /// How many placements `spacing` apart fit: along an open chain from its start, so one on each whole spacing; round a
    /// closed one, without repeating the start.
    func count(spacing: Double) -> Int {
        guard spacing > 0, length.isFinite else { return 0 }
        let fits = (length / spacing + 1e-9).rounded(.down)
        guard fits < Double(Int.max / 2) else { return Int.max / 2 }
        return isClosed ? max(Int(fits), 1) : Int(fits) + 1
    }

    /// The distances of the placements `spacing` apart.
    func distances(spacing: Double) -> [Double] {
        (0..<count(spacing: spacing)).map { Double($0) * spacing }
    }
}
