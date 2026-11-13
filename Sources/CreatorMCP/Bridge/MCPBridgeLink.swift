import Foundation
import Synchronization

final class OutputLock: Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        try? handle.write(contentsOf: data)
    }
}

/// One live connection to the app. Its reader thread owns reading; the stdin thread owns writing and closing.
final class BridgeLink: Sendable {
    /// The id of the `initialize` the bridge sends on the client's behalf; the app's answer to it goes nowhere.
    static let replayID = "metalcreator-bridge-initialize"

    enum Handshake: Sendable {
        /// The app took the client; its whole answer, which the bridge hands the client when the replay was the client's own request.
        case accepted(Data)
        case refused(String)
    }

    let socket: LocalSocket
    /// The app's answer to the replayed `initialize`, once it comes.
    let handshake = Mutex<Handshake?>(nil)
    let handshakeSignal = DispatchSemaphore(value: 0)
    private let stopped = Mutex(false)
    private let ended = Mutex(false)
    private let finished = DispatchSemaphore(value: 0)
    /// Requests forwarded and not yet answered: the id as encoded JSON, and whether it was a `tools/call`.
    private let pending = Mutex<[String: Bool]>([:])

    init(_ socket: LocalSocket) { self.socket = socket }

    var isStopped: Bool { stopped.withLock { $0 } }
    /// True once the app's side closed or failed.
    var hasEnded: Bool { ended.withLock { $0 } }
    var pendingCount: Int { pending.withLock { $0.count } }

    func markEnded() { ended.withLock { $0 = true } }

    static func key(_ id: JSONValue) -> String { String(bytes: id.encoded(), encoding: .utf8) ?? "" }

    func expectReply(to id: JSONValue, isToolCall: Bool) { pending.withLock { $0[Self.key(id)] = isToolCall } }
    func forgetReply(to id: JSONValue) { pending.withLock { _ = $0.removeValue(forKey: Self.key(id)) } }

    /// Answers every request still waiting, once: the app went away before replying.
    func failPending(into output: OutputLock) {
        let waiting = pending.withLock { held -> [String: Bool] in
            let all = held
            held = [:]
            return all
        }
        for (key, isToolCall) in waiting.sorted(by: { $0.key < $1.key }) {
            guard let id = try? JSONValue.parse(Data(key.utf8)) else { continue }
            let sentence = MCPBridge.closedSentence
            if isToolCall {
                output.write(JSONRPC.result(id: id, MCPBridge.toolError(sentence)))
            } else {
                output.write(JSONRPC.error(id: id, code: -32603, sentence))
            }
        }
    }

    func startReading(into output: OutputLock) {
        let thread = Thread { [self] in
            var reader = LineReader()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let replay = Data(Self.replayID.utf8)
            loop: while !isStopped {
                guard socket.waitReadable(milliseconds: 100) else { continue }
                let count = socket.read(into: &buffer)
                if count <= 0 { break }
                reader.append(buffer[0..<count])
                while let next = reader.nextLine() {
                    guard case .line(let line) = next else { break loop }
                    if line.isEmpty { continue }
                    if Self.isReplayAnswer(line, replay) {
                        handshake.withLock { $0 = Self.handshake(of: line) }
                        handshakeSignal.signal()
                        continue
                    }
                    if pendingCount > 0, let reply = try? JSONValue.parse(line), reply["method"] == nil, let id = reply["id"] {
                        forgetReply(to: id)
                    }
                    output.write(line + Data("\n".utf8))
                }
            }
            markEnded()
            if !isStopped { failPending(into: output) }
            finished.signal()
        }
        thread.name = "MCP bridge reader"
        thread.start()
    }

    /// A refusal carries the busy code and the sentence; anything else is the app accepting.
    private static func handshake(of line: Data) -> Handshake {
        let error = (try? JSONValue.parse(line))?["error"]
        guard error?["code"]?.int == JSONRPC.alreadyConnected else { return .accepted(line) }
        return .refused(error?["message"]?.string ?? MCPListener.busySentence)
    }

    private static func isReplayAnswer(_ line: Data, _ needle: Data) -> Bool {
        line.range(of: needle) != nil && (try? JSONValue.parse(line))?["id"]?.string == replayID
    }

    /// Stops the reader, waits for it, then closes the socket.
    func shutDown() {
        stopped.withLock { $0 = true }
        finished.wait()
        socket.close()
    }
}
