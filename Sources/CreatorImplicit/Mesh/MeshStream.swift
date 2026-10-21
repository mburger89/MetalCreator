import CreatorGraph
import CreatorKernel
import Foundation

/// A mesh that is not made yet (implicit spec Errata D12): what a Mesh node returns while an export streams to its file. It is the
/// implicit solid, the voxel size to mesh it at, and the stages (Decimate) to apply to every window on the way; nothing is meshed
/// until the writer takes it, one window at a time. The mesh tools that change the surface add a stage; the ones that need the whole
/// mesh take a copy of it (`checkCopy`, `materialized`).
public struct MeshStream: MeshPayload, Hashable, Sendable {
    public var solid: ImplicitSolid
    public var resolution: Double
    public var stages: [MeshStage]
    /// The check copy made for this stream, shared by every copy of the value (and so by the checks one after another in a run). It is
    /// not part of what the stream is: two streams that mesh the same way are equal.
    private let copies = CheckCopies()

    public init(solid: ImplicitSolid, resolution: Double, stages: [MeshStage] = []) {
        self.solid = solid
        self.resolution = resolution
        self.stages = stages
    }

    public static func == (lhs: MeshStream, rhs: MeshStream) -> Bool {
        lhs.solid == rhs.solid && lhs.resolution == rhs.resolution && lhs.stages == rhs.stages
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(solid)
        hasher.combine(resolution)
        hasher.combine(stages)
    }

    /// The count is not known until it is written.
    public var triangleCount: Int { 0 }

    public var estimatedBytes: Int { 256 }

    public var inspectorFacts: [PayloadFact] {
        let size = resolution.formatted(.number.precision(.fractionLength(0...3)).locale(.messages))
        var facts = [PayloadFact("Export", "Streamed to the file at \(size) mm")]
        for case .decimate(let tolerance) in stages {
            let size = tolerance.formatted(.number.precision(.fractionLength(0...4)).locale(.messages))
            facts.append(PayloadFact("Decimate", "within \(size) mm"))
        }
        return facts
    }

    /// This stream with one more stage.
    public func appending(_ stage: MeshStage) -> MeshStream {
        var next = self
        next.stages.append(stage)
        return next
    }

    /// Lets go of the check copy, which a stream keeps so that the checks that follow one another in a run mesh the part once. The
    /// export calls this before it writes, so the copy is not held while the file streams.
    public func releaseCheckCopy() {
        copies.clear()
    }

    public enum Failure: Error, Equatable, Sendable {
        /// The stream has `count` triangles, more than the limit that was asked for.
        case tooManyTriangles(Int)
    }

    /// The stream as one mesh in memory, stages applied. Past `limit` triangles it counts them (without keeping any) and throws
    /// `Failure.tooManyTriangles` with the count.
    public func materialized(limit: Int, using evaluator: any ImplicitBatchEvaluator,
                             progress: @Sendable (Double) -> Void = { _ in }) async throws -> TriangleMesh {
        let mesher = StreamingMesher(evaluator: evaluator)
        var collector = MeshCollector(limit: limit)
        let start = ContinuousClock.now
        do {
            _ = try await mesher.stream(solid, resolution: resolution, stages: stages, into: &collector, progress: progress)
        } catch is MeshCollector.Overflow {
            var counter = MeshCounter()
            _ = try await mesher.stream(solid, resolution: resolution, stages: stages, into: &counter)
            throw Failure.tooManyTriangles(counter.triangleCount)
        }
        return TriangleMesh(positions: collector.positions, triangles: collector.triangles, resolution: resolution, quality: .export,
                            meshingSeconds: start.duration(to: .now) / .seconds(1))
    }

    /// A mesh of the solid for a check, which needs the whole surface in memory: at the stream's resolution when that is at most
    /// `triangleBudget` triangles (the check is exact), else as much coarser as brings it there (`isExact` is false and the warning
    /// says so). The stages are not applied: a decimated surface is within its tolerance of this one.
    public func checkCopy(using evaluator: any ImplicitBatchEvaluator,
                          triangleBudget: Int = 2_000_000) async throws -> (mesh: TriangleMesh, isExact: Bool) {
        // The same solid at the same resolution meshes the same way, so a second check takes the first one's copy.
        if let made = copies.copy(for: triangleBudget) { return made }
        let bytes = try await MeshingBudget.estimate(for: solid, resolution: resolution, using: evaluator)
        // The estimate counts about 100 bytes a triangle.
        let triangles = max(bytes / 100, 1)
        var used = resolution
        if triangles > triangleBudget {
            used = (resolution * (Double(triangles) / Double(triangleBudget)).squareRoot() * 100).rounded(.up) / 100
        }
        let mesh = try await ImplicitMesher(evaluator: evaluator).mesh(solid, resolution: used, quality: .preview)
        let made = (mesh: mesh, isExact: used == resolution)
        copies.keep(made, for: triangleBudget)
        return made
    }
}

/// The check copy of a `MeshStream`: one mesh, kept for as long as the checks that follow one another need it.
private final class CheckCopies: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: (budget: Int, mesh: TriangleMesh, isExact: Bool)?

    func copy(for budget: Int) -> (mesh: TriangleMesh, isExact: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard let kept, kept.budget == budget else { return nil }
        return (kept.mesh, kept.isExact)
    }

    func keep(_ made: (mesh: TriangleMesh, isExact: Bool), for budget: Int) {
        lock.lock()
        kept = (budget, made.mesh, made.isExact)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        kept = nil
        lock.unlock()
    }
}
