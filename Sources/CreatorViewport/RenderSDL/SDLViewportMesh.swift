#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import MetalUISDLGPU

/// One mesh on the GPU: its de-indexed triangles as a storage buffer, plus edge-instance, face-flag and field-value buffers built
/// when first asked for (the same cache rules as `GPUMesh`). Like the renderer it belongs to, it is used from one thread at a time.
final class SDLViewportMesh: @unchecked Sendable {
    let vertexBuffer: SDLGPUBuffer?
    let vertexCount: Int
    /// One more than the highest face ID, so face flags can be indexed by ID.
    let faceCount: Int
    private let polylines: [EdgeID: [Vector3]]
    private var edgeBuffers: [EdgeInstanceKey: (buffer: SDLGPUBuffer, count: Int)] = [:]
    /// The palette `edgeBuffers` were built in; another one (the theme changed) drops them.
    private var edgePalette = ViewportPalette.dracula
    private var flagBuffer: (hovered: FaceID?, selected: Set<FaceID>, warning: Set<FaceID>, buffer: SDLGPUBuffer)?
    private var fieldBuffer: (values: [Float], middle: Float, buffer: SDLGPUBuffer)?
    /// The ID pass's edge instances by solid index (the pick IDs name the solid), built by `pickEdges`. An entry of `nil` is a mesh
    /// with no edges (a refused buffer leaves no entry).
    private var pickEdgeBuffers: [Int: (buffer: SDLGPUBuffer, count: Int)?] = [:]
    /// Field value buffers made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var fieldUploads = 0

    init(uploader: SDLViewportUploader, mesh: DisplayMesh) {
        let vertices = GPUGeometry.meshVertices(mesh)
        vertexBuffer = uploader.storageBuffer(vertices)
        vertexCount = vertices.count
        faceCount = (mesh.triangleFaces.map(\.rawValue).max() ?? -1) + 1
        polylines = mesh.edgePolylines
    }

    /// The edge instances for `key`, in `palette`'s colours. They're built once and kept: there are only a few keys in use (the
    /// main pass at one scale, and the ID pass), so a fifth key clears the lot, and so does a new palette.
    func edges(_ key: EdgeInstanceKey, palette: ViewportPalette, uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if palette != edgePalette {
            edgeBuffers.removeAll()
            edgePalette = palette
        }
        if let cached = edgeBuffers[key] { return cached }
        let instances = GPUGeometry.edgeInstances(polylines, solid: key.solid, selected: key.selected,
                                                  selectedOnly: key.selectedOnly, scale: key.scale, palette: palette,
                                                  hidden: key.hidden)
        guard let buffer = uploader.storageBuffer(instances) else { return nil }
        if edgeBuffers.count >= 4 { edgeBuffers.removeAll() }
        edgeBuffers[key] = (buffer, instances.count)
        return (buffer, instances.count)
    }

    /// The instances the ID pass draws for the solid at `solid`: every edge, with its pick ID. They don't depend on the palette or the
    /// pixel scale (the pass draws edges 6 points wide in one colour), so they are built once per solid index and kept apart from
    /// `edges(_:palette:uploader:)`'s few keys; `nil` for a mesh with no edges.
    func pickEdges(solid: Int, uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let cached = pickEdgeBuffers[solid] { return cached }
        let instances = GPUGeometry.edgeInstances(polylines, solid: solid, selected: [], selectedOnly: false, scale: 1)
        let built = uploader.storageBuffer(instances).map { (buffer: $0, count: instances.count) }
        // A refused buffer is not cached (the next frame asks again); only a mesh that truly has no edges is remembered as having none.
        if built != nil || instances.isEmpty { pickEdgeBuffers[solid] = .some(built) }
        return built
    }

    /// The instances `pickEdges(solid:uploader:)` built for `solid`, or `nil` when it has not been asked for it or the mesh has none.
    func cachedPickEdges(solid: Int) -> (buffer: SDLGPUBuffer, count: Int)? {
        pickEdgeBuffers[solid] ?? nil
    }

    /// Whether `pickEdges(solid:uploader:)` has been asked for `solid` (a mesh with no edges counts), so the ID pass can use it
    /// without a command buffer to upload into.
    func hasPickEdges(solid: Int) -> Bool { pickEdgeBuffers[solid] != nil }

    /// The face flags (bit 1 hovered, bit 2 selected, bit 4 warning), rebuilt only when the hover or selection changes. A mesh
    /// with no faces gets a one-entry buffer: a storage buffer cannot be empty, and the shader never reads it.
    func faceFlags(hovered: FaceID?, selected: Set<FaceID>, warning: Set<FaceID>, uploader: SDLViewportUploader) -> SDLGPUBuffer? {
        if let cached = flagBuffer, cached.hovered == hovered, cached.selected == selected, cached.warning == warning {
            return cached.buffer
        }
        let flags = GPUGeometry.faceFlags(count: max(faceCount, 1), hovered: hovered, selected: selected, warning: warning)
        guard let buffer = uploader.storageBuffer(flags) else { return nil }
        flagBuffer = (hovered, selected, warning, buffer)
        return buffer
    }

    /// The tint's value buffer, one float per de-indexed corner, rebuilt only when the values change. `nil` when the values are not
    /// one per vertex of `mesh`. A mesh is one solid and a solid has one tint, so the buffer is a single cached entry.
    func fieldValues(_ values: [Float], mesh: DisplayMesh, ramp: FieldRamp, uploader: SDLViewportUploader) -> SDLGPUBuffer? {
        if let cached = fieldBuffer, cached.middle == ramp.midValue, cached.values == values { return cached.buffer }
        guard let corners = GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp), corners.count == vertexCount,
              let buffer = uploader.storageBuffer(corners) else { return nil }
        fieldBuffer = (values, ramp.midValue, buffer)
        fieldUploads += 1
        return buffer
    }
}
#endif
