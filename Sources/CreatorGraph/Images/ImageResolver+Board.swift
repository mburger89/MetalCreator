import Foundation

extension ImageResolver {
    /// The most bytes a board file may hold (KiCad import spec, Limits): 256 MB.
    public static let maxBoardFileBytes = 256 << 20

    /// The bytes of a linked KiCad board file, read whole through the one descriptor that was opened and checked (a regular
    /// file of at most `maxBoardFileBytes`; a folder, a device or a pipe is refused, and a file over the limit is refused
    /// without being read). A board is linked only, so an embedded reference is `.notChosen`.
    public func pcbFileBytes(of reference: ImageReference) throws(BoardImportProblem) -> Data {
        guard case .linked = reference else { throw .notChosen }
        let name = reference.fileName ?? "file"
        switch stamp(of: reference) {
        case .missing(let path): throw .missing(name: name, folder: Self.folder(ofPath: path))
        case .notAFile: throw .notAFile(name: name)
        case .embedded: throw .notChosen
        case .file(let path, _, _):
            let (handle, size) = try Self.openedBoardFile(URL(filePath: path).resolvingSymlinksInPath(), name: name)
            defer { try? handle.close() }
            do {
                return try handle.read(upToCount: size) ?? Data()
            } catch {
                throw .unreadable(name: name, reason: error.localizedDescription)
            }
        }
    }

    private static func openedBoardFile(_ url: URL, name: String) throws(BoardImportProblem) -> (handle: FileHandle, size: Int) {
        do throws(ImageProblem) {
            return try openedRegularFile(url, name: name, limit: maxBoardFileBytes)
        } catch {
            switch error {
            case .notAFile: throw .notAFile(name: name)
            case .tooManyBytes: throw .tooLarge
            case .notFound(let name, let folder): throw .missing(name: name, folder: folder)
            case .embeddedMissing, .notChosen: throw .notChosen
            case .unreadable(let name, let reason): throw .unreadable(name: name, reason: reason)
            case .tooManyPixels, .unsupportedType, .undecodable: throw .unreadable(name: name, reason: "Not a regular file.")
            }
        }
    }
}
