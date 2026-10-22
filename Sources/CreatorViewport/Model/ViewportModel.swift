import CreatorGeometry
import CreatorKernel
import CreatorStyle
import Foundation
import Observation

/// The viewport's state and behaviour (spec §6.3, §6.5), testable without a GPU:
/// - the scene, and the camera with its animations
/// - hover and picking, the view cube, handles and the context menu
/// `ViewportView` draws it and feeds it input. The host feeds it solids (`show(_:)`) and handles, and reacts to
/// `events`. It never sees the graph.
@MainActor
@Observable
public final class ViewportModel {
    /// The committed camera. During an animation it's already the destination. `presentedPose(at:)` is what's drawn.
    public var pose: CameraPose
    /// The document's home view. `nil` means isometric, framed on everything.
    /// A non-finite (or zero-distance) value is refused and the old one kept.
    public var homePose: CameraPose? {
        didSet {
            if let home = homePose, !home.isFinite { homePose = oldValue }
        }
    }
    public var shading: ShadingMode = .shadedEdges
    /// True while the host is picking edges in the view ("Pick edges in view…", spec §5.3): the pointer is a
    /// crosshair (`cursor`).
    public var isPicking = false
    /// What takes the primary pointer input first (`ViewportTool`), or `nil`: the sketch editor while sketching. While
    /// one is set the pointer is a crosshair.
    public var tool: (any ViewportTool)?
    /// The colour theme the viewport draws in (spec §6.6). The app shell sets it from its `ThemeStore`; a change is
    /// drawn on the next frame, because the GPU colours (`palette`) are part of `renderKey`.
    public var theme: ColorTheme = .dracula
    public var cubeLayout = ViewCubeLayout()
    public var triadLayout = TriadLayout()
    /// How far floating panels cover the viewport's edges (`setModelArea(_:)`).
    public internal(set) var modelArea = ViewportInsets()
    /// Display tolerance in mm. Meshes are cached per solid and tolerance. A change applies at the next `show(_:)`.
    public var displayTolerance = 0.05
    /// The shown scene: what's drawn, picked, framed and offered in the context menu. It changes only when a
    /// requested scene's meshes are ready.
    public private(set) var items: [ViewportItem] = []
    public internal(set) var handles: [ViewportHandle] = []
    /// Lines and points the host draws over the scene (`showOverlay(_:)`): the sketch editor's geometry.
    public private(set) var overlay = ViewportOverlay()
    /// The field slice drawn through the scene (`showSlice(_:)`), or `nil`. It is no part of the scene: it never picks, frames
    /// or widens `sceneBounds`.
    public private(set) var slice: ViewportSlice?
    /// The cut view's plane (`showClip(_:)`), or `nil`: everything on one side of it is cut away. It is no part of the scene: it
    /// never picks, frames or widens `sceneBounds`.
    public private(set) var clip: ViewportClip?
    public internal(set) var hovered: PickTarget?
    public internal(set) var hoveredCubeRegion: ViewCubeRegion?
    /// What the drag under way does, or `nil` between drags. It's written once at each press and release (never per
    /// move), so the view's pointer style follows it.
    public internal(set) var activeDragMode: ViewportDragMode?
    /// Bumped each time a scene's meshes are ready.
    public private(set) var sceneGeneration = 0
    /// A plain-language message when the last scene couldn't be tessellated, else `nil`.
    public private(set) var meshError: String?
    private(set) var animation: CameraAnimation?

    @ObservationIgnored public var events = ViewportEvents()
    let kernel: any Kernel
    let clock: any ViewportClock
    let cache = TessellationCache()
    /// The view's size in points, from `ViewportView`'s `onGeometryChange` (`recordViewSize(_:)`; zero until the first
    /// build has been laid out). Tracked, so what is built from it (the handle and overlay labels) is rebuilt after a
    /// resize.
    public internal(set) var viewSize = ViewportSize(width: 0, height: 0)
    /// Answers "what is under this point?". It's set when the GPU objects are made (`install(_:)`), and tests set it directly.
    @ObservationIgnored var pick: (@MainActor (ScreenPoint) -> PickTarget?)?
    /// Whether `pick` has no answer yet because the ID buffer for the view as it is now is on its way (an SDL_GPU backend reads it back
    /// asynchronously). A hover then keeps the face it had. `nil` means never.
    @ObservationIgnored var isPickPending: (@MainActor () -> Bool)?
    /// A click's pick: `pick` from an ID buffer for the view as it is now, rendered and waited for when none has landed (user decision U4,
    /// hybrid). `nil` (no backend: tests that set `pick` directly) falls back to `pick`.
    @ObservationIgnored var pickWhenReady: (@MainActor (ScreenPoint) -> PickTarget?)?
    @ObservationIgnored var drag: DragState?
    /// The camera when the scroll under way (a trackpad scroll, or a run of wheel steps) began; `nil` between scrolls.
    @ObservationIgnored var scrollStartPose: CameraPose?
    /// Settles a run of wheel steps once the wheel has been still for `ViewportInputMap.wheelSettleDelay`.
    @ObservationIgnored var wheelSettleTask: Task<Void, Never>?
    /// Where the pinch under way began; `nil` between pinches.
    @ObservationIgnored var pinchStart: PinchStart?
    @ObservationIgnored var lastHoverPoint: ScreenPoint?
    /// The `ViewportModifiers.hoverMask` modifiers held now, from `ViewportView`'s `onModifierKeysChanged`
    /// (`modifiersChanged(_:)`): what a hover tells the tool beside the pointer.
    @ObservationIgnored var heldModifiers: ViewportModifiers = []
    /// The code that draws and picks for this model, made on the first draw (`install(_:)`).
    @ObservationIgnored var backend: (any ViewportBackend)?
    /// Why the GPU objects could not be made, if they could not (`gpuFailureMessage`).
    @ObservationIgnored var gpuFailure: String?
    @ObservationIgnored private var meshTask: Task<Void, Never>?
    @ObservationIgnored private var animationTask: Task<Void, Never>?
    @ObservationIgnored private var needsFirstFraming: Bool
    /// The scene `show(_:)` asked for, while its meshes load. Nothing reads it to draw or pick.
    @ObservationIgnored private(set) var pendingItems: [ViewportItem]?
    /// The deferred first framing scheduled by `recordViewSize(_:)`. Tests await it.
    @ObservationIgnored private(set) var framingTask: Task<Void, Never>?

    /// `pose` is a saved camera (`ViewState.camera`). Without one, the first scene is framed from the home view.
    public init(kernel: any Kernel, pose: CameraPose? = nil, clock: any ViewportClock = SystemViewportClock()) {
        self.kernel = kernel
        self.clock = clock
        // A saved camera that can't be drawn (a hand-edited or corrupt file) is dropped for the default framing.
        let saved = pose.flatMap { $0.isFinite ? $0 : nil }
        self.pose = saved ?? CameraPose()
        needsFirstFraming = saved == nil
    }

    public var isAnimating: Bool { animation != nil }

    /// `theme`'s colours as the GPU takes them.
    var palette: ViewportPalette { ViewportPalette(theme) }

    /// What the drawing depends on. `ViewportView` passes it as the `MetalView`'s `value:`.
    public var renderKey: ViewportRenderKey {
        ViewportRenderKey(pose: pose, isAnimating: isAnimating, shading: shading, hovered: hovered,
                          hoveredCubeRegion: hoveredCubeRegion, sceneGeneration: sceneGeneration, handles: handles,
                          cube: cubeLayout, triad: triadLayout, palette: palette, overlay: overlay,
                          showsViewCube: showsViewCube, slice: slice, clip: clip)
    }

    /// The union of every shown solid's bounds, ghosts included and guides left out.
    public var sceneBounds: BoundingBox? {
        items.filter { !$0.isGuide }.reduce(BoundingBox?.none) { bounds, item in
            bounds?.union(item.solid.bounds) ?? item.solid.bounds
        }
    }

    /// Asks for a new scene. Its meshes load in the background, and until they arrive the shown scene stays up
    /// unchanged: `items`, `sceneBounds`, the hover pick and every drawn frame still describe it (spec §7.3's
    /// fillet drag re-shows on every step). Once the load succeeds, `items`, `sceneGeneration` and the hover pick
    /// change together, with no suspension in between. A newer call supersedes an older one, which then changes
    /// nothing. A failed load keeps the shown scene and sets `meshError`.
    public func show(_ newItems: [ViewportItem]) {
        pendingItems = newItems
        meshTask?.cancel()
        let solids = newItems.map(\.solid)
        let tolerance = displayTolerance
        meshTask = Task { [weak self] in
            guard let self else { return }
            do {
                // The cache keeps the shown scene's meshes until this load has every new one: it prunes only at
                // the end of a load that wasn't cancelled.
                try await cache.load(solids, tolerance: tolerance, kernel: kernel)
            } catch is CancellationError {
                return
            } catch {
                // A cancelled load can surface as another error; a newer scene owns the state now.
                guard !Task.isCancelled else { return }
                meshError = (error as? KernelError)?.userMessage ?? "The part could not be displayed."
                pendingItems = nil
                return
            }
            // No `await` from here on: the swap is one step on the main actor. (Don't add a cancellation check
            // here either. The load has already pruned the old meshes, so this scene must be shown.)
            pendingItems = nil
            items = newItems
            meshError = nil
            sceneGeneration += 1
            frameFirstSceneIfNeeded()
            refreshHover()
        }
    }

    /// The handles to draw, already resolved against their nodes' outputs by the host (spec §6.5).
    public func showHandles(_ newHandles: [ViewportHandle]) {
        handles = newHandles
    }

    /// The overlay to draw over the scene (the sketch editor's geometry and plane grid); an equal one changes nothing.
    public func showOverlay(_ newOverlay: ViewportOverlay) {
        if overlay != newOverlay { overlay = newOverlay }
    }

    /// The slice to draw through the scene, or `nil` for none. An equal slice (the same `generation`) changes nothing.
    public func showSlice(_ newSlice: ViewportSlice?) {
        if slice != newSlice { slice = newSlice }
    }

    /// The plane to cut the scene by (the cut view), or `nil` for none. A plane with no usable normal or a position that is not a number
    /// is none; an equal plane changes nothing.
    public func showClip(_ newClip: ViewportClip?) {
        let valid = newClip.flatMap { $0.isValid ? $0 : nil }
        if clip != valid { clip = valid }
    }

    /// Returns once the most recent `show(_:)` has finished loading.
    public func waitForMeshes() async {
        while let task = meshTask {
            await task.value
            if meshTask == task { return }
        }
    }

    /// Returns once the most recent camera animation has finished.
    public func waitForAnimation() async {
        while let task = animationTask {
            await task.value
            if animationTask == task { return }
        }
    }

    func presentedPose(at time: Double) -> CameraPose {
        animation?.pose(at: time) ?? pose
    }

    func currentPose() -> CameraPose {
        presentedPose(at: clock.now())
    }

    /// Animates from what's on screen now to `target` (spec §6.3: about 250 ms). `pose` becomes `target` at once. An
    /// explicit camera move (Look At, a cube region, F) counts as the first framing: the first scene won't undo it.
    func animate(to target: CameraPose) {
        guard target.isFinite else { return }
        needsFirstFraming = false
        let now = clock.now()
        animation = CameraAnimation(from: presentedPose(at: now), to: target, start: now,
                                    duration: CameraAnimation.viewCubeDuration)
        pose = target
        animationTask?.cancel()
        let clock = clock
        animationTask = Task { [weak self] in
            await clock.sleep(for: CameraAnimation.viewCubeDuration)
            guard !Task.isCancelled, let self else { return }
            animation = nil
            refreshHover()
            events.cameraSettled(pose)
        }
    }

    /// Freezes an animation where it is now, so input continues from what the user sees. While navigation is planar
    /// it finishes the animation instead (`pose` is already its end): frozen part-way, the turn onto the plane would
    /// lock an oblique view in.
    func stopAnimation() {
        guard animation != nil else { return }
        if !isPlanar { pose = currentPose() }
        animation = nil
        animationTask?.cancel()
        events.cameraSettled(pose)
    }

    /// Takes `next` as the camera, unless it's non-finite (which would make the view and the document unusable).
    func apply(_ next: CameraPose) {
        if next.isFinite, next != pose { pose = next }
    }

    /// Re-picks under a pointer that hasn't moved, after the camera or the scene changed beneath it, so the hover
    /// tint never names a face that's no longer under the pointer. Nothing is picked during a drag, so there the old
    /// pick is just dropped.
    func refreshHover() {
        if drag == nil {
            pointerHovered(at: lastHoverPoint)
        } else if hovered != nil {
            hovered = nil
        }
    }

    /// Records the view's size, from `ViewportView`'s `onGeometryChange` (which runs after the build, so it may write
    /// tracked state). The first real size frames a scene that arrived before it, from a task.
    func recordViewSize(_ size: ViewportSize) {
        let wasEmpty = viewSize.isEmpty
        if size != viewSize { viewSize = size }
        guard wasEmpty, !size.isEmpty, needsFirstFraming, sceneBounds != nil else { return }
        framingTask = Task { [weak self] in self?.frameFirstSceneIfNeeded() }
    }

    /// Frames the first shown scene from the home view, once. It waits for a real view size: framed for a zero
    /// size, a narrow viewport would clip the part. Never while navigation is planar (the camera faces the tool's
    /// plane, and the home view would turn it): that counts as framed.
    private func frameFirstSceneIfNeeded() {
        if isPlanar { needsFirstFraming = false }
        guard needsFirstFraming, !viewSize.isEmpty, let bounds = sceneBounds else { return }
        needsFirstFraming = false
        pose = homePose ?? defaultHome(for: bounds)
        events.cameraSettled(pose)
    }

    /// Isometric, perspective, framed on `bounds` in the model area.
    func defaultHome(for bounds: BoundingBox) -> CameraPose {
        var home = ViewCubeRegion.isometric.pose(from: CameraPose())
        home.projection = .perspective
        return CameraNavigation.frame(bounds, home, size: viewSize, insets: modelArea)
    }
}
