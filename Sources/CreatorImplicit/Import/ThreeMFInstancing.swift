import CreatorGraph
import Foundation

/// Counting and making the meshes of a model's build items (mesh import spec, Limits and Construction). A small file can nest
/// components into billions of triangles, so the triangles after instancing are counted first, per object and remembered, which
/// makes the count as long as the file and not as long as the product; nothing is instantiated until the total is under the limit.
/// Both walks keep their own stack, so a file cannot overflow the thread's.
extension ThreeMFModel {
    /// The deepest chain of components accepted, counted in components from a build item's object.
    static let maximumNesting = 32

    private static let cancellationInterval = 1 << 16

    private static func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? .max : sum
    }

    /// The triangles each object makes once its components are placed, in `Int` (saturating, so 10^32 reads as `Int.max`). Refuses a
    /// component that contains itself and nesting deeper than `maximumNesting`.
    func instancedCounts(reachableFrom roots: [Int]) throws -> [Int] {
        var counts = objects.map(\.triangleCount)
        var heights = [Int](repeating: 0, count: objects.count)
        var state = [UInt8](repeating: 0, count: objects.count)  // 0 not seen, 1 on the stack, 2 finished
        for root in roots where state[root] == 0 {
            var stack: [(object: Int, next: Int)] = [(root, 0)]
            state[root] = 1
            while let top = stack.last {
                let object = objects[top.object]
                guard top.next < object.componentCount else {
                    state[top.object] = 2
                    stack.removeLast()
                    if let parent = stack.last {
                        counts[parent.object] = Self.saturatingAdd(counts[parent.object], counts[top.object])
                        heights[parent.object] = max(heights[parent.object], heights[top.object] + 1)
                    }
                    continue
                }
                stack[stack.count - 1].next += 1
                let child = components[object.componentStart + top.next].object
                switch state[child] {
                case 1: throw MeshImportProblem.malformedModel("a component contains itself.")
                case 2:
                    counts[top.object] = Self.saturatingAdd(counts[top.object], counts[child])
                    heights[top.object] = max(heights[top.object], heights[child] + 1)
                default:
                    guard stack.count <= Self.maximumNesting else {
                        throw MeshImportProblem.malformedModel("its components nest too deeply.")
                    }
                    state[child] = 1
                    stack.append((child, 0))
                }
            }
            guard heights[root] <= Self.maximumNesting else { throw MeshImportProblem.malformedModel("its components nest too deeply.") }
        }
        return counts
    }

    /// The meshes of the build items: one per item that has triangles, each its object's tree placed, welded by exact position.
    func buildMeshes(triangleLimit: Int, isCancelled: () -> Bool) throws -> [ImportedMesh] {
        let counts = try instancedCounts(reachableFrom: items.map(\.object))
        var total = 0
        for item in items { total = Self.saturatingAdd(total, counts[item.object]) }
        guard total <= triangleLimit else { throw MeshImportProblem.tooManyTriangles(total) }
        var meshes: [ImportedMesh] = []
        var work = 0
        for item in items where counts[item.object] > 0 {
            var corners: [SIMD3<Float>] = []
            corners.reserveCapacity(3 * counts[item.object])
            let transform = item.transform < 0 ? ThreeMFTransform.identity : transforms[item.transform]
            try place(item.object, transform, counts: counts, into: &corners, work: &work, isCancelled: isCancelled)
            let welded = ExactWeld.weld(corners: corners)
            guard !welded.triangles.isEmpty else { continue }
            meshes.append(ImportedMesh(mesh: TriangleMesh(positions: welded.positions, triangles: welded.triangles),
                                       droppedTriangles: welded.dropped, unit: unit, ignoredExtras: ignoredExtras))
        }
        return meshes
    }

    /// Appends the corners of `root` and everything under it, moved by `transform`, three per triangle. A mirror reverses the winding so
    /// the part stays right side out. A subtree with no triangles is not entered.
    private func place(_ root: Int, _ transform: ThreeMFTransform, counts: [Int], into corners: inout [SIMD3<Float>],
                       work: inout Int, isCancelled: () -> Bool) throws {
        var stack: [(object: Int, next: Int, transform: ThreeMFTransform)] = [(root, 0, transform)]
        var moved: [SIMD3<Float>] = []
        try emit(root, transform, into: &corners, moved: &moved, work: &work, isCancelled: isCancelled)
        while let top = stack.last {
            let object = objects[top.object]
            guard top.next < object.componentCount else {
                stack.removeLast()
                continue
            }
            stack[stack.count - 1].next += 1
            let component = components[object.componentStart + top.next]
            guard counts[component.object] > 0 else { continue }
            let own = component.transform < 0 ? ThreeMFTransform.identity : transforms[component.transform]
            let composed = own.then(top.transform)
            try emit(component.object, composed, into: &corners, moved: &moved, work: &work, isCancelled: isCancelled)
            stack.append((component.object, 0, composed))
        }
    }

    private func emit(_ index: Int, _ transform: ThreeMFTransform, into corners: inout [SIMD3<Float>], moved: inout [SIMD3<Float>],
                      work: inout Int, isCancelled: () -> Bool) throws {
        let object = objects[index]
        guard object.triangleCount > 0 else { return }
        moved.removeAll(keepingCapacity: true)
        moved.reserveCapacity(object.vertexCount)
        for vertex in vertices[object.vertexStart..<(object.vertexStart + object.vertexCount)] {
            if work % Self.cancellationInterval == 0, isCancelled() { throw CancellationError() }
            work += 1
            let p = transform.apply(SIMD3(Double(vertex.x), Double(vertex.y), Double(vertex.z)))
            let narrowed = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            guard narrowed.x.isFinite, narrowed.y.isFinite, narrowed.z.isFinite else { throw MeshImportProblem.coordinatesOverflow }
            moved.append(narrowed)
        }
        let mirrored = transform.determinant < 0
        let first = object.triangleStart * 3
        for base in stride(from: first, to: first + object.triangleCount * 3, by: 3) {
            if work % Self.cancellationInterval == 0, isCancelled() { throw CancellationError() }
            work += 1
            let (a, b, c) = (Int(triangles[base]), Int(triangles[base + 1]), Int(triangles[base + 2]))
            corners.append(moved[a])
            corners.append(moved[mirrored ? c : b])
            corners.append(moved[mirrored ? b : c])
        }
    }
}
