import CreatorGeometry
import CreatorGraph
import Foundation

/// Where a mesh was made.
public enum MeshingPath: Sendable, Equatable {
    /// By the CPU mesher over the evaluator's values: the reference, and the fall-back.
    case cpu
    /// By the evaluator's GPU engine (Errata D13).
    case gpu
}

/// Meshes an implicit solid by marching cubes over the sparse bricks of a `BrickPlan` (implicit spec §4.3). The mesh is watertight and
/// manifold by construction: the table (`MarchingCubesTable`) draws the same outline on a face from either side, and a vertex on an edge
/// of the lattice is made once, whichever brick or cube reaches it first, by a global key. Each vertex then takes one Newton step
/// towards f = 0 along the gradient (central differences), at most half a voxel, and the gradient gives its normal.
///
/// When the evaluator can mesh bricks itself (`ImplicitBatchEvaluator.meshBricks`, which a GPU engine implements: Errata D13) the
/// bricks go to it and the CPU does none of this; when it cannot, or fails, or returns arrays that do not fit together, the CPU
/// mesher below does, so it is the reference and the fall-back.
public struct ImplicitMesher: Sendable {
    public let evaluator: any ImplicitBatchEvaluator
    public let budget: MeshingBudget
    /// How many bricks are sampled and meshed at a time (implicit spec §4.2).
    public let bricksPerBatch: Int

    public init(evaluator: any ImplicitBatchEvaluator, budget: MeshingBudget = MeshingBudget(), bricksPerBatch: Int = 4096) {
        self.evaluator = evaluator
        self.budget = budget
        self.bricksPerBatch = max(1, bricksPerBatch)
    }

    /// Meshes `solid` with voxels of `resolution` millimetres.
    /// - Parameters:
    ///   - quality: recorded on the mesh. An export is first checked against the memory budget (`MeshingBudget`).
    ///   - snap: whether vertices take the Newton step (tests turn it off to see what it does).
    ///   - source: recorded on the mesh when it is the first pass of a progressive preview, so the viewport can refine it.
    ///   - progress: the fraction done, 0 to 1, from any thread.
    /// - Throws: `ImplicitMeshingError` and `CancellationError`.
    public func mesh(_ solid: ImplicitSolid, resolution: Double, quality: MeshQuality, snap: Bool = true,
                     source: MeshSource? = nil, progress: @Sendable (Double) -> Void = { _ in }) async throws -> TriangleMesh {
        try await meshReportingPath(solid, resolution: resolution, quality: quality, snap: snap, source: source, progress: progress).mesh
    }

    /// `mesh`, and which path made it: the benchmarks and the tests say so, since a fall-back to the CPU is silent.
    public func meshReportingPath(_ solid: ImplicitSolid, resolution: Double, quality: MeshQuality, snap: Bool = true,
                                  source: MeshSource? = nil, progress: @Sendable (Double) -> Void = { _ in })
        async throws -> (mesh: TriangleMesh, path: MeshingPath) {
        let start = ContinuousClock.now
        progress(0)
        if quality == .export { try await budget.check(solid, resolution: resolution, using: evaluator) }
        let plan = try await BrickPlan.build(for: solid, resolution: resolution, using: evaluator)
        guard !plan.bricks.isEmpty else { throw ImplicitMeshingError.empty }
        if let fromEngine = try await evaluator.meshBricks(BrickMeshRequest(plan: plan, snap: snap), progress: progress),
           fromEngine.isConsistent {
            guard !fromEngine.triangles.isEmpty else { throw ImplicitMeshingError.empty }
            progress(1)
            let mesh = TriangleMesh(positions: fromEngine.positions, normals: fromEngine.normals, triangles: fromEngine.triangles,
                                    resolution: resolution, quality: quality, source: source,
                                    meshingSeconds: start.duration(to: .now) / .seconds(1))
            return (mesh, .gpu)
        }
        var builder = MeshBuilder(plan: plan)
        let total = plan.bricks.count
        for start in stride(from: 0, to: total, by: bricksPerBatch) {
            try Task.checkCancellation()
            let bricks = plan.bricks[start..<min(start + bricksPerBatch, total)]
            builder.add(bricks: bricks, samples: try await plan.samples(of: bricks, using: evaluator))
            progress(0.9 * Double(min(start + bricksPerBatch, total)) / Double(total))
        }
        guard !builder.triangles.isEmpty else { throw ImplicitMeshingError.empty }
        var positions = builder.positions
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        if snap { try await Self.snap(&positions, &normals, resolution: resolution, evaluator: evaluator) { progress(0.9 + 0.1 * $0) } }
        progress(1)
        let mesh = TriangleMesh(positions: positions, normals: normals, triangles: builder.triangles, resolution: resolution,
                                quality: quality, source: source, meshingSeconds: start.duration(to: .now) / .seconds(1))
        return (mesh, .cpu)
    }

    /// Moves each vertex one Newton step towards f = 0 and sets its normal from the gradient. The gradient is the central difference
    /// over a quarter of a voxel; the move is limited to half a voxel. `progress` gets the fraction snapped, after each batch.
    private static func snap(_ positions: inout [SIMD3<Float>], _ normals: inout [SIMD3<Float>], resolution: Double,
                             evaluator: any ImplicitBatchEvaluator, progress: (Double) -> Void) async throws {
        let step = Float(resolution / 4)
        let limit = Float(resolution / 2)
        let offsets: [SIMD3<Float>] = [
            SIMD3(step, 0, 0), SIMD3(-step, 0, 0), SIMD3(0, step, 0), SIMD3(0, -step, 0), SIMD3(0, 0, step), SIMD3(0, 0, -step),
        ]
        let batch = 100_000
        for start in stride(from: 0, to: positions.count, by: batch) {
            try Task.checkCancellation()
            let range = start..<min(start + batch, positions.count)
            var points: [SIMD3<Float>] = []
            points.reserveCapacity(range.count * 7)
            for index in range {
                points.append(positions[index])
                for offset in offsets { points.append(positions[index] + offset) }
            }
            let values = try await evaluator.evaluate(points)
            for (slot, index) in range.enumerated() {
                let base = slot * 7
                let gradient = SIMD3((values[base + 1] - values[base + 2]) / (2 * step), (values[base + 3] - values[base + 4]) / (2 * step),
                                     (values[base + 5] - values[base + 6]) / (2 * step))
                let squared = (gradient * gradient).sum()
                guard squared > 1e-12 else { continue }
                normals[index] = gradient / squared.squareRoot()
                var move = gradient * (-values[base] / squared)
                let length = (move * move).sum().squareRoot()
                if length > limit { move *= limit / length }
                positions[index] += move
            }
            progress(Double(range.upperBound) / Double(positions.count))
        }
    }
}

/// Collects the vertices and triangles of the bricks meshed so far.
struct MeshBuilder {
    let plan: BrickPlan
    private(set) var positions: [SIMD3<Float>] = []
    private(set) var triangles: [UInt32] = []
    /// A lattice edge's key → the vertex on it.
    private var vertexOfEdge: [Int: UInt32] = [:]

    init(plan: BrickPlan) {
        self.plan = plan
    }

    /// Meshes the cubes of `bricks`, whose 9³ samples each are in `samples`, brick after brick.
    mutating func add(bricks: ArraySlice<SIMD3<Int32>>, samples: [Float]) {
        let size = BrickPlan.brickSize
        let side = size + 1
        let perBrick = side * side * side
        let latticeX = plan.brickCounts[0] * size + 1, latticeY = plan.brickCounts[1] * size + 1
        var corners = [Float](repeating: 0, count: 8)
        for (number, brick) in bricks.enumerated() {
            let base = number * perBrick
            for z in 0..<size {
                for y in 0..<size {
                    for x in 0..<size {
                        var pattern = 0
                        for corner in 0..<8 {
                            let value = samples[base + ((z + corner >> 2) * side + y + (corner >> 1 & 1)) * side + x + (corner & 1)]
                            corners[corner] = value
                            if value < 0 { pattern |= 1 << corner }
                        }
                        let table = MarchingCubesTable.triangles[pattern]
                        guard !table.isEmpty else { continue }
                        let lattice = SIMD3(Int(brick.x) * size + x, Int(brick.y) * size + y, Int(brick.z) * size + z)
                        for edge in table {
                            let (a, b) = MarchingCubesTable.edgeCorners[Int(edge)]
                            let low = SIMD3(lattice.x + (a & 1), lattice.y + (a >> 1 & 1), lattice.z + (a >> 2 & 1))
                            let axis = (a ^ b) == 1 ? 0 : ((a ^ b) == 2 ? 1 : 2)
                            let key = ((low.z * latticeY + low.y) * latticeX + low.x) * 3 + axis
                            if let existing = vertexOfEdge[key] {
                                triangles.append(existing)
                            } else {
                                let (fa, fb) = (corners[a], corners[b])
                                let t = Double(fa / (fa - fb))
                                let start = plan.point(low.x, low.y, low.z)
                                let step = Vector3(axis == 0 ? 1 : 0, axis == 1 ? 1 : 0, axis == 2 ? 1 : 0) * plan.resolution
                                let point = start + step * t
                                let number = UInt32(positions.count)
                                positions.append(SIMD3(Float(point.x), Float(point.y), Float(point.z)))
                                vertexOfEdge[key] = number
                                triangles.append(number)
                            }
                        }
                    }
                }
            }
        }
    }
}
