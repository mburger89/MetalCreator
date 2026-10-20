extension TriangleBVH {
    /// The nearest hit of a ray, or `nil` when none is within `limit`. `test(triangle)` returns the distance along the ray at which it
    /// meets that triangle, or `nil`; the walk skips boxes the ray does not reach within the best hit found so far.
    func nearestHit(origin: SIMD3<Double>, direction: SIMD3<Double>, limit: Double, test: (Int) -> Double?) -> Double? {
        guard !nodes.isEmpty else { return nil }
        // A zero component would make 0 × ∞ = NaN in the slab test, so it is a tiny one.
        let safe = SIMD3(direction.x == 0 ? 1e-300 : direction.x, direction.y == 0 ? 1e-300 : direction.y,
                         direction.z == 0 ? 1e-300 : direction.z)
        let inverse = SIMD3<Double>(1, 1, 1) / safe
        var best = limit
        var found = false
        var stack = [0]
        stack.reserveCapacity(64)
        while let index = stack.popLast() {
            let node = nodes[index]
            guard reaches(node, origin: origin, inverse: inverse, within: best) else { continue }
            if node.count > 0 {
                for slot in Int(node.first)..<Int(node.first + node.count) {
                    if let distance = test(Int(order[slot])), distance < best {
                        best = distance
                        found = true
                    }
                }
            } else {
                stack.append(Int(node.first))
                stack.append(Int(node.second))
            }
        }
        return found ? best : nil
    }

    /// The slab test: whether the ray enters the node's box at a distance of at most `limit`.
    private func reaches(_ node: Node, origin: SIMD3<Double>, inverse: SIMD3<Double>, within limit: Double) -> Bool {
        let (a, b) = ((node.low - origin) * inverse, (node.high - origin) * inverse)
        let (near, far) = (pointwiseMin(a, b), pointwiseMax(a, b))
        let entry = max(near.x, near.y, near.z, 0)
        let exit = min(far.x, far.y, far.z)
        return entry <= exit && entry <= limit
    }
}
