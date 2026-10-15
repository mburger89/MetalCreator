import CreatorGeometry

/// Meshes an implicit solid straight into a file (implicit spec Errata D12): the bricks the surface passes through are taken in order,
/// a run of whole columns of them at a time (a window), each window is meshed and snapped on its own and handed to a `MeshSink`,
/// and nothing of it is kept but the vertices on the edge it shares with the next window. A whole 0.1 mm lattice is some 150 million
/// triangles; this holds one window of them. The vertices both windows make on the shared plane have the same bits (the samples
/// there are the same numbers, the marching cubes rule and the snap are the same arithmetic), so they are matched by bits and
/// written once, and the file is as watertight as a mesh made whole (`StreamingMesherTests` holds it to the same triangles).
///
/// Each window may be decimated first (`MeshStage.decimate`). A window's open edge is the plane it shares with its neighbour; the
/// decimator pins every vertex on an open edge, so the plane's vertices and edges come out exactly as they went in.
public struct StreamingMesher: Sendable {
    public struct Report: Sendable {
        public var windows = 0
        public var vertices = 0
        public var triangles = 0
        /// The most triangles one window held: what memory scales with.
        public var largestWindow = 0
    }

    public let evaluator: any ImplicitBatchEvaluator
    /// About how many bricks a window holds: whole columns are taken until there are at least this many.
    public let windowBricks: Int
    /// How many bricks are sampled at a time inside a window.
    public let bricksPerBatch: Int

    public init(evaluator: any ImplicitBatchEvaluator, windowBricks: Int = 20_000, bricksPerBatch: Int = 4096) {
        self.evaluator = evaluator
        self.windowBricks = max(1, windowBricks)
        self.bricksPerBatch = max(1, bricksPerBatch)
    }

    /// The vertex a window shares with its neighbour: its bits are its identity.
    private struct VertexKey: Hashable {
        var x: UInt32
        var y: UInt32
        var z: UInt32

        init(_ position: SIMD3<Float>) {
            (x, y, z) = (position.x.bitPattern, position.y.bitPattern, position.z.bitPattern)
        }
    }

    /// Meshes `solid` with voxels of `resolution` millimetres into `sink`, which the caller has begun an object on and will end and
    /// finish. There is no memory refusal: the window is the memory.
    /// - Parameters:
    ///   - stages: applied to each window in order.
    ///   - firstVertex: the number the first new vertex gets: how many vertices the sink's object already holds, when this is not the
    ///     first mesh in it.
    ///   - progress: the fraction of bricks done, 0 to 1.
    /// - Throws: `ImplicitMeshingError` and `CancellationError`.
    public func stream(_ solid: ImplicitSolid, resolution: Double, stages: [MeshStage] = [], startingAt firstVertex: Int = 0,
                       into sink: inout some MeshSink, progress: @Sendable (Double) -> Void = { _ in }) async throws -> Report {
        progress(0)
        let plan = try await BrickPlan.build(for: solid, resolution: resolution, using: evaluator)
        guard !plan.bricks.isEmpty else { throw ImplicitMeshingError.empty }
        var report = Report()
        var carried: [VertexKey: UInt32] = [:]
        var carriedPlane: Int32?
        var done = 0
        for range in windows(of: plan.bricks) {
            try Task.checkCancellation()
            let bricks = plan.bricks[range]
            var (positions, triangles) = try await mesh(bricks, of: plan)
            for stage in stages {
                switch stage {
                case .decimate(let tolerance):
                    let output = try MeshDecimator.decimate(positions: positions, triangles: triangles, tolerance: tolerance)
                    (positions, triangles) = (output.positions, output.triangles)
                }
            }
            let bottom = Int32(bricks.first?.x ?? 0)
            guard !triangles.isEmpty else {
                done += bricks.count
                continue
            }
            let sharing = carriedPlane == bottom ? carried : [:]
            let first = UInt32(firstVertex + report.vertices)
            let window = Self.window(positions: positions, triangles: triangles, matching: sharing, firstNew: first)
            try sink.add(window)
            report.windows += 1
            report.vertices += positions.count - window.globalIndex.filter { $0 < window.firstNew }.count
            report.triangles += window.triangleCount
            report.largestWindow = max(report.largestWindow, window.triangleCount)
            // What the next window may share: the vertices near this one's top plane.
            let top = Int32(bricks.last?.x ?? 0) + 1
            let topX = Float(plan.point(Int(top) * BrickPlan.brickSize, 0, 0).x - 1.5 * resolution)
            carried = [:]
            for (index, position) in window.positions.enumerated() where position.x >= topX {
                carried[VertexKey(position)] = window.globalIndex[index]
            }
            carriedPlane = top
            done += bricks.count
            progress(Double(done) / Double(plan.bricks.count))
        }
        guard report.triangles > 0 else { throw ImplicitMeshingError.empty }
        return report
    }

    /// The runs of whole brick columns (all bricks of one x) that make up the windows, as ranges of the plan's bricks.
    func windows(of bricks: [SIMD3<Int32>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        while start < bricks.count {
            var end = start
            while end < bricks.count {
                let column = bricks[end].x
                while end < bricks.count, bricks[end].x == column { end += 1 }
                if end - start >= windowBricks { break }
            }
            result.append(start..<end)
            start = end
        }
        return result
    }

    /// The marching cubes mesh of `bricks`, its vertices snapped to the surface.
    private func mesh(_ bricks: ArraySlice<SIMD3<Int32>>, of plan: BrickPlan) async throws -> ([SIMD3<Float>], [UInt32]) {
        var builder = MeshBuilder(plan: plan)
        for start in stride(from: bricks.startIndex, to: bricks.endIndex, by: bricksPerBatch) {
            try Task.checkCancellation()
            let batch = bricks[start..<min(start + bricksPerBatch, bricks.endIndex)]
            builder.add(bricks: batch, samples: try await plan.samples(of: batch, using: evaluator))
        }
        var positions = builder.positions
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        try await ImplicitMesher.snap(&positions, &normals, resolution: plan.resolution, evaluator: evaluator) { _ in }
        return (positions, builder.triangles)
    }

    /// The window with its vertices numbered: one that the neighbour already wrote takes the neighbour's number, the others count on
    /// from `firstNew`.
    private static func window(positions: [SIMD3<Float>], triangles: [UInt32], matching shared: [VertexKey: UInt32],
                               firstNew: UInt32) -> MeshWindow {
        var next = firstNew
        var numbers: [UInt32] = []
        numbers.reserveCapacity(positions.count)
        for position in positions {
            if !shared.isEmpty, let known = shared[VertexKey(position)] {
                numbers.append(known)
            } else {
                numbers.append(next)
                next += 1
            }
        }
        return MeshWindow(positions: positions, triangles: triangles, globalIndex: numbers, firstNew: firstNew)
    }
}
