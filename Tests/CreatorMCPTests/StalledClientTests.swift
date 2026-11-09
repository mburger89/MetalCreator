import CreatorGraph
import CreatorKernel
import Foundation
import Synchronization
import Testing
@testable import CreatorMCP

/// A client that asks for a large document and never reads must not freeze the window (the main actor) and is eventually dropped.
@MainActor struct StalledClientTests {
    /// The fastest time the main actor took to answer a hop over the window. Recursion, not a loop: a loop that keeps locals
    /// across an `await` crashes the Windows compiler. A blocked main actor answers none until the stall ends; a busy test run
    /// can delay some hops, so it is the best one that counts.
    private func fastestMainActorHop(until deadline: ContinuousClock.Instant, fastest: Duration = .seconds(3_600)) async -> Duration {
        guard ContinuousClock.now < deadline else { return fastest }
        let before = ContinuousClock.now
        await Task { @MainActor in }.value
        let took = ContinuousClock.now - before
        try? await Task.sleep(for: .milliseconds(50))
        return await fastestMainActorHop(until: deadline, fastest: min(fastest, took))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, until deadline: Date = Date().addingTimeInterval(30)) async -> Bool {
        if condition() { return true }
        guard Date() < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
        return await waitUntil(condition, until: deadline)
    }

    @Test func aClientThatNeverReadsLeavesTheMainActorFreeAndIsDropped() async throws {
        let fixture = try await SessionFixture()
        // Long names make the first page well over a megabyte: bigger than any socket buffer (Linux's is about 200 KB).
        let numbers = (0..<450).map { index in
            var node = fixture.document.registry.makeNode("creator.number")
            node.name = "Number \(index) " + String(repeating: "x", count: 8_000)
            return GraphCommand.addNode(node)
        }
        try fixture.document.perform(.batch(numbers), name: "Add Node")
        let core = fixture.core
        let connected = Mutex<[Bool]>([])
        let url = URL(fileURLWithPath: "/tmp/mcps-\(UInt32.random(in: 0...9_999_999))").appendingPathComponent("s.sock")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // The app's wiring (MCPService): parse on the listener's task, then hop to the main actor.
        let listener = MCPListener(
            path: url,
            handle: { line, send in
                switch MCPServerCore.parse(line: line) {
                case .invalid(let response): send(response)
                case .message(let message): await Task { @MainActor in await core.handle(message: message, send: send) }.value
                }
            },
            connectionChanged: { value in connected.withLock { $0.append(value) } },
            writeTimeoutMilliseconds: 500)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        let client = try LocalSocket.connect(to: url)
        defer { client.close() }
        let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\","
            + "\"params\":{\"name\":\"get_document\",\"arguments\":{}}}\n"
        #expect(client.write(Data(request.utf8)))
        #expect(await waitUntil { connected.withLock { $0 } == [true] })
        let fastest = await fastestMainActorHop(until: .now + .seconds(2))
        #expect(fastest < .seconds(1), "the main actor answered within \(fastest)")
        #expect(await waitUntil { connected.withLock { $0 } == [true, false] }, "the stalled connection is dropped")
    }
}
