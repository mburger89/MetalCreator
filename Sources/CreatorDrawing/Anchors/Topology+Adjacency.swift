import CreatorKernel

extension Topology {
    /// The edges that border `face`, in edge order. A seam lists its face twice and is included once.
    public func edges(of face: FaceID) -> [EdgeInfo] {
        edges.filter { $0.faces.contains(face) }
    }
}
