import CreatorKernel

/// A projection with the topology of the solid it shows (plan R26): one solid's own, the compound's for several, nil for none.
public struct CachedProjection: Sendable {
    public var projection: Projection2D
    public var topology: Topology?

    public init(projection: Projection2D, topology: Topology?) {
        self.projection = projection
        self.topology = topology
    }
}

/// Projections by the identities of what they were made from (plan R19). Keyed on the source solids and curves, never on a
/// compound of them (`Kernel.compound` returns a new `Solid` every call); a miss with two or more solids compounds them once.
public actor ProjectionCache {
    private struct Key: Hashable {
        var solids: [ObjectIdentifier]
        var curves: [ObjectIdentifier]
        var compoundTag: NodeTag
        var frame: ProjectionFrame
        var options: ProjectionOptions
    }

    /// The entry keeps its inputs alive so an identity can't be reused while it is cached.
    private struct Entry {
        var solids: [Solid]
        var curves: [Curve]
        var cached: CachedProjection
        var bytes: Int
        var stamp: Int
    }

    private struct CompoundKey: Hashable {
        var solids: [ObjectIdentifier]
        var tag: NodeTag
    }

    /// The compound of a set of solids, made once and shared by a topology request and a projection (plan R26). It keeps its
    /// inputs alive so an identity can't be reused while it is cached.
    private struct CompoundEntry {
        var solids: [Solid]
        var compound: Solid
        var bytes: Int
        var stamp: Int
    }

    private struct CutKey: Hashable {
        var solid: ObjectIdentifier
        var index: Int
        var cutter: SectionCutter
        var tolerance: Double
    }

    /// A cut and its regions; it keeps the solid alive so an identity can't be reused while it is cached.
    private struct CutEntry {
        var solid: Solid
        var piece: SectionCutPiece
        var bytes: Int
        var stamp: Int
    }

    private struct Request: Sendable {
        var solids: [Solid]
        var curves: [Curve]
        var tag: NodeTag
        var frame: ProjectionFrame
        var options: ProjectionOptions
    }

    private let limit: Int
    private var entries: [Key: Entry] = [:]
    private var compounds: [CompoundKey: CompoundEntry] = [:]
    private var compoundFlights: [CompoundKey: Task<Solid, any Error>] = [:]
    private var cuts: [CutKey: CutEntry] = [:]
    private struct CutFlight {
        var id: Int
        var task: Task<SectionCutPiece, any Error>
        var waiters: Int
    }

    private var cutFlights: [CutKey: CutFlight] = [:]
    private struct Flight {
        var id: Int
        var task: Task<Void, Never>
        var waiters: [Int: CheckedContinuation<CachedProjection, any Error>]
    }

    private var inFlight: [Key: Flight] = [:]
    private var waiterSerial = 0
    private var flightSerial = 0
    private var clock = 0

    public private(set) var bytesUsed = 0
    public private(set) var kernelCalls = 0
    public private(set) var compoundCalls = 0
    /// Cuts made (not served from the cache).
    public private(set) var cutCalls = 0
    public var count: Int { entries.count }
    /// Cuts held in the cache (finished, not in flight); for tests.
    var cachedCutCount: Int { cuts.count }
    /// Callers currently waiting on cuts in flight, summed over flights; for tests.
    var cutWaiterCount: Int { cutFlights.values.reduce(0) { $0 + $1.waiters } }

    public init(limit: Int = 512 * 1024 * 1024) {
        self.limit = limit
    }

    public func projection(
        of solids: [Solid], curves: [Curve], compoundTag: NodeTag, frame: ProjectionFrame, options: ProjectionOptions,
        kernel: any Kernel
    ) async throws -> CachedProjection {
        let key = Key(
            solids: solids.map(ObjectIdentifier.init), curves: curves.map(ObjectIdentifier.init), compoundTag: compoundTag,
            frame: frame, options: options)
        if var hit = entries[key] {
            clock += 1
            hit.stamp = clock
            entries[key] = hit
            return hit.cached
        }
        waiterSerial += 1
        let waiter = waiterSerial
        let request = Request(solids: solids, curves: curves, tag: compoundTag, frame: frame, options: options)
        let result = try await withTaskCancellationHandler {
            try await join(key, waiter: waiter, request: request, kernel: kernel)
        } onCancel: {
            Task { await self.leave(key, waiter: waiter) }
        }
        try Task.checkCancellation()
        return result
    }

    /// Waiters in flight, over every key (a test reads it to know a request has joined).
    public var waitingCount: Int { inFlight.values.reduce(0) { $0 + $1.waiters.count } }

    private func join(_ key: Key, waiter: Int, request: Request, kernel: any Kernel) async throws -> CachedProjection {
        try await withCheckedThrowingContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
                return
            }
            if var flight = inFlight[key] {
                flight.waiters[waiter] = continuation
                inFlight[key] = flight
            } else {
                flightSerial += 1
                let id = flightSerial
                let task = Task { await self.run(key, flight: id, request, kernel) }
                inFlight[key] = Flight(id: id, task: task, waiters: [waiter: continuation])
            }
        }
    }

    /// A waiter that is cancelled leaves at once; the last one to go cancels the shared build and drops it.
    private func leave(_ key: Key, waiter: Int) {
        guard var flight = inFlight[key], let continuation = flight.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            inFlight[key] = nil
            flight.task.cancel()
        } else {
            inFlight[key] = flight
        }
    }

    private func run(_ key: Key, flight id: Int, _ request: Request, _ kernel: any Kernel) async {
        let result: Result<CachedProjection, any Error>
        do {
            result = .success(try await build(key, request, kernel))
        } catch {
            result = .failure(error)
        }
        // A build every waiter left was dropped from `inFlight` already (and a newer one may hold the key).
        guard let flight = inFlight[key], flight.id == id else { return }
        inFlight[key] = nil
        for continuation in flight.waiters.values { continuation.resume(with: result) }
    }

    public func removeAll() {
        entries.removeAll()
        compounds.removeAll()
        cuts.removeAll()
        bytesUsed = 0
    }

    /// The topology of the solids a view shows (plan R26): nil for none, a single solid's own with no kernel call, else the
    /// compound's, made once per set of solid identities and tag.
    public func topology(of solids: [Solid], compoundTag: NodeTag, kernel: any Kernel) async throws -> Topology? {
        guard let first = solids.first else { return nil }
        if solids.count == 1 { return first.topology }
        let made = try await compound(of: solids, tag: compoundTag, kernel: kernel)
        try Task.checkCancellation()
        return made.topology
    }

    private func compound(of solids: [Solid], tag: NodeTag, kernel: any Kernel) async throws -> Solid {
        let key = CompoundKey(solids: solids.map(ObjectIdentifier.init), tag: tag)
        if var hit = compounds[key] {
            clock += 1
            hit.stamp = clock
            compounds[key] = hit
            return hit.compound
        }
        if let flight = compoundFlights[key] { return try await flight.value }
        compoundCalls += 1
        let flight = Task { try await kernel.compound(solids, tag: tag) }
        compoundFlights[key] = flight
        let made: Solid
        do {
            made = try await flight.value
        } catch {
            compoundFlights[key] = nil
            throw error
        }
        compoundFlights[key] = nil
        clock += 1
        let bytes = Self.estimatedBytes(of: made.topology)
        compounds[key] = CompoundEntry(solids: solids, compound: made, bytes: bytes, stamp: clock)
        bytesUsed += bytes
        evict()
        return made
    }

    private static func estimatedBytes(of topology: Topology) -> Int {
        256 * (topology.faces.count + topology.edges.count) + 64
    }

    private func build(_ key: Key, _ request: Request, _ kernel: any Kernel) async throws -> CachedProjection {
        let (solids, curves, tag) = (request.solids, request.curves, request.tag)
        let (frame, options) = (request.frame, request.options)
        var target = solids.first
        if solids.count > 1 { target = try await compound(of: solids, tag: tag, kernel: kernel) }
        kernelCalls += 1
        let projection = try await kernel.projection(of: target, curves: curves, frame: frame, options: options)
        try Task.checkCancellation()
        clock += 1
        let bytes = projection.estimatedBytes
        let cached = CachedProjection(projection: projection, topology: target?.topology)
        entries[key] = Entry(solids: solids, curves: curves, cached: cached, bytes: bytes, stamp: clock)
        bytesUsed += bytes
        evict()
        return cached
    }

    /// Drops the least recently used projection, compound or cut until the limit holds, always keeping the newest of all.
    private func evict() {
        while bytesUsed > limit, entries.count + compounds.count + cuts.count > 1 {
            let oldestEntry = entries.min { $0.value.stamp < $1.value.stamp }
            let oldestCompound = compounds.min { $0.value.stamp < $1.value.stamp }
            let oldestCut = cuts.min { $0.value.stamp < $1.value.stamp }
            let stamps = [oldestEntry?.value.stamp, oldestCompound?.value.stamp, oldestCut?.value.stamp].compactMap { $0 }
            guard let lowest = stamps.min() else { return }
            if let entry = oldestEntry, entry.value.stamp == lowest {
                bytesUsed -= entry.value.bytes
                entries[entry.key] = nil
            } else if let compound = oldestCompound, compound.value.stamp == lowest {
                bytesUsed -= compound.value.bytes
                compounds[compound.key] = nil
            } else if let cut = oldestCut {
                bytesUsed -= cut.value.bytes
                cuts[cut.key] = nil
            } else {
                return
            }
        }
    }
}

extension ProjectionCache {
    /// What one solid gives a section view (R14): its remainder past the cutting line and the regions to hatch, made once per solid
    /// identity, index, cutter and tolerance. Regions are in `SectionFrame.frame(for: cutter)`'s plane.
    public func sectionCut(
        of solid: Solid, index: Int, cutter: SectionCutter, tolerance: Double, kernel: any Kernel
    ) async throws -> SectionCutPiece {
        let key = CutKey(solid: ObjectIdentifier(solid), index: index, cutter: cutter, tolerance: tolerance)
        if var hit = cuts[key] {
            clock += 1
            hit.stamp = clock
            cuts[key] = hit
            return hit.piece
        }
        let flight: CutFlight
        if var joined = cutFlights[key] {
            joined.waiters += 1
            cutFlights[key] = joined
            flight = joined
        } else {
            cutCalls += 1
            flightSerial += 1
            let id = flightSerial
            let task = Task {
                try await self.runCut(key, flight: id, solid: solid, kernel: kernel)
            }
            flight = CutFlight(id: id, task: task, waiters: 1)
            cutFlights[key] = flight
        }
        // A cancelled caller leaves; the last one to go cancels the shared cut, so a dragged cutting line never queues booleans.
        let piece = try await withTaskCancellationHandler {
            try await flight.task.value
        } onCancel: {
            Task { await self.leaveCut(key, flight: flight.id) }
        }
        try Task.checkCancellation()
        return piece
    }

    /// Builds one cut and caches it unless it was cancelled or superseded.
    private func runCut(_ key: CutKey, flight id: Int, solid: Solid, kernel: any Kernel) async throws -> SectionCutPiece {
        do {
            let piece = try await SectionMaker.cut(
                solid, index: key.index, cutter: key.cutter, tolerance: key.tolerance, kernel: kernel)
            try Task.checkCancellation()
            if cutFlights[key]?.id == id { cutFlights[key] = nil }
            clock += 1
            let bytes = piece.estimatedBytes
            if let old = cuts[key] { bytesUsed -= old.bytes }
            cuts[key] = CutEntry(solid: solid, piece: piece, bytes: bytes, stamp: clock)
            bytesUsed += bytes
            evict()
            return piece
        } catch {
            if cutFlights[key]?.id == id { cutFlights[key] = nil }
            throw error
        }
    }

    private func leaveCut(_ key: CutKey, flight id: Int) {
        guard var flight = cutFlights[key], flight.id == id else { return }
        flight.waiters -= 1
        if flight.waiters <= 0 {
            cutFlights[key] = nil
            flight.task.cancel()
        } else {
            cutFlights[key] = flight
        }
    }
}
