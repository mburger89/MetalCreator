import Foundation

/// Finds the bytes behind an `ImageReference` (fields spec §5): the embedded images the document holds, and, for a linked
/// one, the file at its path. A value, handed to every evaluation (`Evaluator.evaluate(_:images:)`, `EvalContext.images`);
/// it decodes nothing (`GreyImageDecoder` does, in CreatorNodes).
///
/// A linked path is tried relative to the document's folder first, then as the absolute fallback; nothing is ever written
/// beside a linked image, and a path that names anything but a regular file (a folder, a device, a pipe) is refused before it
/// is opened, so a hand-edited document cannot make the app read `/dev/zero`.
public struct ImageResolver: Sendable {
    /// The document's embedded images by hash.
    public var embedded: [ImageHash: Data]
    /// The folder the document lives in; `nil` while it is unsaved.
    public var documentFolder: URL?

    public init(embedded: [ImageHash: Data] = [:], documentFolder: URL? = nil) {
        self.embedded = embedded
        self.documentFolder = documentFolder
    }

    // MARK: Where a linked file is

    /// The place a linked reference points at now: the relative path under the document's folder when something is there, else
    /// the absolute path (whether or not anything is there). `nil` for an embedded image.
    public func location(of reference: ImageReference) -> URL? {
        guard case .linked(let relative, let absolute) = reference else { return nil }
        if let relative, let folder = documentFolder {
            // The folder's symbolic links are resolved before the relative path is applied, because `relativePath(from:to:)`
            // counts `..` on resolved paths; applied lexically to a symlinked folder, a `..` would climb the wrong tree.
            let candidate = folder.resolvingSymlinksInPath().appending(path: relative).standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
        }
        return URL(filePath: absolute).standardizedFileURL
    }

    /// What `reference` points at now (see `ImageStamp`). Two limits: the stamp is taken before the bytes are read, so a file
    /// changed in between is read newer than its stamp says; and a symbolic link retargeted to a file with the same modification
    /// date and size gives the same stamp, so that change goes unnoticed until the date or size differs.
    public func stamp(of reference: ImageReference) -> ImageStamp {
        switch reference {
        case .embedded(let hash):
            return .embedded(hash, isPresent: embedded[hash] != nil)
        case .linked:
            guard let url = location(of: reference) else { return .missing(path: "") }
            let path = url.path(percentEncoded: false)
            let target = url.resolvingSymlinksInPath().path(percentEncoded: false)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: target) else { return .missing(path: path) }
            guard attributes[.type] as? FileAttributeType == .typeRegular else { return .notAFile(path: path) }
            return .file(path: path, modified: attributes[.modificationDate] as? Date ?? .distantPast,
                         size: (attributes[.size] as? NSNumber)?.intValue ?? 0)
        }
    }

    // MARK: Reading

    /// The bytes of `reference`, never more than `ImageLimits.maxBytes`: a linked file is read at most that far (plus one
    /// byte to notice it is bigger), so a file that grows or lies about its size cannot fill memory.
    public func bytes(of reference: ImageReference) throws(ImageProblem) -> Data {
        switch reference {
        case .embedded(let hash):
            guard let data = embedded[hash] else { throw .embeddedMissing }
            return data
        case .linked:
            let name = reference.fileName ?? "image"
            switch stamp(of: reference) {
            case .missing(let path):
                throw .notFound(name: name, folder: Self.folder(ofPath: path))
            case .notAFile:
                throw .notAFile(name: name)
            case .file(let path, _, let size):
                guard size <= ImageLimits.maxBytes else { throw .tooManyBytes(size) }
                return try Self.read(URL(filePath: path).resolvingSymlinksInPath(), name: name)
            case .embedded:
                throw .embeddedMissing
            }
        }
    }

    /// Reads the file at `url`, at most `ImageLimits.maxBytes`.
    static func read(_ url: URL, name: String) throws(ImageProblem) -> Data {
        let (handle, _) = try openedRegularFile(url, name: name, limit: ImageLimits.maxBytes)
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: ImageLimits.maxBytes + 1) ?? Data()
        } catch {
            throw .unreadable(name: name, reason: error.localizedDescription)
        }
        guard data.count <= ImageLimits.maxBytes else { throw .tooManyBytes(data.count) }
        return data
    }

    /// Opens `url` for reading and checks what was opened: the path was checked a moment ago by `stamp(of:)`, but a path can
    /// be swapped for something else between that check and this open, so the file is opened without blocking (a named pipe
    /// would otherwise hold the caller until someone wrote to it) and its descriptor must be a regular file, whatever the path
    /// was, of at most `limit` bytes. Shared by image reads and mesh file reads (`mappedBytes`); the caller closes the handle.
    static func openedRegularFile(_ url: URL, name: String, limit: Int) throws(ImageProblem) -> (handle: FileHandle, size: Int) {
        let handle: FileHandle
        #if os(Windows)
        // No POSIX descriptors here: the attributes say whether it is a regular file, then it is opened for reading. Unlike the
        // descriptor check below, this is NOT race-free: the path can be swapped between the attributes and the open (the size
        // is still bounded by the caller's read). A symlink reports `.typeSymbolicLink`, not `.typeRegular`, so the caller resolves
        // symlinks first (`URL.resolvingSymlinksInPath`, in `bytes(of:)`), which makes this answer as POSIX `open` does: it follows them.
        let attributes: [FileAttributeKey: Any]
        let size: Int
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ImageProblem.notAFile(name: name) }
            size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size > limit { throw ImageProblem.tooManyBytes(size) }
            handle = try FileHandle(forReadingFrom: url)
        } catch let problem as ImageProblem {
            throw problem
        } catch {
            throw .unreadable(name: name, reason: error.localizedDescription)
        }
        #else
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw .unreadable(name: name, reason: Self.message(forErrno: errno)) }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            try? handle.close()
            throw .unreadable(name: name, reason: Self.message(forErrno: errno))
        }
        guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            try? handle.close()
            throw .notAFile(name: name)
        }
        let size = Int(status.st_size)
        guard size <= limit else {
            try? handle.close()
            throw .tooManyBytes(size)
        }
        #endif
        return (handle, size)
    }

    #if !os(Windows)
    /// The system's message for an `errno` value, with a full stop, as the problem text wants.
    private static func message(forErrno code: Int32) -> String {
        String(cString: strerror(code)) + "."
    }
    #endif

    /// The bytes of the file at `url` as an image to choose or embed, with the same bounds as `bytes(of:)`.
    public static func bytes(ofFileAt url: URL) throws(ImageProblem) -> Data {
        let resolver = ImageResolver()
        return try resolver.bytes(of: .linked(relativePath: nil, absolutePath: url.path(percentEncoded: false)))
    }

    // MARK: Mesh files

    /// The bytes behind a mesh file's `reference` (mesh import spec, Reading and Limits): the embedded bytes, or a linked file
    /// mapped into memory (`Data.alwaysMapped`, so a file of up to `MeshImportLimits.maxFileBytes` costs address space, not
    /// memory, until it is read). A path that names anything but a regular file is refused before it is mapped, by the checks
    /// `read` makes on the opened descriptor, and a file over the limit is refused without being read. An embedded file shares
    /// the document's `images` table with the pictures.
    public func mappedBytes(of reference: ImageReference) throws(MeshImportProblem) -> Data {
        switch reference {
        case .embedded(let hash):
            guard let data = embedded[hash] else { throw .embeddedMissing }
            return data
        case .linked:
            let name = reference.fileName ?? "file"
            switch stamp(of: reference) {
            case .missing(let path):
                throw .missing(name: name, folder: Self.folder(ofPath: path))
            case .notAFile:
                throw .notAFile(name: name)
            case .file(let path, _, _):
                return try Self.mapped(URL(filePath: path).resolvingSymlinksInPath(), name: name)
            case .embedded:
                throw .embeddedMissing
            }
        }
    }

    /// The bytes of the file at `url` as a mesh file to choose or embed, with the same bounds as `mappedBytes(of:)`.
    public static func mappedBytes(ofFileAt url: URL) throws(MeshImportProblem) -> Data {
        try ImageResolver().mappedBytes(of: .linked(relativePath: nil, absolutePath: url.path(percentEncoded: false)))
    }

    private static func mapped(_ url: URL, name: String) throws(MeshImportProblem) -> Data {
        do throws(ImageProblem) {
            let (handle, _) = try openedRegularFile(url, name: name, limit: MeshImportLimits.maxFileBytes)
            try? handle.close()
        } catch {
            throw Self.meshProblem(error)
        }
        do {
            return try Data(contentsOf: url, options: .alwaysMapped)
        } catch {
            throw .unreadable(name: name, reason: error.localizedDescription)
        }
    }

    /// The mesh import problem for a failed open: the image problem's cases, said without the word image.
    private static func meshProblem(_ problem: ImageProblem) -> MeshImportProblem {
        switch problem {
        case .notAFile(let name): .notAFile(name: name)
        case .unreadable(let name, let reason): .unreadable(name: name, reason: reason)
        case .tooManyBytes: .tooLarge
        case .notFound(let name, let folder): .missing(name: name, folder: folder)
        case .embeddedMissing: .embeddedMissing
        case .notChosen: .notChosen
        case .tooManyPixels, .unsupportedType, .undecodable: .notAMeshFile
        }
    }

    // MARK: Saving

    /// `reference` as the document saved in `folder` should store it: a linked file that can be found is written with its
    /// absolute path and a path relative to `folder` (an unsaved document gains its relative path on first save); one that
    /// cannot be found is stored as it was, so a missing file keeps both of its paths. An embedded image is unchanged.
    public func stored(_ reference: ImageReference, inDocumentFolder folder: URL?) -> ImageReference {
        guard case .linked = reference, let url = location(of: reference),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return reference }
        return .linked(relativePath: folder.map { Self.relativePath(from: $0, to: url) }, absolutePath: url.path(percentEncoded: false))
    }

    /// The path of `file` relative to `folder`, such as `textures/vent.png` or `../shared/vent.png`. Symbolic links are
    /// resolved on both sides first, so `/tmp` and `/private/tmp` agree.
    public static func relativePath(from folder: URL, to file: URL) -> String {
        let from = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let to = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var shared = 0
        while shared < min(from.count, to.count), from[shared] == to[shared] { shared += 1 }
        let parts = [String](repeating: "..", count: from.count - shared) + to[shared...]
        return parts.joined(separator: "/")
    }

    /// The folder part of a path, written with a closing slash ("/Users/me/textures/").
    static func folder(ofPath path: String) -> String {
        URL(filePath: path).deletingLastPathComponent().path(percentEncoded: false)
    }
}
