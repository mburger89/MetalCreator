import CreatorGraph
import CreatorKernel
import Foundation

/// Why a model file could not be read, as the sentence a node shows. A fact about the file's contents, so it is remembered under the
/// file's stamp and fails at once until the stamp changes.
struct ImportedModelProblem: Error, Equatable, Sendable {
    var message: String
}

/// What a read of a model file made: its shapes and the format its bytes were.
struct ImportedModel: Sendable {
    var shapes: ImportedShapes
    var format: SolidModelFormat
}

/// The shapes of STEP and IGES model files kept by what they were read from (NURBS spec, Import Model): an embedded file by its
/// content hash, a linked one by path, modification date and size (`ImageStamp`), so moving or scaling an Import Model node never
/// reads the file again and two nodes on one file share one read. Every kept shape carries `sentinel` as its tag's node; a node
/// rewrites it to its own id when it uses them (`ImportedModelTags`). Least recently used files go first past `maxBytes`.
///
/// A file whose contents are wrong (the shim's own sentences, a format refusal) is remembered under its stamp (at most `maxProblems`); a file that could not be reached (missing,
/// permissions) an out-of-memory or other kernel failure, or a kernel that cannot read models is tried again every time, because fixing that changes no stamp. Only a stamp
/// that names a definite thing (`ImageStamp.isKeepable`) is kept.
actor ImportedModelCache {
    static let maxBytes = 512 << 20
    static let maxProblems = 256
    static let shared = ImportedModelCache()

    /// The node every kept shape's tags name.
    static let sentinel = NodeID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-4D4F44454C31") ?? UUID())

    private var entries: [ImageStamp: (model: ImportedModel, bytes: Int, lastUsed: Int)] = [:]
    private var problems: [ImageStamp: (problem: ImportedModelProblem, lastUsed: Int)] = [:]
    private var total = 0
    private var clock = 0
    private var reads = 0

    init() {}

    /// The shapes for `stamp`: the kept ones, else what `read` makes. The work runs outside the actor, so one slow file never holds up
    /// another; two evaluations of one new file may both read it.
    nonisolated func model(for stamp: ImageStamp, read: @Sendable () async throws -> ImportedModel) async throws -> ImportedModel {
        if let kept = try await lookup(stamp) { return kept }
        await noteRead()
        do {
            let made = try await read()
            await store(made, for: stamp)
            return made
        } catch let problem as ImportedModelProblem {
            await storeProblem(problem, for: stamp)
            throw problem
        }
    }

    private func noteRead() { reads += 1 }

    private func lookup(_ stamp: ImageStamp) throws -> ImportedModel? {
        clock += 1
        if let kept = entries[stamp] {
            entries[stamp] = (kept.model, kept.bytes, clock)
            return kept.model
        }
        if let known = problems[stamp] {
            problems[stamp] = (known.problem, clock)
            throw known.problem
        }
        return nil
    }

    private func store(_ model: ImportedModel, for stamp: ImageStamp) {
        let shapes = model.shapes
        guard stamp.isKeepable else { return }
        clock += 1
        let size = shapes.solids.reduce(0) { $0 + $1.estimatedBytes } + shapes.sheets.reduce(0) { $0 + $1.estimatedBytes }
            + shapes.curves.reduce(0) { $0 + $1.estimatedBytes }
        guard size <= Self.maxBytes else { return }
        if let old = entries[stamp] { total -= old.bytes }
        entries[stamp] = (model, size, clock)
        total += size
        while total > Self.maxBytes, entries.count > 1, let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            total -= oldest.value.bytes
            entries[oldest.key] = nil
        }
    }

    private func storeProblem(_ problem: ImportedModelProblem, for stamp: ImageStamp) {
        guard stamp.isKeepable else { return }
        clock += 1
        problems[stamp] = (problem, clock)
        while problems.count > Self.maxProblems, let oldest = problems.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            problems[oldest.key] = nil
        }
    }

    /// How many files are kept.
    var count: Int { entries.count }
    /// How many failed files are remembered.
    var problemCount: Int { problems.count }
    /// How many files were read (not served from the cache).
    var readCount: Int { reads }
}

/// Naming a cached model's shapes for the node that uses them.
enum ImportedModelTags {
    /// `solid` with every face and edge tag of `ImportedModelCache.sentinel` naming `node` instead (the order of faces and edges is
    /// untouched).
    static func retargeted(_ solid: Solid, to node: NodeID, item: Int) -> Solid {
        func change(_ tag: TopoTag) -> TopoTag {
            tag.node == ImportedModelCache.sentinel ? TopoTag(node: node, item: item, role: tag.role) : tag
        }
        var topology = solid.topology
        for index in topology.faces.indices {
            topology.faces[index].tags = Set(topology.faces[index].tags.map(change))
        }
        for index in topology.edges.indices {
            topology.edges[index].tags = Set(topology.edges[index].tags.map(change))
        }
        return Solid(topology: topology, bounds: solid.bounds, storage: solid.storage)
    }
}
