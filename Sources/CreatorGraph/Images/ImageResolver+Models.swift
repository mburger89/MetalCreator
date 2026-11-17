import Foundation

extension ImageResolver {
    /// What the file at the absolute `path` is now, as `stamp(of:)` says for a linked reference to it.
    public static func stamp(ofFileAt path: String) -> ImageStamp {
        ImageResolver().stamp(of: .linked(relativePath: nil, absolutePath: path))
    }

    /// The folder a linked file lies in (a board's, for its relative model paths); nil for an embedded reference.
    public func folder(of reference: ImageReference) -> URL? {
        guard case .linked = reference, let url = location(of: reference) else { return nil }
        return url.deletingLastPathComponent()
    }

    /// A regular file of at most `limit` bytes, read whole through the one descriptor that was opened and checked. The stamp is
    /// taken first (it equals `stamp(ofFileAt:)` of `path`), so a file changed while it is read is read newer than its stamp says and runs the node again next time.
    public static func modelFile(at path: String, limit: Int) throws(ModelFileProblem) -> (data: Data, stamp: ImageStamp) {
        let stamp = stamp(ofFileAt: path)
        switch stamp {
        case .missing: throw .missing
        case .notAFile: throw .notAFile
        case .embedded: throw .missing
        case .file:
            let opened = try openedModelFile(path, limit: limit)
            defer { try? opened.handle.close() }
            let data: Data
            do {
                data = try opened.handle.read(upToCount: limit + 1) ?? Data()
            } catch {
                let words = error.localizedDescription
                throw .unreadable(words.hasSuffix(".") ? String(words.dropLast()) : words)
            }
            guard data.count <= limit else { throw .tooLarge(limit: limit) }
            return (data, stamp)
        }
    }

    private static func openedModelFile(_ path: String, limit: Int) throws(ModelFileProblem) -> (handle: FileHandle, size: Int) {
        let url = URL(filePath: path).resolvingSymlinksInPath()
        do throws(ImageProblem) {
            return try openedRegularFile(url, name: url.lastPathComponent, limit: limit)
        } catch {
            switch error {
            case .notAFile: throw .notAFile
            case .tooManyBytes: throw .tooLarge(limit: limit)
            case .notFound: throw .missing
            case .unreadable(_, let reason):
                // ENOENT: the file went between the stamp and the open.
                if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { throw .missing }
                throw .unreadable(reason.hasSuffix(".") ? String(reason.dropLast()) : reason)
            case .embeddedMissing, .notChosen, .tooManyPixels, .unsupportedType, .undecodable:
                throw .unreadable("it isn't a regular file")
            }
        }
    }
}
