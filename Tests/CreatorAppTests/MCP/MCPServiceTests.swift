import Foundation
import Synchronization
import Testing
@testable import CreatorApp
@testable import CreatorMCP

/// The switch, the server it starts and the chip's state. Each test listens on a short socket path of its own (macOS caps a path at
/// 104 bytes).
@MainActor
struct MCPServiceTests {
    private func socketURL() -> URL {
        URL(fileURLWithPath: "/tmp/mcpa-\(UInt32.random(in: 0...9_999_999))").appendingPathComponent("s.sock")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func preferenceTurnsTheServerOn() async {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: url)
        #expect(service.isOn)
        service.start()
        defer { service.stop() }
        #expect(service.state == .listening)
    }

    @Test func offByDefaultAndTheLaunchFlagTurnsItOnForTheSession() async {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let preference = MemoryMCPPreference()
        let off = MCPService(model: await makeApp(), preference: preference, path: url)
        off.start()
        #expect(off.state == .off && !off.isOn)
        let flagged = MCPService(model: await makeApp(), preference: preference, launchFlag: true, path: url)
        flagged.start()
        defer { flagged.stop() }
        #expect(flagged.state == .listening)
        #expect(!preference.allowsAIConnections, "the flag is for one session; nothing is remembered")
    }

    @Test func theMenuSwitchRemembersAndStops() async {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let preference = MemoryMCPPreference()
        let service = MCPService(model: await makeApp(), preference: preference, path: url)
        service.setOn(true)
        #expect(preference.allowsAIConnections && service.state == .listening)
        service.setOn(false)
        #expect(!preference.allowsAIConnections && service.state == .off)
        #expect(!FileManager.default.fileExists(atPath: url.path), "stopping removes the socket file")
    }

    @Test func chipFollowsConnection() async throws {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: url)
        service.start()
        defer { service.stop() }
        let client = try LocalSocket.connect(to: url)
        #expect(client.write(Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\n".utf8)))
        #expect(await waitUntil { service.isClientConnected })
        client.close()
        #expect(await waitUntil { !service.isClientConnected })
    }

    @Test func secondServiceIsInUse() async {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: url)
        first.start()
        defer { first.stop() }
        let second = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: url)
        second.start()
        #expect(second.state == .inUse)
        second.stop()
        #expect(first.state == .listening, "the other window's file is left alone")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aClientIsServedAnswers() async throws {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: url)
        service.start()
        defer { service.stop() }
        let client = try LocalSocket.connect(to: url)
        defer { client.close() }
        #expect(client.write(Data("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}\n".utf8)))
        var reader = LineReader()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var reply: String?
        let deadline = Date().addingTimeInterval(30)
        while reply == nil, Date() < deadline {
            if case .line(let data)? = reader.nextLine() { reply = String(bytes: data, encoding: .utf8); break }
            guard await Task.detached(operation: { client.waitReadable(milliseconds: 20) }).value else { continue }
            let count = client.read(into: &buffer)
            if count <= 0 { break }
            reader.append(buffer[0..<count])
        }
        #expect(reply?.contains("\"id\":7") == true)
    }

    @Test func thePreferenceKeyAndDefaults() {
        let suite = "MCPPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = UserDefaultsMCPPreference(defaults: defaults)
        #expect(!preference.allowsAIConnections)
        preference.allowsAIConnections = true
        #expect(defaults.bool(forKey: "MetalCreator.allowsAIConnections"))
    }
}
