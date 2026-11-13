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
        session.beginClosing()
        session.waitForReplies(upTo: 1)
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

/// The bridge's state, shared by the stdin thread and the watcher: every change happens inside `state`. The reader threads never take it.
private struct SessionState {
    var link: BridgeLink?
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
    /// app sees exactly one `initialize`, also when its answer is late), so the app's answer is handed to the client under that id
    /// by the link's reader and the request is not forwarded again, and no `notifications/initialized` is sent (the client sends
    /// its own). Returns true when the link owes that answer.
    @discardableResult
    private func connectIfPossible(_ held: inout SessionState, replayingInitialize: Bool, answering: JSONValue? = nil) -> Bool {
        if let link = held.link, link.hasEnded { dropLink(&held) }
        guard held.link == nil else { return false }
        guard let socket = try? LocalSocket.connect(to: socketPath) else {
            held.refusal = nil
            return false
        }
        let fresh = BridgeLink(socket)
        let replay = replayingInitialize ? held.initializeParams : nil
        if let params = replay, !sendHandshake(params, over: socket, sendingInitialized: answering == nil) {
            socket.close()
            return false
        }
        fresh.startReading(into: output)
        var answer: Data?
        if replay != nil {
            switch settleHandshake(of: fresh, answering: answering) {
            case .refused(let message):
                fresh.shutDown()
                held.refusal = message
                return false
            case .lost:
                fresh.shutDown()
                return false
            case .accepted(let line): answer = line
            case .late: break
            }
        }
        let answered = replay != nil && answering != nil
        held.refusal = nil
        held.link = fresh
        // The answer to the client's `initialize` goes first: nothing may precede it.
        if let id = answering, let line = answer, let reply = BridgeLink.reply(line, id: id) { output.write(reply) }
        announceIfNeeded(&held)
        return answered
    }

    private func announceIfNeeded(_ held: inout SessionState) {
        guard held.needsAnnounce else { return }
        held.needsAnnounce = false
        output.write(JSONRPC.line(.object([
            "jsonrpc": .string("2.0"), "method": .string("notifications/tools/list_changed"),
        ])))
        output.write(JSONRPC.line(.object([
            "jsonrpc": .string("2.0"), "method": .string("notifications/resources/list_changed"),
        ])))
    }

    private func sendHandshake(_ params: JSONValue, over socket: LocalSocket, sendingInitialized: Bool) -> Bool {
        let hello = JSONRPC.line(.object([
            "jsonrpc": .string("2.0"), "id": .string(BridgeLink.replayID), "method": .string("initialize"), "params": params,
        ]))
        guard socket.write(hello) else { return false }
        return !sendingInitialized || socket.write(JSONRPC.notification("notifications/initialized", .object([:])))
    }

    private enum Settled {
        case accepted(Data)
        case refused(String)
        /// The link ended, or the bridge is closing: nothing is stored or announced.
        case lost
        /// Still no answer on a live link: it is kept, and the app's late answer reaches the client through the link, so the
        /// client's request is not forwarded a second time.
        case late
    }

    private func settleHandshake(of link: BridgeLink, answering: JSONValue?) -> Settled {
        var result = awaitHandshake(of: link)
        if result == nil, !link.hasEnded, !closing.withLock({ $0 }), let id = answering { result = link.owe(initializeAnswerTo: id) }
        switch result {
        case .accepted(let line)?: return .accepted(line)
        case .refused(let message)?: return .refused(message)
        case nil: return link.hasEnded || closing.withLock { $0 } ? .lost : .late
        }
    }

    /// Waits for the app's answer to the replayed `initialize`; `nil` on a timeout, a lost link or a closing bridge.
    private func awaitHandshake(of link: BridgeLink) -> BridgeLink.Handshake? {
        let deadline = Date().addingTimeInterval(handshakeSeconds)
        while true {
            if let answer = link.currentHandshake { return answer }
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
