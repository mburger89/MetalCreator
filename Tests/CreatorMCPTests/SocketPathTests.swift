import Foundation
import Testing
@testable import CreatorMCP

struct SocketPathTests {
    #if os(macOS)
    @Test func macOSPathIsInApplicationSupport() {
        let url = SocketPath.default(environment: ["HOME": "/Users/ada"])
        #expect(url.path == "/Users/ada/Library/Application Support/MetalCreator/mcp.sock")
    }
    #elseif os(Windows)
    @Test func windowsPathIsInLocalAppData() {
        let url = SocketPath.default(environment: ["LOCALAPPDATA": "C:\\Users\\ada\\AppData\\Local"])
        #expect(url.lastPathComponent == "mcp.sock")
        #expect(url.path.contains("MetalCreator"))
    }
    #else
    @Test func linuxUsesTheRuntimeFolder() {
        let url = SocketPath.default(environment: ["XDG_RUNTIME_DIR": "/run/user/1000"])
        #expect(url.path == "/run/user/1000/metalcreator/mcp.sock")
    }

    @Test func linuxFallsBackToTmpWithTheUserID() {
        let url = SocketPath.default(environment: [:])
        #expect(url.path == "/tmp/metalcreator-\(getuid())/mcp.sock")
    }
    #endif

    #if !os(Windows)
    @Test func prepareFolderCreatesAPrivateFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UInt32.random(in: 0...999_999))")
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appendingPathComponent("sub/mcp.sock")
        try SocketPath.prepareFolder(socket)
        let mode = try FileManager.default.attributesOfItem(atPath: socket.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        try SocketPath.prepareFolder(socket)
    }

    @Test func prepareFolderRefusesAWiderFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UInt32.random(in: 0...999_999))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: SocketProblem.self) { try SocketPath.prepareFolder(root.appendingPathComponent("mcp.sock")) }
        do {
            try SocketPath.prepareFolder(root.appendingPathComponent("mcp.sock"))
        } catch {
            #expect(error.message == "The folder for AI connections isn't private: \(root.path).")
        }
    }
    #endif
}
