/// What an engine returns for a `BrickMeshRequest`: the mesh as flat arrays (implicit spec Errata D13).
///
/// The triangles are counter-clockwise seen from outside, with one vertex per lattice edge the surface crosses. The order of
/// vertices and triangles is the engine's: the CPU mesher's is the order the bricks and cubes are visited, a GPU's need not be the
/// same twice. The set is what is fixed.
public struct BrickMesh: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    /// One unit normal per vertex, or zero vectors when the request did not snap.
    public var normals: [SIMD3<Float>]
    /// Three indices into `positions` per triangle.
    public var triangles: [UInt32]

    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.triangles = triangles
    }

    /// Whether the arrays fit together: whole triangles, a normal for every vertex, every index in range. The mesher checks it
    /// before it trusts an engine, so a buggy one costs a fall-back to the CPU and not a crash in the viewport.
    public var isConsistent: Bool {
        triangles.count.isMultiple(of: 3) && normals.count == positions.count && triangles.allSatisfy { Int($0) < positions.count }
    }
}
