import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorPCB
import Foundation

/// Finding and reading model files, and the sentences about the ones that failed.
enum ModelFiles {
    enum Result {
        case notFound
        case unreadable(name: String, reason: String)
        case file(path: String, format: ModelFormat, stamp: ImageStamp)
        /// A model stored in the board: its name, base64 text and format.
        case stored(name: String, base64: String, format: ModelFormat)
    }

    /// Where a model's bytes come from.
    enum Source: Sendable {
        case file(String)
        case stored(base64: String)
    }

    /// The first candidate for `path` that is a file; every candidate looked at is a dependency, with the stamp it had.
    static func resolve(_ path: String, folder: String, variables: KiCadPathVariables,
                        stored: (String) -> EmbeddedFile? = { _ in nil }) -> (result: Result, dependencies: [FileDependency]) {
        switch ModelPathResolver.locate(path, boardFolder: folder, variables: variables, platform: .current) {
        case .embedded(let name):
            guard let file = stored(name) else { return (.notFound, []) }
            if file.base64.allSatisfy(\.isWhitespace) { return (.unreadable(name: name, reason: "it is empty"), []) }
            let format = ModelFormat(fileName: name)
            if format == .unknown { return (.unreadable(name: name, reason: "this kind of file isn't read"), []) }
            return (.stored(name: name, base64: file.base64, format: format), [])
        case .files(let candidates):
            var dependencies: [FileDependency] = []
            for candidate in candidates {
                let stamp = ImageResolver.stamp(ofFileAt: candidate)
                dependencies.append(FileDependency(path: candidate, stamp: stamp))
                guard case .file = stamp else { continue }
                let name = fileName(of: candidate)
                switch ModelFormat(fileName: candidate) {
                case .step, .stepGzip, .iges, .vrml, .vrmlGzip, .x3d, .idf:
                    return (.file(path: candidate, format: ModelFormat(fileName: candidate), stamp: stamp), dependencies)
                case .unknown: return (.unreadable(name: name, reason: "this kind of file isn't read"), dependencies)
                }
            }
            return (.notFound, dependencies)
        }
    }

    /// The model file's solid: read within the limit, checked against its format, gunzipped when compressed, handed to the kernel.
    static func read(_ source: Source, format: ModelFormat, stamp: ImageStamp, kernel: any Kernel,
                     tag: NodeTag) async throws -> ComponentModelCache.Made {
        if format == .idf { return try await readOutline(source, stamp: stamp, kernel: kernel, tag: tag) }
        let file = try bytes(of: source, format: format, stamp: stamp)
        var bytes = file.data
        let word = format == .iges ? "IGES" : "STEP"
        guard format.matches(bytes) else { throw ModelProblem("the file isn't a \(word) model", isRemembered: true) }
        if format == .stepGzip {
            bytes = try gunzipped(bytes, limit: BoardComponents.maxModelBytes)
            guard ModelFormat.step.matches(bytes) else { throw ModelProblem("the file isn't a STEP model", isRemembered: true) }
        }
        do {
            let solid = try await kernel.readModel(bytes, format: format == .iges ? .iges : .step, tag: tag)
            return ComponentModelCache.Made(solid: solid, isCurrent: file.isCurrent)
        } catch let error as KernelError {
            throw problem(from: error)
        }
    }

    static func scale(_ solid: Solid, by factors: Vector3, kernel: any Kernel, tag: NodeTag) async throws -> Solid {
        do {
            return try await kernel.scaled(solid, by: factors, tag: tag)
        } catch let error as KernelError {
            throw problem(from: error)
        }
    }

    /// The most bytes a model of `format` may have (a stored one is limited the same way, both as its frame and unpacked).
    static func limit(for format: ModelFormat) -> Int {
        switch format {
        case .idf: IDFReader.maximumBytes
        case .vrml, .x3d: VRMLReader.maximumBytes
        default: BoardComponents.maxModelBytes
        }
    }

    /// The model's bytes: a file read within the limit, or a stored model's base64 text decoded and unpacked from its zstd frame.
    /// Whether they are still what `stamp` says (always, for a stored model).
    static func bytes(of source: Source, format: ModelFormat, stamp: ImageStamp) throws -> (data: Data, isCurrent: Bool) {
        let limit = limit(for: format)
        switch source {
        case .file(let path):
            let file = try fileBytes(at: path, limit: limit)
            return (file.data, file.stamp == stamp)
        case .stored(let base64):
            guard let frame = Base64.decode(base64[...].utf8, limit: limit) else {
                throw ModelProblem("it is damaged", isRemembered: true)
            }
            do {
                return (try ZstdDecoder.decode(frame, limit: limit, isCancelled: { Task.isCancelled }), true)
            } catch let problem as ZstdProblem {
                throw ModelProblem(readerReason(problem.message), isRemembered: true)
            }
        }
    }

    static func fileBytes(at path: String, limit: Int) throws -> (data: Data, stamp: ImageStamp) {
        do {
            return try ImageResolver.modelFile(at: path, limit: limit)
        } catch {
            if case .tooLarge = error { throw ModelProblem(error.reason, isRemembered: true) }
            throw ModelProblem(error.reason)
        }
    }

    static func gunzipped(_ bytes: Data, limit: Int) throws -> Data {
        do {
            return try Gzip.decompress(bytes, limit: limit, isCancelled: { Task.isCancelled })
        } catch {
            switch error {
            case .cancelled: throw CancellationError()
            case .tooLarge:
                throw ModelProblem("it is larger than \(limit >> 20) MB when unpacked", isRemembered: true)
            case .allocationFailed: throw ModelProblem("there isn't enough memory to unpack it")
            case .notGzip, .malformed, .checksumMismatch: throw ModelProblem("the compressed file is damaged", isRemembered: true)
            }
        }
    }

    static func problem(from error: KernelError) -> ModelProblem {
        if case .invalidInput = error { return ModelProblem(reason(from: error.userMessage), isRemembered: true) }
        return ModelProblem(reason(from: error.userMessage))
    }

    /// A sentence as the phrase in parentheses: no final period, and a first word that isn't an abbreviation in lower case.
    static func reason(from sentence: String) -> String {
        var text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(".") { text.removeLast() }
        let firstWord = text.prefix { $0 != " " }
        if let first = firstWord.first, firstWord.dropFirst().allSatisfy({ !$0.isUppercase }) {
            text = first.lowercased() + text.dropFirst()
        }
        return text
    }

    static func fileName(of path: String) -> String {
        String(path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? Substring(path))
    }
}

/// What went wrong with a board's components, in the words the node warns in.
struct Problems: Equatable {
    var noModel: [String] = []
    var notFound: [String] = []
    var unreadable: [String] = []
    /// Model files with shapes that aren't read, each named once.
    var skipped: [String] = []
    /// Model files that refer to other files, which aren't read, each named once.
    var inlined: [String] = []
    /// References of footprints whose meshes together exceed the per-footprint triangle limit.
    var meshesOverFootprintLimit: [String] = []
    /// How many footprints' meshes were left out because the board's budget was spent.
    var meshesLeftOut = 0

    func sentences() -> [String] {
        var result: [String] = []
        let (none, missing, bad) = (noModel, Self.unique(notFound), Self.unique(unreadable))
        if !none.isEmpty {
            result.append("\(none.count.display) component\(none.count == 1 ? " has" : "s have") no 3D model: \(Self.list(none)).")
        }
        if !missing.isEmpty {
            result.append("\(missing.count.display) model\(missing.count == 1 ? " wasn't" : "s weren't") found: \(Self.list(missing)).")
        }
        if !bad.isEmpty {
            result.append("\(bad.count.display) model\(bad.count == 1 ? "" : "s") couldn't be read: \(Self.list(bad)).")
        }
        for name in Self.unique(skipped) { result.append("\(name) has shapes that aren't read (spheres, cylinders and the like).") }
        for name in Self.unique(inlined) { result.append("\(name) refers to other files, which aren't read.") }
        if !meshesOverFootprintLimit.isEmpty {
            let names = Self.unique(meshesOverFootprintLimit)
            let limit = BoardComponents.meshLimits.footprint.display
            if names.count == 1 {
                result.append("\(names[0])'s component meshes were left out: they have more than \(limit) triangles together.")
            } else {
                let count = names.count.display
                result.append("\(count) components' meshes were left out because each has more than \(limit) triangles together: "
                    + "\(Self.list(names)).")
            }
        }
        if meshesLeftOut > 0 {
            let limit = BoardComponents.meshLimits.board.display
            let (count, noun, verb) = meshesLeftOut == 1 ? ("1", "mesh", "was") : (meshesLeftOut.display, "meshes", "were")
            result.append("\(count) component \(noun) \(verb) left out: a board's meshes are limited to \(limit) triangles.")
        }
        return result
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// The first eight, then "… (and N more)".
    private static func list(_ names: [String]) -> String {
        let shown = names.prefix(BoardComponents.listedNames).joined(separator: ", ")
        let more = names.count - BoardComponents.listedNames
        return more > 0 ? "\(shown) … (and \(more.display) more)" : shown
    }
}
