import CreatorGeometry
import CreatorKernel
import CreatorViewport
import Foundation
import Observation

/// Computes the section's cap off the main actor and holds it for the viewport (section spec §3.4). It follows the clip and
/// the shown parts; a newer request cancels the older, and the last cap stays until the new one lands. Nothing here is
/// document state: no command, no undo step.
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
    @ObservationIgnored private let tolerance: Double
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var followed: Key?

    private struct Key: Equatable {
        var clip: ViewportClip
        var solids: [Solid]

        /// Solids by identity; the key holds them, so a freed address can never match a new one.
        static func == (a: Key, b: Key) -> Bool {
            a.clip == b.clip && a.solids.count == b.solids.count && zip(a.solids, b.solids).allSatisfy { $0 === $1 }
        }
    }

    init(kernel: any Kernel, tolerance: Double) {
        self.kernel = kernel
        self.tolerance = tolerance
    }

    /// Sections the capped items (opaque, not guides) at `clip`, or clears the cap for `nil`. Returns at once when neither changed.
    func follow(clip: ViewportClip?, items: [ViewportItem]) {
        guard let clip, clip.isValid else {
            clear()
            return
        }
        let capped = items.filter { !$0.isGhost && !$0.isGuide }.map(\.solid)
        let key = Key(clip: clip, solids: capped)
        guard key != followed else { return }
        followed = key
        task?.cancel()
        generation += 1
        let current = generation
        isComputing = true
        let plane = SectionCaps.plane(for: clip)
        let (kernel, tolerance) = (kernel, tolerance)
        task = Task { [weak self] in
            var caps: [ViewportSection.Cap] = []
            var failed = false
            for solid in capped {
                do {
                    let result: PlaneSection
                    if let mesh = solid.displayedMesh {
                        result = await SectionCaps.slice(mesh, by: plane)
                    } else {
                        result = try await kernel.section(solid, by: plane, tolerance: tolerance)
                    }
                    try Task.checkCancellation()
                    if let cap = SectionCaps.cap(from: result, hatchAngle: ViewportSection.hatchAngle(forCap: caps.count)) {
                        caps.append(cap)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    failed = true
                }
            }
            self?.finish(current, caps: caps, plane: plane, failed: failed)
        }
    }

    /// Returns once the section under way has finished (or been replaced).
    func waitForCaps() async {
        await task?.value
    }

    /// Forgets everything, for a new or opened document.
    func reset() {
        clear()
    }

    private func clear() {
        guard followed != nil || section != nil || problem != nil || isComputing else { return }
        task?.cancel()
        generation += 1
        followed = nil
        isComputing = false
        section = nil
        problem = nil
        revision += 1
    }

    private func finish(_ current: Int, caps: [ViewportSection.Cap], plane: Plane, failed: Bool) {
        guard current == generation else { return }
        isComputing = false
        section = caps.isEmpty ? nil : ViewportSection(caps: caps, plane: plane, generation: current)
        problem = failed ? Self.capProblem : nil
        revision += 1
    }
}
