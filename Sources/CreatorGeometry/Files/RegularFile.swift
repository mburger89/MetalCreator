import Foundation

/// Why a file could not be read as a bounded regular file (DR-5 R23).
public enum RegularFileProblem: Error, Equatable, Sendable {
    /// A folder, a device, a pipe or anything else that is not a regular file.
    case notAFile
    /// The descriptor reported `size` bytes, over the limit; nothing was read.
    case tooLarge(size: Int)
    /// The system's sentence.
    case unreadable(reason: String)
}

/// Reads a file somebody else put there: opened without blocking, its descriptor checked as a regular file of at most `limit`
/// bytes before a byte is read, then at most `limit + 1` bytes read (a file that grew is refused).
public enum RegularFile {
    public static func read(_ url: URL, limit: Int) throws(RegularFileProblem) -> Data {
        let (handle, _) = try opened(url, limit: limit)
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: limit + 1) ?? Data()
        } catch {
            throw .unreadable(reason: error.localizedDescription)
        }
        guard data.count <= limit else { throw .tooLarge(size: data.count) }
        return data
    }

    /// Opens `url` and checks what was opened; the caller closes the handle.
    public static func opened(_ url: URL, limit: Int) throws(RegularFileProblem) -> (handle: FileHandle, size: Int) {
        let handle: FileHandle
        #if os(Windows)
        // No POSIX descriptors here: the attributes say whether it is a regular file, then it is opened for reading. This is not
        // race-free (the path can be swapped between the two); the size is still bounded by the caller's read. A symbolic link
        // reports `.typeSymbolicLink`, so a caller resolves links first.
        let size: Int
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw RegularFileProblem.notAFile }
            size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size > limit { throw RegularFileProblem.tooLarge(size: size) }
            handle = try FileHandle(forReadingFrom: url)
        } catch let problem as RegularFileProblem {
            throw problem
        } catch {
            throw .unreadable(reason: error.localizedDescription)
        }
        #else
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw .unreadable(reason: message(forErrno: errno)) }
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let reason = message(forErrno: errno)
            try? handle.close()
            throw .unreadable(reason: reason)
        }
        guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            try? handle.close()
            throw .notAFile
        }
        let size = Int(status.st_size)
        guard size <= limit else {
            try? handle.close()
            throw .tooLarge(size: size)
        }
        #endif
        return (handle, size)
    }

    #if !os(Windows)
    /// The system's message for an `errno` value, with a full stop.
    private static func message(forErrno code: Int32) -> String {
        String(cString: strerror(code)) + "."
    }
    #endif
}
