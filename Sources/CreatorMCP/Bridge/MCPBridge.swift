import Foundation
import Synchronization

/// The stdio side of the AI connection: an MCP client launches `metalcreator-mcp`, which copies its lines to the app's local
/// socket and the app's lines back. While the app can't be reached it serves the client itself, so a client that started first
/// still gets a working (empty) server with the reason. The bridge connects to the app only once its client has spoken, and from
/// then on keeps trying in the background, announcing the tools when the app appears (or another client lets go of it).
public struct MCPBridge: Sendable {
    static let closedSentence = "MetalCreator closed the connection before answering."

    static func toolError(_ text: String) -> JSONValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(true),
        ])
    }

    static let noAppSentence =
        "MetalCreator isn't running, or AI connections are off: turn them on in MetalCreator ▸ Allow AI Connections."

    private let socketPath: URL
    private let retryInterval: Duration
    private let handshakeTimeout: Duration

    public init(socketPath: URL, retryInterval: Duration = .seconds(1), handshakeTimeout: Duration = .seconds(5)) {
        self.socketPath = socketPath
        self.retryInterval = retryInterval
        self.handshakeTimeout = handshakeTimeout
    }

    /// Runs until stdin closes; 0 is a normal end.
    public func run(input: FileHandle, output: FileHandle) -> Int32 {
        let session = BridgeSession(socketPath: socketPath, output: output, handshakeTimeout: handshakeTimeout)
        let watcher = Watcher(session: session, interval: retryInterval)
        watcher.start()
        defer { watcher.stopAndJoin() }
        var reader = LineReader()
        while true {
            let data = input.availableData
            if data.isEmpty { break }
            reader.append(Array(data)[...])
            while let next = reader.nextLine() {
                guard case .line(let line) = next else {
                    session.reply(JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, "That message is too long."))
                    session.beginClosing()
                    watcher.stopAndJoin()
                    session.close()
                    return 1
                }
                if !line.isEmpty { session.handle(line) }
            }
        }
        session.waitForReplies(upTo: 1)
        session.beginClosing()
        watcher.stopAndJoin()
        session.close()
        return 0
    }
}

/// Retries the connection in the background while a client has initialized and no link is live.
private final class Watcher: Sendable {
    private let session: BridgeSession
    private let interval: Duration
    private let stopped = Mutex(false)
    private let finished = DispatchSemaphore(value: 0)
    private let started = Mutex(false)

    init(session: BridgeSession, interval: Duration) {
        self.session = session
        self.interval = interval
    }

    private var isStopped: Bool { stopped.withLock { $0 } }

    func start() {
        started.withLock { $0 = true }
        let thread = Thread { [self] in
            while !isStopped {
                session.poll()
                sleepInterval()
            }
            finished.signal()
        }
        thread.name = "MCP bridge watcher"
        thread.start()
    }

    /// Sleeps in 50 ms slices so a stop is noticed promptly.
    private func sleepInterval() {
        let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        let deadline = Date().addingTimeInterval(seconds)
        while !isStopped, Date() < deadline { Thread.sleep(forTimeInterval: min(0.05, max(0.001, seconds))) }
    }

    func stopAndJoin() {
        stopped.withLock { $0 = true }
        guard started.withLock({ let was = $0; $0 = false; return was }) else { return }
        finished.wait()
    }
}

/// One live connection to the app. Its reader thread owns reading; the stdin thread owns writing and closing.
private final class Link: Sendable {
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

private final class OutputLock: Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        try? handle.write(contentsOf: data)
    }
}

/// The bridge's state, shared by the stdin thread and the watcher: every change happens inside `state`. The reader threads never take it.
private struct SessionState {
    var link: Link?
    var initializeParams: JSONValue?
    /// Whether the client may hold an empty tool list: set when the bridge answers alone or a link is lost, cleared by the announcement.
    var needsAnnounce = false
    /// Why the app wouldn't take this client (another client holds it), as the app worded it.
    var refusal: String?
}

private final class BridgeSession: Sendable {
    private let socketPath: URL
    private let output: OutputLock
    private let handshakeSeconds: Double
    private let state = Mutex(SessionState())
    private let closing = Mutex(false)

    init(socketPath: URL, output: FileHandle, handshakeTimeout: Duration) {
        self.socketPath = socketPath
        self.output = OutputLock(output)
        handshakeSeconds = Double(handshakeTimeout.components.seconds) + Double(handshakeTimeout.components.attoseconds) / 1e18
    }

    func reply(_ data: Data) { output.write(data) }

    /// Tells a handshake in progress to give up: stdin has closed.
    func beginClosing() { closing.withLock { $0 = true } }

    /// After stdin closes: gives requests in flight up to `seconds` to be answered.
    func waitForReplies(upTo seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let waiting = state.withLock { held -> Bool in
                guard let link = held.link else { return false }
                return !link.hasEnded && link.pendingCount > 0
            }
            guard waiting else { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// The watcher's step: once the client has initialized, notices a lost link and connects again when there is none.
    func poll() {
        state.withLock { held in
            guard held.initializeParams != nil else { return }
            if let link = held.link, link.hasEnded { dropLink(&held) }
            if held.link == nil { connectIfPossible(&held, replayingInitialize: true) }
        }
    }

    private func dropLink(_ held: inout SessionState) {
        held.link?.shutDown()
        held.link?.failPending(into: output)
        held.link = nil
        held.needsAnnounce = true
    }

    func close() {
        state.withLock { held in
            held.link?.shutDown()
            held.link = nil
        }
    }

    /// Connects when nothing is connected (called inside `state`). A client that already initialized gets the app brought up to
    /// date first, and the app's answer to that says whether it will take this client.
    /// `answering` is the id of the client's own `initialize` that triggered this connect: that request is the handshake itself (the
    /// app sees exactly one `initialize`), so the app's answer is handed to the client under that id and the request is not
    /// forwarded again, and no `notifications/initialized` is sent (the client sends its own). Returns true once it was answered.
    @discardableResult
    private func connectIfPossible(_ held: inout SessionState, replayingInitialize: Bool, answering: JSONValue? = nil) -> Bool {
        if let link = held.link, link.hasEnded { dropLink(&held) }
        guard held.link == nil else { return false }
        guard let socket = try? LocalSocket.connect(to: socketPath) else {
            held.refusal = nil
            return false
        }
        let fresh = Link(socket)
        let replay = replayingInitialize ? held.initializeParams : nil
        if let params = replay {
            let hello = JSONRPC.line(.object([
                "jsonrpc": .string("2.0"), "id": .string(Link.replayID), "method": .string("initialize"), "params": params,
            ]))
            let ready = JSONRPC.notification("notifications/initialized", .object([:]))
            guard socket.write(hello), answering != nil || socket.write(ready) else {
                socket.close()
                return false
            }
        }
        fresh.startReading(into: output)
        var answer: Data?
        if replay != nil {
            switch awaitHandshake(of: fresh) {
            case .refused(let message)?:
                fresh.shutDown()
                held.refusal = message
                return false
            case .accepted(let line)?: answer = line
            case nil: break
            }
        }
        held.refusal = nil
        held.link = fresh
        // The answer to the client's `initialize` goes first: nothing may precede it.
        var answered = false
        if let id = answering, let line = answer, let reply = try? JSONValue.parse(line), var fields = reply.object {
            fields["id"] = id
            output.write(JSONRPC.line(.object(fields)))
            answered = true
        }
        if held.needsAnnounce {
            held.needsAnnounce = false
            output.write(JSONRPC.line(.object([
                "jsonrpc": .string("2.0"), "method": .string("notifications/tools/list_changed"),
            ])))
            output.write(JSONRPC.line(.object([
                "jsonrpc": .string("2.0"), "method": .string("notifications/resources/list_changed"),
            ])))
        }
        return answered
    }

    /// Waits for the app's answer to the replayed `initialize`; `nil` on a timeout, a lost link or a closing bridge.
    private func awaitHandshake(of link: Link) -> Link.Handshake? {
        let deadline = Date().addingTimeInterval(handshakeSeconds)
        while true {
            if let answer = link.handshake.withLock({ $0 }) { return answer }
            if link.hasEnded || closing.withLock({ $0 }) || Date() >= deadline { return nil }
            _ = link.handshakeSignal.wait(timeout: .now() + .milliseconds(50))
        }
    }

    func handle(_ line: Data) {
        state.withLock { handle(line, &$0) }
    }

    private func handle(_ line: Data, _ state: inout SessionState) {
        let message = try? JSONValue.parse(line)
        let isInitialize = message?["method"]?.string == "initialize"
        if isInitialize { state.initializeParams = message?["params"] ?? .object([:]) }
        if let message, message.object == nil {
            reply(JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, "That isn't a JSON-RPC request."))
            return
        }
        let isRequest = message.map { $0["method"]?.string != nil && ($0["id"] ?? .null) != .null } ?? true
        // The client's own `initialize` is the handshake (see `connectIfPossible`): a synthetic one beside it would show the app two.
        // The connect and its handshake wait stay inside `state` on purpose: the stdin thread and the watcher both decide from
        // `link`, `refusal` and `needsAnnounce` and a connect that ran outside the lock could race them (two links, or an announcement
        // twice) in ways no test here can pin down; the cost is that stdin waits (up to the handshake timeout, 5 s, plus the app's
        // 1 s grace) only while another client holds the app.
        if isRequest {
            let answered = connectIfPossible(&state, replayingInitialize: true, answering: isInitialize ? message?["id"] : nil)
            if answered { return }
        }
        if let held = state.link, !held.hasEnded {
            let id = isRequest ? message?["id"] : nil
            if let id { held.expectReply(to: id, isToolCall: message?["method"]?.string == "tools/call") }
            if held.socket.write(line + Data("\n".utf8)) {
                if held.hasEnded { held.failPending(into: output) }
                return
            }
            if let id { held.forgetReply(to: id) }
            held.markEnded()
        }
        guard isRequest else { return }
        answerAlone(message, &state)
    }

    /// The reply for a request while no app is there (or it is serving another client).
    private func answerAlone(_ message: JSONValue?, _ state: inout SessionState) {
        guard let message, message.object != nil, let method = message["method"]?.string else {
            reply(JSONRPC.error(id: message?["id"] ?? .null, code: message == nil ? JSONRPC.parseError : JSONRPC.invalidRequest,
                                message == nil ? "The message isn't valid JSON." : "That isn't a JSON-RPC request."))
            return
        }
        let id = message["id"] ?? .null
        let sentence = state.refusal ?? MCPBridge.noAppSentence
        state.needsAnnounce = true
        switch method {
        case "initialize":
            let offered = message["params"]?["protocolVersion"]?.string
            let version = offered.flatMap { MCPProtocol.supportedVersions.contains($0) ? $0 : nil } ?? MCPProtocol.supportedVersions[0]
            reply(JSONRPC.result(id: id, .object([
                "protocolVersion": .string(version),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(true)]), "resources": .object(["listChanged": .bool(true)]),
                ]),
                "serverInfo": .object(["name": .string("MetalCreator"), "version": .string("bridge")]),
                "instructions": .string(sentence),
            ])))
        case "ping": reply(JSONRPC.result(id: id, .object([:])))
        case "tools/list": reply(JSONRPC.result(id: id, .object(["tools": .array([])])))
        case "resources/list": reply(JSONRPC.result(id: id, .object(["resources": .array([])])))
        case "tools/call":
            reply(JSONRPC.result(id: id, MCPBridge.toolError(sentence)))
        default: reply(JSONRPC.error(id: id, code: JSONRPC.methodNotFound, "There's no method “\(method)”."))
        }
    }
}
