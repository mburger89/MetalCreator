import Foundation
import Synchronization

/// The stdio side of the AI connection: an MCP client launches `metalcreator-mcp`, which copies its lines to the app's local
/// socket and the app's lines back. While the app can't be reached it serves the client itself, so a client that started first
/// still gets a working (empty) server with the reason, and connects to the app at the next request once it runs.
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

    public init(socketPath: URL) { self.socketPath = socketPath }

    /// Runs until stdin closes; 0 is a normal end.
    public func run(input: FileHandle, output: FileHandle) -> Int32 {
        let session = BridgeSession(socketPath: socketPath, output: output)
        var reader = LineReader()
        session.connectIfPossible(replayingInitialize: false)
        while true {
            let data = input.availableData
            if data.isEmpty { break }
            reader.append(Array(data)[...])
            while let next = reader.nextLine() {
                guard case .line(let line) = next else {
                    session.reply(JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, "That message is too long."))
                    session.close()
                    return 1
                }
                if !line.isEmpty { session.handle(line) }
            }
        }
        session.waitForReplies(upTo: 1)
        session.close()
        return 0
    }
}

/// One live connection to the app. Its reader thread owns reading; the stdin thread owns writing and closing.
private final class Link: Sendable {
    /// The id of the `initialize` the bridge sends on the client's behalf; the app's answer to it goes nowhere.
    static let replayID = "metalcreator-bridge-initialize"

    let socket: LocalSocket
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
                    if line.isEmpty || Self.isReplayAnswer(line, replay) { continue }
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

/// The stdin thread's state: the link (if any) and what the client said at `initialize`.
private final class BridgeSession {
    private let socketPath: URL
    private let output: OutputLock
    private var link: Link?
    private var initializeParams: JSONValue?
    /// Whether the bridge has answered anything itself, so a client may hold an empty tool list.
    private var answeredAlone = false

    init(socketPath: URL, output: FileHandle) {
        self.socketPath = socketPath
        self.output = OutputLock(output)
    }

    func reply(_ data: Data) { output.write(data) }

    /// After stdin closes: gives requests in flight up to `seconds` to be answered.
    func waitForReplies(upTo seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while let held = link, !held.hasEnded, held.pendingCount > 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func dropLink() {
        link?.shutDown()
        link?.failPending(into: output)
        link = nil
    }

    func close() {
        link?.shutDown()
        link = nil
    }

    /// Connects when nothing is connected. A client that already initialized with the bridge gets the app brought up to date first.
    func connectIfPossible(replayingInitialize: Bool) {
        if let held = link, held.hasEnded { dropLink() }
        guard link == nil, let socket = try? LocalSocket.connect(to: socketPath) else { return }
        let fresh = Link(socket)
        if replayingInitialize, let params = initializeParams {
            let hello = JSONRPC.line(.object([
                "jsonrpc": .string("2.0"), "id": .string(Link.replayID), "method": .string("initialize"), "params": params,
            ]))
            let ready = JSONRPC.notification("notifications/initialized", .object([:]))
            guard socket.write(hello), socket.write(ready) else {
                socket.close()
                return
            }
        }
        fresh.startReading(into: output)
        link = fresh
        if answeredAlone {
            answeredAlone = false
            output.write(JSONRPC.line(.object([
                "jsonrpc": .string("2.0"), "method": .string("notifications/tools/list_changed"),
            ])))
            output.write(JSONRPC.line(.object([
                "jsonrpc": .string("2.0"), "method": .string("notifications/resources/list_changed"),
            ])))
        }
    }

    func handle(_ line: Data) {
        let message = try? JSONValue.parse(line)
        if message?["method"]?.string == "initialize" { initializeParams = message?["params"] ?? .object([:]) }
        if let message, message.object == nil {
            reply(JSONRPC.error(id: .null, code: JSONRPC.invalidRequest, "That isn't a JSON-RPC request."))
            return
        }
        let isRequest = message.map { $0["method"]?.string != nil && ($0["id"] ?? .null) != .null } ?? true
        if isRequest { connectIfPossible(replayingInitialize: true) }
        if let held = link, !held.hasEnded {
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
        answerAlone(message)
    }

    /// The reply for a request while no app is there.
    private func answerAlone(_ message: JSONValue?) {
        guard let message, message.object != nil, let method = message["method"]?.string else {
            reply(JSONRPC.error(id: message?["id"] ?? .null, code: message == nil ? JSONRPC.parseError : JSONRPC.invalidRequest,
                                message == nil ? "The message isn't valid JSON." : "That isn't a JSON-RPC request."))
            return
        }
        let id = message["id"] ?? .null
        let sentence = MCPBridge.noAppSentence
        answeredAlone = true
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
