import Foundation
import Synchronization
import Testing
@testable import CreatorMCP

private let sentence = "MetalCreator isn't running, or AI connections are off: turn them on in MetalCreator ▸ Allow AI Connections."

private final class Exit: Sendable {
    private let value = Mutex<Int32?>(nil)
    var code: Int32? { value.withLock { $0 } }
    func set(_ code: Int32) { value.withLock { $0 = code } }
}

private final class Lines: Sendable {
    private let items = Mutex<[String]>([])
    func add(_ line: String) { items.withLock { $0.append(line) } }
    var all: [String] { items.withLock { $0 } }
    func wait(count: Int, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if all.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

/// The bridge on pipes; every wait has a timeout.
private final class Harness: Sendable {
    let stdin = Pipe()
    let stdout = Pipe()
    let received = Lines()
    let exitCode = Exit()

    init(socket: URL) {
        let bridge = MCPBridge(socketPath: socket)
        let input = stdin.fileHandleForReading, output = stdout.fileHandleForWriting
        let readEnd = stdout.fileHandleForReading
        let received = received
        let thread = Thread { [exitCode] in
            let code = bridge.run(input: input, output: output)
            exitCode.set(code)
            try? output.close()
        }
        thread.start()
        let collector = Thread {
            var reader = LineReader()
            while true {
                let data = readEnd.availableData
                if data.isEmpty { break }
                reader.append(Array(data)[...])
                while case .line(let line)? = reader.nextLine() { received.add(String(bytes: line, encoding: .utf8) ?? "") }
            }
        }
        collector.start()
    }

    func send(_ text: String) { try? stdin.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8)) }

    func finish() async -> Int32? {
        try? stdin.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let code = exitCode.code { return code }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    func json(_ index: Int) throws -> JSONValue { try JSONValue.parse(Data(received.all[index].utf8)) }
}

private func tempSocketURL() -> URL {
    URL(fileURLWithPath: "/tmp/mcpb-\(UInt32.random(in: 0...9_999_999))").appendingPathComponent("s.sock")
}

/// A stand-in app: answers every request with `{"from":"app"}` and records the lines it gets.
private func makeApp(at url: URL, seen: Lines) -> MCPListener {
    MCPListener(path: url, handle: { line, send in
        let text = String(bytes: line, encoding: .utf8) ?? ""
        seen.add(text)
        guard let message = try? JSONValue.parse(line), let id = message["id"] else { return }
        send(JSONRPC.result(id: id, .object(["from": .string("app"), "method": message["method"] ?? .null])))
    }, connectionChanged: { _ in })
}

struct BridgeTests {
    @Test func bridgeCopiesBothWays() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let seen = Lines()
        let app = makeApp(at: url, seen: seen)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let harness = Harness(socket: url)
        harness.send(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(await harness.received.wait(count: 2))
        #expect(try harness.json(0)["result"]?["from"]?.string == "app")
        #expect(try harness.json(1)["id"]?.int == 2)
        #expect(seen.all.count == 2)
        #expect(await harness.finish() == 0)
    }

    @Test func noAppAnswersInitializeWithTheSentence() async throws {
        let harness = Harness(socket: tempSocketURL())
        harness.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        harness.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        harness.send(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        #expect(await harness.received.wait(count: 3))
        let result = try harness.json(0)["result"]
        #expect(result?["instructions"]?.string == sentence)
        #expect(result?["protocolVersion"]?.string == "2025-03-26")
        #expect(try harness.json(1)["result"]?.object?.isEmpty == true)
        #expect(try harness.json(2)["result"]?["tools"]?.array?.isEmpty == true)
        #expect(await harness.finish() == 0)
    }

    @Test func noAppToolCallIsAToolError() async throws {
        let harness = Harness(socket: tempSocketURL())
        harness.send(#"{"jsonrpc":"2.0","id":"a","method":"tools/call","params":{"name":"list_nodes"}}"#)
        #expect(await harness.received.wait(count: 1))
        let result = try harness.json(0)["result"]
        #expect(result?["isError"]?.bool == true)
        #expect(result?["content"]?.array?.first?["text"]?.string == sentence)
        #expect(try harness.json(0)["id"]?.string == "a")
        #expect(await harness.finish() == 0)
    }

    @Test func appStartingLaterIsPickedUp() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let harness = Harness(socket: url)
        harness.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"t"}}}"#)
        harness.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(await harness.received.wait(count: 1))
        #expect(try harness.json(0)["result"]?["instructions"]?.string == sentence)

        let seen = Lines()
        let app = makeApp(at: url, seen: seen)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(await harness.received.wait(count: 2))
        #expect(try harness.json(1)["id"]?.int == 2)
        #expect(try harness.json(1)["result"]?["from"]?.string == "app")
        // The app was brought up to date first, and its answer to that never reached the client.
        #expect(await seen.wait(count: 3))
        let methods = try seen.all.map { try JSONValue.parse(Data($0.utf8))["method"]?.string }
        #expect(methods == ["initialize", "notifications/initialized", "tools/list"])
        #expect(try JSONValue.parse(Data(seen.all[0].utf8))["params"]?["clientInfo"]?["name"]?.string == "t")
        #expect(harness.received.all.count == 2)
        #expect(await harness.finish() == 0)
    }
}
