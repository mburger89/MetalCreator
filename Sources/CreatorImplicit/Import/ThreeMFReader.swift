import CreatorGraph
import Foundation

/// Reads a 3MF (mesh import spec, Reading, Limits and Construction): a zip, located through `_rels/.rels`, read as the core
/// specification: objects, components with transforms, build items with transforms and the `unit` attribute. Colours, materials,
/// slices and beam lattices are dropped (`ImportedMesh.ignoredExtras`); the Production extension's parts in other files of the package
/// (Bambu Studio and Orca projects) are read, one at a time, against one budget; encrypted parts are refused. The
/// file is untrusted: the size, the triangles after instancing and the depth of components are checked before anything is built, the
/// XML is read by `XMLScanner` (no DOCTYPE, so no expansion), and every way to be wrong is a `MeshImportProblem`.
public enum ThreeMFReader {
    /// What the node says when a 3MF held data this reader does not use.
    public static let ignoredExtrasWarning = "This mesh's color and material data was ignored."
    /// What the node says when a 3MF's support, modifier or negative parts were left out (Bambu Studio and Orca write all of them as
    /// `type="other"`; a mesh reader cannot cut a negative part out of the model, so the shape may differ).
    public static let partsLeftOutWarning = "This 3MF's support, modifier and negative parts were left out, so the shape may differ."

    private static let modelRelationship = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    private static let relationshipsLimit = 1 << 20

    /// One mesh per build item (an item with no triangles left out), in the file's order, in the file's units: `unit` is the
    /// millimetres per unit, and nothing is scaled. `isCancelled` is asked every 65,536 elements or vertices.
    public static func read(_ data: Data, isCancelled: @escaping () -> Bool) throws -> [ImportedMesh] {
        try read(data, triangleLimit: MeshImportLimits.maxTriangles, isCancelled: isCancelled)
    }

    /// `read` with the limits as parameters, so a test can reach them without a file of millions of triangles.
    static func read(_ data: Data, triangleLimit: Int, recordLimit: Int = ThreeMFLimits().records, partLimit: Int = ThreeMFLimits().parts,
                     byteLimit: Int = ThreeMFLimits().modelBytes, isCancelled: @escaping () -> Bool) throws -> [ImportedMesh] {
        guard data.count <= MeshImportLimits.maxFileBytes else { throw MeshImportProblem.tooLarge }
        let limits = ThreeMFLimits(triangles: triangleLimit, records: recordLimit, parts: partLimit, modelBytes: byteLimit)
        // The inflated XML, which can be 2 GB, is gone before the meshes are made.
        let model = try parsedModel(in: data, limits: limits, isCancelled: isCancelled)
        let meshes = try model.buildMeshes(limits: limits, isCancelled: isCancelled)
        guard !meshes.isEmpty else { throw MeshImportProblem.noTriangles }
        return meshes
    }

    /// The root model with the parts its components and build items name merged in. At no point is more than one model part inflated:
    /// each part's bytes are gone before the next is read, and the bytes of all of them together count against one budget.
    private static func parsedModel(in data: Data, limits: ThreeMFLimits, isCancelled: @escaping () -> Bool) throws -> ThreeMFModel {
        let zip = try open(data)
        let rootEntry = try modelEntry(in: zip, isCancelled: isCancelled)
        var (model, bytesUsed) = try parsed(rootEntry, in: zip, limits: limits, byteLimit: limits.modelBytes, isCancelled: isCancelled)
        guard !model.paths.isEmpty else { return model }
        let targets = try appendParts(to: &model, root: rootEntry, in: zip, limits: limits, bytesUsed: &bytesUsed, isCancelled: isCancelled)
        try model.resolvePaths(targets)
        return model
    }

    /// One model part inflated and parsed; its buffer is released on return. Returns the bytes it inflated to. A damaged part (not the
    /// root, which has no `part` name) is refused naming the part.
    private static func parsed(_ entry: ZipReader.Entry, in zip: ZipReader, limits: ThreeMFLimits, byteLimit: Int, part: String? = nil,
                               isCancelled: @escaping () -> Bool) throws -> (ThreeMFModel, Int) {
        do {
            let bytes = try content(of: entry, in: zip, limit: byteLimit, isCancelled: isCancelled)
            let model = try bytes.withUnsafeBytes {
                try ThreeMFModelParser.parse($0, limits: limits, isRoot: part == nil, isCancelled: isCancelled)
            }
            return (model, bytes.count)
        } catch MeshImportProblem.malformedModel(let reason) where part != nil {
            throw MeshImportProblem.malformedModel("in the part \(MeshImportProblem.quoted(part ?? "")), \(reason)")
        }
    }

    /// Reads each part the root names, once, in the order the root first names them, and appends it to `model`. Returns, for each name
    /// in `model.paths`, the object IDs of the part it names mapped to their indices in `model`. Every name is looked up before any
    /// part is inflated, so a missing one is refused at once.
    private static func appendParts(to model: inout ThreeMFModel, root: ZipReader.Entry, in zip: ZipReader, limits: ThreeMFLimits,
                                    bytesUsed: inout Int, isCancelled: @escaping () -> Bool) throws -> [[Int: Int]] {
        let rootIndex = model.objectIndex
        let names = try PartNames(zip, isCancelled: isCancelled)
        var entries: [(entry: ZipReader.Entry, name: String)] = []
        for (position, path) in model.paths.enumerated() {
            if position % PartNames.lookupInterval == 0, isCancelled() { throw CancellationError() }
            let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
            guard !name.isEmpty else { throw MeshImportProblem.malformedModel("it names a part with no name.") }
            guard let found = names.entry(named: name) else {
                throw MeshImportProblem.malformedModel("it names the part \(MeshImportProblem.quoted(name)), which the file doesn't have.")
            }
            entries.append((found, name))
        }
        var read: [String: [Int: Int]] = [root.name: rootIndex]
        var targets: [[Int: Int]] = []
        for (entry, name) in entries {
            if let known = read[entry.name] {
                targets.append(known)
                continue
            }
            if isCancelled() { throw CancellationError() }
            let (part, size) = try parsed(entry, in: zip, limits: limits.remaining(after: model), byteLimit: limits.modelBytes - bytesUsed,
                                          part: name, isCancelled: isCancelled)
            guard part.unit == model.unit else {
                throw MeshImportProblem.malformedModel("the part \(MeshImportProblem.quoted(name)) uses a different unit from the model.")
            }
            bytesUsed += size
            let indices = model.append(part: part)
            read[entry.name] = indices
            targets.append(indices)
        }
        return targets
    }

    private static func open(_ data: Data) throws -> ZipReader {
        do {
            return try ZipReader(data: data)
        } catch ZipError.overlappingEntries {
            throw MeshImportProblem.malformedModel("its parts overlap.")
        } catch {
            throw MeshImportProblem.notAMeshFile
        }
    }

    private static func content(of entry: ZipReader.Entry, in zip: ZipReader, limit: Int, isCancelled: () -> Bool) throws -> Data {
        do {
            return try zip.content(of: entry, limit: limit, isCancelled: isCancelled)
        } catch let error as ZipError {
            throw problem(for: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MeshImportProblem.malformedModel("a part of the file can't be read.")
        }
    }

    /// What a zip entry that can't be read is to the person: the file's own fault in words, or the computer's memory, which is no
    /// verdict on the file (the cache doesn't remember it).
    static func problem(for error: ZipError) -> MeshImportProblem {
        switch error {
        case .encrypted: .encrypted
        case .tooLarge: .modelTooLarge
        case .allocationFailed: .notEnoughMemory
        default: .malformedModel("a part of the file can't be read.")
        }
    }

    /// The entry named `name` as an Open Packaging part name: exactly, else percent-decoded, else ignoring case (part names are case
    /// insensitive), the decoded form first.
    static func entry(named name: String, in zip: ZipReader) -> ZipReader.Entry? {
        let decoded = name.removingPercentEncoding
        let candidates = [name] + (decoded.map { $0 == name ? [] : [$0] } ?? [])
        for candidate in candidates {
            if let found = zip.entries.first(where: { $0.name == candidate }) { return found }
        }
        let folded = candidates.map { $0.lowercased() }
        return zip.entries.first { folded.contains($0.name.lowercased()) }
    }

    private static func isRelationship(_ name: Range<Int>, in scanner: XMLScanner) -> Bool {
        scanner.equals(name, "Relationship") || scanner.hasSuffix(name, ":Relationship")
    }

    /// The zip entry the package's relationships name as the 3D model: its target, without the leading slash. A relationship to a
    /// key store marks Secure Content, which is encrypted.
    private static func modelEntry(in zip: ZipReader, isCancelled: () -> Bool) throws -> ZipReader.Entry {
        guard let relationships = entry(named: "_rels/.rels", in: zip) else { throw MeshImportProblem.noModelPart }
        let bytes: Data
        do {
            bytes = try content(of: relationships, in: zip, limit: relationshipsLimit, isCancelled: isCancelled)
        } catch MeshImportProblem.modelTooLarge {
            throw MeshImportProblem.malformedModel("its relationships part is larger than any real one.")
        }
        var target: String?
        try bytes.withUnsafeBytes { raw in
            var scanner = XMLScanner(bytes: raw)
            while let event = try scanner.next() {
                guard case .start(let tag) = event, isRelationship(tag.name, in: scanner) else { continue }
                var type = "", path = ""
                for attribute in scanner.attributes(of: tag) {
                    if scanner.equals(attribute.name, "Type") { type = try scanner.decoded(attribute.value) }
                    if scanner.equals(attribute.name, "Target") { path = try scanner.decoded(attribute.value) }
                }
                if type.lowercased().contains("keystore") { throw MeshImportProblem.encrypted }
                if type == modelRelationship, target == nil { target = path }
            }
        }
        guard let target, let found = entry(named: target.hasPrefix("/") ? String(target.dropFirst()) : target, in: zip) else {
            throw MeshImportProblem.noModelPart
        }
        return found
    }
}
