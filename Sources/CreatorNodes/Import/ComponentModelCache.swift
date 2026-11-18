import Foundation
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorPCB

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
        var format: ModelFormat
    }

    /// What a read made, and whether the file was still what the key's stamp says when it was read (else it is not kept).
    struct Made: Sendable {
        var solid: Solid
        var isCurrent = true
    }

    /// The tag node every kept solid carries; a node rewrites it to its own id when it uses the solid (`ModelTags.retargeted`).
    static let sentinel = NodeID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-4B4943414D32") ?? UUID())

    private enum Key: Hashable {
        case read(ReadKey)
        case scaled(ReadKey, Double, Double, Double)

        var readKey: ReadKey {
            switch self {
            case .read(let key), .scaled(let key, _, _, _): key
            }
        }
    }

    /// What a read made: a solid (STEP, IGES, IDF) or a mesh in its file's units (VRML, X3D).
    private enum Kept: Sendable {
        case solid(Solid)
        case mesh(ImportedModelMesh)

        var bytes: Int {
            switch self {
            case .solid(let solid): solid.estimatedBytes
            case .mesh(let model): model.mesh.estimatedBytes
            }
        }
    }

    private var entries: [Key: (kept: Kept, bytes: Int, lastUsed: Int)] = [:]
    private var problems: [Key: (problem: ModelProblem, lastUsed: Int)] = [:]
    private var total = 0
    private var clock = 0
    private var readLog: [ReadKey] = []
    private var scaleLog: [ReadKey] = []

    init() {}

    /// The model for `key`: the kept one, else what `read` makes. The work runs outside the actor, so one slow model never holds
    /// up another; two evaluations of one new model may both read it.
    nonisolated func solid(for key: ReadKey, read: @Sendable () async throws -> Made) async throws -> Made {
        let (kept, isCurrent) = try await fetch(.read(key)) {
            let made = try await read()
            return (.solid(made.solid), made.isCurrent)
        }
        guard case .solid(let solid) = kept else { throw ModelProblem("the file isn't a model of that kind") }
        return Made(solid: solid, isCurrent: isCurrent)
    }

    /// What a mesh read made, and whether the file was still what the key's stamp says when it was read (else it is not kept).
    struct MadeMesh: Sendable {
        var model: ImportedModelMesh
        var isCurrent = true
    }

    /// The mesh (in its file's units) for `key`, kept by the same budget and rules as a solid.
    nonisolated func mesh(for key: ReadKey, read: @Sendable () async throws -> MadeMesh) async throws -> MadeMesh {
        let (kept, isCurrent) = try await fetch(.read(key)) {
            let made = try await read()
            return (.mesh(made.model), made.isCurrent)
        }
        guard case .mesh(let model) = kept else { throw ModelProblem("the file isn't a model of that kind") }
        return MadeMesh(model: model, isCurrent: isCurrent)
    }

    /// `key`'s model scaled by `factors`, kept the same way.
    nonisolated func scaled(of key: ReadKey, by factors: Vector3, isCurrent: Bool,
                            make: @Sendable () async throws -> Solid) async throws -> Made {
        let (kept, current) = try await fetch(.scaled(key, factors.x, factors.y, factors.z)) { (.solid(try await make()), isCurrent) }
        guard case .solid(let solid) = kept else { throw ModelProblem("the file isn't a model of that kind") }
        return Made(solid: solid, isCurrent: current)
    }

    private nonisolated func fetch(_ key: Key, _ make: @Sendable () async throws -> (Kept, Bool)) async throws -> (Kept, Bool) {
        if let kept = try await lookup(key) { return (kept, true) }
        await noteRun(key)
        do {
            let made = try await make()
            if made.1 { await store(made.0, for: key) }
            return made
        } catch let problem as ModelProblem {
            if problem.isRemembered { await storeProblem(problem, for: key) }
            throw problem
        }
    }

    private func noteRun(_ key: Key) {
        if case .read = key { Self.append(key.readKey, to: &readLog) } else { Self.append(key.readKey, to: &scaleLog) }
    }

    /// The test counters keep the latest `maxLog` runs.
    private static let maxLog = 4_096

    private static func append(_ key: ReadKey, to log: inout [ReadKey]) {
        if log.count >= maxLog { log.removeFirst(maxLog / 2) }
        log.append(key)
    }

    private func lookup(_ key: Key) throws -> Kept? {
        clock += 1
        if let kept = entries[key] {
            entries[key] = (kept.kept, kept.bytes, clock)
            return kept.kept
        }
        if let known = problems[key] {
            problems[key] = (known.problem, clock)
            throw known.problem
        }
        return nil
    }

    private func store(_ made: Kept, for key: Key) {
        guard key.readKey.stamp.isKeepable else { return }
        clock += 1
        let size = made.bytes
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

    /// How many models were read (not served from the cache) from files whose path contains `folder`, or stored models whose hash
    /// contains it: what the tests count.
    func reads(containing folder: String) -> Int { Self.count(readLog, containing: folder) }

    /// How many scaled copies were made of models read from files whose path contains `folder`.
    func scales(containing folder: String) -> Int { Self.count(scaleLog, containing: folder) }

    private static func count(_ log: [ReadKey], containing folder: String) -> Int {
        log.filter { key in
            switch key.stamp {
            case .file(let path, _, _): return path.contains(folder)
            case .embedded(let hash, _): return hash.hex.contains(folder)
            default: return false
            }
        }.count
    }
}

/// Rewriting the tags of a cached or placed model's faces.
enum ModelTags {
    /// `solid` with every face tag passed through `change` (faces, edges and order untouched).
    static func rewritten(_ solid: Solid, _ change: (TopoTag) -> TopoTag) -> Solid {
        var topology = solid.topology
        for index in topology.faces.indices {
            topology.faces[index].tags = Set(topology.faces[index].tags.map(change))
        }
        return Solid(topology: topology, bounds: solid.bounds, storage: solid.storage)
    }

    /// `solid` with the tags of `ComponentModelCache.sentinel` naming `node` instead.
    static func retargeted(_ solid: Solid, to node: NodeID) -> Solid {
        rewritten(solid) { tag in
            tag.node == ComponentModelCache.sentinel ? TopoTag(node: node, item: tag.item, role: tag.role) : tag
        }
    }
}
