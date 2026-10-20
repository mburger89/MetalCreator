/// The cut view's plane for the shaders: `plane` is (n, d) with a point cut away when n·p + d > 0, and `enabled` is 0 for no cut.
/// Mirrors `ClipUniforms` in `ViewportShaders` (stride pinned by `GPUDataTests`).
struct ClipUniforms {
    var plane: SIMD4<Float>
    var enabled: UInt32
    var padding0: UInt32 = 0
    var padding1: UInt32 = 0
    var padding2: UInt32 = 0

    /// No cut: what handles, the triad and the overlay draw with.
    static let off = ClipUniforms(plane: .zero, enabled: 0)

    init(plane: SIMD4<Float>, enabled: UInt32) {
        self.plane = plane
        self.enabled = enabled
    }

    init(_ clip: ViewportClip?) {
        if let clip, clip.isValid {
            self.init(plane: clip.coefficients, enabled: 1)
        } else {
            self = .off
        }
    }
}
