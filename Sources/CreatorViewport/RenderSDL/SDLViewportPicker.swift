#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// Answers "what is under this point?" from the ID pass (spec §6.3) on SDL_GPU. Reading a texture back is asynchronous here: the pass
/// is recorded and submitted as a batch of its own (`SDLGPUDevice.submitBatch`), its fence awaited off the main actor, and the `r32Uint`
/// words downloaded. So the picker works ahead: the draw that follows a change of camera or scene calls ``schedule(_:)``, which starts
/// the pass once the view has been still for ``settleDelay`` (an orbit draws every frame, and a read-back per frame nobody asked for
/// would be waste), the ID buffer lands a few milliseconds after that, and ``pick(at:in:)`` reads it with no wait, as `ViewportPicker`
/// reads Metal's: a hover's answer (user decision U4, hybrid). A click does not wait for the quiet: ``pickWhenReady(at:in:)`` answers
/// from the buffer for the click's own view, and when none has landed renders it now and waits for the GPU (MetalUI's
/// `submitBatchSynchronously`, `SDLGPUFence.waitBlocking()` and `SDLGPUDevice.downloadSynchronously`: gaps XP-G22 and XP-G14), never
/// answering from another view's buffer.
///
/// A pick for a view whose buffer has not landed answers `nil` and ``isPending(for:)`` says so. The buffer is kept until the camera or
/// the scene changes (`PickKey`), as Metal's is. A pass that fails (no GPU memory, a lost device, meshes not uploaded yet) counts as
/// landed with nothing in it, so nothing waits for it forever; the next draw's ``schedule(_:)`` and the next ``refresh(_:)`` try again.
@MainActor
final class SDLViewportPicker {
    /// How long the view must be still before a draw's ``schedule(_:)`` starts the ID pass.
    static let settleDelay = Duration.milliseconds(40)

    private enum Landed {
        case pixels(width: Int, height: Int, words: [UInt32])
        /// The pass could not run; ``schedule(_:)`` and ``refresh(_:)`` run it again.
        case failed
    }

    private let device: SDLGPUDevice
    private let renderer: SDLViewportRenderer
    private var landed: (key: PickKey, result: Landed)?
    /// Every pass takes a ticket when it starts; a result lands only if no later pass has landed (a click's pass can overtake a batch).
    private var tickets = 0
    private var landedTicket = 0
    /// The newest frame asked for; a pass in flight for an older view is followed by one for this.
    private var wanted: ViewportFrame?
    private var running = false
    private var settleTask: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Called after a buffer has landed (`ViewportModel.refreshHover`).
    var onReady: (@MainActor () -> Void)?
    /// ID passes that have landed. Tests use it to check the read-back is reused.
    private(set) var renderCount = 0

    init(renderer: SDLViewportRenderer) {
        self.renderer = renderer
        device = renderer.device
    }

    /// The face or edge under `point` (viewport points), or `nil` for empty space, a point outside the view, a view with no size
    /// yet, or a buffer that has not landed.
    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        guard !frame.size.isEmpty, point.x.isFinite, point.y.isFinite,
              let landed, landed.key == frame.pickKey, case .pixels(let width, let height, let words) = landed.result else { return nil }
        guard point.x >= 0, point.y >= 0, point.x < Double(width), point.y < Double(height) else { return nil }
        return PickID.decode(words[Int(point.y) * width + Int(point.x)])
    }

    /// Whether the buffer for `frame` has yet to land: ``pick(at:in:)`` would answer `nil` for want of it. A pass that failed has
    /// landed, with nothing in it.
    func isPending(for frame: ViewportFrame) -> Bool {
        guard !frame.size.isEmpty else { return false }
        return landed?.key != frame.pickKey
    }

    /// Whether the ID pass has still to run for `frame`. A pass that failed counts as run unless `retryFailed`.
    private func needsPass(for frame: ViewportFrame, retryFailed: Bool) -> Bool {
        guard !frame.size.isEmpty else { return false }
        guard let landed, landed.key == frame.pickKey else { return true }
        if retryFailed, case .failed = landed.result { return true }
        return false
    }

    /// Makes sure the buffer for `frame` is on its way, once the view has been still for ``settleDelay``. The draw calls it after it
    /// encodes, once the frame's meshes are on the GPU; a newer call replaces an older one that has not started.
    func schedule(_ frame: ViewportFrame) {
        guard needsPass(for: frame, retryFailed: true) else { return }
        wanted = frame
        armSettle()
    }

    private func armSettle() {
        guard !running else { return }   // the pass in flight re-arms it when it ends
        settleTask?.cancel()
        settleTask = Task { [self] in
            try? await Task.sleep(for: Self.settleDelay)
            if !Task.isCancelled { start() }
        }
    }

    /// Starts the pass for `wanted` now, unless one is running (it takes `wanted` when it ends).
    private func start() {
        settleTask?.cancel()
        settleTask = nil
        guard !running, wanted != nil else { return }
        running = true
        Task { await self.run() }
    }

    /// Returns once the buffer for `frame` has landed, running its pass at once (the quiet is not waited for). A buffer that landed
    /// failed is tried again once. Tests await it.
    func refresh(_ frame: ViewportFrame) async {
        if needsPass(for: frame, retryFailed: true) {
            wanted = frame
            start()
        }
        await idle()
        // A pass for an older view may have been in flight and taken the place of this one.
        if needsPass(for: frame, retryFailed: false) {
            wanted = frame
            start()
            await idle()
        }
    }

    /// Returns once no pass is running.
    private func idle() async {
        while running {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// The click's pick: ``pick(at:in:)`` from the buffer for `frame`, rendered now and waited for when it has not landed (or landed
    /// failed). It blocks the main actor for one ID pass, as Metal's picker does; it is called outside a draw (a click), never inside one.
    /// A pass that fails (typically a click right after an edit, before the next draw has uploaded the new meshes) answers empty space at
    /// once, and the next draw's ``schedule(_:)`` or the next click tries again.
    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        if needsPass(for: frame, retryFailed: true) {
            let ticket = nextTicket()
            land(renderNow(frame), for: frame.pickKey, ticket: ticket)
        }
        return pick(at: point, in: frame)
    }

    /// Renders the ID pass for the frame asked for last. The bookkeeping around the pass is synchronous (`takeWanted`, `land`,
    /// `finish`), so no loop's locals are held across an `await` (the Windows Swift 6.4 compiler asserts on that).
    private func run() async {
        if let frame = takeWanted() {
            let ticket = nextTicket()
            let result = await render(frame)
            land(result, for: frame.pickKey, ticket: ticket)
        }
        finish()
    }

    private func nextTicket() -> Int {
        tickets += 1
        return tickets
    }

    private func takeWanted() -> ViewportFrame? {
        defer { wanted = nil }
        return wanted
    }

    /// Keeps `result` as the buffer for `key` and tells the model, unless a pass that started later has landed already.
    private func land(_ result: Landed, for key: PickKey, ticket: Int) {
        guard ticket > landedTicket else { return }
        landedTicket = ticket
        landed = (key, result)
        if case .pixels = result { renderCount += 1 }
        onReady?()
    }

    /// The pass is over: a request that came meanwhile waits for the quiet again, and whoever waits for the pass is woken.
    private func finish() {
        running = false
        if wanted != nil { armSettle() }
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }

    /// One ID pass's inputs and targets, made here on the main actor, or the answer when there is nothing to render.
    private enum Prepared {
        case answered(Landed)
        case pass(width: Int, height: Int, inputs: SDLIDPassInputs, ids: SDLGPUTexture, depth: SDLGPUTexture)
    }

    private func prepare(_ frame: ViewportFrame) -> Prepared {
        let width = Int(frame.size.width.rounded(.down))
        let height = Int(frame.size.height.rounded(.down))
        guard width > 0, height > 0, let inputs = renderer.idPassInputs(for: frame, width: width, height: height) else {
            return .answered(.failed)
        }
        if inputs.isEmpty {
            return .answered(.pixels(width: width, height: height, words: [UInt32](repeating: 0, count: width * height)))
        }
        guard let ids = device.makeTexture(SDLGPUTextureDescription(width: width, height: height, format: SDLViewportPipelines.idFormat,
                                                                    usage: [.colorTarget])),
              let depth = device.makeTexture(SDLGPUTextureDescription(width: width, height: height, format: .d32Float,
                                                                      usage: [.depthStencilTarget])) else { return .answered(.failed) }
        return .pass(width: width, height: height, inputs: inputs, ids: ids, depth: depth)
    }

    /// The words of a read-back ID texture, or `.failed` when the read-back is missing or the wrong size.
    private static func words(_ bytes: [UInt8]?, width: Int, height: Int) -> Landed {
        guard let bytes, bytes.count == width * height * MemoryLayout<UInt32>.stride else { return .failed }
        return .pixels(width: width, height: height, words: bytes.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) })
    }

    /// The pass in a batch of its own, awaited off the main actor (the ahead-of-time path a hover reads).
    private func render(_ frame: ViewportFrame) async -> Landed {
        switch prepare(frame) {
        case .answered(let answer):
            return answer
        case .pass(let width, let height, let inputs, let ids, let depth):
            guard let fence = try? await device.submitBatch({ commandBuffer in
                SDLViewportRenderer.encodeIDs(inputs, into: ids, depth: depth, commandBuffer: commandBuffer)
            }) else { return .failed }
            await fence.wait()
            return Self.words(await device.download(ids), width: width, height: height)
        }
    }

    /// The pass now, on the main actor, waited for (a click's path): submitted without `await` (XP-G22), the fence waited on, the words
    /// read back synchronously (XP-G14).
    private func renderNow(_ frame: ViewportFrame) -> Landed {
        switch prepare(frame) {
        case .answered(let answer):
            return answer
        case .pass(let width, let height, let inputs, let ids, let depth):
            guard let fence = try? device.submitBatchSynchronously({ commandBuffer in
                SDLViewportRenderer.encodeIDs(inputs, into: ids, depth: depth, commandBuffer: commandBuffer)
            }) else { return .failed }
            fence.waitBlocking()
            return Self.words(device.downloadSynchronously(ids), width: width, height: height)
        }
    }
}
#endif
