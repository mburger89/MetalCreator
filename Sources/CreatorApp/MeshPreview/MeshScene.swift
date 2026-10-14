import CreatorImplicit
import Foundation

/// What `SceneBuilder` needs to show meshes: the solids that display them, and the refined passes that have replaced the meshes the
/// evaluator made (`MeshRefinementModel`).
struct MeshScene: Sendable {
    let solids: MeshSolids
    /// The finest pass so far for each preview mesh, by the ID of the mesh the evaluator made.
    var refined: [UUID: TriangleMesh] = [:]

    /// The mesh to show for one the evaluator made: its refinement when it has one.
    func shown(_ mesh: TriangleMesh) -> TriangleMesh { refined[mesh.id] ?? mesh }
}
