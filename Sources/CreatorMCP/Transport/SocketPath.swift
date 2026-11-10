import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Where the AI connection's socket lives.
public enum SocketPath {
    public static func `default`(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        #if os(Windows)
        let base = environment["LOCALAPPDATA"] ?? NSHomeDirectory() + "\\AppData\\Local"
        return URL(fileURLWithPath: base).appendingPathComponent("MetalCreator").appendingPathComponent("mcp.sock")
        #elseif os(macOS)
        let home = environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/MetalCreator/Connection").appendingPathComponent("mcp.sock")
        #else
        if let runtime = environment["XDG_RUNTIME_DIR"], !runtime.isEmpty {
            return URL(fileURLWithPath: runtime).appendingPathComponent("metalcreator").appendingPathComponent("mcp.sock")
        }
        return URL(fileURLWithPath: "/tmp/metalcreator-\(getuid())").appendingPathComponent("mcp.sock")
        #endif
    }

    /// Creates the socket's folder (0700 where the platform has modes). A folder this user owns that is wider than 0700 is
    /// tightened to 0700; one that another user owns, a symlink or a file is refused.
    public static func prepareFolder(_ url: URL) throws(SocketProblem) {
        let folder = url.deletingLastPathComponent()
        #if os(Windows)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw SocketProblem.notPrivate(folder.path)
        }
        #else
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw SocketProblem.notPrivate(folder.path)
        }
        var info = stat()
        guard lstat(folder.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else {
            throw SocketProblem.notPrivate(folder.path)
        }
        if info.st_mode & 0o077 != 0 {
            guard chmod(folder.path, 0o700) == 0, lstat(folder.path, &info) == 0, info.st_mode & 0o077 == 0 else {
                throw SocketProblem.notPrivate(folder.path)
            }
        }
        #endif
    }
}
