import Foundation
import Testing
@testable import CreatorMCP

struct SocketPathTests {
    #if os(macOS)
    @Test func macOSPathIsInApplicationSupport() {
        let url = SocketPath.default(environment: ["HOME": "/Users/ada"])
        #expect(url.path == "/Users/ada/Library/Application Support/MetalCreator/Connection/mcp.sock")
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

    @Test func prepareFolderTightensAWiderFolderWeOwn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UInt32.random(in: 0...999_999))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: root) }
        try SocketPath.prepareFolder(root.appendingPathComponent("mcp.sock"))
        let mode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test(.enabled(if: getuid() != 0, "root owns everything it creates; /usr is another user's only for others"))
    func prepareFolderRefusesAFolderAnotherUserOwns() {
        let socket = URL(fileURLWithPath: "/usr/mcp.sock")
        #expect(throws: SocketProblem.self) { try SocketPath.prepareFolder(socket) }
        do {
            try SocketPath.prepareFolder(socket)
        } catch {
            #expect(error.message == "The folder for AI connections isn't private: /usr.")
        }
    }

    @Test func prepareFolderRefusesASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UInt32.random(in: 0...999_999))")
        let target = root.appendingPathComponent("real")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: SocketProblem.self) { try SocketPath.prepareFolder(link.appendingPathComponent("mcp.sock")) }
    }
    #endif
}
