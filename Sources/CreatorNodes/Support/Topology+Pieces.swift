import CreatorKernel

extension Topology {
    /// How many separate pieces the faces form: faces joined by a shared edge are one piece.
    /// A kernel result with more than one piece is a multi-body compound (spec §11).
    var pieceCount: Int {
        var parent = Array(faces.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        let position = Dictionary(faces.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for edge in edges where edge.faces.count == 2 {
            guard let a = position[edge.faces[0]], let b = position[edge.faces[1]] else { continue }
            parent[root(a)] = root(b)
        }
        return Set(faces.indices.map(root)).count
    }
}
