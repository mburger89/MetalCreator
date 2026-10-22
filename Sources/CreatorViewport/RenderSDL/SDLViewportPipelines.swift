#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// The viewport's graphics pipelines, made once per device from the compiled shaders. SDL_GPU puts the depth test in the pipeline
/// (Metal has separate depth states), so a draw that differs only in its depth test is a pipeline of its own. Main-pass pipelines
/// render 4× MSAA `bgra8Unorm` (MetalUI's surface format) with `d32Float`; the ID pipelines render single-sample `r32Uint`. A refused
/// pipeline throws `ViewportRenderError.deviceRefused` with the shader pair and SDL's reason ("The GPU could not create the mesh/mesh
/// pipeline (pipeline: E_INVALIDARG …)."), which `ViewportModel.gpuFailureMessage` and `--smoke-test` show.
struct SDLViewportPipelines: Sendable {
    static let colorFormat = SDLGPUTextureFormat.b8g8r8a8Unorm
    static let idFormat = SDLGPUTextureFormat.r32Uint
    static let sampleCount = SDLGPUSampleCount.four

    /// No depth test or write: the background and the overlay's fills.
    let background: SDLGPUGraphicsPipeline
    let fill: SDLGPUGraphicsPipeline
    /// Opaque solids: test (less) and write.
    let mesh: SDLGPUGraphicsPipeline
    /// The surface coloured by a field's values (`field_mesh`).
    let fieldMesh: SDLGPUGraphicsPipeline
    /// The ghosts' depth-only prepass (no colour is written), then their blended colour pass, which passes only where its depth equals the
    /// prepass's (less-or-equal, no write): each pixel blends once, at its nearest ghost surface.
    let ghostDepth: SDLGPUGraphicsPipeline
    let ghost: SDLGPUGraphicsPipeline
    /// Lines (premultiplied source-over): tested against the solids (less-or-equal) without writing; never tested; and only where
    /// something nearer already wrote depth (a guide's edges behind the part).
    let lineTest: SDLGPUGraphicsPipeline
    let lineAlways: SDLGPUGraphicsPipeline
    let lineBehind: SDLGPUGraphicsPipeline
    /// The ground grid: blended, tested against the solids without writing.
    let grid: SDLGPUGraphicsPipeline
    /// The view cube: blended, never depth-tested (a cube is convex, so back-face culling does the hiding).
    let cube: SDLGPUGraphicsPipeline
    let idMesh: SDLGPUGraphicsPipeline
    let idLine: SDLGPUGraphicsPipeline

    init(device: SDLGPUDevice, library: SDLGPUShaderLibrary) throws {
        func pipeline(_ vertex: String, _ fragment: String, primitive: SDLGPUPrimitiveType = .triangleList,
                      cull: SDLGPUCullMode = .none, color: SDLGPUTextureFormat = Self.colorFormat, blend: SDLGPUBlend = .none,
                      samples: SDLGPUSampleCount = Self.sampleCount, depth: SDLGPUDepthState,
                      writesColor: Bool = true) throws -> SDLGPUGraphicsPipeline {
            let description = SDLGPUGraphicsPipelineDescription(
                vertex: try library.vertex(vertex, for: device), fragment: try library.fragment(fragment, for: device),
                primitiveType: primitive, cullMode: cull, colorFormat: color, blend: blend, sampleCount: samples, depth: depth,
                writesColor: writesColor)
            do {
                return try device.compileGraphicsPipeline(description)
            } catch {
                // MetalUI's `SDLGPUError` names the stage that failed with SDL's own text (ruling GB-G, gap XP-G19).
                throw ViewportRenderError.deviceRefused("the \(vertex)/\(fragment) pipeline (\(error))")
            }
        }
        let always = SDLGPUDepthState(compare: .always, write: false)
        let writes = SDLGPUDepthState(compare: .less, write: true)
        let tests = SDLGPUDepthState(compare: .lessOrEqual, write: false)
        let behind = SDLGPUDepthState(compare: .greater, write: false)
        background = try pipeline("background", "background", depth: always)
        fill = try pipeline("fill", "fill", blend: .premultipliedAlpha, depth: always)
        mesh = try pipeline("mesh", "mesh", depth: writes)
        fieldMesh = try pipeline("field_mesh", "field_mesh", depth: writes)
        ghostDepth = try pipeline("mesh", "mesh", depth: writes, writesColor: false)
        ghost = try pipeline("mesh", "mesh", blend: .premultipliedAlpha, depth: tests)
        lineTest = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: tests)
        lineAlways = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: always)
        lineBehind = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: behind)
        grid = try pipeline("grid", "grid", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: tests)
        cube = try pipeline("cube", "cube", cull: .back, blend: .premultipliedAlpha, depth: always)
        idMesh = try pipeline("id_mesh", "id_mesh", color: Self.idFormat, samples: .one, depth: writes)
        idLine = try pipeline("id_line", "id_line", primitive: .triangleStrip, color: Self.idFormat, samples: .one, depth: tests)
    }
}
#endif
