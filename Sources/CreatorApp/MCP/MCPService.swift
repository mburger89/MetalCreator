import CreatorMCP
import Foundation
import Synchronization

/// The AI connection: the on/off switch (the person's preference, or `--mcp` for one session), the listener on the local socket
/// and the document session it serves. Off by default; nothing listens until it is on.
@MainActor @Observable
public final class MCPService {
    public enum State: Equatable, Sendable {
        case off
        case listening
        /// Another MetalCreator window already serves the socket.
        case inUse
        case failed(String)
    }

    public private(set) var state = State.off
    /// True while an AI client has the socket open.
    public private(set) var isClientConnected = false
    /// The preference or the launch flag.
    public var isOn: Bool { preference.allowsAIConnections || launchFlag }

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let preference: any MCPPreference
    @ObservationIgnored private let launchFlag: Bool
    @ObservationIgnored private let path: URL
    @ObservationIgnored private var listener: MCPListener?
    /// Bumped by every start and stop, so a late callback of an older listener changes nothing.
    @ObservationIgnored private var generation = 0
    /// The number of the newest connection event applied for this listener.
    @ObservationIgnored private var lastEvent = 0

    public init(model: AppModel, preference: any MCPPreference, launchFlag: Bool = false, path: URL = SocketPath.default()) {
        self.model = model
        self.preference = preference
        self.launchFlag = launchFlag
        self.path = path
    }

    /// The menu's switch: remembers the choice, then starts or stops. Under `--mcp` the session stays on.
    public func setOn(_ on: Bool) {
        preference.allowsAIConnections = on
        if on {
            start()
        } else if !launchFlag {
            stop()
        }
    }

    /// Starts listening when the service is on. Does nothing when it is off or already listening.
    public func start() {
        guard isOn, listener == nil else { return }
        let session = AppDocumentSession(model: model)
        let core = MCPServerCore(session: session, tools: MCPCatalogue.tools, resources: MCPCatalogue.resources,
                                 serverVersion: AppBundleInfo.version)
        generation += 1
        lastEvent = 0
        let mine = generation
        // Events are numbered where they happen (the listener's thread), so the main-actor hops can't reorder them.
        let events = EventCounter()
        let made = MCPListener(
            path: path,
            handle: { line, send in
                // `send` is valid until this returns, so the main actor's work is awaited inside it.
                await Task { @MainActor in await core.handle(line: line, send: send) }.value
            },
            connectionChanged: { [weak self] connected in
                let number = events.next()
                Task { @MainActor in self?.connectionChanged(connected, number: number, generation: mine) }
            },
            failed: { [weak self] message in
                Task { @MainActor in self?.listenerFailed(message, generation: mine) }
            })
        do {
            switch try made.start() {
            case .listening:
                listener = made
                state = .listening
                SocketExitCleanup.register(path)
            case .inUse:
                state = .inUse
            }
        } catch {
            state = .failed(error.message)
        }
    }

    /// Stops listening and removes the socket file.
    public func stop() {
        generation += 1
        if listener != nil { SocketExitCleanup.forget() }
        listener?.stop()
        listener = nil
        isClientConnected = false
        state = .off
    }

    private func connectionChanged(_ connected: Bool, number: Int, generation: Int) {
        guard generation == self.generation, number > lastEvent else { return }
        lastEvent = number
        isClientConnected = connected
    }

    private func listenerFailed(_ message: String, generation: Int) {
        guard generation == self.generation else { return }
        SocketExitCleanup.forget()
        listener = nil
        isClientConnected = false
        state = .failed(message)
    }
}

/// Removes the socket file when the process exits, so a quit leaves no stale file for the next launch to probe. Not main-actor
/// isolated: `atexit` runs on whichever thread exits.
private enum SocketExitCleanup {
    private struct State {
        var path: String?
        var registered = false
    }

    private static let state = Mutex(State())

    /// Remembers the file this process listens on; the exit handler is installed once.
    static func register(_ url: URL) {
        let install = state.withLock { held -> Bool in
            held.path = url.path
            defer { held.registered = true }
            return !held.registered
        }
        guard install else { return }
        atexit {
            if let path = SocketExitCleanup.state.withLock({ $0.path }) { try? FileManager.default.removeItem(atPath: path) }
        }
    }

    /// The process no longer owns the file (stopped), so a later listener of another window is never touched.
    static func forget() {
        state.withLock { $0.path = nil }
    }
}

/// Numbers the listener's connection events in the order they happen.
private final class EventCounter: Sendable {
    private let count = Mutex(0)

    func next() -> Int {
        count.withLock { value in
            value += 1
            return value
        }
    }
}
