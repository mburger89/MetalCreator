import CreatorGeometry
import CreatorKernel
import Metal

/// One mesh on the GPU: its de-indexed triangles, plus edge-instance buffers built when first asked for.
@MainActor
final class GPUMesh {
    let vertexBuffer: (any MTLBuffer)?
    let vertexCount: Int
    /// One more than the highest face ID, so face flags can be indexed by ID.
    let faceCount: Int
    private let polylines: [EdgeID: [Vector3]]
    private var edgeBuffers: [EdgeInstanceKey: (buffer: any MTLBuffer, count: Int)] = [:]
    /// The palette `edgeBuffers` were built in; another one (the theme changed) drops them.
    private var edgePalette = ViewportPalette.dracula
    private var flagBuffer: (hovered: FaceID?, selected: Set<FaceID>, buffer: any MTLBuffer)?
    /// The field values last uploaded for the tint, with the ramp middle that stood in for any that were not numbers.
    private var fieldBuffer: (values: [Float], middle: Float, buffer: any MTLBuffer)?
    /// Field value buffers made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var fieldUploads = 0

    init(device: any MTLDevice, mesh: DisplayMesh) {
        let vertices = GPUGeometry.meshVertices(mesh)
        vertexBuffer = GPUBuffers.make(device, vertices)
        vertexCount = vertices.count
        faceCount = (mesh.triangleFaces.map(\.rawValue).max() ?? -1) + 1
        polylines = mesh.edgePolylines
    }

    /// The edge instances for `key`, in `palette`'s colours. They're built once and kept: there are only a few keys
    /// in use (the main pass at one scale, and the ID pass), so a fifth key clears the lot, and so does a new palette.
    func edges(_ key: EdgeInstanceKey, palette: ViewportPalette, device: any MTLDevice) -> (buffer: any MTLBuffer, count: Int)? {
        if palette != edgePalette {
            edgeBuffers.removeAll()
            edgePalette = palette
        }
        if let cached = edgeBuffers[key] { return cached }
        let instances = GPUGeometry.edgeInstances(polylines, solid: key.solid, selected: key.selected,
                                                  selectedOnly: key.selectedOnly, scale: key.scale, palette: palette,
                                                  hidden: key.hidden)
        guard let buffer = GPUBuffers.make(device, instances) else { return nil }
        if edgeBuffers.count >= 4 { edgeBuffers.removeAll() }
        edgeBuffers[key] = (buffer, instances.count)
        return (buffer, instances.count)
    }

    /// The tint's value buffer, one float per de-indexed corner, rebuilt only when the values change (comparing two arrays that
    /// share storage costs nothing). `nil` when the values are not one per vertex of `mesh`. It assumes one tint per mesh (a mesh
    /// is one solid and a solid has one tint), so the buffer is a single cached entry, not a table.
    func fieldValues(_ values: [Float], mesh: DisplayMesh, ramp: FieldRamp, device: any MTLDevice) -> (any MTLBuffer)? {
        if let cached = fieldBuffer, cached.middle == ramp.midValue, cached.values == values { return cached.buffer }
        guard let corners = GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp), corners.count == vertexCount,
              let buffer = GPUBuffers.make(device, corners) else { return nil }
        fieldBuffer = (values, ramp.midValue, buffer)
        fieldUploads += 1
        return buffer
    }

    /// The face flags for a mesh too big for inline bytes, rebuilt only when the hover or selection changes.
    func faceFlags(hovered: FaceID?, selected: Set<FaceID>, device: any MTLDevice) -> (any MTLBuffer)? {
        if let cached = flagBuffer, cached.hovered == hovered, cached.selected == selected { return cached.buffer }
        let flags = GPUGeometry.faceFlags(count: faceCount, hovered: hovered, selected: selected)
        guard let buffer = GPUBuffers.make(device, flags) else { return nil }
        flagBuffer = (hovered, selected, buffer)
        return buffer
    }
}
