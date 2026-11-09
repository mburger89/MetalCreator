import Foundation
import Synchronization

/// Listens on the local socket and serves one connection at a time. Each line is awaited before the next is read, so
/// responses keep the order of the requests. The accept loop runs on its own thread.
public final class MCPListener: Sendable {
    public enum StartResult: Sendable, Equatable {
        case listening
        /// Another live process already listens on the path; its file is left alone.
        case inUse
    }

    public typealias Handler = @Sendable (Data, @escaping @Sendable (Data) -> Void) async -> Void

    private let path: URL
    private let handle: Handler
    private let connectionChanged: @Sendable (Bool) -> Void
    private let stopped = Mutex(false)
    private let ownsFile = Mutex(false)

    public init(path: URL, handle: @escaping Handler, connectionChanged: @escaping @Sendable (Bool) -> Void) {
        self.path = path
        self.handle = handle
        self.connectionChanged = connectionChanged
    }

    public func start() throws(SocketProblem) -> StartResult {
        try SocketPath.prepareFolder(path)
        // A refusal can also mean a live listener whose queue is full, so ask a few times before calling the file stale.
        for attempt in 0..<3 {
            if let live = try? LocalSocket.connect(to: path) {
                live.close()
                return .inUse
            }
            if !FileManager.default.fileExists(atPath: path.path) { break }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.05) }
        }
        try? FileManager.default.removeItem(at: path)
        let socket = try LocalSocket.listen(at: path)
        stopped.withLock { $0 = false }
        ownsFile.withLock { $0 = true }
        let thread = Thread { [self] in acceptLoop(socket) }
        thread.name = "MCP listener"
        thread.start()
        return .listening
    }

    /// Stops accepting and removes the socket file. The thread closes its sockets when the request in hand is answered; this
    /// leaves a file it never created (`.inUse`) alone and never waits for it, so it is safe to call from the main actor while a handler is hopping there.
    public func stop() {
        stopped.withLock { $0 = true }
        if ownsFile.withLock({ let owned = $0; $0 = false; return owned }) {
            try? FileManager.default.removeItem(at: path)
        }
    }

    private var isStopped: Bool { stopped.withLock { $0 } }

    private func acceptLoop(_ listening: LocalSocket) {
        while !isStopped {
            do {
                guard let connection = try listening.accept(timeoutMilliseconds: 100) else { continue }
                serve(connection)
            } catch {
                break
            }
        }
        listening.close()
    }

    private func serve(_ connection: LocalSocket) {
        connectionChanged(true)
        let alive = Alive()
        var reader = LineReader()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var open = true
        while open, !isStopped {
            guard connection.waitReadable(milliseconds: 100) else { continue }
            let count = connection.read(into: &buffer)
            if count <= 0 { break }
            reader.append(buffer[0..<count])
            open = drain(&reader, connection, alive)
        }
        connection.close()
        connectionChanged(false)
    }

    /// Answers every complete line in `reader`; false once the connection should close.
    private func drain(_ reader: inout LineReader, _ connection: LocalSocket, _ alive: Alive) -> Bool {
        while let next = reader.nextLine() {
            guard case .line(let line) = next, alive.isOn, !isStopped else { return false }
            if line.isEmpty { continue }
            respond(to: line, over: connection, alive)
        }
        return alive.isOn
    }

    private func respond(to line: Data, over connection: LocalSocket, _ alive: Alive) {
        let handle = self.handle
        let done = DispatchSemaphore(value: 0)
        Task {
            await handle(line) { data in
                if !connection.write(data) { alive.fail() }
            }
            done.signal()
        }
        done.wait()
    }
}

private final class Alive: Sendable {
    private let state = Mutex(true)
    var isOn: Bool { state.withLock { $0 } }
    func fail() { state.withLock { $0 = false } }
}
