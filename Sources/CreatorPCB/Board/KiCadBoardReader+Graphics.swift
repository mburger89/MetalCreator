import CreatorGeometry
import Foundation

extension KiCadBoardReader {
    /// The Edge.Cuts pieces of one `gr_…` or `fp_…` item, placed by `place` (the identity for a board item).
    static func edgeItems(in item: SExpression, place: Placement2D, version: Int) throws -> [EdgeItem] {
        guard let keyword = item.keyword, keyword.hasPrefix("gr_") || keyword.hasPrefix("fp_"),
              item.child("layer")?.text(at: 1) == "Edge.Cuts" else { return [] }
        let kind = String(keyword.dropFirst(3))
        let shapes: [EdgeItem.Shape]
        switch kind {
        case "line": shapes = try line(item, place)
        case "arc": shapes = try arc(item, place, version: version)
        case "circle": shapes = try circle(item, place)
        case "rect": shapes = try rectangle(item, place)
        case "poly": shapes = try polygon(item, place)
        case "curve": shapes = try bezier(item, place)
        default: return []
        }
        let base = identifier(of: item)
        let pieces = kind == "rect" || kind == "poly"
        return shapes.enumerated().map { index, shape in
            var identity = base.map { "edge:\($0)" } ?? "edge:\(kind):\(coordinates(of: shape))"
            if pieces { identity += ":\(index)" }
            return EdgeItem(shape: shape, identity: identity)
        }
    }

    private static func line(_ item: SExpression, _ place: Placement2D) throws -> [EdgeItem.Shape] {
        guard let start = try point(item, "start"), let end = try point(item, "end") else { return [] }
        return [.line(try placed(place, start), try placed(place, end))]
    }

    private static func arc(_ item: SExpression, _ place: Placement2D, version: Int) throws -> [EdgeItem.Shape] {
        if let start = try point(item, "start"), let mid = try point(item, "mid"), let end = try point(item, "end") {
            return [.arc(start: try placed(place, start), mid: try placed(place, mid), end: try placed(place, end))]
        }
        // Legacy (facts §5): `start` is the centre, `end` the first point, `angle` positive clockwise on screen.
        guard version <= KiCadVersion.lastLegacyArcs, let centre = try point(item, "start"), let first = try point(item, "end"),
              let degrees = try number(item.child("angle"), 1), degrees != 0 else { return [] }
        let radial = first - centre
        let last = centre + Placement2D.turn(radial, byDegrees: -degrees)
        let mid = centre + Placement2D.turn(radial, byDegrees: -degrees / 2)
        let (start, end) = degrees < 0 ? (last, first) : (first, last)
        return [.arc(start: try placed(place, start), mid: try placed(place, mid), end: try placed(place, end))]
    }

    private static func circle(_ item: SExpression, _ place: Placement2D) throws -> [EdgeItem.Shape] {
        guard let centre = try point(item, "center"), let edge = try point(item, "end") else { return [] }
        let middle = try placed(place, centre)
        let radius = (try placed(place, edge) - middle).length
        return radius > 0 ? [.circle(center: middle, radius: radius)] : []
    }

    private static func rectangle(_ item: SExpression, _ place: Placement2D) throws -> [EdgeItem.Shape] {
        guard let start = try point(item, "start"), let end = try point(item, "end") else { return [] }
        let corners = try [start, Vector2(end.x, start.y), end, Vector2(start.x, end.y)].map { try placed(place, $0) }
        return (0..<4).map { .line(corners[$0], corners[($0 + 1) % 4]) }
    }

    private static func bezier(_ item: SExpression, _ place: Placement2D) throws -> [EdgeItem.Shape] {
        let points = try item.child("pts")?.children("xy").compactMap { try point($0) } ?? []
        guard points.count == 4 else { return [] }
        let moved = try points.map { try placed(place, $0) }
        return [.bezier(moved[0], moved[1], moved[2], moved[3])]
    }

    /// The outline of a polygon: lines between its points and arcs, closed.
    private static func polygon(_ item: SExpression, _ place: Placement2D) throws -> [EdgeItem.Shape] {
        guard case .list(let entries)? = item.child("pts") else { return [] }
        var shapes: [EdgeItem.Shape] = []
        var first: Vector2?
        var current: Vector2?
        func join(to target: Vector2) {
            if let current, current != target { shapes.append(.line(current, target)) }
            if first == nil { first = target }
        }
        for entry in entries {
            switch entry.keyword {
            case "xy":
                guard let local = try point(entry) else { continue }
                let target = try placed(place, local)
                join(to: target)
                current = target
            case "arc":
                guard let start = try point(entry, "start"), let mid = try point(entry, "mid"),
                      let end = try point(entry, "end") else { continue }
                let placedStart = try placed(place, start), placedEnd = try placed(place, end)
                join(to: placedStart)
                shapes.append(.arc(start: placedStart, mid: try placed(place, mid), end: placedEnd))
                current = placedEnd
            default:
                continue
            }
        }
        if let current, let first, current != first { shapes.append(.line(current, first)) }
        return shapes
    }

    // MARK: Identity

    /// Coordinates to 1 nm, for an item that has no uuid or tstamp.
    private static func coordinates(of shape: EdgeItem.Shape) -> String {
        func text(_ point: Vector2) -> String { "\(nanometres(point.x)),\(nanometres(point.y))" }
        switch shape {
        case .line(let start, let end): return "\(text(start)):\(text(end))"
        case .arc(let start, let mid, let end): return "\(text(start)):\(text(mid)):\(text(end))"
        case .circle(let centre, let radius): return "\(text(centre)):\(nanometres(radius))"
        case .bezier(let a, let b, let c, let d): return "\(text(a)):\(text(b)):\(text(c)):\(text(d))"
        }
    }

    private static func nanometres(_ value: Double) -> Int {
        Int((value * 1e6).rounded())
    }
}
