import CreatorGeometry
import CreatorKernel
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
    public var homePose: CameraPose?
    public var shading: ShadingMode = .shadedEdges
    public var cubeLayout = ViewCubeLayout()
    public var triadLayout = TriadLayout()
    /// Display tolerance in mm. Meshes are cached per solid and tolerance. A change applies at the next `show(_:)`.
    public var displayTolerance = 0.05
    /// The shown scene: what's drawn, picked, framed and offered in the context menu. It changes only when a
    /// requested scene's meshes are ready.
    public private(set) var items: [ViewportItem] = []
    public internal(set) var handles: [ViewportHandle] = []
    public internal(set) var hovered: PickTarget?
    public internal(set) var hoveredCubeRegion: ViewCubeRegion?
    /// Bumped each time a scene's meshes are ready.
    public private(set) var sceneGeneration = 0
    /// A plain-language message when the last scene couldn't be tessellated, else `nil`.
    public private(set) var meshError: String?
    private(set) var animation: CameraAnimation?

    @ObservationIgnored public var events = ViewportEvents()
    let kernel: any Kernel
    let clock: any ViewportClock
    let cache = TessellationCache()
    /// The view's size in points, recorded by the draw (MetalUI has no size callback: docs/metalui-gaps.md).
    @ObservationIgnored var viewSize = ViewportSize(width: 0, height: 0)
    /// Answers "what is under this point?". It's set when the GPU objects are made, and tests set it directly.
    @ObservationIgnored var pick: (@MainActor (ScreenPoint) -> PickTarget?)?
    @ObservationIgnored var drag: DragState?
    @ObservationIgnored var lastHoverPoint: ScreenPoint?
    @ObservationIgnored var gpuRenderer: ViewportRenderer?
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
        self.pose = pose ?? CameraPose()
        needsFirstFraming = pose == nil
    }

    public var isAnimating: Bool { animation != nil }

    /// What the drawing depends on. `ViewportView` passes it as the `MetalView`'s `value:`.
    public var renderKey: ViewportRenderKey {
        ViewportRenderKey(pose: pose, isAnimating: isAnimating, shading: shading, hovered: hovered,
                          hoveredCubeRegion: hoveredCubeRegion, sceneGeneration: sceneGeneration, handles: handles,
                          cube: cubeLayout)
    }

    /// The union of every shown solid's bounds, ghosts included.
    public var sceneBounds: BoundingBox? {
        items.reduce(BoundingBox?.none) { bounds, item in bounds?.union(item.solid.bounds) ?? item.solid.bounds }
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

    /// Animates from what's on screen now to `target` (spec §6.3: about 250 ms). `pose` becomes `target` at once.
    func animate(to target: CameraPose) {
        guard target.isFinite else { return }
        let now = clock.now()
        animation = CameraAnimation(from: presentedPose(at: now), to: target, start: now,
                                    duration: CameraAnimation.viewCubeDuration)
        pose = target
        animationTask?.cancel()
        let clock = clock
        animationTask = Task { [weak self] in
            await clock.sleep(for: CameraAnimation.viewCubeDuration)
            guard !Task.isCancelled else { return }
            self?.animation = nil
            self?.refreshHover()
        }
    }

    /// Freezes an animation where it is now, so input continues from what the user sees.
    func stopAnimation() {
        guard animation != nil else { return }
        pose = currentPose()
        animation = nil
        animationTask?.cancel()
    }

    /// Takes `next` as the camera, unless it's non-finite (which would make the view and the document unusable).
    func apply(_ next: CameraPose) {
        if next.isFinite, next != pose { pose = next }
    }

    /// Re-picks under a pointer that hasn't moved, after the camera or the scene changed beneath it, so the hover
    /// tint and the context menu (which reads the hover pick until C7 item 4) never name a face that's no longer
    /// under the pointer. Nothing is picked during a drag, so there the old pick is just dropped.
    func refreshHover() {
        if drag == nil {
            pointerHovered(at: lastHoverPoint)
        } else if hovered != nil {
            hovered = nil
        }
    }

    /// Records the view's size, from the draw. The first real size frames a scene that arrived before it. That's
    /// done from a task, because a draw must not write tracked state.
    func recordViewSize(_ size: ViewportSize) {
        let wasEmpty = viewSize.isEmpty
        viewSize = size
        guard wasEmpty, !size.isEmpty, needsFirstFraming, sceneBounds != nil else { return }
        framingTask = Task { [weak self] in self?.frameFirstSceneIfNeeded() }
    }

    /// Frames the first shown scene from the home view, once. It waits for a real view size: framed for a zero
    /// size, a narrow viewport would clip the part.
    private func frameFirstSceneIfNeeded() {
        guard needsFirstFraming, !viewSize.isEmpty, let bounds = sceneBounds else { return }
        needsFirstFraming = false
        pose = homePose ?? defaultHome(for: bounds)
    }

    /// Isometric, perspective, framed on `bounds`.
    func defaultHome(for bounds: BoundingBox) -> CameraPose {
        var home = ViewCubeRegion.isometric.pose(from: CameraPose())
        home.projection = .perspective
        return CameraNavigation.frame(bounds, home, size: viewSize)
    }
}
