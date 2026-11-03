import CreatorGraph
import CreatorImplicit

/// Parsed mesh files kept by what they were read from (mesh import spec, the node): an embedded file by its content hash, a linked
/// one by path, modification date and size (`ImageStamp`), so moving or scaling an Import Mesh node never parses again and two
/// nodes on one file share one read. Least recently used meshes go first when the meshes kept pass `budgetBytes`.
///
/// A file whose bytes are wrong (not an STL, cut short) is remembered under its stamp and fails at once until the stamp changes; at
/// most `maxProblems` are kept. A file that could not be read (missing, permissions) is tried again every time, because fixing that
/// changes no stamp. An actor, so a second caller for the same stamp waits for the first read and then finds it kept.
actor ImportedMeshCache {
    static let maxProblems = 256

    /// The cache the Import Mesh node uses: 1 GB.
    static let shared = ImportedMeshCache(budgetBytes: 1 << 30)

    let budgetBytes: Int
    private var entries: [ImageStamp: (meshes: [ImportedMesh], lastUsed: Int)] = [:]
    private var problems: [ImageStamp: (problem: MeshImportProblem, lastUsed: Int)] = [:]
    private var clock = 0

    init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    /// The meshes for `stamp` (an STL gives one, a 3MF one per object): the kept ones, else what `read` makes (and keeps, when the stamp names a definite thing).
    func meshes(for stamp: ImageStamp, read: @Sendable () throws -> [ImportedMesh]) throws -> [ImportedMesh] {
        clock += 1
        if let kept = entries[stamp] {
            entries[stamp] = (kept.meshes, clock)
            return kept.meshes
        }
        if let known = problems[stamp] {
            problems[stamp] = (known.problem, clock)
            throw known.problem
        }
        do {
            let made = try read()
            if stamp.isKeepable { keep(made, for: stamp) }
            return made
        } catch let problem as MeshImportProblem {
            if stamp.isKeepable, problem.isAboutTheBytes { keepProblem(problem, for: stamp) }
            throw problem
        }
    }

    private func keep(_ made: [ImportedMesh], for stamp: ImageStamp) {
        guard Self.bytes(of: made) <= budgetBytes else { return }
        clock += 1
        entries[stamp] = (made, clock)
        var total = entries.values.reduce(0) { $0 + Self.bytes(of: $1.meshes) }
        while total > budgetBytes, let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            total -= Self.bytes(of: oldest.value.meshes)
            entries[oldest.key] = nil
        }
    }

    private static func bytes(of meshes: [ImportedMesh]) -> Int {
        meshes.reduce(0) { $0 + $1.mesh.estimatedBytes }
    }

    private func keepProblem(_ problem: MeshImportProblem, for stamp: ImageStamp) {
        clock += 1
        problems[stamp] = (problem, clock)
        while problems.count > Self.maxProblems, let oldest = problems.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            problems[oldest.key] = nil
        }
    }

    /// How many meshes are kept.
    var count: Int { entries.count }

    /// How many failed files are remembered.
    var problemCount: Int { problems.count }
}

private extension MeshImportProblem {
    /// Whether the problem comes from the file's bytes (so the same bytes fail the same way) and not from reaching the file.
    var isAboutTheBytes: Bool {
        switch self {
        case .notChosen, .notAFile, .unreadable, .missing, .embeddedMissing, .coordinatesOverflow: false
        case .notAMeshFile, .endsEarly, .badNumber, .noTriangles, .tooManyTriangles, .tooLarge, .noModelPart, .otherFiles, .encrypted,
             .malformedModel, .unsupportedExtension, .modelTooLarge, .overTriangleLimit: true
        }
    }
}
