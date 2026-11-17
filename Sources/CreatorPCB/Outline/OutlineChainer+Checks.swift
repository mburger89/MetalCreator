import CreatorGeometry

extension OutlineChainer {
    // MARK: Checks

    struct Shape {
        let loop: Int
        let index: Int
        let count: Int
        let points: [Vector2]
        let minX: Double, maxX: Double, minY: Double, maxY: Double
    }

    static func makeShapes(_ loops: [[Piece]]) -> (shapes: [Shape], selfCrossings: [Vector2]) {
        var shapes: [Shape] = []
        var crossings: [Vector2] = []
        for (loopIndex, loop) in loops.enumerated() {
            for (index, piece) in loop.enumerated() {
                let points = ArcGeometry.polyline(piece.segment)
                let xs = points.map(\.x), ys = points.map(\.y)
                shapes.append(Shape(loop: loopIndex, index: index, count: loop.count, points: points,
                                    minX: xs.min() ?? 0, maxX: xs.max() ?? 0, minY: ys.min() ?? 0, maxY: ys.max() ?? 0))
                if case .spline = piece.segment, let point = selfCrossing(points) { crossings.append(point) }
            }
        }
        return (shapes, crossings)
    }

    static func rejectCrossings(_ loops: [[Piece]], isCancelled: () -> Bool = { false }) throws {
        var steps = 0
        var found: Vector2?
        func note(_ point: Vector2) {
            let rounded = Vector2((point.x * 1e6).rounded() / 1e6 + 0, (point.y * 1e6).rounded() / 1e6 + 0)
            if found == nil || lexicographically(rounded, found!) { found = rounded }
        }
        let (shapes, selfCrossings) = makeShapes(loops)
        selfCrossings.forEach(note)
        let order = shapes.indices.sorted { shapes[$0].minX < shapes[$1].minX }
        for (position, i) in order.enumerated() {
            let a = shapes[i]
            for j in order[(position + 1)...] {
                try tick(&steps, isCancelled)
                let b = shapes[j]
                if b.minX > a.maxX + exact { break }
                if b.minY > a.maxY + exact || b.maxY < a.minY - exact { continue }
                if a.loop == b.loop {
                    let gap = abs(a.index - b.index)
                    if gap == 1 || gap == a.count - 1 { continue }
                }
                if let point = firstIntersection(a.points, b.points) { note(point) }
            }
        }
        if let found { throw crosses(at: found) }
    }

    static func selfCrossing(_ points: [Vector2]) -> Vector2? {
        guard points.count > 3 else { return nil }
        for i in 0..<(points.count - 1) {
            for j in stride(from: i + 2, to: points.count - 1, by: 1) {
                if let point = intersection(points[i], points[i + 1], points[j], points[j + 1]) { return point }
            }
        }
        return nil
    }

    static func firstIntersection(_ a: [Vector2], _ b: [Vector2]) -> Vector2? {
        for i in 0..<(a.count - 1) {
            for j in 0..<(b.count - 1) {
                if let point = intersection(a[i], a[i + 1], b[j], b[j + 1]) { return point }
            }
        }
        return nil
    }

    /// Where the closed segments p to p2 and q to q2 meet, nil when parallel or apart.
    static func intersection(_ p: Vector2, _ p2: Vector2, _ q: Vector2, _ q2: Vector2) -> Vector2? {
        let r = p2 - p, s = q2 - q
        let denominator = r.x * s.y - r.y * s.x
        let offset = q - p
        guard abs(denominator) > 1e-14 else { return overlap(p, r, q, q2) }
        let t = (offset.x * s.y - offset.y * s.x) / denominator
        let u = (offset.x * r.y - offset.y * r.x) / denominator
        guard t >= -exact, t <= 1 + exact, u >= -exact, u <= 1 + exact else { return nil }
        return p + r * t
    }

    /// The start of the stretch two parallel segments share, nil unless they lie on one line and share more than a point.
    static func overlap(_ p: Vector2, _ r: Vector2, _ q: Vector2, _ q2: Vector2) -> Vector2? {
        let length = r.length
        guard length > 1e-12 else { return nil }
        let offset = q - p
        guard abs(offset.x * r.y - offset.y * r.x) / length <= exact,
              abs((q2 - p).x * r.y - (q2 - p).y * r.x) / length <= exact else { return nil }
        let t0 = (offset.x * r.x + offset.y * r.y) / (length * length)
        let t1 = ((q2 - p).x * r.x + (q2 - p).y * r.y) / (length * length)
        let low = max(0, min(t0, t1)), high = min(1, max(t0, t1))
        guard (high - low) * length > exact else { return nil }
        return p + r * low
    }

    static func requireInside(_ holes: [[Piece]], of outer: [Piece], isCancelled: () -> Bool = { false }) throws {
        var steps = 0
        var polygon: [Vector2] = []
        for piece in outer { polygon += ArcGeometry.polyline(piece.segment) }
        let outerBox = box(of: polygon)
        for hole in holes {
            for piece in hole {
                try tick(&steps, isCancelled)
                if !outerBox.contains(piece.start) || !contains(polygon, piece.start) {
                    throw KiCadProblem("A cutout lies outside the board outline near \(coordinates(piece.start)) mm.")
                }
            }
        }
        let polygons = holes.map { hole in hole.flatMap { ArcGeometry.polyline($0.segment) } }
        let boxes = polygons.map(box(of:))
        for (index, hole) in holes.enumerated() {
            for (other, shape) in polygons.enumerated() where other != index {
                try tick(&steps, isCancelled)
                if boxes[other].contains(hole[0].start), contains(shape, hole[0].start) {
                    throw KiCadProblem("The board outline has a piece inside a cutout near \(coordinates(hole[0].start)) mm, "
                        + "which isn't supported.")
                }
            }
        }
    }

    struct Box {
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity

        func contains(_ point: Vector2) -> Bool {
            point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    static func box(of points: [Vector2]) -> Box {
        var result = Box()
        for point in points {
            result.minX = min(result.minX, point.x)
            result.maxX = max(result.maxX, point.x)
            result.minY = min(result.minY, point.y)
            result.maxY = max(result.maxY, point.y)
        }
        return result
    }

    static func contains(_ polygon: [Vector2], _ point: Vector2) -> Bool {
        var inside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            if (current.y > point.y) != (previous.y > point.y),
               point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }
}
