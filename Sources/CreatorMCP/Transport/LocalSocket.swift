import Foundation

/// Why a socket could not be made, in the app's voice.
public struct SocketProblem: Error, Equatable, Sendable {
    public let message: String
    /// The system's error number (`errno`, or Winsock's), 0 when there isn't one.
    public let code: Int32

    public init(_ message: String, code: Int32 = 0) {
        self.message = message
        self.code = code
    }

    /// Whether a connect failed because nothing listens at the path (a stale file), as opposed to any other failure.
    var isRefused: Bool {
        #if os(Windows)
        code == 10061
        #else
        code == ECONNREFUSED
        #endif
    }

    /// Whether an accept failed in a way a retry can outlive: an interrupted or aborted connection, or no descriptors for a moment.
    var isTransientAccept: Bool {
        #if os(Windows)
        code == 10054 || code == 10024 || code == 10053
        #else
        code == EINTR || code == ECONNABORTED || code == EMFILE || code == ENFILE || code == ENOBUFS || code == ENOMEM
        #endif
    }

    static let pathTooLong = SocketProblem("The path for AI connections is too long.")

    static func notPrivate(_ path: String) -> SocketProblem {
        SocketProblem("The folder for AI connections isn't private: \(path).")
    }

    static func failed(_ what: String, _ code: Int32) -> SocketProblem {
        SocketProblem("AI connections couldn't \(what) (error \(code)).", code: code)
    }
}

// `LocalSocket` itself is one small file per OS family: `LocalSocket+POSIX.swift` and `LocalSocket+Windows.swift`.
// Both give: `listen(at:)` (bind, owner-only, backlog 8), `connect(to:)`, `accept(timeoutMilliseconds:)`, `accept()`,
// `waitReadable(milliseconds:)`, `read(into:)` (bytes read, 0 at the end, -1 on an error), `write(_:)` and `close()`.
