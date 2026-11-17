import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Why one 3D model could not be used, as the phrase that goes in parentheses after its file's name ("the file isn't a STEP model").
struct ModelProblem: Error, Sendable, Equatable {
    var reason: String
    /// Whether the file's own contents caused it, so it will fail again until the file changes. A problem with the file's
    /// reachability or the kernel's abilities is tried again next time.
    var isRemembered: Bool

    init(_ reason: String, isRemembered: Bool = false) {
        self.reason = reason
        self.isRemembered = isRemembered
    }
}

/// The solids of 3D model files kept by what they were read from (KiCad import spec, Components). One switch used on sixty
/// footprints is read once and scaled once per distinct scale. Least recently used solids go first past `maxBytes`. A file whose
/// contents are wrong is remembered under its stamp and fails at once until the stamp changes (at most `maxProblems`); a read
/// that failed for another reason (missing file, a kernel that can't read models) is tried again every time.
actor ComponentModelCache {
    static let maxBytes = 512 << 20
    static let maxProblems = 256
    static let shared = ComponentModelCache()

    /// A model file as read: what it was (stamp), how it was read, and for which node (every face is tagged with the node).
    struct ReadKey: Hashable, Sendable {
        var stamp: ImageStamp
        var format: SolidModelFormat
        var node: NodeID
    }

    private enum Key: Hashable {
        case read(ReadKey)
        case scaled(ReadKey, Double, Double, Double)

        var readKey: ReadKey {
            switch self {
            case .read(let key), .scaled(let key, _, _, _): key
            }
        }
    }

    private var entries: [Key: (solid: Solid, bytes: Int, lastUsed: Int)] = [:]
    private var problems: [Key: (problem: ModelProblem, lastUsed: Int)] = [:]
    private var total = 0
    private var clock = 0
    private var readLog: [ReadKey] = []
    private var scaleLog: [ReadKey] = []

    init() {}

    /// The model for `key`: the kept one, else what `read` makes. The work runs outside the actor, so one slow model never holds
    /// up another; two evaluations of one new model may both read it.
    nonisolated func solid(for key: ReadKey, read: @Sendable () async throws -> Solid) async throws -> Solid {
        try await fetch(.read(key), read)
    }

    /// `key`'s model scaled by `factors`, kept the same way.
    nonisolated func scaled(of key: ReadKey, by factors: Vector3, make: @Sendable () async throws -> Solid) async throws -> Solid {
        try await fetch(.scaled(key, factors.x, factors.y, factors.z), make)
    }

    private nonisolated func fetch(_ key: Key, _ make: @Sendable () async throws -> Solid) async throws -> Solid {
        if let kept = try await lookup(key) { return kept }
        await noteRun(key)
        do {
            let made = try await make()
            await store(made, for: key)
            return made
        } catch let problem as ModelProblem {
            if problem.isRemembered { await storeProblem(problem, for: key) }
            throw problem
        }
    }

    private func noteRun(_ key: Key) {
        if case .read = key { readLog.append(key.readKey) } else { scaleLog.append(key.readKey) }
    }

    private func lookup(_ key: Key) throws -> Solid? {
        clock += 1
        if let kept = entries[key] {
            entries[key] = (kept.solid, kept.bytes, clock)
            return kept.solid
        }
        if let known = problems[key] {
            problems[key] = (known.problem, clock)
            throw known.problem
        }
        return nil
    }

    private func store(_ made: Solid, for key: Key) {
        guard key.readKey.stamp.isKeepable else { return }
        clock += 1
        let size = made.estimatedBytes
        if let old = entries[key] { total -= old.bytes }
        entries[key] = (made, size, clock)
        total += size
        while total > Self.maxBytes, entries.count > 1, let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            total -= oldest.value.bytes
            entries[oldest.key] = nil
        }
    }

    private func storeProblem(_ problem: ModelProblem, for key: Key) {
        guard key.readKey.stamp.isKeepable else { return }
        clock += 1
        problems[key] = (problem, clock)
        while problems.count > Self.maxProblems, let oldest = problems.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            problems[oldest.key] = nil
        }
    }

    var count: Int { entries.count }
    var problemCount: Int { problems.count }
    var byteCount: Int { total }

    /// How many models were read (not served from the cache) from files whose path contains `folder`: what the tests count.
    func reads(containing folder: String) -> Int { Self.count(readLog, containing: folder) }

    /// How many scaled copies were made of models read from files whose path contains `folder`.
    func scales(containing folder: String) -> Int { Self.count(scaleLog, containing: folder) }

    private static func count(_ log: [ReadKey], containing folder: String) -> Int {
        log.filter { key in
            if case .file(let path, _, _) = key.stamp { return path.contains(folder) }
            return false
        }.count
    }
}
