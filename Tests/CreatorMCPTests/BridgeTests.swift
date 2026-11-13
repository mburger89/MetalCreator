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
    /// Polls by recursion, not a loop: a loop that keeps locals across an `await` crashes the Windows compiler.
    /// No wall-clock deadline: it gives up when the test is cancelled by the suite's time limit.
    func wait(count: Int) async -> Bool {
        if all.count >= count { return true }
        guard !Task.isCancelled else { return false }
        try? await Task.sleep(for: .milliseconds(10))
        return await wait(count: count)
    }
}

/// The bridge on pipes; every wait has a timeout.
private final class Harness: Sendable {
    let stdin = Pipe()
    let stdout = Pipe()
    let received = Lines()
    let exitCode = Exit()

    init(socket: URL, retryInterval: Duration = .milliseconds(50)) {
        let bridge = MCPBridge(socketPath: socket, retryInterval: retryInterval)
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
        return await waitForExit()
    }

    private func waitForExit() async -> Int32? {
        if let code = exitCode.code { return code }
        guard !Task.isCancelled else { return nil }
        try? await Task.sleep(for: .milliseconds(10))
        return await waitForExit()
    }

    func json(_ index: Int) throws -> JSONValue {
        let lines = received.all
        try #require(lines.indices.contains(index), "only \(lines.count) lines arrived, wanted index \(index)")
        return try JSONValue.parse(Data(lines[index].utf8))
    }
}

private func bridgeSocketURL() -> URL {
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

@Suite(.serialized, .timeLimit(.minutes(5))) struct BridgeTests {
    @Test func bridgeCopiesBothWays() async throws {
        let url = bridgeSocketURL()
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
        let harness = Harness(socket: bridgeSocketURL())
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
        let harness = Harness(socket: bridgeSocketURL())
        harness.send(#"{"jsonrpc":"2.0","id":"a","method":"tools/call","params":{"name":"list_nodes"}}"#)
        #expect(await harness.received.wait(count: 1))
        let result = try harness.json(0)["result"]
        #expect(result?["isError"]?.bool == true)
        #expect(result?["content"]?.array?.first?["text"]?.string == sentence)
        #expect(try harness.json(0)["id"]?.string == "a")
        #expect(await harness.finish() == 0)
    }

    private static let initializeLine =
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"t"}}}"#

    @Test func appStartingLaterIsAnnouncedWithoutAnotherRequest() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let harness = Harness(socket: url)
        harness.send(Self.initializeLine)
        harness.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(await harness.received.wait(count: 1))
        #expect(try harness.json(0)["result"]?["instructions"]?.string == sentence)
        #expect(try harness.json(0)["result"]?["capabilities"]?["tools"]?["listChanged"]?.bool == true)

        let seen = Lines()
        let app = makeApp(at: url, seen: seen)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        #expect(await harness.received.wait(count: 3))
        #expect(try harness.json(1)["method"]?.string == "notifications/tools/list_changed")
        #expect(try harness.json(2)["method"]?.string == "notifications/resources/list_changed")
        // The replay reached the app; its answer never reached the client.
        #expect(await seen.wait(count: 2))
        let methods = try seen.all.map { try JSONValue.parse(Data($0.utf8))["method"]?.string }
        #expect(methods == ["initialize", "notifications/initialized"])
        #expect(try JSONValue.parse(Data(seen.all[0].utf8))["params"]?["clientInfo"]?["name"]?.string == "t")
        #expect(harness.received.all.count == 3)
        #expect(await harness.finish() == 0)
    }

    @Test func appStartingLaterThenARequestGetsTheAppsAnswer() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let harness = Harness(socket: url)
        harness.send(Self.initializeLine)
        harness.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(await harness.received.wait(count: 1))
        let seen = Lines()
        let app = makeApp(at: url, seen: seen)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        #expect(await harness.received.wait(count: 3))
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(await harness.received.wait(count: 4))
        #expect(try harness.json(3)["id"]?.int == 2)
        #expect(try harness.json(3)["result"]?["from"]?.string == "app")
        #expect(await seen.wait(count: 3))
        let methods = try seen.all.map { try JSONValue.parse(Data($0.utf8))["method"]?.string }
        #expect(methods == ["initialize", "notifications/initialized", "tools/list"])
        #expect(await harness.finish() == 0)
    }

    @Test func theAppSeesExactlyOneInitializeWhenTheClientSendsFirst() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let seen = Lines()
        let app = makeApp(at: url, seen: seen)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let harness = Harness(socket: url)
        harness.send(Self.initializeLine)
        harness.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        #expect(await harness.received.wait(count: 2))
        #expect(await seen.wait(count: 3))
        let methods = try seen.all.map { try JSONValue.parse(Data($0.utf8))["method"]?.string }
        #expect(methods == ["initialize", "notifications/initialized", "ping"])
        #expect(try harness.json(0)["id"]?.int == 1, "the app's own answer to the client's initialize")
        #expect(await harness.finish() == 0)
    }

    @Test func appRestartIsAnnouncedAgain() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let seen = Lines()
        let app = makeApp(at: url, seen: seen)
        #expect(try app.start() == .listening)
        let harness = Harness(socket: url)
        harness.send(Self.initializeLine)
        #expect(await harness.received.wait(count: 1))
        #expect(await seen.wait(count: 1), "the client's own initialize")
        app.stop()
        let reborn = makeApp(at: url, seen: seen)
        #expect(try reborn.start() == .listening)
        defer { reborn.stop() }
        #expect(await harness.received.wait(count: 3))
        #expect(try harness.json(1)["method"]?.string == "notifications/tools/list_changed")
        #expect(try harness.json(2)["method"]?.string == "notifications/resources/list_changed")
        harness.send(#"{"jsonrpc":"2.0","id":5,"method":"tools/list"}"#)
        #expect(await harness.received.wait(count: 4))
        #expect(try harness.json(3)["result"]?["from"]?.string == "app")
        #expect(await harness.finish() == 0)
    }

    @Test func anIdleBridgeDoesNotHoldTheApp() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let states = Flags()
        let app = MCPListener(path: url, handle: { line, send in send(line + Data("\n".utf8)) }, connectionChanged: { states.add($0) })
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let harness = Harness(socket: url)
        try? await Task.sleep(for: .milliseconds(500))
        let raw = try LocalSocket.connect(to: url)
        defer { raw.close() }
        #expect(raw.write(Data("hello\n".utf8)))
        var reader = LineReader()
        var buffer = [UInt8](repeating: 0, count: 64)
        #expect(raw.waitReadable(milliseconds: 5_000))
        let count = raw.read(into: &buffer)
        reader.append(buffer[0..<max(count, 0)])
        #expect(reader.nextLine() == .line(Data("hello".utf8)))
        #expect(states.all == [true], "only the raw client was ever connected")
        #expect(await harness.finish() == 0)
    }

    @Test func aSecondClientIsToldTheAppIsBusy() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let seen = Lines()
        let app = MCPListener(path: url, handle: { line, send in
            seen.add(String(bytes: line, encoding: .utf8) ?? "")
            guard let message = try? JSONValue.parse(line), let id = message["id"] else { return }
            send(JSONRPC.result(id: id, .object(["from": .string("app")])))
        }, connectionChanged: { _ in }, busyGraceMilliseconds: 50)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let raw = try LocalSocket.connect(to: url)
        #expect(raw.write(Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\n".utf8)))
        #expect(raw.waitReadable(milliseconds: 5_000))
        var buffer = [UInt8](repeating: 0, count: 256)
        _ = raw.read(into: &buffer)
        let harness = Harness(socket: url)
        harness.send(Self.initializeLine)
        #expect(await harness.received.wait(count: 1))
        #expect(try harness.json(0)["result"]?["instructions"]?.string == MCPListener.busySentence)
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"x"}}"#)
        harness.send(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        #expect(await harness.received.wait(count: 3))
        #expect(try harness.json(1)["result"]?["isError"]?.bool == true)
        #expect(try harness.json(1)["result"]?["content"]?.array?.first?["text"]?.string == MCPListener.busySentence)
        #expect(try harness.json(2)["result"]?["tools"]?.array?.isEmpty == true)
        raw.close()
        #expect(await harness.received.wait(count: 5))
        #expect(try harness.json(3)["method"]?.string == "notifications/tools/list_changed")
        harness.send(#"{"jsonrpc":"2.0","id":4,"method":"tools/list"}"#)
        #expect(await harness.received.wait(count: 6))
        #expect(try harness.json(5)["result"]?["from"]?.string == "app")
        #expect(await harness.finish() == 0)
    }

    @Test func noWatcherWorkBeforeInitialize() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let seen = Lines()
        let app = makeApp(at: url, seen: seen)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let harness = Harness(socket: url)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(harness.received.all.isEmpty)
        #expect(seen.all.isEmpty)
        #expect(await harness.finish() == 0)
    }

    @Test func endOfInputStopsTheWatcher() async throws {
        let harness = Harness(socket: bridgeSocketURL(), retryInterval: .seconds(1))
        harness.send(Self.initializeLine)
        #expect(await harness.received.wait(count: 1))
        #expect(await harness.finish() == 0)
    }

    @Test func appClosingMidRequestAnswersEachPendingRequest() async throws {
        for (method, isTool) in [("tools/call", true), ("ping", false)] {
            let url = bridgeSocketURL()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            try SocketPath.prepareFolder(url)
            let stub = try LocalSocket.listen(at: url)
            let thread = Thread {
                guard let connection = try? stub.accept(timeoutMilliseconds: 5_000) else { return stub.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = connection.waitReadable(milliseconds: 5_000)
                _ = connection.read(into: &buffer)
                connection.close()
                stub.close()
            }
            thread.start()
            let harness = Harness(socket: url)
            harness.send(#"{"jsonrpc":"2.0","id":9,"method":"\#(method)","params":{"name":"x"}}"#)
            #expect(await harness.received.wait(count: 1))
            let reply = try harness.json(0)
            #expect(reply["id"]?.int == 9)
            if isTool {
                #expect(reply["result"]?["isError"]?.bool == true)
                #expect(reply["result"]?["content"]?.array?.first?["text"]?.string == MCPBridge.closedSentence)
            } else {
                #expect(reply["error"]?["code"]?.int == -32603)
                #expect(reply["error"]?["message"]?.string == MCPBridge.closedSentence)
            }
            #expect(await harness.finish() == 0)
        }
    }

    @Test func endOfInputWaitsForAPendingReply() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let app = MCPListener(path: url, handle: { _, send in
            try? await Task.sleep(for: .milliseconds(300))
            send(JSONRPC.result(id: .int(1), .object(["late": .bool(true)])))
        }, connectionChanged: { _ in })
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let harness = Harness(socket: url)
        harness.send(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        #expect(await harness.finish() == 0)
        #expect(await harness.received.wait(count: 1))
        #expect(try harness.json(0)["result"]?["late"]?.bool == true)
    }

    @Test func aTopLevelArrayIsAnInvalidRequest() async throws {
        let harness = Harness(socket: bridgeSocketURL())
        harness.send(#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#)
        #expect(await harness.received.wait(count: 1))
        #expect(try harness.json(0)["error"]?["code"]?.int == -32600)
        #expect(try harness.json(0)["id"] == .null)
        #expect(await harness.finish() == 0)
    }
}
