import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Foundation
import Observation

/// The measurements the person kept (measure spec, part B). They are the document's view state (`DocumentModel.measurements`);
/// the book resolves each one's anchors against the shown scene after every evaluation, reads its numbers, and measures the
/// distance between a pair off the main actor. A measurement whose anchors no longer resolve stays, reading "no longer found",
/// until a later scene finds them again.
@MainActor
@Observable
final class MeasureBook {
    struct Entry: Identifiable {
        let id: UUID
        /// The anchors resolved in the latest scene; `nil` when some no longer resolve (or no scene has been seen yet).
        var picks: [MeasurePick]?
        var readings: [MeasureReading]
        var distance: ShapeDistance?
        var isApproximate: Bool
        var meshResolution: Double?
        var isMeasuring: Bool
    }

    private(set) var entries: [Entry] = []
    /// Bumps on every change the viewport must draw again.
    private(set) var revision = 0
    /// The entries changed: the app shows the dimensions again.
    @ObservationIgnored var changed: (@MainActor () -> Void)?

    @ObservationIgnored private let kernel: any Kernel
    @ObservationIgnored private let document: DocumentModel
    @ObservationIgnored private var scene: MeasureScene?
    /// What each entry's distance was measured (or is being measured) for: its picks and the identity of the solids under them.
    @ObservationIgnored private var measured: [UUID: Basis] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// The solid index each entry's anchors last resolved on, for `MeasureResolver.resolve(_:in:preferring:)`.
    /// The latest distance that landed for each entry and what it was measured for, kept while the entry is lost, so a scene that
    /// loses a pick for one pass (a sketch closing) and finds it again does not measure it again.
    @ObservationIgnored private var settled: [UUID: (basis: Basis, distance: ShapeDistance)] = [:]
    @ObservationIgnored private var hints: [UUID: [Int]] = [:]

    private struct Basis: Equatable {
        var picks: [MeasurePick]
        var solids: [ObjectIdentifier]
    }

    init(kernel: any Kernel, document: DocumentModel) {
        self.kernel = kernel
        self.document = document
        entries = document.measurements.map(Self.unresolved)
    }

    private static func unresolved(_ kept: KeptMeasurement) -> Entry {
        Entry(id: kept.id, picks: nil, readings: [], distance: nil, isApproximate: false, meshResolution: nil, isMeasuring: false)
    }

    // MARK: - Editing (view state: no command, no undo step)

    /// Keeps `measurement`, resolved against the latest scene.
    /// `hints` are the solid indices its anchors were picked on, when known.
    func add(_ measurement: KeptMeasurement, hints: [Int] = []) {
        if hints.count == measurement.anchors.count { self.hints[measurement.id] = hints }
        document.measurements.append(measurement)
        refreshFromLastScene()
    }

    func remove(_ id: UUID) {
        document.measurements.removeAll { $0.id == id }
        settled[id] = nil
        refreshFromLastScene()
    }

    func removeAll() {
        guard !document.measurements.isEmpty else { return }
        document.measurements = []
        settled = [:]
        refreshFromLastScene()
    }

    private func refreshFromLastScene() {
        if let scene { refresh(scene) } else { rebuild() }
    }

    // MARK: - Following the scene

    /// Resolves every kept measurement in `scene` and makes the distances of the pairs whose picks, or a solid under them,
    /// changed; a newer refresh drops an older one's results.
    func refresh(_ scene: MeasureScene) {
        self.scene = scene
        var pending: [(UUID, MeasureElement, MeasureElement)] = []
        var isNewWork = false
        let previous = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next: [Entry] = []
        var bases: [UUID: Basis] = [:]
        for kept in document.measurements {
            let known = hints[kept.id]
            let resolved = kept.anchors.enumerated().compactMap { index, anchor in
                MeasureResolver.resolve(anchor, in: scene, preferring: known?[index])
            }
            guard !kept.anchors.isEmpty, resolved.count == kept.anchors.count else {
                next.append(Self.unresolved(kept))
                continue
            }
            hints[kept.id] = resolved.map(\.solidIndex)
            let basis = Basis(picks: resolved, solids: resolved.compactMap { identity(of: $0, in: scene) })
            bases[kept.id] = basis
            var entry = Entry(id: kept.id, picks: resolved,
                              readings: MeasureReadings.readings(for: resolved, topologies: topologies(of: resolved, in: scene)),
                              distance: nil, isApproximate: resolved.contains(where: \.isApproximate),
                              meshResolution: resolved.compactMap { MeasureResolver.meshResolution(of: $0, in: scene) }.max(),
                              isMeasuring: false)
            if resolved.count == 2 {
                let unchanged = measured[kept.id] == basis ? previous[kept.id] : nil
                if let unchanged, !unchanged.isMeasuring {
                    entry.distance = unchanged.distance
                } else if unchanged == nil, let again = settled[kept.id], again.basis == basis {
                    entry.distance = again.distance
                } else if let a = resolved[0].element(in: scene.solids), let b = resolved[1].element(in: scene.solids) {
                    entry.isMeasuring = true
                    pending.append((kept.id, a, b))
                    // Measuring the same picks on the same solids already: that work is left to finish.
                    if unchanged == nil { isNewWork = true }
                }
            }
            next.append(entry)
        }
        measured = bases
        entries = next
        // Cancelling a task does not stop a kernel call already running, so a refresh that changed nothing under the running
        // distances leaves them alone; any change restarts every unfinished one.
        if isNewWork || pending.isEmpty || task == nil {
            task?.cancel()
            task = nil
            generation += 1
            startDistances(pending)
        }
        bump()
    }

    /// Entries only (no scene yet): every measurement reads "no longer found" until the first evaluation.
    private func rebuild() {
        stop()
        measured = [:]
        entries = document.measurements.map(Self.unresolved)
        bump()
    }

    /// Drops the distances being measured: the book is going away or has nothing to follow.
    func stop() {
        task?.cancel()
        task = nil
        generation += 1
    }

    private func startDistances(_ jobs: [(UUID, MeasureElement, MeasureElement)]) {
        guard !jobs.isEmpty else { return }
        let generation = generation
        task = Task { [weak self, kernel] in
            for (id, a, b) in jobs {
                if Task.isCancelled { return }
                do {
                    let found = try await kernel.shortestDistance(between: a, and: b)
                    self?.landed(found, for: id, generation: generation)
                } catch {
                    // A task we cancelled has an older generation, so its result is dropped; any other failure reads as none.
                    self?.landed(nil, for: id, generation: generation)
                }
            }
        }
    }

    /// A distance for an older refresh than the latest is dropped.
    private func landed(_ found: ShapeDistance?, for id: UUID, generation: Int) {
        guard generation == self.generation, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].distance = found
        if let found, let basis = measured[id] { settled[id] = (basis, found) }
        entries[index].isMeasuring = false
        bump()
    }

    /// Waits until no distance is being computed.
    func waitForDistances() async {
        while let running = task {
            await running.value
            if task == running { task = nil }
        }
    }

    // MARK: - Drawing

    /// The dimensions of every found measurement, as references, ids `kept/<id>/<n>`.
    func dimensions(style: DimensionStyle, units: DocumentUnits) -> [OverlayDimension] {
        guard let scene else { return [] }
        return entries.flatMap { entry -> [OverlayDimension] in
            guard let picks = entry.picks else { return [] }
            let drawn = MeasureDimensions.dimensions(for: picks, readings: entry.readings, distance: entry.distance,
                                                     topologies: topologies(of: picks, in: scene), style: style, units: units)
            return drawn.enumerated().map { index, dimension in
                var renamed = dimension
                renamed.id = OverlayDimensionID("kept/\(entry.id.uuidString)/\(index)")
                return renamed
            }
        }
    }

    // MARK: - Helpers

    private func bump() {
        revision += 1
        changed?()
    }

    private func identity(of pick: MeasurePick, in scene: MeasureScene) -> ObjectIdentifier? {
        scene.solids.indices.contains(pick.solidIndex) ? ObjectIdentifier(scene.solids[pick.solidIndex]) : nil
    }

    private func topologies(of picks: [MeasurePick], in scene: MeasureScene) -> [Int: Topology] {
        var result: [Int: Topology] = [:]
        for pick in picks where scene.solids.indices.contains(pick.solidIndex) {
            result[pick.solidIndex] = scene.solids[pick.solidIndex].topology
        }
        return result
    }
}
