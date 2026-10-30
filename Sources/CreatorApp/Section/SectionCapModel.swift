import CreatorGeometry
import CreatorKernel
import CreatorViewport
import Foundation
import Observation

/// Computes the section's cap off the main actor and holds it for the viewport (section spec §3.4). It follows the clip and
/// the shown parts and the last cap stays until the new one lands. At most one computation runs and only the latest
/// request waits. A request that moves only the clip lets the running one finish and publish (an older cap is fine, the
/// viewport clips it to the current plane; a slice that takes longer than a drag step would otherwise never land); one that
/// changes the solids or the tolerance cancels the running one, which publishes nothing. Nothing here is document state:
/// no command, no undo step.
@MainActor @Observable
final class SectionCapModel {
    /// What the Section panel says when a part's cut face could not be filled.
    static let capProblem = "The cut face couldn't be filled for every part."

    /// Counts every change of `section` or `problem`, for the scene's observation.
    private(set) var revision = 0
    private(set) var section: ViewportSection?
    private(set) var problem: String?
    private(set) var isComputing = false

    @ObservationIgnored private let kernel: any Kernel
    @ObservationIgnored private let defaultTolerance: Double
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var pending: Request?
    @ObservationIgnored private var generation = 0
    /// The generation at the last `clear()`: a computation from before it publishes nothing.
    @ObservationIgnored private var clearedGeneration = 0
    /// The request under way, to tell a moved clip from an edit.
    @ObservationIgnored private var current: Request?
    /// Set when the running computation was cancelled, so a result that slipped past its last check is dropped.
    @ObservationIgnored private var discardsRunning = false
    @ObservationIgnored private var followed: Key?
    /// How many mesh slices have been started (for tests: a burst of moves must not start one per move).
    @ObservationIgnored private(set) var slicesStarted = 0

    /// What one computation is asked to cut.
    private struct Request {
        var generation: Int
        var plane: Plane
        var solids: [Solid]
        var tolerance: Double

        /// Whether `other` cuts the same solids (by identity) at the same tolerance, whatever the plane.
        func sameInputs(as other: Request) -> Bool {
            tolerance == other.tolerance && solids.count == other.solids.count
                && zip(solids, other.solids).allSatisfy { $0 === $1 }
        }
    }

    private struct Key: Equatable {
        var clip: ViewportClip
        var solids: [Solid]
        var tolerance: Double

        /// Solids by identity; the key holds them, so a freed address can never match a new one.
        static func == (a: Key, b: Key) -> Bool {
            a.clip == b.clip && a.tolerance == b.tolerance && a.solids.count == b.solids.count
                && zip(a.solids, b.solids).allSatisfy { $0 === $1 }
        }
    }

    /// `tolerance` is the chord tolerance used until a `follow` gives one.
    init(kernel: any Kernel, tolerance: Double) {
        self.kernel = kernel
        defaultTolerance = tolerance
    }

    /// Sections the capped items (opaque, not guides) at `clip`, or clears the cap for `nil`. `tolerance` is the viewport's current tessellation tolerance. Returns at once when neither changed.
    func follow(clip: ViewportClip?, items: [ViewportItem], tolerance: Double? = nil) {
        guard let clip, clip.isValid else {
            clear()
            return
        }
        let capped = items.filter { !$0.isGhost && !$0.isGuide }.map(\.solid)
        let key = Key(clip: clip, solids: capped, tolerance: tolerance ?? defaultTolerance)
        guard key != followed else { return }
        followed = key
        generation += 1
        isComputing = true
        let request = Request(generation: generation, plane: SectionCaps.plane(for: clip), solids: capped,
                              tolerance: tolerance ?? defaultTolerance)
        // At most one computation runs; a newer request waits for it to end (cancelled only when the solids or tolerance
        // changed) and is the only one that then starts.
        if let running, let current {
            if !current.sameInputs(as: request) {
                running.cancel()
                discardsRunning = true
            }
            pending = request
        } else {
            start(request)
        }
    }

    /// Returns once the section under way, and any request queued behind it, has finished (or been replaced).
    func waitForCaps() async {
        while let task = running { await task.value }
    }

    private func start(_ request: Request) {
        let kernel = kernel
        current = request
        discardsRunning = false
        running = Task { [weak self] in
            var caps: [ViewportSection.Cap] = []
            var failed = false
            var cancelled = false
            for (index, solid) in request.solids.enumerated() {
                do {
                    try Task.checkCancellation()
                    let result: PlaneSection
                    if let mesh = solid.displayedMesh {
                        self?.slicesStarted += 1
                        result = await SectionCaps.slice(mesh, by: request.plane)
                    } else {
                        result = try await kernel.section(solid, by: request.plane, tolerance: request.tolerance)
                    }
                    try Task.checkCancellation()
                    if SectionCaps.isUnfilled(result) { failed = true }
                    if let cap = SectionCaps.cap(from: result, hatchAngle: ViewportSection.hatchAngle(forCap: index)) {
                        caps.append(cap)
                    }
                } catch is CancellationError {
                    cancelled = true
                    break
                } catch {
                    failed = true
                }
            }
            self?.ended(request, caps: cancelled ? nil : caps, failed: failed)
        }
    }

    /// A computation is over: publish it unless it was cancelled or predates a clear (it may be older than the latest
    /// request), then start the one queued behind it.
    private func ended(_ request: Request, caps: [ViewportSection.Cap]?, failed: Bool) {
        running = nil
        current = nil
        let publishes = caps != nil && !discardsRunning && request.generation > clearedGeneration
        discardsRunning = false
        let next = pending
        pending = nil
        if publishes, let caps {
            section = caps.isEmpty ? nil : ViewportSection(caps: caps, plane: request.plane, generation: request.generation)
            problem = failed ? Self.capProblem : nil
            revision += 1
        }
        if let next {
            start(next)
        } else if publishes || request.generation == generation {
            isComputing = false
        }
    }

    /// Forgets everything, for a new or opened document.
    func reset() {
        clear()
    }

    private func clear() {
        guard followed != nil || section != nil || problem != nil || isComputing else { return }
        running?.cancel()
        discardsRunning = true
        pending = nil
        generation += 1
        clearedGeneration = generation
        followed = nil
        isComputing = false
        section = nil
        problem = nil
        revision += 1
    }
}
