import CreatorGeometry

extension Topology {
    /// How far (micrometres) a part may lie from the picked face's plane and still count as in it: a model rebuilt
    /// by OCCT lands within a tiny fraction of this, and a real move is far more.
    static let planeTolerance = 1.0

    /// Every face whose tags include all of `pick`'s, in ID order. An empty pick matches nothing.
    public func faces(matching pick: FacePick) -> [FaceInfo] {
        guard !pick.tags.isEmpty else { return [] }
        return faces.filter { pick.tags.isSubset(of: $0.tags) }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The pick that names face `id`: its whole tag set, and, for a flat face, its normal and centroid. `nil`
    /// for a face that isn't in the table.
    public func facePick(for id: FaceID) -> FacePick? {
        guard let face = face(id) else { return nil }
        return FacePick(tags: face.tags, normal: face.kind == .plane ? face.normal : nil, centroid: face.centroid)
    }

    /// The faces a remembered pick names now: its matches (`faces(matching:)`) or, only when it has none, the
    /// part of its face that is left. A pick on a face a union merged names both operands' tags; when one
    /// operand changes and the faces no longer merge, the pick matches nothing, so it is retried with each
    /// operand's tags alone (`partsByOrigin`). A candidate must face the way the picked face did; the one in the
    /// picked face's plane wins, nearest its centroid first. The answer is unambiguous only when the pick
    /// recorded its position and exactly one candidate lies in that plane. A pick that matches anything is never
    /// narrowed, so a pick that resolves today resolves the same way.
    public func resolution(of pick: FacePick) -> FaceResolution {
        let matches = faces(matching: pick)
        guard matches.isEmpty else { return FaceResolution(faces: matches) }
        var candidates: [FaceInfo] = []
        var seen: Set<FaceID> = []
        for part in pick.tags.partsByOrigin {
            for face in faces(matching: FacePick(tags: part)) where seen.insert(face.id).inserted {
                candidates.append(face)
            }
        }
        if let normal = pick.normal?.normalized {
            candidates = candidates.filter { face in
                face.kind == .plane && (face.normal?.normalized.map { $0.dot(normal) > 1 - 1e-6 } ?? false)
            }
        }
        guard !candidates.isEmpty else { return FaceResolution(faces: []) }
        guard let normal = pick.normal?.normalized, let centroid = pick.centroid else {
            return FaceResolution(faces: [candidates[0]], isNarrowed: true, isAmbiguous: true)
        }
        // Distance from the picked face's plane in micrometres (the model is in millimetres); within
        // `planeTolerance` counts as in the plane, so parts in it tie at 0.
        func offset(_ face: FaceInfo) -> Double {
            let micrometres = abs(normal.dot(face.centroid - centroid)) * 1e3
            return micrometres <= Self.planeTolerance ? 0 : micrometres
        }
        let ranked = candidates.sorted { a, b in
            if offset(a) != offset(b) { return offset(a) < offset(b) }
            let (da, db) = ((a.centroid - centroid).length, (b.centroid - centroid).length)
            return da != db ? da < db : a.id.rawValue < b.id.rawValue
        }
        let inPlane = ranked.filter { offset($0) == 0 }.count
        return FaceResolution(faces: [ranked[0]], isNarrowed: true, isAmbiguous: inPlane != 1)
    }
}
