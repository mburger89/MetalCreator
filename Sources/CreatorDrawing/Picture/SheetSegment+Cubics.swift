import CreatorGeometry
import Foundation

/// One cubic Bezier piece of an arc or ellipse.
public struct CubicPiece: Hashable, Sendable {
    public var start: Vector2
    public var control1: Vector2
    public var control2: Vector2
    public var end: Vector2

    public init(start: Vector2, control1: Vector2, control2: Vector2, end: Vector2) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }
}

extension SheetSegment {
    /// An arc or ellipse as cubic Beziers of at most 90 degrees each, control length 4/3 tan(θ/4). The screen and
    /// both writers use this one function (plan R12). Lines and polylines give none.
    public func cubics() -> [CubicPiece] {
        switch self {
        case let .arc(center, radius, start, sweep):
            return Self.cubics(center: center, u: Vector2(1, 0), major: radius, minor: radius, start: start, sweep: sweep)
        case let .ellipse(center, axis, major, minor, start, sweep):
            let length = axis.length
            let u = length > 0 ? Vector2(axis.x / length, axis.y / length) : Vector2(1, 0)
            return Self.cubics(center: center, u: u, major: major, minor: minor, start: start, sweep: sweep)
        case .line, .polyline:
            return []
        }
    }

    private static func cubics(
        center: Vector2, u: Vector2, major: Double, minor: Double, start: Double, sweep: Double
    ) -> [CubicPiece] {
        guard sweep != 0 else { return [] }
        let count = max(1, Int((abs(sweep) / (.pi / 2) - 1e-9).rounded(.up)))
        let theta = sweep / Double(count)
        let k = 4.0 / 3.0 * tan(theta / 4)
        let v = Vector2(-u.y, u.x)
        func point(_ t: Double) -> Vector2 {
            let c = cos(t) * major, s = sin(t) * minor
            return Vector2(center.x + u.x * c + v.x * s, center.y + u.y * c + v.y * s)
        }
        func tangent(_ t: Double) -> Vector2 {
            let c = -sin(t) * major, s = cos(t) * minor
            return Vector2(u.x * c + v.x * s, u.y * c + v.y * s)
        }
        var pieces: [CubicPiece] = []
        for index in 0..<count {
            let a = start + Double(index) * theta
            let b = a + theta
            let p0 = point(a), p3 = point(b)
            pieces.append(CubicPiece(start: p0, control1: p0 + tangent(a) * k, control2: p3 - tangent(b) * k, end: p3))
        }
        return pieces
    }
}
