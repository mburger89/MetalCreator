import CreatorKernel

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
        var compound: Solid?
        var projection: Projection2D
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
    private struct Flight {
        var id: Int
        var task: Task<Void, Never>
        var waiters: [Int: CheckedContinuation<Projection2D, any Error>]
    }

    private var inFlight: [Key: Flight] = [:]
    private var waiterSerial = 0
    private var flightSerial = 0
    private var clock = 0

    public private(set) var bytesUsed = 0
    public private(set) var kernelCalls = 0
    public private(set) var compoundCalls = 0
    public var count: Int { entries.count }

    public init(limit: Int = 512 * 1024 * 1024) {
        self.limit = limit
    }

    public func projection(
        of solids: [Solid], curves: [Curve], compoundTag: NodeTag, frame: ProjectionFrame, options: ProjectionOptions,
        kernel: any Kernel
    ) async throws -> Projection2D {
        let key = Key(
            solids: solids.map(ObjectIdentifier.init), curves: curves.map(ObjectIdentifier.init), compoundTag: compoundTag,
            frame: frame, options: options)
        if var hit = entries[key] {
            clock += 1
            hit.stamp = clock
            entries[key] = hit
            return hit.projection
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

    private func join(_ key: Key, waiter: Int, request: Request, kernel: any Kernel) async throws -> Projection2D {
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
        let result: Result<Projection2D, any Error>
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
        bytesUsed = 0
    }

    private func build(_ key: Key, _ request: Request, _ kernel: any Kernel) async throws -> Projection2D {
        let (solids, curves, tag) = (request.solids, request.curves, request.tag)
        let (frame, options) = (request.frame, request.options)
        var compound: Solid?
        var target = solids.first
        if solids.count > 1 {
            compoundCalls += 1
            let made = try await kernel.compound(solids, tag: tag)
            compound = made
            target = made
        }
        kernelCalls += 1
        let projection = try await kernel.projection(of: target, curves: curves, frame: frame, options: options)
        try Task.checkCancellation()
        clock += 1
        let bytes = projection.estimatedBytes
        entries[key] = Entry(
            solids: solids, curves: curves, compound: compound, projection: projection, bytes: bytes, stamp: clock)
        bytesUsed += bytes
        evict(keeping: key)
        return projection
    }

    private func evict(keeping newest: Key) {
        while bytesUsed > limit, entries.count > 1 {
            guard let oldest = entries.filter({ $0.key != newest }).min(by: { $0.value.stamp < $1.value.stamp }) else { return }
            bytesUsed -= oldest.value.bytes
            entries[oldest.key] = nil
        }
    }
}
