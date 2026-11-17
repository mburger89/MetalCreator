import CreatorImplicit
import CreatorKernel
import CreatorViewport
import Foundation
import Synchronization

/// The display solid of each mesh the viewport shows (implicit spec §5.1). A mesh is shown as a `Solid` that holds only its triangles
/// (`Solid(displaying:)`), and the viewport tells solids apart by identity, so a mesh must get the same one every time the scene is
/// rebuilt or the viewport would load it again. The solid lives as long as the scene shows its mesh.
final class MeshSolids: Sendable {
    private let solids = Mutex<[UUID: Solid]>([:])
    /// A curve's display solid by the curve's identity; the curve is held so the identity can't be reused while it is cached.
    private let curveSolids = Mutex<[ObjectIdentifier: (curve: Curve, solid: Solid)]>([:])

    /// The solid that shows `mesh`.
    func solid(for mesh: TriangleMesh) -> Solid {
        solids.withLock { solids in
            if let known = solids[mesh.id] { return known }
            let made = Solid(displaying: mesh.displayMesh, resolution: mesh.resolution > 0 ? mesh.resolution : nil)
            solids[mesh.id] = made
            return made
        }
    }

    /// The solid that shows `curve`, made once per curve.
    func solid(forCurve curve: Curve) -> Solid {
        curveSolids.withLock { solids in
            if let known = solids[ObjectIdentifier(curve)] { return known.solid }
            let made = ViewportItem.displaySolid(for: curve)
            solids[ObjectIdentifier(curve)] = (curve, made)
            return made
        }
    }

    /// Forgets the solids of curves not in `curves`.
    func keep(curves: [Curve]) {
        let identities = Set(curves.map(ObjectIdentifier.init))
        curveSolids.withLock { $0 = $0.filter { identities.contains($0.key) } }
    }

    /// Forgets the solids of meshes not in `ids`.
    func keep(_ ids: Set<UUID>) {
        solids.withLock { $0 = $0.filter { ids.contains($0.key) } }
    }

    var count: Int { solids.withLock { $0.count } }
    var curveCount: Int { curveSolids.withLock { $0.count } }
}
