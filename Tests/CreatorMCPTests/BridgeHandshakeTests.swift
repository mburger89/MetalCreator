import Foundation
import Testing
@testable import CreatorMCP

/// The handshake the bridge makes with the app on the client's behalf.
@Suite(.serialized, .timeLimit(.minutes(5))) struct BridgeHandshakeTests {
    private static let initializeLine = BridgeTests.initializeLine

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

    @Test func anAppThatClosesWithoutAnsweringIsNeitherLinkedNorAnnounced() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try SocketPath.prepareFolder(url)
        let stub = try LocalSocket.listen(at: url)
        let stopping = Flags()
        let thread = Thread {
            while stopping.all.isEmpty {
                guard let connection = try? stub.accept(timeoutMilliseconds: 20) else { continue }
                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = connection.waitReadable(milliseconds: 1_000)
                _ = connection.read(into: &buffer)
                connection.close()
            }
            stub.close()
        }
        thread.start()
        defer { stopping.add(true) }
        let harness = Harness(socket: url)
        harness.send(Self.initializeLine)
        #expect(await harness.received.wait(count: 1))
        #expect(try harness.json(0)["result"]?["instructions"]?.string == sentence)
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        #expect(await harness.received.wait(count: 2))
        #expect(await harness.finish() == 0)
        let lines = try harness.received.all.map { try JSONValue.parse(Data($0.utf8)) }
        #expect(lines.allSatisfy { $0["method"] == nil }, "nothing was announced")
        #expect(lines.count == 2)
    }

    @Test func aRefusedBridgeWhoseHandshakeIsTwoLinesStillGetsTheBusySentence() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // The watcher must not retry on its own: with the app's socket up, a retry that lands before `raw` below is served would
        // take the slot, and the bridge, not `raw`, would be the client the app serves (and answers, not refuses).
        let harness = Harness(socket: url, retryInterval: .seconds(3600))
        harness.send(Self.initializeLine)
        harness.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(await harness.received.wait(count: 1))
        let seen = Lines()
        let app = MCPListener(path: url, handle: { line, send in
            seen.add(String(bytes: line, encoding: .utf8) ?? "")
            guard let message = try? JSONValue.parse(line), let id = message["id"] else { return }
            send(JSONRPC.result(id: id, .object(["from": .string("app")])))
        }, connectionChanged: { _ in }, busyGraceMilliseconds: 50)
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let raw = try LocalSocket.connect(to: url)
        defer { raw.close() }
        #expect(raw.write(Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\n".utf8)))
        // Only once the app has served `raw`'s line does it hold the slot; then the bridge's connect is the one refused.
        #expect(await seen.wait(count: 1))
        // The watcher's replay is two writes; the app refuses it and the bridge says why.
        harness.send(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"x"}}"#)
        #expect(await harness.received.wait(count: 2))
        let text = try harness.json(1)["result"]?["content"]?.array?.first?["text"]?.string
        #expect(text == MCPListener.busySentence)
        #expect(await harness.finish() == 0)
    }

    @Test func aLateAnswerToTheClientsInitializeReachesItAndTheAppSeesOne() async throws {
        let url = bridgeSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let seen = Lines()
        let app = MCPListener(path: url, handle: { line, send in
            seen.add(String(bytes: line, encoding: .utf8) ?? "")
            guard let message = try? JSONValue.parse(line), let id = message["id"] else { return }
            if message["method"]?.string == "initialize" { try? await Task.sleep(for: .milliseconds(400)) }
            send(JSONRPC.result(id: id, .object(["from": .string("app")])))
        }, connectionChanged: { _ in })
        #expect(try app.start() == .listening)
        defer { app.stop() }
        let harness = Harness(socket: url, handshakeTimeout: .milliseconds(100))
        harness.send(Self.initializeLine)
        #expect(await harness.received.wait(count: 1))
        #expect(try harness.json(0)["id"]?.int == 1)
        #expect(try harness.json(0)["result"]?["from"]?.string == "app")
        harness.send(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)
        #expect(await harness.received.wait(count: 2))
        let methods = try seen.all.map { try JSONValue.parse(Data($0.utf8))["method"]?.string }
        #expect(methods == ["initialize", "ping"])
        #expect(await harness.finish() == 0)
    }
}
