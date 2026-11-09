import Foundation
import Synchronization
import Testing
@testable import CreatorMCP

private final class Flags: Sendable {
    private let states = Mutex<[Bool]>([])
    func add(_ value: Bool) { states.withLock { $0.append(value) } }
    var all: [Bool] { states.withLock { $0 } }
    func settle() { Thread.sleep(forTimeInterval: 0.3) }
    func waitFor(_ value: Bool, count: Int = 1) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if all.filter({ $0 == value }).count >= count { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }
}

/// A test client over the real socket; every wait has a timeout.
private struct Client {
    let socket: LocalSocket
    var reader = LineReader()

    init(_ url: URL) throws { socket = try LocalSocket.connect(to: url) }

    func send(_ text: String) -> Bool { socket.write(Data(text.utf8)) }

    /// The next line, `nil` on a timeout, `""` on a closed connection.
    mutating func line(timeout: TimeInterval = 5) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            if case .line(let data)? = reader.nextLine() { return String(bytes: data, encoding: .utf8) ?? "" }
            guard socket.waitReadable(milliseconds: 20) else { continue }
            let count = socket.read(into: &buffer)
            if count <= 0 { return "" }
            reader.append(buffer[0..<count])
        }
        return nil
    }
}

private func tempSocketURL() -> URL {
    let folder = URL(fileURLWithPath: "/tmp/mcp-\(UInt32.random(in: 0...9_999_999))")
    return folder.appendingPathComponent("s.sock")
}

private func makeListener(
    at url: URL, flags: Flags = Flags(),
    handler: @escaping @Sendable (Data, @escaping @Sendable (Data) -> Void) async -> Void = { line, send in
        send(line + Data("\n".utf8))
    }
) -> MCPListener {
    MCPListener(path: url, handle: handler, connectionChanged: { flags.add($0) })
}

struct TransportTests {
    @Test func roundTripOverARealSocket() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        #expect(client.send("ping\r\n"))
        #expect(client.line() == "ping")
    }

    @Test func pipelinedRequestsAnswerInOrder() throws {
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
        #expect(client.line() == "first")
        #expect(client.line() == "second")
    }

    @Test func clientVanishingMidRequestFreesTheServer() throws {
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
        #expect(flags.waitFor(true))
        first.socket.close()
        #expect(flags.waitFor(false))
        var second = try Client(url)
        #expect(second.send("hello\n"))
        #expect(second.line() == "hello")
    }

    @Test func oversizedLineClosesTheConnection() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        let chunk = Data(repeating: 0x61, count: 1 << 20)
        var sent = 0
        while sent < 17, client.socket.write(chunk) { sent += 1 }
        #expect(client.line() == "")
        client.socket.close()
        var next = try Client(url)
        #expect(next.send("again\n"))
        #expect(next.line() == "again")
    }

    @Test func staleSocketIsReplaced() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try SocketPath.prepareFolder(url)
        let dead = try LocalSocket.listen(at: url)
        dead.close()
        #expect(FileManager.default.fileExists(atPath: url.path))
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        #expect(client.send("x\n"))
        #expect(client.line() == "x")
    }

    @Test func liveSocketIsLeftAlone() throws {
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
        #expect(client.line() == "still")
    }

    @Test func stopRemovesTheFile() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        listener.stop()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func tooLongPathIsRefused() {
        let url = URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 200) + "/s.sock")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(throws: SocketProblem.self) { try listener.start() }
        do { _ = try listener.start() } catch { #expect(error.message == "The path for AI connections is too long.") }
    }

    #if !os(Windows)
    @Test func socketIsPrivate() throws {
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

    @Test func probeConnectionFiresNoConnectionChange() throws {
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
        flags.settle()
        #expect(flags.all.isEmpty)
        var client = try Client(url)
        #expect(client.send("x\n"))
        #expect(client.line() == "x")
        #expect(flags.all == [true])
    }

    @Test func stopThenStartServesANewClientAndLeavesNoOldThread() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        listener.stop()
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var client = try Client(url)
        #expect(client.send("again\n"))
        #expect(client.line() == "again")
        let deadline = Date().addingTimeInterval(5)
        while listener.runningLoops > 1, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(listener.runningLoops == 1)
        listener.stop()
        while listener.runningLoops > 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(listener.runningLoops == 0)
    }

    @Test func startingTwiceReturnsTheSameState() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        #expect(try listener.start() == .listening)
        #expect(listener.runningLoops == 1)
    }

    @Test func probeLeavesABusyListenersFileAlone() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url) { line, send in
            if line == Data("slow".utf8) { try? await Task.sleep(for: .milliseconds(600)) }
            send(line + Data("\n".utf8))
        }
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var busy = try Client(url)
        #expect(busy.send("slow\n"))
        var queued = try Client(url)
        #expect(queued.send("queued\n"))
        let second = makeListener(at: url)
        #expect(try second.start() == .inUse)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(busy.line() == "slow")
        busy.socket.close()
        #expect(queued.line() == "queued")
    }

    @Test func onlyOneClientAtATime() throws {
        let url = tempSocketURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let listener = makeListener(at: url)
        #expect(try listener.start() == .listening)
        defer { listener.stop() }
        var first = try Client(url)
        #expect(first.send("one\n"))
        #expect(first.line() == "one")
        var second = try Client(url)
        #expect(second.send("two\n"))
        #expect(second.line(timeout: 0.4) == nil)
        first.socket.close()
        #expect(second.line() == "two")
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
