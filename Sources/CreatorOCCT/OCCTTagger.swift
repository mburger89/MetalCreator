import CreatorKernel

/// Applies spec §5.3: names every output face from the operation's history.
enum OCCTTagger {
    /// `boundaryRoles` names a sheet builder's boundary edges, one entry per edge in the shape's edge order (`nil`: not
    /// named). `carriesEdgeTags` is for a move (transform, place): output edge n is input 0's edge n, so its tags come
    /// along when the counts agree.
    static func topology(raw: OCCTRawTopology, history: [OCCTHistoryRecord], inputs: [Topology], tag: NodeTag,
                         boundaryRoles: [BoundaryRole?] = [], carriesEdgeTags: Bool = false) -> Topology {
        var tags: [Int: Set<TopoTag>] = [:]
        for record in history where raw.faces.indices.contains(record.outFace) {
            switch record.kind {
            case .startCap:
                tags[record.outFace, default: []].insert(TopoTag(tag, .startCap))
            case .endCap:
                tags[record.outFace, default: []].insert(TopoTag(tag, .endCap))
            case .segment:
                // A segment record's operand is the profile loop (0 = outer), see cocct.h.
                tags[record.outFace, default: []].insert(TopoTag(tag, .side(loop: record.operand, segment: record.index)))
            case .face:
                guard inputs.indices.contains(record.operand),
                      inputs[record.operand].faces.indices.contains(record.index) else { continue }
                tags[record.outFace, default: []].formUnion(inputs[record.operand].faces[record.index].tags)
            case .edge:
                guard inputs.indices.contains(record.operand),
                      let edge = inputs[record.operand].edge(EdgeID(record.index)),
                      let key = inputs[record.operand].key(of: edge) else { continue }
                tags[record.outFace, default: []].insert(TopoTag(tag, .blend(sourceEdge: key)))
            }
        }
        let faces = raw.faces.enumerated().map { index, face in
            FaceInfo(id: FaceID(index), kind: face.kind, normal: face.normal, area: face.area, centroid: face.centroid,
                     tags: tags[index].flatMap { $0.isEmpty ? nil : $0 } ?? [TopoTag(tag, .unnamed(face: index))],
                     radius: face.radius, axisPoint: face.axisPoint, isOnOpenShell: face.isOnOpenShell)
        }
        // Carried edge tags are dropped when the counts differ: only a rigid move (transform, place) carries them.
        let carried = carriesEdgeTags && inputs.count == 1 && inputs[0].edges.count == raw.edges.count ? inputs[0].edges : []
        let edges = raw.edges.enumerated().map { index, edge in
            EdgeInfo(id: EdgeID(index), kind: edge.kind, direction: edge.direction, length: edge.length,
                     midpoint: edge.midpoint, convexity: edge.convexity, faces: edge.faces.map(FaceID.init),
                     curve: edge.curve, tags: edgeTags(at: index, boundaryRoles, carried, tag: tag))
        }
        return Topology(faces: faces, edges: edges)
    }

    private static func edgeTags(at index: Int, _ roles: [BoundaryRole?], _ carried: [EdgeInfo], tag: NodeTag) -> Set<TopoTag> {
        if carried.indices.contains(index) { return carried[index].tags }
        guard roles.indices.contains(index), let role = roles[index] else { return [] }
        return [TopoTag(tag, .boundary(role))]
    }
}
