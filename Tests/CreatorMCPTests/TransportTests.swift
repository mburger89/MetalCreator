import Foundation
import Synchronization
import Testing
@testable import CreatorMCP

/// A door a handler waits at until the test opens it, so no sleep stands in for "long enough". Polls by recursion, never a loop.
final class Gate: Sendable {
    private let state = Mutex(false)
    func open() { state.withLock { $0 = true } }
    func wait() async {
        if state.withLock({ $0 }) || Task.isCancelled { return }
        try? await Task.sleep(for: .milliseconds(5))
        await wait()
    }
}

final class Flags: Sendable {
    private let states = Mutex<[Bool]>([])
    func add(_ value: Bool) { states.withLock { $0.append(value) } }
    var all: [Bool] { states.withLock { $0 } }
    func settle() async { try? await Task.sleep(for: .milliseconds(300)) }

    /// Polls by recursion (a loop holding locals across an `await` crashes the Windows compiler) and sleeps with `Task.sleep`, so the
    /// cooperative thread that runs the test is free for the listener's handler tasks. It has no wall-clock deadline of its own
    /// (a loaded runner decides nothing here): it stops when the test is cancelled, which the suites' time limit does.
    func waitFor(_ value: Bool, count: Int = 1) async -> Bool {
        if all.filter({ $0 == value }).count >= count { return true }
        guard !Task.isCancelled else { return false }
        try? await Task.sleep(for: .milliseconds(10))
        return await waitFor(value, count: count)
    }
}

/// A test client over the real socket; its waits end when the test is cancelled by the suite's time limit.
struct Client {
    let socket: LocalSocket
    var reader = LineReader()

    init(_ url: URL) throws { socket = try LocalSocket.connect(to: url) }

    func send(_ text: String) -> Bool { socket.write(Data(text.utf8)) }

    /// The next line, `nil` on a timeout, `""` on a closed connection. It never blocks a cooperative thread: it polls without waiting
    /// and sleeps with `Task.sleep` between polls, because the server's handlers are tasks on that same pool (a test that blocked
    /// the pool starved them on a CI runner with two cores). It has no wall-clock deadline: it gives up only when the test is cancelled.
    mutating func line() async -> String? {
        if case .line(let data)? = reader.nextLine() { return String(bytes: data, encoding: .utf8) ?? "" }
        if socket.waitReadable(milliseconds: 0) {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = socket.read(into: &buffer)
            if count <= 0 { return "" }
            reader.append(buffer[0..<count])
            return await line()
        }
        guard !Task.isCancelled else { return nil }
        try? await Task.sleep(for: .milliseconds(5))
        return await line()
    }
}

func tempSocketURL() -> URL {
    let folder = URL(fileURLWithPath: "/tmp/mcp-\(UInt32.random(in: 0...9_999_999))")
    return folder.appendingPathComponent("s.sock")
}

func makeListener(
    at url: URL, flags: Flags = Flags(),
    graceMilliseconds: Int = 1_000,
    handler: @escaping @Sendable (Data, @escaping @Sendable (Data) -> Void) async -> Void = { line, send in
        send(line + Data("\n".utf8))
    }
) -> MCPListener {
    MCPListener(path: url, handle: handler, connectionChanged: { flags.add($0) }, busyGraceMilliseconds: graceMilliseconds)
}

/// Waits (without blocking the pool) until the listener's accept loops are down to `count`.
func loops(of listener: MCPListener, atMost count: Int) async -> Bool {
    if listener.runningLoops <= count { return true }
    guard !Task.isCancelled else { return false }
    try? await Task.sleep(for: .milliseconds(10))
    return await loops(of: listener, atMost: count)
}

@Suite(.serialized, .timeLimit(.minutes(5))) struct TransportTests {
    @Test func roundTripOverARealSocket() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        #expect(client.send("ping\r\n"))
        #expect(await client.line() == "ping")
    }

    @Test func pipelinedRequestsAnswerInOrder() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url) { line, send in
            if line == Data("first".utf8) { try? await Task.sleep(for: .milliseconds(50)) }
            send(line + Data("\n".utf8))
        }
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        #expect(client.send("first\nsecond\n"))
        #expect(await client.line() == "first")
        #expect(await client.line() == "second")
    }

    @Test func clientVanishingMidRequestFreesTheServer() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let flags = Flags()
        let listener = makeListener(at: url, flags: flags) { line, send in
            if line == Data("slow".utf8) { try? await Task.sleep(for: .milliseconds(300)) }
            send(line + Data("\n".utf8))
        }
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        let first = try Client(url)
        #expect(first.send("slow\n"))
        #expect(await flags.waitFor(true))
        first.socket.close()
        #expect(await flags.waitFor(false))
        var second = try Client(url)
        #expect(second.send("hello\n"))
        #expect(await second.line() == "hello")
    }

    @Test func oversizedLineClosesTheConnection() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        let chunk = Data(repeating: 0x61, count: 1 << 20)
        var sent = 0
        while sent < 17, client.socket.write(chunk) { sent += 1 }
        #expect(await client.line() == "")
        client.socket.close()
        var next = try Client(url)
        #expect(next.send("again\n"))
        #expect(await next.line() == "again")
    }

    @Test func aClientThatNeverReadsIsDroppedAndTheHandlerIsNeverBlocked() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let flags = Flags()
        let returned = Flags()
        let big = Data(repeating: 0x61, count: 8 << 20) + Data("\n".utf8)
        let listener = MCPListener(
            path: url,
            handle: { _, send in
                send(big)  // only queues: it must return at once although nobody reads
                returned.add(true)
            },
            connectionChanged: { flags.add($0) }, writeTimeoutMilliseconds: 300)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        let client = try Client(url)
        #expect(client.send("go\n"))
        #expect(await returned.waitFor(true))
        #expect(await flags.waitFor(false), "the stalled connection is dropped")
        var next = try Client(url)
        #expect(next.send("x\n"))
        #expect(await next.line() != nil, "the next client is served")
    }

    @Test func aBoundedConnectFindsALiveListenerAndRefusesAStaleFile() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try SocketPath.prepareFolder(url)
        let live = try LocalSocket.listen(at: url)
        let probe = try LocalSocket.connect(to: url, timeoutMilliseconds: 200)
        probe.close()
        live.close()
        do {
            _ = try LocalSocket.connect(to: url, timeoutMilliseconds: 200)
            Issue.record("a stale file accepted a connection")
        } catch {
            #expect(error.isRefused)
        }
    }

    @Test func removingAStaleFileIsCheckedNotSwallowed() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try SocketPath.prepareFolder(url)
        try LocalSocket.removeFile(at: url)  // missing: fine
        let dead = try LocalSocket.listen(at: url)
        dead.close()
        #expect(LocalSocket.fileExists(at: url))
        try LocalSocket.removeFile(at: url)
        #expect(!LocalSocket.fileExists(at: url))
    }

    @Test func staleSocketIsReplaced() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try SocketPath.prepareFolder(url)
        let dead = try LocalSocket.listen(at: url)
        dead.close()
        #expect(LocalSocket.fileExists(at: url))
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        #expect(client.send("x\n"))
        #expect(await client.line() == "x")
    }

    @Test func liveSocketIsLeftAlone() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = makeListener(at: url)
        #expect(try first.start() == .listening)
        defer { first.stop() }
        let second = makeListener(at: url)
        #expect(try second.start() == .inUse)
        second.stop()
        var client = try Client(url)
        #expect(client.send("still\n"))
        #expect(await client.line() == "still")
    }

    @Test func stopRemovesTheFile() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        listener.stop()
        #expect(!LocalSocket.fileExists(at: url))
    }

    @Test func tooLongPathIsRefused() {
        let url = URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 200) + "/s.sock")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(throws: SocketProblem.self) { try listener.start() }
        do { _ = try listener.start() } catch { #expect(error.message == "The path for AI connections is too long.") }
    }

    #if !os(Windows)
    @Test func socketIsPrivate() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        let file = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        let folderPath = url.deletingLastPathComponent().path
        let folder = try FileManager.default.attributesOfItem(atPath: folderPath)[.posixPermissions] as? Int
        #expect(file == 0o600)
        #expect(folder == 0o700)
    }
    #endif

    @Test func probeConnectionFiresNoConnectionChange() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let flags = Flags()
        let listener = makeListener(at: url, flags: flags)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        let probe = try LocalSocket.connect(to: url)
        probe.close()
        let second = makeListener(at: url)
        #expect(try second.start() == .inUse)
        await flags.settle()
        #expect(flags.all.isEmpty)
        var client = try Client(url)
        #expect(client.send("x\n"))
        #expect(await client.line() == "x")
        #expect(flags.all == [true])
    }

    @Test func stopThenStartServesANewClientAndLeavesNoOldThread() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        listener.stop()
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        #expect(client.send("again\n"))
        #expect(await client.line() == "again")
        #expect(await loops(of: listener, atMost: 1))
        #expect(listener.runningLoops == 1)
        listener.stop()
        #expect(await loops(of: listener, atMost: 0))
        #expect(listener.runningLoops == 0)
    }

    @Test func startingTwiceReturnsTheSameState() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        #expect(try listener.start() == .listening)
        #expect(listener.runningLoops == 1)
    }

    @Test func probeLeavesABusyListenersFileAlone() async throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = Gate()
        let started = Lines()
        // A long grace: `queued` waits for the slot through the gate and the probe, however loaded the machine is.
        let listener = makeListener(at: url, graceMilliseconds: 60_000) { line, send in
            if line == Data("slow".utf8) {
                started.add("slow")
                await gate.wait()
            }
            send(line + Data("\n".utf8))
        }
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var busy = try Client(url)
        #expect(busy.send("slow\n"))
        // Each connection is admitted on its own thread, so `queued` could win the slot if it connected before `busy` held it.
        #expect(await started.wait(count: 1))
        var queued = try Client(url)
        #expect(queued.send("queued\n"))
        let second = makeListener(at: url)
        #expect(try second.start() == .inUse)
        #expect(LocalSocket.fileExists(at: url))
        gate.open()
        #expect(await busy.line() == "slow")
        busy.socket.close()
        #expect(await queued.line() == "queued")
    }
}

struct LineReaderTests {
    @Test func splitsLinesAndStripsReturns() {
        var reader = LineReader()
        reader.append(Array("a\r\nb\npart".utf8)[...])
        #expect(reader.nextLine() == .line(Data("a".utf8)))
        #expect(reader.nextLine() == .line(Data("b".utf8)))
        #expect(reader.nextLine() == nil)
        reader.append(Array("ial\n".utf8)[...])
        #expect(reader.nextLine() == .line(Data("partial".utf8)))
    }

    @Test func capsALine() {
        var reader = LineReader()
        reader.append(ArraySlice(repeating: 0x61, count: LineReader.maximumLineLength + 1))
        #expect(reader.nextLine() == .tooLong)
    }

    @Test func aLineAtTheCapIsKept() {
        var reader = LineReader()
        reader.append(ArraySlice(repeating: 0x61, count: LineReader.maximumLineLength))
        #expect(reader.nextLine() == nil)
        reader.append(ArraySlice([0x0A]))
        guard case .line(let data)? = reader.nextLine() else {
            Issue.record("no line")
            return
        }
        #expect(data.count == LineReader.maximumLineLength)
    }
}
