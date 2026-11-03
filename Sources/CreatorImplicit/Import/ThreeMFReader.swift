import CreatorGraph
import Foundation

/// Reads a 3MF (mesh import spec, Reading, Limits and Construction): a zip, located through `_rels/.rels`, read as the core
/// specification: objects, components with transforms, build items with transforms and the `unit` attribute. Colours, materials,
/// slices and beam lattices are dropped (`ImportedMesh.ignoredExtras`); parts in other files and encrypted parts are refused. The
/// file is untrusted: the size, the triangles after instancing and the depth of components are checked before anything is built, the
/// XML is read by `XMLScanner` (no DOCTYPE, so no expansion), and every way to be wrong is a `MeshImportProblem`.
public enum ThreeMFReader {
    /// What the node says when a 3MF held data this reader does not use.
    public static let ignoredExtrasWarning = "This mesh's color and material data was ignored."
    /// What the node says when a 3MF's support structures were left out.
    public static let supportsLeftOutWarning = "This 3MF's support structures were left out."

    private static let modelRelationship = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    private static let relationshipsLimit = 1 << 20

    /// One mesh per build item (an item with no triangles left out), in the file's order, in the file's units: `unit` is the
    /// millimetres per unit, and nothing is scaled. `isCancelled` is asked every 65,536 elements or vertices.
    public static func read(_ data: Data, isCancelled: @escaping () -> Bool) throws -> [ImportedMesh] {
        try read(data, triangleLimit: MeshImportLimits.maxTriangles, isCancelled: isCancelled)
    }

    /// `read` with the limits as parameters, so a test can reach them without a file of millions of triangles.
    static func read(_ data: Data, triangleLimit: Int, recordLimit: Int = ThreeMFLimits().records,
                     isCancelled: @escaping () -> Bool) throws -> [ImportedMesh] {
        guard data.count <= MeshImportLimits.maxFileBytes else { throw MeshImportProblem.tooLarge }
        let limits = ThreeMFLimits(triangles: triangleLimit, records: recordLimit)
        // The inflated XML, which can be 2 GB, is gone before the meshes are made.
        let model = try parsedModel(in: data, limits: limits, isCancelled: isCancelled)
        let meshes = try model.buildMeshes(limits: limits, isCancelled: isCancelled)
        guard !meshes.isEmpty else { throw MeshImportProblem.noTriangles }
        return meshes
    }

    private static func parsedModel(in data: Data, limits: ThreeMFLimits, isCancelled: @escaping () -> Bool) throws -> ThreeMFModel {
        let zip = try open(data)
        let entry = try modelEntry(in: zip, isCancelled: isCancelled)
        let bytes = try content(of: entry, in: zip, limit: ZipReader.defaultLimit, isCancelled: isCancelled)
        return try bytes.withUnsafeBytes { try ThreeMFModelParser.parse($0, limits: limits, isCancelled: isCancelled) }
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
