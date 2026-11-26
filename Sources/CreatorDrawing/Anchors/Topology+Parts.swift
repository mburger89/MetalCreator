import CreatorKernel

extension Topology {
    /// The faces at `range` of `faces` and the edges whose every face lies among them, IDs unchanged (DR-5 R3): one part of a compound.
    public func restricted(toFaces range: Range<Int>) -> Topology {
        let bounded = range.clamped(to: 0..<faces.count)
        let kept = Array(faces[bounded])
        let ids = Set(kept.map(\.id))
        return Topology(faces: kept, edges: edges.filter { !$0.faces.isEmpty && $0.faces.allSatisfy(ids.contains) })
    }
}
