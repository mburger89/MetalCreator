import CreatorGraph
import CreatorImplicit
import Foundation
import Observation

/// The progressive preview of meshes (implicit spec §4.3): the evaluator hands the viewport the first, coarse pass of each Mesh node
/// (`TriangleMesh.source` remembers the implicit and the target), and this meshes the same implicit again with the voxel size halved,
/// pass after pass, until the preview resolution (Auto: the finest that meshes in under a second, estimated from the pass before).
/// Each pass replaces the mesh on screen (`refined`), and an edit cancels the passes running for the meshes it replaced: a mesh that
/// is no longer in the scene (`follow`) has its pass stopped, so the machine works for the shape that is on screen.
@MainActor
@Observable
final class MeshRefinementModel {
    /// What the badge says: the coarsest resolution on screen, and whether some mesh is still being refined.
    struct Badge: Equatable {
        var text: String
        var isRefining: Bool
    }

    /// A mesh's progress.
    struct Status: Equatable {
        var resolution: Double
        var isRefining: Bool
    }

    /// The finest pass so far for each mesh being followed, by the ID of the mesh the evaluator made.
    private(set) var refined: [UUID: TriangleMesh] = [:]
    private(set) var statuses: [UUID: Status] = [:]
    /// Changes whenever a pass arrives or a mesh goes, so the scene follows.
    private(set) var revision = 0

    @ObservationIgnored private let engine: ImplicitEngineChoice
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    init(engine: ImplicitEngineChoice) {
        self.engine = engine
    }

    /// The badge for the meshes on screen: "Preview 0.4 mm" (the coarsest of them) with a spinner while any is refining; `nil` with
    /// none.
    var badge: Badge? {
        guard let coarsest = statuses.values.map(\.resolution).max() else { return nil }
        let size = coarsest.formatted(.number.precision(.fractionLength(0...3)).locale(.messages))
        return Badge(text: "Preview \(size) mm", isRefining: statuses.values.contains { $0.isRefining })
    }

    /// Follows `meshes`, the preview meshes now in the scene: stops the passes of meshes that have gone, forgets their refinements,
    /// and starts refining the new ones. A mesh already followed is left alone.
    func follow(_ meshes: [TriangleMesh]) {
        let ids = Set(meshes.map(\.id))
        var changed = false
        for id in Array(tasks.keys) where !ids.contains(id) {
            tasks[id]?.cancel()
            tasks[id] = nil
        }
        for id in Array(statuses.keys) where !ids.contains(id) {
            statuses[id] = nil
            refined[id] = nil
            changed = true
        }
        for mesh in meshes where statuses[mesh.id] == nil {
            guard let source = mesh.source else { continue }
            statuses[mesh.id] = Status(resolution: mesh.resolution, isRefining: true)
            changed = true
            tasks[mesh.id] = Task { [weak self, engine] in
                await Self.refine(mesh, source: source, engine: engine) { pass, isLast in
                    self?.arrived(pass, for: mesh.id, isLast: isLast)
                }
            }
        }
        if changed { revision += 1 }
    }

    /// Stops everything and forgets it (a new document).
    func reset() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        refined = [:]
        statuses = [:]
        revision += 1
    }

    /// Returns when no mesh is being refined.
    func waitForRefinement() async {
        for task in Array(tasks.values) { await task.value }
    }

    private func arrived(_ pass: TriangleMesh?, for id: UUID, isLast: Bool) {
        guard statuses[id] != nil else { return }
        if let pass {
            refined[id] = pass
            statuses[id] = Status(resolution: pass.resolution, isRefining: !isLast)
        } else {
            statuses[id]?.isRefining = false
        }
        if isLast { tasks[id] = nil }
        revision += 1
    }

    /// Meshes `source` again, finer pass by finer pass, calling `deliver(pass, isLast)` for each; a final `deliver(nil, true)` when a
    /// pass cannot be made. Returns early, delivering nothing more, when the task is cancelled.
    private nonisolated static func refine(_ base: TriangleMesh, source: MeshSource, engine: ImplicitEngineChoice,
                                           deliver: @MainActor @escaping (TriangleMesh?, Bool) -> Void) async {
        let schedule = PreviewSchedule(source.target)
        let selection = await ImplicitEvaluators.make(for: source.solid, choice: engine)
        let mesher = ImplicitMesher(evaluator: selection.evaluator)
        var resolution = base.resolution
        var seconds = base.meshingSeconds
        guard var next = schedule.next(after: resolution, seconds: seconds) else {
            await deliver(nil, true)
            return
        }
        while !Task.isCancelled {
            do {
                let pass = try await mesher.mesh(source.solid, resolution: next, quality: .preview)
                guard !Task.isCancelled else { return }
                (resolution, seconds) = (next, pass.meshingSeconds)
                let following = schedule.next(after: resolution, seconds: seconds)
                await deliver(pass, following == nil)
                guard let following else { return }
                next = following
            } catch is CancellationError {
                return
            } catch {
                // A pass that cannot be made (the shape vanished at this resolution) ends the refinement where it is.
                await deliver(nil, true)
                return
            }
        }
    }
}
