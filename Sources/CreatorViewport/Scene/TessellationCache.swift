import CreatorKernel

/// Display meshes cached per `Solid` and tolerance (spec §6.3). An entry holds its solid strongly, so the solid's
/// identity can't be reused while the entry exists.
@MainActor
final class TessellationCache {
    private struct Entry {
        let solid: Solid
        let tolerance: Double
        let cached: CachedMesh
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var nextSerial = 1
    /// Kernel tessellations so far. A cache hit doesn't count, and neither does a mesh shown as it is.
    private(set) var tessellationCount = 0

    /// Meshes every solid in `solids` at `tolerance`, reusing cached meshes, then drops the entries of solids not
    /// listed. A cancelled load never prunes (it stops before changing anything else), so a superseded
    /// load can't drop the newer scene's meshes.
    func load(_ solids: [Solid], tolerance: Double, kernel: any Kernel) async throws {
        for solid in solids {
            let key = ObjectIdentifier(solid)
            if let entry = entries[key], entry.tolerance == tolerance { continue }
            // A solid that is only a mesh on display (a Mesh node's result) is drawn as it is; the kernel tessellates the rest.
            let mesh: DisplayMesh
            if let shown = solid.displayedMesh {
                mesh = shown
            } else {
                mesh = try await kernel.tessellate(solid, tolerance: tolerance)
                tessellationCount += 1
            }
            try Task.checkCancellation()
            entries[key] = Entry(solid: solid, tolerance: tolerance, cached: CachedMesh(serial: nextSerial, mesh: mesh))
            nextSerial += 1
        }
        try Task.checkCancellation()
        let keep = Set(solids.map(ObjectIdentifier.init))
        entries = entries.filter { keep.contains($0.key) }
    }

    func mesh(for solid: Solid) -> CachedMesh? {
        entries[ObjectIdentifier(solid)]?.cached
    }
}
