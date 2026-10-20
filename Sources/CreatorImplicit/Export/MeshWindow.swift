/// A piece of a mesh on its way to a file (implicit spec Errata D12): the vertices and triangles of a run of bricks, with each vertex's
/// number in the whole mesh, so a vertex that two windows share is written once. `positions` and `triangles` are the window's own
/// (the triangles index `positions`); `globalIndex[i]` is the number of vertex `i` in the file, and the vertices numbered from
/// `firstNew` up are the ones the file has not seen, in order.
public struct MeshWindow: Sendable {
    public var positions: [SIMD3<Float>]
    public var triangles: [UInt32]
    public var globalIndex: [UInt32]
    public var firstNew: UInt32

    public init(positions: [SIMD3<Float>], triangles: [UInt32], globalIndex: [UInt32], firstNew: UInt32) {
        self.positions = positions
        self.triangles = triangles
        self.globalIndex = globalIndex
        self.firstNew = firstNew
    }

    /// A mesh of its own, all new: its vertices are numbered from `start`, the number of vertices the file already holds.
    public init(positions: [SIMD3<Float>], triangles: [UInt32], startingAt start: Int) {
        self.init(positions: positions, triangles: triangles, globalIndex: positions.indices.map { UInt32(start + $0) },
                  firstNew: UInt32(start))
    }

    public var triangleCount: Int { triangles.count / 3 }
}
