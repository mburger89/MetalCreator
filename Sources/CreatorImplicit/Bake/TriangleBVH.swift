/// A bounding volume hierarchy over triangles (implicit spec §4.4): a binary tree of boxes, split at the median of the triangles'
/// centres along the longest axis, with at most four triangles in a leaf. It answers "which triangle is nearest to this point" by
/// walking the tree nearest box first and skipping boxes farther than the best found.
struct TriangleBVH: Sendable {
    struct Node: Sendable {
        var low: SIMD3<Double>
        var high: SIMD3<Double>
        /// For a leaf the index of its first triangle in `order`, else the index of the left child.
        var first: Int32
        /// For an inner node the index of the right child.
        var second: Int32
        /// The number of triangles in a leaf; 0 for an inner node.
        var count: Int32
    }

    private(set) var nodes: [Node] = []
    /// Triangle numbers in leaf order.
    private(set) var order: [Int32] = []

    private static let leafSize = 4

    init(vertices: [SIMD3<Double>], triangles: [SIMD3<Int32>]) {
        order = triangles.indices.map(Int32.init)
        guard !triangles.isEmpty else { return }
        let boxes = triangles.map { triangle -> (low: SIMD3<Double>, high: SIMD3<Double>, centre: SIMD3<Double>) in
            let (a, b, c) = (vertices[Int(triangle.x)], vertices[Int(triangle.y)], vertices[Int(triangle.z)])
            let low = pointwiseMin(a, pointwiseMin(b, c)), high = pointwiseMax(a, pointwiseMax(b, c))
            return (low, high, (a + b + c) / 3)
        }
        nodes.reserveCapacity(2 * triangles.count / Self.leafSize + 1)
        _ = build(range: 0..<triangles.count, boxes: boxes)
    }

    /// Builds the subtree over `order[range]` and returns its node's index.
    private mutating func build(range: Range<Int>, boxes: [(low: SIMD3<Double>, high: SIMD3<Double>, centre: SIMD3<Double>)]) -> Int {
        var low = SIMD3<Double>(repeating: .infinity), high = SIMD3<Double>(repeating: -.infinity)
        var centreLow = low, centreHigh = high
        for slot in range {
            let box = boxes[Int(order[slot])]
            low = pointwiseMin(low, box.low)
            high = pointwiseMax(high, box.high)
            centreLow = pointwiseMin(centreLow, box.centre)
            centreHigh = pointwiseMax(centreHigh, box.centre)
        }
        let index = nodes.count
        nodes.append(Node(low: low, high: high, first: Int32(range.lowerBound), second: 0, count: Int32(range.count)))
        guard range.count > Self.leafSize else { return index }
        let spread = centreHigh - centreLow
        let axis = spread.x >= spread.y && spread.x >= spread.z ? 0 : (spread.y >= spread.z ? 1 : 2)
        let middle = range.lowerBound + range.count / 2
        // Ties on the centre are broken by triangle number, so the build is the same on every run.
        order[range].sort { lhs, rhs in
            let (a, b) = (boxes[Int(lhs)].centre[axis], boxes[Int(rhs)].centre[axis])
            return a == b ? lhs < rhs : a < b
        }
        let left = build(range: range.lowerBound..<middle, boxes: boxes)
        let right = build(range: middle..<range.upperBound, boxes: boxes)
        nodes[index].first = Int32(left)
        nodes[index].second = Int32(right)
        nodes[index].count = 0
        return index
    }

    /// The squared distance from `point` to a node's box.
    private func boxDistanceSquared(_ node: Node, _ point: SIMD3<Double>) -> Double {
        let outside = pointwiseMax(pointwiseMax(node.low - point, point - node.high), .zero)
        return (outside * outside).sum()
    }

    /// Calls `visit(triangle)` for the triangles whose boxes could hold something nearer than `bound()`, nearest box first. `visit`
    /// returns nothing; the caller tightens what `bound()` returns as it finds closer triangles.
    func search(from point: SIMD3<Double>, bound: () -> Double, visit: (Int) -> Void) {
        guard !nodes.isEmpty else { return }
        var stack: [Int] = [0]
        stack.reserveCapacity(64)
        while let index = stack.popLast() {
            let node = nodes[index]
            guard boxDistanceSquared(node, point) < bound() else { continue }
            if node.count > 0 {
                for slot in Int(node.first)..<Int(node.first + node.count) { visit(Int(order[slot])) }
            } else {
                let (left, right) = (Int(node.first), Int(node.second))
                // Push the farther child first, so the nearer is searched first.
                if boxDistanceSquared(nodes[left], point) <= boxDistanceSquared(nodes[right], point) {
                    stack.append(right)
                    stack.append(left)
                } else {
                    stack.append(left)
                    stack.append(right)
                }
            }
        }
    }
}
