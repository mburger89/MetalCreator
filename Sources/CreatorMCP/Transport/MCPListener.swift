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

    /// Answers one request line. The `send` closure writes a response line and is valid only until the handler returns.
    public typealias Handler = @Sendable (Data, @escaping @Sendable (Data) -> Void) async -> Void

    /// One run of the accept loop: `stop()` marks its token, and only that run's thread watches it, so a later `start()`
    /// never shares a flag with a thread still winding down.
    private final class Run: Sendable {
        private let stopped = Mutex(false)
        var isStopped: Bool { stopped.withLock { $0 } }
        func stop() { stopped.withLock { $0 = true } }
    }

    private let path: URL
    private let handle: Handler
    private let connectionChanged: @Sendable (Bool) -> Void
    private let failed: @Sendable (String) -> Void
    private let current = Mutex<Run?>(nil)
    private let loops = Mutex(0)

    /// - Parameter failed: told, with a sentence, when the accept loop dies on an error it can't retry.
    public init(
        path: URL, handle: @escaping Handler, connectionChanged: @escaping @Sendable (Bool) -> Void,
        failed: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.path = path
        self.handle = handle
        self.connectionChanged = connectionChanged
        self.failed = failed
    }

    /// Accept loops still running (including ones winding down after `stop()`); a test's read-back.
    var runningLoops: Int { loops.withLock { $0 } }

    public func start() throws(SocketProblem) -> StartResult {
        if current.withLock({ $0 }) != nil { return .listening }
        try SocketPath.prepareFolder(path)
        if try probeFindsLiveListener() { return .inUse }
        try? FileManager.default.removeItem(at: path)
        let socket = try LocalSocket.listen(at: path)
        let run = Run()
        current.withLock { $0 = run }
        loops.withLock { $0 += 1 }
        let thread = Thread { [self] in acceptLoop(socket, run) }
        thread.name = "MCP listener"
        thread.start()
        return .listening
    }

    /// True when a live listener answers on the path. A missing file is no listener; a refusal (asked a few times, since a
    /// live listener with a full queue refuses too) is a stale file; any other failure throws and deletes nothing.
    private func probeFindsLiveListener() throws(SocketProblem) -> Bool {
        for attempt in 0..<3 {
            guard FileManager.default.fileExists(atPath: path.path) else { return false }
            do {
                let live = try LocalSocket.connect(to: path)
                live.close()
                return true
            } catch {
                guard error.isRefused else { throw error }
                if attempt < 2 { Thread.sleep(forTimeInterval: 0.05) }
            }
        }
        return false
    }

    /// Stops accepting and removes the socket file. The thread closes its sockets when the request in hand is answered; this
    /// leaves a file it never created (`.inUse`) alone and never waits for it, so it is safe to call from the main actor
    /// while a handler is hopping there.
    public func stop() {
        guard let run = current.withLock({ let run = $0; $0 = nil; return run }) else { return }
        run.stop()
        try? FileManager.default.removeItem(at: path)
    }

    private func acceptLoop(_ listening: LocalSocket, _ run: Run) {
        while !run.isStopped {
            do {
                guard let connection = try listening.accept(timeoutMilliseconds: 100) else { continue }
                serve(connection, run)
            } catch {
                if error.isTransientAccept {
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
                die(run, error)
                break
            }
        }
        listening.close()
        loops.withLock { $0 -= 1 }
    }

    /// A fatal accept error: this run's file goes (unless a newer run owns the path) and the owner is told.
    private func die(_ run: Run, _ error: SocketProblem) {
        run.stop()
        let wasCurrent = current.withLock { held -> Bool in
            guard held === run else { return false }
            held = nil
            return true
        }
        if wasCurrent {
            try? FileManager.default.removeItem(at: path)
            failed(error.message)
        }
    }

    private func serve(_ connection: LocalSocket, _ run: Run) {
        let alive = Alive()
        var reader = LineReader()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var announced = false
        var open = true
        while open, !run.isStopped {
            guard connection.waitReadable(milliseconds: 100) else { continue }
            let count = connection.read(into: &buffer)
            if count <= 0 { break }
            if !announced, !run.isStopped {
                announced = true
                connectionChanged(true)
            }
            reader.append(buffer[0..<count])
            open = drain(&reader, connection, alive, run)
        }
        connection.close()
        if announced { connectionChanged(false) }
    }

    /// Answers every complete line in `reader`; false once the connection should close.
    private func drain(_ reader: inout LineReader, _ connection: LocalSocket, _ alive: Alive, _ run: Run) -> Bool {
        while let next = reader.nextLine() {
            guard case .line(let line) = next, alive.isOn, !run.isStopped else { return false }
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
