import Foundation

/// Why a socket could not be made, in the app's voice.
public struct SocketProblem: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) { self.message = message }

    static let pathTooLong = SocketProblem("The path for AI connections is too long.")

    static func notPrivate(_ path: String) -> SocketProblem {
        SocketProblem("The folder for AI connections isn't private: \(path).")
    }

    static func failed(_ what: String, _ code: Int32) -> SocketProblem {
        SocketProblem("AI connections couldn't \(what) (error \(code)).")
    }
}

// `LocalSocket` itself is one small file per OS family: `LocalSocket+POSIX.swift` and `LocalSocket+Windows.swift`.
// Both give: `listen(at:)` (bind, owner-only, backlog 1), `connect(to:)`, `accept(timeoutMilliseconds:)`, `accept()`,
// `waitReadable(milliseconds:)`, `read(into:)` (bytes read, 0 at the end, -1 on an error), `write(_:)` and `close()`.
