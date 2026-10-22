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

    var opaque: [Solid] = []
    var ghosts: [Solid] = []
    var edges: [Lines] = []
    var guides: [Lines] = []
    /// A guide's faded edges, drawn only where the part hides them.
    var hiddenGuides: [Lines] = []
    var fills: (buffer: SDLGPUBuffer, count: Int)?
    var overlay: Lines?
    var handles: Lines?
}
#endif
