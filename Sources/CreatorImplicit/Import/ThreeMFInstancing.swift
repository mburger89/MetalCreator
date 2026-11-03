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

    /// The triangles each object makes once its components are placed, in `Int` (saturating, so 10^32 reads as `Int.max`), and
    /// whether a support structure was left out on the way. Refuses a component that contains itself and nesting deeper than
    /// `maximumNesting`. Support structures count as nothing, and nothing under them is visited.
    func instancedCounts(reachableFrom roots: [Int]) throws -> (counts: [Int], leftOutSupports: Bool) {
        var counts = objects.map { $0.leftOut ? 0 : $0.triangleCount }
        var heights = [Int](repeating: 0, count: objects.count)
        var state = [UInt8](repeating: 0, count: objects.count)  // 0 not seen, 1 on the stack, 2 finished
        var leftOut = false
        for root in roots where state[root] == 0 {
            guard !objects[root].leftOut else {
                leftOut = true
                continue
            }
            var stack: [(object: Int, next: Int)] = [(root, 0)]
            state[root] = 1
            while let top = stack.last {
                let object = objects[top.object]
                guard top.next < object.componentCount else {
                    state[top.object] = 2
                    stack.removeLast()
                    if let parent = stack.last { absorb(top.object, into: parent.object, counts: &counts, heights: &heights) }
                    continue
                }
                stack[stack.count - 1].next += 1
                let child = components[object.componentStart + top.next].object
                if objects[child].leftOut {
                    leftOut = true
                    continue
                }
                switch state[child] {
                case 1: throw MeshImportProblem.malformedModel("a component contains itself.")
                case 2:
                    absorb(child, into: top.object, counts: &counts, heights: &heights)
                default:
                    try Self.requireNesting(stack.count)
                    state[child] = 1
                    stack.append((child, 0))
                }
            }
            try Self.requireNesting(heights[root])
        }
        return (counts, leftOut)
    }

    private static func requireNesting(_ depth: Int) throws {
        guard depth <= maximumNesting else { throw MeshImportProblem.malformedModel("its components nest too deeply.") }
    }

    private func absorb(_ child: Int, into parent: Int, counts: inout [Int], heights: inout [Int]) {
        counts[parent] = Self.saturatingAdd(counts[parent], counts[child])
        heights[parent] = max(heights[parent], heights[child] + 1)
    }

    /// The components of each object that make any triangle, as indices into `components`, so a placement visits only parts that add
    /// to its output: its work is bounded by the triangles it makes, not by how many empty parts a file lists. `start[i]..<start[i + 1]`
    /// is object `i`'s run.
    private func liveComponents(counts: [Int]) -> (start: [Int], indices: [Int]) {
        var start = [Int](repeating: 0, count: objects.count + 1)
        var indices: [Int] = []
        for (index, object) in objects.enumerated() {
            start[index] = indices.count
            guard counts[index] > 0 else { continue }
            for component in object.componentStart..<(object.componentStart + object.componentCount)
            where counts[components[component].object] > 0 {
                indices.append(component)
            }
        }
        start[objects.count] = indices.count
        return (start, indices)
    }

    /// The meshes of the build items: one per item that has triangles, each its object's tree placed, welded by exact position.
    func buildMeshes(limits: ThreeMFLimits, isCancelled: () -> Bool) throws -> [ImportedMesh] {
        let (counts, leftOutSupports) = try instancedCounts(reachableFrom: items.map(\.object))
        var total = 0
        for item in items { total = Self.saturatingAdd(total, counts[item.object]) }
        guard total <= limits.triangles else {
            throw total == .max ? MeshImportProblem.overTriangleLimit : MeshImportProblem.tooManyTriangles(total)
        }
        let live = liveComponents(counts: counts)
        var meshes: [ImportedMesh] = []
        var work = 0
        for item in items where counts[item.object] > 0 {
            var corners: [SIMD3<Float>] = []
            corners.reserveCapacity(3 * counts[item.object])
            let transform = item.transform < 0 ? ThreeMFTransform.identity : transforms[item.transform]
            try place(item.object, transform, live: live, into: &corners, work: &work, isCancelled: isCancelled)
            let welded = ExactWeld.weld(corners: corners)
            guard !welded.triangles.isEmpty else { continue }
            meshes.append(ImportedMesh(mesh: TriangleMesh(positions: welded.positions, triangles: welded.triangles),
                                       droppedTriangles: welded.dropped, unit: unit, ignoredExtras: ignoredExtras,
                                       supportsLeftOut: leftOutSupports))
        }
        return meshes
    }

    /// Appends the corners of `root` and everything under it, moved by `transform`, three per triangle. A mirror reverses the winding so
    /// the part stays right side out. Only parts that make triangles are entered.
    private func place(_ root: Int, _ transform: ThreeMFTransform, live: (start: [Int], indices: [Int]),
                       into corners: inout [SIMD3<Float>], work: inout Int, isCancelled: () -> Bool) throws {
        var stack: [(object: Int, next: Int, transform: ThreeMFTransform)] = [(root, 0, transform)]
        try emit(root, transform, into: &corners, work: &work, isCancelled: isCancelled)
        while let top = stack.last {
            let position = live.start[top.object] + top.next
            guard position < live.start[top.object + 1] else {
                stack.removeLast()
                continue
            }
            stack[stack.count - 1].next += 1
            if work % Self.cancellationInterval == 0, isCancelled() { throw CancellationError() }
            work += 1
            let component = components[live.indices[position]]
            let own = component.transform < 0 ? ThreeMFTransform.identity : transforms[component.transform]
            let composed = own.then(top.transform)
            try emit(component.object, composed, into: &corners, work: &work, isCancelled: isCancelled)
            stack.append((component.object, 0, composed))
        }
    }

    /// The object's own triangles through `transform`. Each corner is moved when it is used, so the work is the triangles made, however
    /// many vertices the object lists.
    private func emit(_ index: Int, _ transform: ThreeMFTransform, into corners: inout [SIMD3<Float>], work: inout Int,
                      isCancelled: () -> Bool) throws {
        let object = objects[index]
        guard object.triangleCount > 0 else { return }
        let mirrored = transform.determinant < 0
        func moved(_ local: UInt32) throws -> SIMD3<Float> {
            let v = vertices[object.vertexStart + Int(local)]
            let p = transform.apply(SIMD3(Double(v.x), Double(v.y), Double(v.z)))
            let narrowed = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z))
            guard narrowed.x.isFinite, narrowed.y.isFinite, narrowed.z.isFinite else { throw MeshImportProblem.coordinatesOverflow }
            return narrowed
        }
        let first = object.triangleStart * 3
        for base in stride(from: first, to: first + object.triangleCount * 3, by: 3) {
            if work % Self.cancellationInterval == 0, isCancelled() { throw CancellationError() }
            work += 1
            corners.append(try moved(triangles[base]))
            corners.append(try moved(triangles[base + (mirrored ? 2 : 1)]))
            corners.append(try moved(triangles[base + (mirrored ? 1 : 2)]))
        }
    }
}
