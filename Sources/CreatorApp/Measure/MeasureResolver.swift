import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Turns a pick into an anchor that names it without a scene, and an anchor back into a pick on the scene as it is now.
/// An anchor resolves on the first scene item where it names exactly one face or edge, and never on a ghost or a guide.
enum MeasureResolver {
    /// How far (mm) a mesh section edge's stored point may lie from a piece and still name it.
    static let meshTolerance = 1.0

    // MARK: - Pick to anchor

    static func anchor(for pick: MeasurePick, in scene: MeasureScene) -> MeasureAnchor? {
        guard scene.solids.indices.contains(pick.solidIndex) else { return nil }
        let solid = scene.solids[pick.solidIndex]
        switch pick {
        case let .face(_, id):
            return solid.topology.facePick(for: id).map(MeasureAnchor.face)
        case let .edge(_, id):
            return solid.topology.picks(for: [id]).first.map(MeasureAnchor.edge)
        case let .corner(_, id, end, _):
            return solid.topology.picks(for: [id]).first.map { MeasureAnchor.corner($0, end) }
        case let .meshPoint(_, point):
            return .meshPoint(point)
        case let .sectionEdge(_, piece, point):
            if solid.displayedMesh != nil { return .meshSectionEdge(point) }
            guard let face = piece.sourceFace, let facePick = solid.topology.facePick(for: face),
                  let part = scene.parts.first(where: { $0.solid === solid }) else { return nil }
            let siblings = part.section.pieces.filter { $0.sourceFace == face }
            guard let index = siblings.firstIndex(of: piece) else { return nil }
            return .sectionEdge(SectionEdgeAnchor(face: facePick, index: index, count: siblings.count,
                                                  midpoint: midpoint(of: piece)))
        }
    }

    // MARK: - Anchor to pick

    /// `solid`, when given, is tried first: two parts built from one feature share tags, and a pick must stay on the part it was made on.
    static func resolve(_ anchor: MeasureAnchor, in scene: MeasureScene, preferring solid: Int? = nil) -> MeasurePick? {
        var shown = scene.solids.indices.filter { index in
            scene.pickable.indices.contains(index) && scene.pickable[index]
        }
        if let solid, let at = shown.firstIndex(of: solid) { shown.insert(shown.remove(at: at), at: 0) }
        switch anchor {
        case let .face(pick):
            return shown.lazy.compactMap { index in
                face(pick, in: scene.solids[index]).map { MeasurePick.face(solid: index, $0) }
            }.first
        case let .edge(pick):
            return shown.lazy.compactMap { index in
                edge(pick, in: scene.solids[index]).map { MeasurePick.edge(solid: index, $0.id) }
            }.first
        case let .corner(pick, end):
            return shown.lazy.compactMap { index -> MeasurePick? in
                guard let found = edge(pick, in: scene.solids[index]), let point = point(of: found, end) else { return nil }
                return .corner(solid: index, found.id, end, at: point)
            }.first
        case let .sectionEdge(target):
            guard scene.plane != nil else { return nil }
            return shown.lazy.compactMap { index in
                sectionPick(target, solid: index, in: scene)
            }.first
        case let .meshSectionEdge(point):
            guard let plane = scene.plane else { return nil }
            let onPlane = point - plane.normal * (point - plane.origin).dot(plane.normal)
            return shown.lazy.compactMap { index in
                meshSectionPick(near: onPlane, solid: index, in: scene)
            }.first
        case let .meshPoint(point):
            return shown.first { scene.solids[$0].displayedMesh != nil }.map { .meshPoint(solid: $0, at: point) }
        }
    }

    /// The mesh resolution behind an approximate pick, if a mesh made it.
    static func meshResolution(of pick: MeasurePick, in scene: MeasureScene) -> Double? {
        switch pick {
        case .meshPoint, .sectionEdge:
            scene.solids.indices.contains(pick.solidIndex) ? scene.solids[pick.solidIndex].displayedMeshResolution : nil
        case .face, .edge, .corner:
            nil
        }
    }

    // MARK: - Pieces

    private static func face(_ pick: FacePick, in solid: Solid) -> FaceID? {
        guard solid.displayedMesh == nil else { return nil }
        let faces = solid.topology.resolution(of: pick).faces
        return faces.count == 1 ? faces[0].id : nil
    }

    /// The one edge a pick names, chosen as `EdgeTagMatch.choose` (CreatorNodes) chooses: what the key resolves to, narrowed by
    /// the pick's ordinals; `nil` unless exactly one is left.
    private static func edge(_ pick: EdgePick, in solid: Solid) -> EdgeInfo? {
        guard solid.displayedMesh == nil,
              solid.topology.vanishedInstances(in: pick.key.first.union(pick.key.second)).isEmpty else { return nil }
        let matches = solid.topology.resolution(of: pick.key, expecting: pick.matchCount).edges
        let chosen = pick.ordinals.map { ordinals in ordinals.filter(matches.indices.contains).map { matches[$0] } } ?? matches
        return chosen.count == 1 ? chosen[0] : nil
    }

    private static func point(of edge: EdgeInfo, _ end: CornerEnd) -> Vector3? {
        switch (edge.curve, end) {
        case let (.circle(center, _, _, _, _)?, .centre): return center
        case (nil, _), (_, .centre): return nil
        case let (curve?, .start): return curve.ends.first
        case let (curve?, .end): return curve.ends.last
        }
    }

    private static func sectionPick(_ target: SectionEdgeAnchor, solid index: Int, in scene: MeasureScene) -> MeasurePick? {
        let solid = scene.solids[index]
        guard let face = face(target.face, in: solid), let part = scene.parts.first(where: { $0.solid === solid }) else { return nil }
        let siblings = part.section.pieces.filter { $0.sourceFace == face }
        guard !siblings.isEmpty else { return nil }
        let piece: SectionPiece
        if siblings.count == target.count, siblings.indices.contains(target.index) {
            piece = siblings[target.index]
        } else {
            let nearest = siblings.min { distance(midpoint(of: $0), target.midpoint) < distance(midpoint(of: $1), target.midpoint) }
            piece = nearest ?? siblings[0]
        }
        return .sectionEdge(solid: index, piece: piece, at: midpoint(of: piece))
    }

    private static func meshSectionPick(near point: Vector3, solid index: Int, in scene: MeasureScene) -> MeasurePick? {
        let solid = scene.solids[index]
        guard solid.displayedMesh != nil, let part = scene.parts.first(where: { $0.solid === solid }) else { return nil }
        var best: (piece: SectionPiece, at: Vector3, distance: Double)?
        for piece in part.section.pieces {
            guard let hit = nearest(to: point, on: piece.polyline), hit.distance <= meshTolerance else { continue }
            if best == nil || hit.distance < best!.distance { best = (piece, hit.point, hit.distance) }
        }
        return best.map { .sectionEdge(solid: index, piece: $0.piece, at: $0.at) }
    }

    // MARK: - Geometry

    private static func distance(_ a: Vector3, _ b: Vector3) -> Double { (a - b).length }

    /// The point halfway along a piece's polyline by length.
    static func midpoint(of piece: SectionPiece) -> Vector3 {
        let line = piece.polyline
        guard let first = line.first else { return .zero }
        let total = zip(line, line.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
        var remaining = total / 2
        for (a, b) in zip(line, line.dropFirst()) {
            let length = distance(a, b)
            if remaining <= length, length > 0 { return a + (b - a) * (remaining / length) }
            remaining -= length
        }
        return line.last ?? first
    }

    private static func nearest(to p: Vector3, on line: [Vector3]) -> (point: Vector3, distance: Double)? {
        var best: (point: Vector3, distance: Double)?
        if line.count == 1 { return (line[0], distance(p, line[0])) }
        for (a, b) in zip(line, line.dropFirst()) {
            let ab = b - a
            let lengthSquared = ab.dot(ab)
            let t = lengthSquared > 0 ? max(0, min(1, (p - a).dot(ab) / lengthSquared)) : 0
            let q = a + ab * t
            let d = distance(p, q)
            if best == nil || d < best!.distance { best = (q, d) }
        }
        return best
    }
}
