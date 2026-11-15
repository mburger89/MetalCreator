import Foundation
import Testing
@testable import CreatorMCP

@Suite(.serialized, .timeLimit(.minutes(5))) struct BusyClientTests {
    @Test func onlyOneClientAtATime() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url, graceMilliseconds: 100)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var first = try Client(url)
        #expect(first.send("one\n"))
        #expect(await first.line() == "one")
        var second = try Client(url)
        #expect(second.send("{\"id\":1}\n"))
        let refusal = try JSONValue.parse(Data((await second.line() ?? "").utf8))
        #expect(refusal["error"]?["code"]?.int == -32001)
        first.socket.close()
        var third = try Client(url)
        #expect(third.send("three\n"))
        #expect(await third.line() == "three")
    }

    @Test func secondClientIsRefusedWithTheBusySentence() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url, graceMilliseconds: 100)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var first = try Client(url)
        #expect(first.send("one\n"))
        #expect(await first.line() == "one")
        var second = try Client(url)
        #expect(second.send(#"{"jsonrpc":"2.0","id":7,"method":"initialize"}"# + "\n"))
        let line = await second.line()
        let reply = try JSONValue.parse(Data((line ?? "").utf8))
        #expect(reply["error"]?["code"]?.int == -32001)
        #expect(reply["error"]?["message"]?.string == MCPListener.busySentence)
        #expect(reply["id"]?.int == 7)
        #expect(await second.line() == "", "the refused connection is closed")
        #expect(first.send("again\n"))
        #expect(await first.line() == "again", "the first client is unaffected")
    }

    @Test func aSlotFreedWithinTheGraceServesTheNextClient() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url, graceMilliseconds: 5_000)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var first = try Client(url)
        #expect(first.send("one\n"))
        #expect(await first.line() == "one")
        var second = try Client(url)
        #expect(second.send("two\n"))
        try? await Task.sleep(for: .milliseconds(100))
        first.socket.close()
        #expect(await second.line() == "two")
    }

    @Test func aProbeWhileBusyIsClosedQuietly() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let flags = Flags()
        let listener = makeListener(at: url, flags: flags, graceMilliseconds: 100)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var first = try Client(url)
        #expect(first.send("one\n"))
        #expect(await first.line() == "one")
        let probe = try Client(url)
        try? await Task.sleep(for: .milliseconds(300))
        probe.socket.close()
        #expect(first.send("two\n"))
        #expect(await first.line() == "two")
        #expect(flags.all == [true])
    }

    @Test func refusalDoesNotChangeTheConnectionState() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let flags = Flags()
        let listener = makeListener(at: url, flags: flags, graceMilliseconds: 50)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var first = try Client(url)
        #expect(first.send("one\n"))
        #expect(await first.line() == "one")
        var second = try Client(url)
        #expect(second.send("{\"id\":1}\n"))
        #expect(await second.line() != nil)
        second.socket.close()
        await flags.settle()
        #expect(flags.all == [true])
    }

    @Test func connectionsBeyondTheWaitingCapAreClosedAtOnce() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url, graceMilliseconds: 600_000)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var first = try Client(url)
        #expect(first.send("one\n"))
        #expect(await first.line() == "one")
        // One thread serves, `maximumWaiting` more wait out the grace.
        var waiting: [Client] = []
        for _ in 0..<MCPListener.maximumWaiting { waiting.append(try Client(url)) }
        #expect(await connections(of: listener, atLeast: MCPListener.maximumWaiting + 1))
        var extra = try Client(url)
        #expect(await extra.line() == "", "the connection beyond the cap is closed without waiting")
        #expect(listener.activeConnections == MCPListener.maximumWaiting + 1)
        first.socket.close()
        for client in waiting { client.socket.close() }
    }

    @Test func stopWithABusyAdmitThreadLeavesNoThread() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url, graceMilliseconds: 60_000)
        #expect(try listener.start() == .listening)
        let first = try Client(url)
        #expect(first.send("one\n"))
        let waiting = try Client(url)
        try? await Task.sleep(for: .milliseconds(200))
        listener.stop()
        #expect(await loops(of: listener, atMost: 0))
        #expect(await connections(of: listener, atMost: 0))
        first.socket.close()
        waiting.socket.close()
    }
}

/// Waits (without blocking the pool) until the listener's connection threads are down to `count`.
private func connections(of listener: MCPListener, atMost count: Int) async -> Bool {
    if listener.activeConnections <= count { return true }
    guard !Task.isCancelled else { return false }
    try? await Task.sleep(for: .milliseconds(10))
    return await connections(of: listener, atMost: count)
}

private func connections(of listener: MCPListener, atLeast count: Int) async -> Bool {
    if listener.activeConnections >= count { return true }
    guard !Task.isCancelled else { return false }
    try? await Task.sleep(for: .milliseconds(10))
    return await connections(of: listener, atLeast: count)
}
