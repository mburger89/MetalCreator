import CreatorGeometry
import CreatorKernel
import Foundation

/// Face charts kept so editing a number downstream of a Face-mapped lattice measures nothing again (implicit spec §3.5: "baked once per
/// face and tolerance"). Keyed by the solid object, the face and the tolerance it was baked at; the least recently used go first once
/// the charts hold more than `capacity` bytes. An entry holds its solid, so its identity can't be reused while the entry exists.
public actor FaceChartCache {
    public static let shared = FaceChartCache()

    private struct Key: Hashable {
        var solid: ObjectIdentifier
        var face: Int
        var tolerance: Double
        /// The box the chart covers: blocks of one solid and tolerance can still cover different boxes (grown for a bake).
        var bounds: BoundingBox
    }

    private struct Entry {
        var solid: Solid
        var chart: FaceChart
        var used: Int
    }

    /// A measurement under way, and how many callers wait for it (`leaving` of them have been cancelled).
    private struct Flight {
        var id: UUID
        var task: Task<FaceChart, any Error>
        var waiters: Int
        var leaving = 0
    }

    public let capacity: Int
    private var inFlight: [Key: Flight] = [:]
    private var entries: [Key: Entry] = [:]
    private var clock = 0
    /// How many charts have been measured (a hit doesn't count).
    public private(set) var bakeCount = 0

    public init(capacity: Int = 256 * 1024 * 1024) {
        self.capacity = capacity
    }

    public var entryCount: Int { entries.count }
    public var totalBytes: Int { entries.values.reduce(0) { $0 + $1.chart.estimatedBytes } }

    /// The chart of `face` on the solid `blocks` were baked from, covering the box `blocks` cover, from the cache or made now.
    /// - Throws: `KernelError.invalidInput` for blocks that were not baked from a solid, and anything the kernel throws.
    public func chart(for blocks: DistanceBlocks, face: FaceID, kernel: any Kernel) async throws -> FaceChart {
        guard let source = blocks.source else { throw KernelError.invalidInput("These distances were not baked from a solid.") }
        let key = Key(solid: ObjectIdentifier(source.solid), face: face.rawValue, tolerance: source.tolerance, bounds: blocks.bounds)
        clock += 1
        if var hit = entries[key] {
            hit.used = clock
            entries[key] = hit
            return hit.chart
        }
        // Callers asking for a key that is being measured share the measurement. It runs in a task of its own, so one caller's
        // cancellation doesn't end it for the others; only when every caller has left is it cancelled and forgotten.
        let id: UUID
        if let running = inFlight[key] {
            id = running.id
            inFlight[key]?.waiters += 1
        } else {
            id = UUID()
            let bounds = blocks.bounds
            let task = Task { [self] in
                do {
                    let chart = try await FaceChartBaker.bake(bounds: bounds, solid: source.solid, face: face,
                                                              tolerance: source.tolerance, kernel: kernel)
                    store(chart, key, id, solid: source.solid)
                    return chart
                } catch {
                    finish(key, id)
                    throw error
                }
            }
            inFlight[key] = Flight(id: id, task: task, waiters: 1)
        }
        guard let task = inFlight[key]?.task else { throw CancellationError() }
        let chart = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(key, id) }
        }
        try Task.checkCancellation()
        return chart
    }

    /// A cancelled caller leaves its flight; the last to leave cancels the measurement.
    private func leave(_ key: Key, _ id: UUID) {
        guard var flight = inFlight[key], flight.id == id else { return }
        flight.leaving += 1
        inFlight[key] = flight
        if flight.leaving >= flight.waiters {
            flight.task.cancel()
            inFlight[key] = nil
        }
    }

    private func finish(_ key: Key, _ id: UUID) {
        if inFlight[key]?.id == id { inFlight[key] = nil }
    }

    private func store(_ chart: FaceChart, _ key: Key, _ id: UUID, solid: Solid) {
        bakeCount += 1
        clock += 1
        entries[key] = Entry(solid: solid, chart: chart, used: clock)
        finish(key, id)
        evict()
    }

    /// Drops the least recently used entries until the rest fit, keeping the newest.
    private func evict() {
        var bytes = totalBytes
        for (key, entry) in entries.sorted(by: { $0.value.used < $1.value.used }) where bytes > capacity && entries.count > 1 {
            entries[key] = nil
            bytes -= entry.chart.estimatedBytes
        }
    }
}
