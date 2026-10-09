extension Topology {
    /// Every face whose tags include all of `pick`'s, in ID order. An empty pick matches nothing.
    public func faces(matching pick: FacePick) -> [FaceInfo] {
        guard !pick.tags.isEmpty else { return [] }
        return faces.filter { pick.tags.isSubset(of: $0.tags) }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// The pick that names face `id`: its whole tag set. `nil` for a face that isn't in the table.
    public func facePick(for id: FaceID) -> FacePick? {
        face(id).map { FacePick(tags: $0.tags) }
    }
}
