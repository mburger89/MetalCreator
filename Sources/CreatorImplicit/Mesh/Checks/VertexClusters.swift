/// Union-find over vertex numbers: which vertices belong to the same place.
struct VertexClusters {
    private var parent: [Int32]

    init(count: Int) {
        parent = (0..<count).map(Int32.init)
    }

    mutating func root(of vertex: Int) -> Int {
        var current = vertex
        while Int(parent[current]) != current {
            parent[current] = parent[Int(parent[current])]
            current = Int(parent[current])
        }
        return current
    }

    mutating func join(_ a: Int, _ b: Int) {
        let (rootA, rootB) = (root(of: a), root(of: b))
        if rootA != rootB { parent[max(rootA, rootB)] = Int32(min(rootA, rootB)) }
    }
}
