import CreatorGeometry

extension Topology {
    /// How many runs `edges` form: chains of edges that meet end to end (to 1e-6 mm). An edge an operation
    /// split in two is still one run, so a run is what a person picking sees as one edge. An edge whose ends
    /// aren't known (no `curve`, or a full circle) is a run of its own.
    public static func runCount(_ edges: [EdgeInfo]) -> Int {
        var parent = Array(edges.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        let ends = edges.map { $0.curve?.ends ?? [] }
        for i in edges.indices {
            for j in edges.indices where j > i {
                let meet = ends[i].contains { p in ends[j].contains { q in (p - q).length <= 1e-6 } }
                if meet { parent[root(j)] = root(i) }
            }
        }
        return Set(edges.indices.map(root)).count
    }
}
