import CreatorGeometry
import CreatorKernel

extension OCCTKernel {
    /// Removes the material on the removed side of `cutter`'s line (DR-3 R1): the removed prism is built with `extrude`, then one
    /// serialized subtract, face count and validity check. A line that misses the part returns it; one that swallows it gives `nil`.
    public func cutAway(_ solid: Solid, by cutter: SectionCutter, tag: NodeTag) async throws -> Solid? {
        try await cutAwayNoting(solid, by: cutter, tag: tag).solid
    }

    public static let sheetLeftOutSentence = "The sheet beside a part couldn't be cut, so it's left out of this section."

    public func cutAwayNoting(_ solid: Solid, by cutter: SectionCutter, tag: NodeTag) async throws
        -> (solid: Solid?, warnings: [String]) {
        try Task.checkCancellation()
        try cutter.validate()
        try cutter.frame.validate()
        let frame = cutter.frame
        let bounds = solid.bounds
        let corners = Self.boxCorners(bounds)
        let placed = corners.map { frame.place($0) }
        let across = (placed + cutter.points).reduce(into: (low: Vector2(.infinity, .infinity), high: Vector2(-.infinity, -.infinity))) {
            $0.low = Vector2(min($0.low.x, $1.x), min($0.low.y, $1.y))
            $0.high = Vector2(max($0.high.x, $1.x), max($0.high.y, $1.y))
        }
        let reach = 2 * (across.high - across.low).length + 1
        let polygon = cutter.removedPolygon(reach: reach)
        switch Self.coverage(of: placed, by: polygon) {
        case .inside: return (nil, [])
        case .outside: return (solid, [])
        case .partial: break
        }
        let depths = corners.map { $0.dot(frame.direction) }
        guard let near = depths.min(), let far = depths.max() else { return (solid, []) }
        let plane = Plane(origin: frame.direction * bounds.center.dot(frame.direction), normal: frame.direction * -1,
                          xAxis: frame.right)
        let segments = polygon.indices.map { Segment2D.line(polygon[$0], polygon[($0 + 1) % polygon.count]) }
        let tool = try await extrude(Profile2D(plane: plane, segments: segments), distance: far - near + 2, mode: .symmetric, tag: tag)
        if solid.hasOpenShell && solid.holdsClosedSolid {
            return try await cutMixed(solid, by: cutter, tool: tool, tag: tag)
        }
        if solid.hasOpenShell {
            return (try await cutSheet(solid, by: tool, frame: frame, removed: polygon, tag: tag), [])
        }
        return (try await subtract(tool, from: solid, tag: tag), [])
    }

    /// R18: a closed solid beside a sheet. `occt_boolean` would lose the sheet, so the value is divided by shell kind (the sheets'
    /// faces through `subSheet`, the solids' sewn back into solids, which keeps each face's own tags), each part is cut on its own
    /// and the remainders are compounded. Either part may vanish; both vanishing gives `nil`.
    private func cutMixed(_ mixed: Solid, by cutter: SectionCutter, tool: Solid, tag: NodeTag) async throws
        -> (solid: Solid?, warnings: [String]) {
        let sheetFaces = mixed.topology.faces.filter(\.isOnOpenShell).map(\.id)
        let solidFaces = mixed.topology.faces.filter { !$0.isOnOpenShell }.map(\.id)
        let sheets = try subSheet(sheetFaces, of: mixed)
        let shell = try subSheet(solidFaces, of: mixed)
        let body: Solid?
        do {
            let sewn = try await sewn([shell], tolerance: 1e-6, tag: tag)
            body = sewn.sheets == 0 && sewn.solids > 0 ? sewn.body : nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            body = nil
        }
        guard let body else {
            // The solid part doesn't re-sew (a stray free edge): cut the value as before, which keeps the solid and drops the sheet.
            return (try await subtract(tool, from: mixed, tag: tag), [Self.sheetLeftOutSentence])
        }
        var parts: [Solid] = []
        if let part = try await cutAway(body, by: cutter, tag: tag) { parts.append(part) }
        if let part = try await cutAway(sheets, by: cutter, tag: tag) { parts.append(part) }
        switch parts.count {
        case 0: return (nil, [])
        case 1: return (parts[0], [])
        default: return (try compound(parts, tag: tag), [])
        }
    }

    private func subtract(_ tool: Solid, from solid: Solid, tag: NodeTag) async throws -> Solid? {
        let target = try shape(of: solid)
        let cutter = try shape(of: tool)
        let outcome: CutOutcome
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure. Revert once fixed.
            outcome = try Self.serialized { () throws -> CutOutcome in
                do {
                    let (shape, history) = try OCCTShape.boolean(.subtract, target, [cutter])
                    guard shape.faceCount > 0 else { return .empty }
                    return shape.isValid ? .cut(shape, history) : .invalid
                } catch let error as OCCTError where error.message == "the result is empty" {
                    return .empty
                }
            }
        } catch is OCCTError {
            throw Self.cutFailure
        }
        try Task.checkCancellation()
        switch outcome {
        case .empty: return nil
        case .invalid: throw Self.cutFailure
        case .cut(let shape, let history):
            return try self.solid(from: shape, history: history, inputs: [solid.topology, tool.topology], tag: tag,
                                  operation: "section")
        }
    }

    private enum CutOutcome {
        case cut(OCCTShape, [OCCTHistoryRecord])
        case empty
        case invalid
    }

    /// A value of sheets only: `occt_boolean` needs a solid, so the sheet is split by the prism (NS-4's body cutter) and the faces
    /// outside it kept.
    private func cutSheet(_ sheet: Solid, by tool: Solid, frame: ProjectionFrame, removed: [Vector2],
                          tag: NodeTag) async throws -> Solid? {
        let split: SheetSplit
        do {
            split = try await self.split(sheet, by: .body(tool), tag: tag)
        } catch let error as KernelError {
            // The splitter refuses when the prism divides nothing (the line misses a sheet that only its bounding rectangle
            // meets): then each face lies wholly on one side, which a point on that face tells (never a centroid, which can
            // lie off a non-convex or curved face).
            guard case .invalidInput(let message) = error, message == Self.noCutMessage else { throw Self.cutFailure }
            return try keepingFacesOutside(sheet, removed: removed, frame: frame)
        } catch is OCCTError {
            throw Self.cutFailure
        }
        try Task.checkCancellation()
        guard let inside = split.inside else { throw Self.cutFailure }
        let kept = split.whole.topology.faces.indices.map { FaceID($0) }.filter { !inside.contains($0) }
        if kept.isEmpty { return nil }
        if inside.isEmpty { return sheet }
        return try subSheet(kept, of: split.whole)
    }

    /// The faces of `sheet` whose own points lie outside `removed`, as a sheet; `nil` when none do.
    private func keepingFacesOutside(_ sheet: Solid, removed: [Vector2], frame: ProjectionFrame) throws -> Solid? {
        let mesh = try tessellate(sheet, tolerance: 0.1, angle: DisplayAngle.standard)
        let edges = removed.indices.map { (removed[$0], removed[($0 + 1) % removed.count]) }
        var onFace: [FaceID: [Vector2]] = [:]
        for (triangle, face) in mesh.triangleFaces.enumerated() {
            for corner in 0..<3 {
                let index = Int(mesh.indices[triangle * 3 + corner])
                onFace[face, default: []].append(frame.place(mesh.positions[index]))
            }
        }
        var kept: [FaceID] = []
        for face in sheet.topology.faces {
            // A point on the line itself decides nothing; take one clear of it.
            guard let point = onFace[face.id]?.first(where: { Self.distance(from: $0, to: edges) > 1e-6 }) else {
                throw Self.cutFailure
            }
            if !Self.contains(removed, point) { kept.append(face.id) }
        }
        if kept.isEmpty { return nil }
        if kept.count == sheet.topology.faces.count { return sheet }
        return try subSheet(kept, of: sheet)
    }

    private static let noCutMessage = "The cutter doesn't cut the surface."

    private static var cutFailure: KernelError {
        .operationFailed(operation: "section", reason: "the section couldn't be cut through this part.")
    }

    private static func boxCorners(_ box: BoundingBox) -> [Vector3] {
        var corners: [Vector3] = []
        for x in [box.min.x, box.max.x] {
            for y in [box.min.y, box.max.y] {
                for z in [box.min.z, box.max.z] { corners.append(Vector3(x, y, z)) }
            }
        }
        return corners
    }

    enum Coverage { case inside, outside, partial }

    /// Whether the rectangle bounding `points` lies wholly inside `polygon`, wholly outside it, or neither (or cannot tell).
    static func coverage(of points: [Vector2], by polygon: [Vector2]) -> Coverage {
        guard let first = points.first, polygon.count >= 3 else { return .partial }
        var low = first, high = first
        for p in points {
            low = Vector2(min(low.x, p.x), min(low.y, p.y))
            high = Vector2(max(high.x, p.x), max(high.y, p.y))
        }
        let rectangle = [low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]
        let edges = polygon.indices.map { (polygon[$0], polygon[($0 + 1) % polygon.count]) }
        let sides = rectangle.indices.map { (rectangle[$0], rectangle[($0 + 1) % 4]) }
        let crosses = edges.contains { edge in sides.contains { segmentsMeet(edge, $0) } }
        let cornersInside = rectangle.map { contains(polygon, $0) }
        if !crosses, cornersInside.allSatisfy({ $0 }), rectangle.allSatisfy({ distance(from: $0, to: edges) > 1e-9 }) {
            return .inside
        }
        let vertexInRectangle = polygon.contains {
            $0.x >= low.x - 1e-9 && $0.x <= high.x + 1e-9 && $0.y >= low.y - 1e-9 && $0.y <= high.y + 1e-9
        }
        if !crosses, !vertexInRectangle, !cornersInside.contains(true) { return .outside }
        return .partial
    }

    private static func contains(_ polygon: [Vector2], _ point: Vector2) -> Bool {
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

    private static func distance(from point: Vector2, to edges: [(Vector2, Vector2)]) -> Double {
        edges.map { edge -> Double in
            let along = edge.1 - edge.0
            let lengthSquared = along.x * along.x + along.y * along.y
            let dot = (point.x - edge.0.x) * along.x + (point.y - edge.0.y) * along.y
            let t = lengthSquared > 0 ? max(0, min(1, dot / lengthSquared)) : 0
            return (point - (edge.0 + along * t)).length
        }.min() ?? .infinity
    }

    /// Whether two closed segments touch (touching counts, so a doubtful case reaches the boolean).
    private static func segmentsMeet(_ a: (Vector2, Vector2), _ b: (Vector2, Vector2)) -> Bool {
        func cross(_ o: Vector2, _ p: Vector2, _ q: Vector2) -> Double { (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x) }
        func onSegment(_ s: (Vector2, Vector2), _ p: Vector2) -> Bool {
            p.x >= min(s.0.x, s.1.x) - 1e-9 && p.x <= max(s.0.x, s.1.x) + 1e-9
                && p.y >= min(s.0.y, s.1.y) - 1e-9 && p.y <= max(s.0.y, s.1.y) + 1e-9
        }
        let d1 = cross(b.0, b.1, a.0), d2 = cross(b.0, b.1, a.1)
        let d3 = cross(a.0, a.1, b.0), d4 = cross(a.0, a.1, b.1)
        if ((d1 > 1e-12 && d2 < -1e-12) || (d1 < -1e-12 && d2 > 1e-12)) && ((d3 > 1e-12 && d4 < -1e-12) || (d3 < -1e-12 && d4 > 1e-12)) {
            return true
        }
        return (abs(d1) <= 1e-12 && onSegment(b, a.0)) || (abs(d2) <= 1e-12 && onSegment(b, a.1))
            || (abs(d3) <= 1e-12 && onSegment(a, b.0)) || (abs(d4) <= 1e-12 && onSegment(a, b.1))
    }
}
