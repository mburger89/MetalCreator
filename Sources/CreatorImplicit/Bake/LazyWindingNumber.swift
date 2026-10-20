import Synchronization

/// A `WindingNumber` that is built on the first question and not before (Errata D18). Its clusters cost build time and about 80 bytes a
/// BVH node, and To Implicit's bake, which only asks for the pseudonormal sign, never needs them.
final class LazyWindingNumber: Sendable {
    private let vertices: [SIMD3<Double>]
    private let triangles: [SIMD3<Int32>]
    private let bvh: TriangleBVH
    private let built = Mutex<WindingNumber?>(nil)

    /// `bvh` must have been built over the same `vertices` and `triangles`.
    init(vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>], bvh: TriangleBVH) {
        self.vertices = vertices
        self.triangles = triangles
        self.bvh = bvh
    }

    /// Whether anyone has asked yet.
    var isBuilt: Bool { built.withLock { $0 != nil } }

    /// The winding number, built by the first caller while the others wait. It is returned by value (arrays are shared), so queries
    /// run outside the lock.
    var number: WindingNumber {
        built.withLock { slot in
            if let made = slot { return made }
            let made = WindingNumber(vertices: vertices, triangles: triangles, bvh: bvh)
            slot = made
            return made
        }
    }
}
