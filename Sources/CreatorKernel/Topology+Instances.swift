extension Topology {
    /// This topology as copy `item` of a placed tool: every face's tags qualified (`TopoTag.qualified`). Faces,
    /// edges and their order are untouched.
    public func qualified(item: Int, _ qualify: (NodeID) -> NodeID) -> Topology {
        var copy = self
        for index in copy.faces.indices {
            copy.faces[index].tags = Set(copy.faces[index].tags.map { $0.qualified(item: item, qualify) })
        }
        return copy
    }

    /// The copies a pick's `tags` name that this topology has no face of any more, sorted (patterns spec §6): an
    /// instance-qualified tag whose node call (`TopoTag.origin`) no face's tags include, however its role. Empty for
    /// a pick with no such tag, and for tags of an ordinary broadcast item, which this never judges.
    public func vanishedInstances(in tags: Set<TopoTag>) -> [Int] {
        let wanted = TopoTag.instanceTags(in: tags)
        guard !wanted.isEmpty else { return [] }
        let present = Set(TopoTag.instanceTags(in: Set(faces.flatMap(\.tags))).map(\.origin))
        return Set(wanted.filter { !present.contains($0.origin) }.map(\.item)).sorted()
    }
}
