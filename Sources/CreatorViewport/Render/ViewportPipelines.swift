import Metal

/// The viewport's compiled pipelines and depth states, made once per device. Main-pass pipelines render 4× MSAA
/// `bgra8Unorm` (MetalUI's surface format, `MV-E`) with `depth32Float`. ID pipelines render single-sample `r32Uint`.
struct ViewportPipelines {
    static let colorFormat: MTLPixelFormat = .bgra8Unorm
    static let depthFormat: MTLPixelFormat = .depth32Float
    static let idFormat: MTLPixelFormat = .r32Uint
    static let sampleCount = 4

    let background: any MTLRenderPipelineState
    let mesh: any MTLRenderPipelineState
    let ghost: any MTLRenderPipelineState
    /// The ghosts' depth-only prepass: no colour is written.
    let ghostDepth: any MTLRenderPipelineState
    let line: any MTLRenderPipelineState
    let grid: any MTLRenderPipelineState
    let cube: any MTLRenderPipelineState
    let idMesh: any MTLRenderPipelineState
    let idLine: any MTLRenderPipelineState
    /// No depth test or write: the background, handles, the cube and the triad.
    let depthAlways: any MTLDepthStencilState
    /// Opaque solids: test and write.
    let depthWrite: any MTLDepthStencilState
    /// The grid, edges and the ghosts' colour pass: test against the solids (less-or-equal) without writing.
    let depthTest: any MTLDepthStencilState
    /// A guide's edges behind the part: pass only where something nearer already wrote depth, without writing.
    let depthBehind: any MTLDepthStencilState

    init(device: any MTLDevice) throws {
        let library = try device.makeLibrary(source: ViewportShaders.source, options: nil)
        func function(_ name: String) throws -> any MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw ViewportRenderError.missingShader(name) }
            return function
        }
        func pipeline(_ vertex: String, _ fragment: String, color: MTLPixelFormat = Self.colorFormat,
                      samples: Int = Self.sampleCount, blended: Bool,
                      writesColor: Bool = true) throws -> any MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = try function(vertex)
            descriptor.fragmentFunction = try function(fragment)
            descriptor.colorAttachments[0].pixelFormat = color
            if !writesColor { descriptor.colorAttachments[0].writeMask = [] }
            descriptor.depthAttachmentPixelFormat = Self.depthFormat
            descriptor.rasterSampleCount = samples
            if blended {
                // Premultiplied source-over, the way MetalUI composites a surface (MV-D).
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                descriptor.colorAttachments[0].alphaBlendOperation = .add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        func depth(_ compare: MTLCompareFunction, write: Bool) throws -> any MTLDepthStencilState {
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = compare
            descriptor.isDepthWriteEnabled = write
            guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
                throw ViewportRenderError.deviceRefused("a depth state")
            }
            return state
        }
        background = try pipeline("background_vertex", "background_fragment", blended: false)
        mesh = try pipeline("mesh_vertex", "mesh_fragment", blended: false)
        ghost = try pipeline("mesh_vertex", "mesh_fragment", blended: true)
        ghostDepth = try pipeline("mesh_vertex", "mesh_fragment", blended: false, writesColor: false)
        line = try pipeline("line_vertex", "line_fragment", blended: true)
        grid = try pipeline("grid_vertex", "grid_fragment", blended: true)
        cube = try pipeline("cube_vertex", "cube_fragment", blended: true)
        idMesh = try pipeline("mesh_vertex", "id_mesh_fragment", color: Self.idFormat, samples: 1, blended: false)
        idLine = try pipeline("line_vertex", "id_line_fragment", color: Self.idFormat, samples: 1, blended: false)
        depthAlways = try depth(.always, write: false)
        depthWrite = try depth(.less, write: true)
        depthTest = try depth(.lessEqual, write: false)
        depthBehind = try depth(.greater, write: false)
    }
}
