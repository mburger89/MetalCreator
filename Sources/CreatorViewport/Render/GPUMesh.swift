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
    private var flagBuffer: (hovered: FaceID?, selected: Set<FaceID>, buffer: any MTLBuffer)?

    init(device: any MTLDevice, mesh: DisplayMesh) {
        let vertices = GPUGeometry.meshVertices(mesh)
        vertexBuffer = GPUBuffers.make(device, vertices)
        vertexCount = vertices.count
        faceCount = (mesh.triangleFaces.map(\.rawValue).max() ?? -1) + 1
        polylines = mesh.edgePolylines
    }

    /// The edge instances for `key`. They're built once and kept: there are only a few keys in use (the main
    /// pass at one scale, and the ID pass), so a fifth key clears the lot.
    func edges(_ key: EdgeInstanceKey, device: any MTLDevice) -> (buffer: any MTLBuffer, count: Int)? {
        if let cached = edgeBuffers[key] { return cached }
        let instances = GPUGeometry.edgeInstances(polylines, solid: key.solid, selected: key.selected,
                                                  selectedOnly: key.selectedOnly, scale: key.scale)
        guard let buffer = GPUBuffers.make(device, instances) else { return nil }
        if edgeBuffers.count >= 4 { edgeBuffers.removeAll() }
        edgeBuffers[key] = (buffer, instances.count)
        return (buffer, instances.count)
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
