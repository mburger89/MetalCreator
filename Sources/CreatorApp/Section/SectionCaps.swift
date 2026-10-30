import CreatorGeometry
import CreatorImplicit
import CreatorKernel
import CreatorViewport

/// The pure parts of the section cap (section spec §3): where the cap's plane lies, and how a kernel section becomes a cap.
enum SectionCaps {
    /// How far towards the kept side the part is sectioned, in millimetres, so a section exactly on a boundary face is a
    /// proper cross-section and the cap is not clipped by its own plane.
    static let inset = 1e-4

    /// The plane the part is sectioned at: the clip plane moved `inset` towards the kept side, with the clip's normal.
    static func plane(for clip: ViewportClip) -> Plane {
        let normal = clip.normal.normalized ?? clip.normal
        let components = [abs(normal.x), abs(normal.y), abs(normal.z)]
        let least = components.firstIndex(of: components.min() ?? 0) ?? 0
        let axis = [Vector3.unitX, .unitY, .unitZ][least]
        let xAxis = normal.cross(axis).normalized ?? .unitX
        return Plane(origin: clip.origin - normal * inset, normal: normal, xAxis: xAxis)
    }

    /// One part's cap from its section, or `nil` when the section is empty.
    static func cap(from section: PlaneSection, hatchAngle: Double) -> ViewportSection.Cap? {
        guard !section.isEmpty else { return nil }
        var positions: [Vector3] = []
        var triangles: [UInt32] = []
        var outlines: [[Vector3]] = []
        for region in section.regions {
            let base = UInt32(positions.count)
            positions += region.positions
            triangles += region.triangles.map { $0 + base }
            outlines += region.boundary.map(\.polyline)
        }
        outlines += section.openOutlines
        return ViewportSection.Cap(positions: positions, triangles: triangles, outlines: outlines, hatchAngle: hatchAngle)
    }

    /// Slices a display mesh off the calling actor.
    @concurrent
    static func slice(_ mesh: DisplayMesh, by plane: Plane) async -> PlaneSection {
        MeshSlicer.slice(positions: mesh.positions, triangles: mesh.indices, plane: plane)
    }
}
