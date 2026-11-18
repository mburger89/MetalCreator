import Foundation

extension ImageResolver {
    /// The most bytes a model file may hold (NURBS spec, Import Model): 256 MB.
    public static let maxModelFileBytes = 256 << 20

    /// The bytes behind a model file's `reference`: the embedded bytes, or a linked file read whole through the one descriptor
    /// that was opened and checked (a regular file of at most `maxModelFileBytes`; a folder, a device or a pipe is refused, and a
    /// file over the limit is refused without being read). An embedded file shares the document's `images` table with the pictures.
    public func modelFileBytes(of reference: ImageReference) throws(ModelImportProblem) -> Data {
        switch reference {
        case .embedded(let hash):
            guard let data = embedded[hash] else { throw .embeddedMissing }
            guard data.count <= Self.maxModelFileBytes else { throw .tooLarge }
            return data
        case .linked:
            let name = reference.fileName ?? "file"
            switch stamp(of: reference) {
            case .missing(let path): throw .missing(name: name, folder: Self.folder(ofPath: path))
            case .notAFile: throw .notAFile(name: name)
            case .embedded: throw .embeddedMissing
            case .file(let path, _, _):
                let (handle, size) = try Self.openedModelFile(URL(filePath: path).resolvingSymlinksInPath(), name: name)
                defer { try? handle.close() }
                do {
                    return try handle.read(upToCount: size) ?? Data()
                } catch {
                    throw .unreadable(name: name, reason: error.localizedDescription)
                }
            }
        }
    }

    private static func openedModelFile(_ url: URL, name: String) throws(ModelImportProblem) -> (handle: FileHandle, size: Int) {
        do throws(ImageProblem) {
            return try openedRegularFile(url, name: name, limit: maxModelFileBytes)
        } catch {
            switch error {
            case .notAFile: throw .notAFile(name: name)
            case .tooManyBytes: throw .tooLarge
            case .notFound(let name, let folder): throw .missing(name: name, folder: folder)
            case .embeddedMissing: throw .embeddedMissing
            case .notChosen: throw .notChosen
            case .unreadable(let name, let reason): throw .unreadable(name: name, reason: reason)
            case .tooManyPixels, .unsupportedType, .undecodable: throw .notAFile(name: name)
            }
        }
    }
}
