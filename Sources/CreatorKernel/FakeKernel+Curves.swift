import CreatorGeometry
import Foundation

extension FakeKernel {
    /// A curve over `pieces`. Geometry is approximate (a spline is its control polygon) but the joins are checked exactly.
    public func makeCurve(_ pieces: [CurvePiece], tag: NodeTag) throws -> Curve {
        try Task.checkCancellation()
        operationLog.append("makeCurve")
        guard !pieces.isEmpty else { throw KernelError.invalidInput("A curve needs at least one piece.") }
        for case .spline(let spline) in pieces where !spline.isWellFormed { throw KernelError.malformedSpline }
        for (a, b) in zip(pieces, pieces.dropFirst()) where (a.end - b.start).length > 1e-6 {
            throw KernelError.invalidInput("The curve's pieces don't join end to end.")
        }
        for case .arc(let center, let normal, let radius, let start, _) in pieces {
            let unit = normal.normalized ?? .unitZ
            if abs((start - center).length - radius) > 1e-6 || abs(unit.dot(start - center)) > 1e-6 {
                throw KernelError.invalidInput("The arc's start isn't on its circle.")
            }
        }
        var points: [Vector3] = [pieces[0].start]
        var length = 0.0
        for piece in pieces {
            let (samples, pieceLength) = Self.sample(piece)
            points.append(contentsOf: samples)
            length += pieceLength
        }
        let isClosed = (pieces[pieces.count - 1].end - pieces[0].start).length <= 1e-6
        let bounds = BoundingBox(points: points) ?? BoundingBox(min: .zero, max: .zero)
        return Curve(pieceCount: pieces.count, isClosed: isClosed, plane: Self.commonPlane(of: points), length: length,
                     bounds: bounds, polyline: points, storage: FakeStorage())
    }

    /// The points after a piece's start (its end last) and its length.
    private static func sample(_ piece: CurvePiece) -> ([Vector3], Double) {
        switch piece {
        case .line(let a, let b): return ([b], (b - a).length)
        case .arc(let center, let normal, let radius, let start, let sweep):
            let steps = max(1, Int((abs(sweep) / 0.5).rounded(.up)))
            let points = (1...steps).map { i in
                CurvePiece.rotate(start - center, about: normal, by: sweep * Double(i) / Double(steps)) + center
            }
            return (points, radius * abs(sweep))
        case .spline(let curve):
            let polygon = Array(curve.poles.dropFirst())
            return (polygon, zip(curve.poles, polygon).reduce(0) { $0 + ($1.1 - $1.0).length })
        }
    }

    /// The plane through `points` when they all lie in one and aren't collinear, else `nil`.
    private static func commonPlane(of points: [Vector3]) -> Plane? {
        guard let origin = points.first else { return nil }
        var normal: Vector3?
        var xAxis: Vector3?
        for p in points.dropFirst() {
            let d = p - origin
            guard d.length > 1e-9 else { continue }
            guard let first = xAxis else { xAxis = d.normalized; continue }
            if let n = first.cross(d).normalized { normal = n; break }
        }
        guard let normal, let xAxis else { return nil }
        let scale = max(1, points.map { ($0 - origin).length }.max() ?? 1)
        guard points.allSatisfy({ abs(normal.dot($0 - origin)) <= 1e-9 * scale }) else { return nil }
        return Plane(origin: origin, normal: normal, xAxis: xAxis)
    }
}
