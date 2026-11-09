import CreatorNodes
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

    /// Polls by recursion, not a loop: a loop that keeps locals across an `await` crashes the Windows compiler.
    private func waitUntil(_ condition: @MainActor () -> Bool, until deadline: Date = Date().addingTimeInterval(30)) async -> Bool {
        if condition() { return true }
        guard Date() < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
        return await waitUntil(condition, until: deadline)
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
        #expect(LocalSocket.fileExists(at: url))
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
        // The read loop is one synchronous body: a loop that keeps locals across an `await` crashes the Windows compiler.
        let reply = await Task.detached { MCPServiceTests.readLine(from: client, timeout: 30) }.value
        #expect(reply?.contains("\"id\":7") == true)
    }

    /// The next line from `client`, `nil` after `timeout` seconds or at the end of the stream.
    private nonisolated static func readLine(from client: LocalSocket, timeout: TimeInterval) -> String? {
        var reader = LineReader()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .line(let data)? = reader.nextLine() { return String(bytes: data, encoding: .utf8) }
            guard client.waitReadable(milliseconds: 20) else { continue }
            let count = client.read(into: &buffer)
            if count <= 0 { return nil }
            reader.append(buffer[0..<count])
        }
        return nil
    }

    /// A client that asks for a large document and never reads does not hold the connection for ever. (That the main actor stays
    /// free meanwhile is `StalledClientTests`, in the lightly loaded CreatorMCPTests: this process's main actor is shared with
    /// the whole app suite, so no timing can be asserted here.)
    @Test func aClientThatNeverReadsIsDropped() async throws {
        var builder = GraphBuilder()
        // Long names make the first page bigger than any socket buffer (Linux's is about 200 KB).
        for index in 0..<400 {
            var node = builder.add(RectangleNode.self)
            node.name = "Rectangle \(index) " + String(repeating: "x", count: 8_000)
            builder.replace(node)
        }
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = MCPService(model: await makeApp(builder.graph), preference: MemoryMCPPreference(allowsAIConnections: true),
                                 path: url, writeTimeoutMilliseconds: 500)
        service.start()
        defer { service.stop() }
        let client = try LocalSocket.connect(to: url)
        defer { client.close() }
        let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\","
            + "\"params\":{\"name\":\"get_document\",\"arguments\":{}}}\n"
        #expect(client.write(Data(request.utf8)))
        #expect(await waitUntil { service.isClientConnected })
        #expect(await waitUntil { !service.isClientConnected }, "the stalled connection is dropped")
    }

    @Test func aSecondWindowShowsInUseAndRetriesWhenChosen() async {
        let url = socketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: url)
        first.start()
        let second = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: url)
        defer { second.stop() }
        #expect(second.menuTitle == "Allow AI Connections")
        second.start()
        #expect(second.state == .inUse && second.retries)
        #expect(second.menuTitle == "AI Connections: in use by another window")
        second.menuChosen(true)
        #expect(second.state == .inUse, "still taken")
        first.stop()
        second.menuChosen(true)
        #expect(second.state == .listening && !second.retries && second.menuTitle == "Allow AI Connections")
    }

    @Test func aListenerThatCouldNotStartSaysWhyAndRetries() async {
        let long = URL(fileURLWithPath: "/tmp/mcpa-" + String(repeating: "a", count: 200)).appendingPathComponent("s.sock")
        let service = MCPService(model: await makeApp(), preference: MemoryMCPPreference(allowsAIConnections: true), path: long)
        service.start()
        #expect(service.state == .failed("The path for AI connections is too long."))
        #expect(service.retries)
        #expect(service.menuTitle == "AI Connections: couldn't start (The path for AI connections is too long.)")
        service.menuChosen(true)
        #expect(service.state == .failed("The path for AI connections is too long."), "the retry ran and failed again")
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
