extension Equation {
    /// Every global unknown column the equation reads, in a fixed order (duplicates allowed).
    var columns: [Int] {
        switch self {
        case .coincident(let p, let q), .horizontal(let p, let q), .vertical(let p, let q), .distance(let p, let q, _):
            Self.columns(p) + Self.columns(q)
        case .pointOnLine(let p, let line), .midpoint(let p, let line), .lineDistance(let p, let line, _, _):
            Self.columns(p) + Self.columns(line)
        case .pointOnCircle(let p, let circle):
            Self.columns(p) + Self.columns(circle)
        case .horizontalLine(let line, _), .verticalLine(let line, _):
            Self.columns(line)
        case .parallel(let a, let b, _), .perpendicular(let a, let b, _), .angle(let a, let b, _, _), .equalLength(let a, let b):
            Self.columns(a) + Self.columns(b)
        case .tangentAtPoint(let p, let center, let line):
            Self.columns(p) + Self.columns(center) + Self.columns(line)
        case .lineTangent(let line, let circle, _):
            Self.columns(line) + Self.columns(circle)
        case .circleTangent(let a, let b, _, _), .equalRadius(let a, let b):
            Self.columns(a) + Self.columns(b)
        case .symmetric(let p, let q, let line):
            Self.columns(p) + Self.columns(q) + Self.columns(line)
        case .fix(let p, _), .target(let p, _):
            Self.columns(p)
        case .length(let line, _):
            Self.columns(line)
        case .radius(let circle, _):
            Self.columns(circle)
        case .arcRadius(let center, let start, let end):
            Self.columns(center) + Self.columns(start) + Self.columns(end)
        }
    }

    static func columns(_ point: PointOperand) -> [Int] {
        if case .unknown(let column) = point { return [column, column + 1] }
        return []
    }

    static func columns(_ line: LineOperand) -> [Int] { columns(line.start) + columns(line.end) }

    static func columns(_ circle: CircleOperand) -> [Int] {
        let radius: [Int] = switch circle.radius {
        case .unknown(let column): [column]
        case .constant: []
        case .through(let point): columns(point)
        }
        return columns(circle.center) + radius
    }
}
