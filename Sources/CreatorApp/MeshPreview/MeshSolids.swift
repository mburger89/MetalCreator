import CreatorImplicit
import CreatorKernel
import Foundation
import Synchronization

/// The display solid of each mesh the viewport shows (implicit spec §5.1). A mesh is shown as a `Solid` that holds only its triangles
/// (`Solid(displaying:)`), and the viewport tells solids apart by identity, so a mesh must get the same one every time the scene is
/// rebuilt or the viewport would load it again. The solid lives as long as the scene shows its mesh.
final class MeshSolids: Sendable {
    private let solids = Mutex<[UUID: Solid]>([:])

    /// The solid that shows `mesh`.
    func solid(for mesh: TriangleMesh) -> Solid {
        solids.withLock { solids in
            if let known = solids[mesh.id] { return known }
            let made = Solid(displaying: mesh.displayMesh)
            solids[mesh.id] = made
            return made
        }
    }

    /// Forgets the solids of meshes not in `ids`.
    func keep(_ ids: Set<UUID>) {
        solids.withLock { $0 = $0.filter { ids.contains($0.key) } }
    }

    var count: Int { solids.withLock { $0.count } }
}
