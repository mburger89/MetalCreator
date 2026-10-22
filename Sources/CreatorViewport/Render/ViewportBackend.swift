/// What `ViewportModel` needs from the code that draws and picks for it, whichever GPU API that code speaks (cross-platform
/// spec section 4): `MetalViewportBackend` on macOS, `SDLViewportBackend` on Linux and Windows. The drawing itself is not here: it
/// takes the API's own draw context, so each backend has its own `draw` in `ViewportModel+Surface` and `+SDLSurface`.
///
/// Picking is the part the model sees (user decision U4, hybrid). Metal answers a pick at once, by rendering the ID buffer and waiting
/// for it. The SDL_GPU backend answers a hover from the ID buffer it rendered ahead (``isPickPending(for:)`` says when that buffer is not
/// for the camera and scene of the frame asked about yet) and calls ``onPickReady`` when a new one lands; a click asks
/// ``pickWhenReady(at:in:)``, which answers from a buffer for the click's own view, rendering it and waiting for the GPU when none has
/// landed, as Metal does.
@MainActor
protocol ViewportBackend: AnyObject {
    /// Main passes drawn so far. Tests and the launch smoke test use it to tell "drew" from "bailed out".
    var drawnFrames: Int { get }

    /// Called after an ID buffer has landed for a frame that had none, so the model can look again under a pointer that
    /// has not moved (`ViewportModel.refreshHover()`). A synchronous backend never calls it.
    var onPickReady: (@MainActor () -> Void)? { get set }

    /// The face or edge under `point` (viewport points) in `frame`, or `nil` for empty space, a point outside the view, a
    /// view with no size yet, or an answer that is not ready (``isPickPending(for:)``).
    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget?

    /// Whether the ID buffer for `frame` is on its way, so ``pick(at:in:)`` would answer `nil` for want of it.
    func isPickPending(for frame: ViewportFrame) -> Bool

    /// The click's pick: ``pick(at:in:)`` from an ID buffer for `frame` itself, rendered and waited for now when none has landed (it may
    /// stall a frame, as Metal's `waitUntilCompleted` does; only a click asks). Never another view's answer.
    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget?

    /// Whether this backend draws the view cube and the axis triad. The model hit-tests the cube (hover, click, drag, the context menu's
    /// exclusion) only while it is drawn: a cube nobody can see must not rotate the camera. Metal draws them; the SDL backend says
    /// `false` until the cube and triad are drawn there (task 10).
    var drawsWidgets: Bool { get }
}

extension ViewportBackend {
    var drawsWidgets: Bool { true }

    func isPickPending(for frame: ViewportFrame) -> Bool { false }

    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        pick(at: point, in: frame)
    }
}
