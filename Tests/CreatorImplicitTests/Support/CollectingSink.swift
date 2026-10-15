import CreatorImplicit

/// A `MeshSink` that puts the windows back together, for the tests of the streamed export: the whole mesh by global vertex number.
struct CollectingSink: MeshSink {
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var triangles: [UInt32] = []
    private(set) var windows = 0
    private(set) var objects: [String] = []
    private(set) var isFinished = false
    private(set) var isCancelled = false
    var triangleCount: Int { triangles.count / 3 }
    var vertexCount: Int { positions.count }

    mutating func beginObject(name: String) throws {
        objects.append(name)
    }

    mutating func add(_ window: MeshWindow) throws {
        windows += 1
        for (local, global) in window.globalIndex.enumerated() where global >= window.firstNew {
            precondition(Int(global) == positions.count, "new vertices come in order")
            positions.append(window.positions[local])
        }
        triangles += window.triangles.map { window.globalIndex[Int($0)] }
    }

    mutating func endObject() throws {}

    mutating func finish() throws {
        isFinished = true
    }

    mutating func cancel() {
        isCancelled = true
    }

    /// The mesh the windows made.
    var mesh: TriangleMesh { TriangleMesh(positions: positions, triangles: triangles) }
}
