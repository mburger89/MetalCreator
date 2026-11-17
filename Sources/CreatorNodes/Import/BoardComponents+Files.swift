import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation

/// Finding and reading model files, and the sentences about the ones that failed.
enum ModelFiles {
    enum Result {
        case notFound
        case unreadable(name: String, reason: String)
        case file(path: String, format: ModelFormat, stamp: ImageStamp)
    }

    /// The first candidate for `path` that is a file; every candidate looked at is a dependency, with the stamp it had.
    static func resolve(_ path: String, folder: String,
                        variables: KiCadPathVariables) -> (result: Result, dependencies: [FileDependency]) {
        switch ModelPathResolver.locate(path, boardFolder: folder, variables: variables, platform: .current) {
        case .embedded(let name):
            return (.unreadable(name: name, reason: "models stored in the board aren't read yet"), [])
        case .files(let candidates):
            var dependencies: [FileDependency] = []
            for candidate in candidates {
                let stamp = ImageResolver.stamp(ofFileAt: candidate)
                dependencies.append(FileDependency(path: candidate, stamp: stamp))
                guard case .file = stamp else { continue }
                let name = fileName(of: candidate)
                switch ModelFormat(fileName: candidate) {
                case .step, .stepGzip, .iges:
                    return (.file(path: candidate, format: ModelFormat(fileName: candidate), stamp: stamp), dependencies)
                case .vrml, .vrmlGzip: return (.unreadable(name: name, reason: "VRML isn't read yet"), dependencies)
                case .x3d: return (.unreadable(name: name, reason: "X3D isn't read yet"), dependencies)
                case .idf: return (.unreadable(name: name, reason: "IDF isn't read yet"), dependencies)
                case .unknown: return (.unreadable(name: name, reason: "this kind of file isn't read"), dependencies)
                }
            }
            return (.notFound, dependencies)
        }
    }

    /// The model file's solid: read within the limit, checked against its format, gunzipped when compressed, handed to the kernel.
    static func read(at path: String, format: ModelFormat, kernel: any Kernel, tag: NodeTag) async throws -> Solid {
        var bytes = try fileBytes(at: path)
        let word = format == .iges ? "IGES" : "STEP"
        guard format.matches(bytes) else { throw ModelProblem("the file isn't a \(word) model", isRemembered: true) }
        if format == .stepGzip {
            bytes = try gunzipped(bytes)
            guard ModelFormat.step.matches(bytes) else { throw ModelProblem("the file isn't a STEP model", isRemembered: true) }
        }
        do {
            return try await kernel.readModel(bytes, format: format == .iges ? .iges : .step, tag: tag)
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

    private static func fileBytes(at path: String) throws -> Data {
        do {
            return try ImageResolver.modelFile(at: path, limit: BoardComponents.maxModelBytes).data
        } catch {
            if case .tooLarge = error { throw ModelProblem(error.reason, isRemembered: true) }
            throw ModelProblem(error.reason)
        }
    }

    private static func gunzipped(_ bytes: Data) throws -> Data {
        do {
            return try Gzip.decompress(bytes, limit: BoardComponents.maxModelBytes, isCancelled: { Task.isCancelled })
        } catch {
            switch error {
            case .cancelled: throw CancellationError()
            case .tooLarge:
                throw ModelProblem("it is larger than \(BoardComponents.maxModelBytes >> 20) MB when unpacked", isRemembered: true)
            case .allocationFailed: throw ModelProblem("there isn't enough memory to unpack it")
            case .notGzip, .malformed, .checksumMismatch: throw ModelProblem("the compressed file is damaged", isRemembered: true)
            }
        }
    }

    private static func problem(from error: KernelError) -> ModelProblem {
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

extension ModelFormat {
    var solidFormat: SolidModelFormat { self == .iges ? .iges : .step }
}

/// What went wrong with a board's components, in the words the node warns in.
struct Problems {
    var noModel: [String] = []
    var notFound: [String] = []
    var unreadable: [String] = []

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
