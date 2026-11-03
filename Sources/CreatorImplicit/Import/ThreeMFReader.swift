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

    private static let modelRelationship = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    private static let relationshipsLimit = 1 << 20

    /// One mesh per build item (an item with no triangles left out), in the file's order, in the file's units: `unit` is the
    /// millimetres per unit, and nothing is scaled. `isCancelled` is asked every 65,536 elements or vertices.
    public static func read(_ data: Data, isCancelled: @escaping () -> Bool) throws -> [ImportedMesh] {
        try read(data, triangleLimit: MeshImportLimits.maxTriangles, isCancelled: isCancelled)
    }

    /// `read` with the triangle limit as a parameter, so a test can reach the limit without a file of millions of triangles.
    static func read(_ data: Data, triangleLimit: Int, isCancelled: @escaping () -> Bool) throws -> [ImportedMesh] {
        guard data.count <= MeshImportLimits.maxFileBytes else { throw MeshImportProblem.tooLarge }
        let zip = try open(data)
        let name = try modelPartName(in: zip, isCancelled: isCancelled)
        guard let entry = zip.entries.first(where: { $0.name == name }) else { throw MeshImportProblem.noModelPart }
        let bytes = try content(of: entry, in: zip, limit: ZipReader.defaultLimit, isCancelled: isCancelled)
        let model = try bytes.withUnsafeBytes {
            try ThreeMFModelParser.parse($0, triangleLimit: triangleLimit, isCancelled: isCancelled)
        }
        let meshes = try model.buildMeshes(triangleLimit: triangleLimit, isCancelled: isCancelled)
        guard !meshes.isEmpty else { throw MeshImportProblem.noTriangles }
        return meshes
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
        } catch ZipError.encrypted {
            throw MeshImportProblem.encrypted
        } catch ZipError.tooLarge {
            throw MeshImportProblem.tooLarge
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MeshImportProblem.malformedModel("a part of the file can't be read.")
        }
    }

    private static func isRelationship(_ name: Range<Int>, in scanner: XMLScanner) -> Bool {
        scanner.equals(name, "Relationship") || scanner.hasSuffix(name, ":Relationship")
    }

    /// The zip entry the package's relationships name as the 3D model: its target, without the leading slash. A relationship to a
    /// key store marks Secure Content, which is encrypted.
    private static func modelPartName(in zip: ZipReader, isCancelled: () -> Bool) throws -> String {
        guard let relationships = zip.entries.first(where: { $0.name == "_rels/.rels" }) else { throw MeshImportProblem.noModelPart }
        let bytes = try content(of: relationships, in: zip, limit: relationshipsLimit, isCancelled: isCancelled)
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
        guard let target else { throw MeshImportProblem.noModelPart }
        return target.hasPrefix("/") ? String(target.dropFirst()) : target
    }
}
