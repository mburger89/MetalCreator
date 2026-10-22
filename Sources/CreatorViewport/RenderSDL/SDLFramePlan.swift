#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// Everything one main pass draws, with every GPU buffer already made and filled. A copy pass cannot run inside a render pass,
/// so the renderer plans the frame first (`SDLViewportRenderer.plan`) and then records the pass from the plan.
struct SDLFramePlan {
    /// A solid: its triangles, its face flags, and the tint when it has one.
    struct Solid {
        var vertices: SDLGPUBuffer
        var vertexCount: Int
        var flags: SDLGPUBuffer
        var faceCount: Int
        var tint: (values: SDLGPUBuffer, ramp: FieldRampUniforms)?
    }

    /// Line instances to draw in one instanced call, the cut view's plane they are clipped by, and their style.
    struct Lines {
        var buffer: SDLGPUBuffer
        var count: Int
        var style: LineUniforms
        var clip: ClipUniforms = .off
    }

    /// A square of the target, in pixels from its top left, that a widget (the view cube, the triad) draws into with a camera of its own.
    struct WidgetViewport {
        var x: Float
        var y: Float
        var side: Float
        var camera: FrameUniforms
    }

    /// The view cube's tiles, its face-name texture with the sampler it is read through, and the ink the names are painted in.
    struct Cube {
        var tiles: SDLGPUBuffer
        var count: Int
        var labels: SDLGPUTexture
        var sampler: SDLGPUSampler
        var ink: SIMD4<Float>
        var viewport: WidgetViewport
    }

    /// The field slice's quad: its grid texture and the sampler it is read through, the quad and the ramp.
    struct Slice {
        var texture: SDLGPUTexture
        var sampler: SDLGPUSampler
        var geometry: SliceUniforms
        var ramp: FieldRampUniforms
    }

    /// The axis triad's lines.
    struct Triad {
        var lines: Lines
        var viewport: WidgetViewport
    }

    var opaque: [Solid] = []
    var ghosts: [Solid] = []
    var edges: [Lines] = []
    var guides: [Lines] = []
    /// A guide's faded edges, drawn only where the part hides them.
    var hiddenGuides: [Lines] = []
    var slice: Slice?
    var fills: (buffer: SDLGPUBuffer, count: Int)?
    var overlay: Lines?
    var handles: Lines?
    var cube: Cube?
    var triad: Triad?
}
#endif
