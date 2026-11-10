#if os(Windows)
import Foundation
import Synchronization
import WinSDK

/// One end of an `AF_UNIX` socket (Windows 10 and later). It holds only its handle, so it can be shared between threads.
public final class LocalSocket: Sendable {
    private let handle: SOCKET
    /// The write timeout in milliseconds, 0 for none (a plain blocking send).
    private let sendTimeout = Mutex(0)
    /// Whether `setSendTimeout` managed to make the socket non-blocking.
    private let isNonBlocking = Mutex(false)

    private init(_ handle: SOCKET) { self.handle = handle }

    /// `afunix.h`'s `sockaddr_un` (WinSDK doesn't always expose it): a `UInt16` family then a 108-byte `sun_path`, built as raw bytes
    /// so no element count can be miscounted.
    static let addressSize = 2 + 108
    private static let pathCapacity = 108

    private static let started: Bool = {
        var data = WSADATA()
        return WSAStartup(0x0202, &data) == 0
    }()

    private static func makeSocket() throws(SocketProblem) -> SOCKET {
        guard started else { throw SocketProblem.failed("start Winsock", 0) }
        let handle = socket(AF_UNIX, SOCK_STREAM, 0)
        guard handle != INVALID_SOCKET else { throw SocketProblem.failed("open a socket", WSAGetLastError()) }
        return handle
    }

    private static func withAddress<T>(_ url: URL, _ body: (UnsafePointer<sockaddr>, Int32) -> T) throws(SocketProblem) -> T {
        let path = Array(LocalSocket.fileSystemPath(url).utf8)
        guard path.count < pathCapacity else { throw SocketProblem.pathTooLong }
        var bytes = [UInt8](repeating: 0, count: addressSize)
        let family = UInt16(AF_UNIX)
        bytes[0] = UInt8(family & 0xff)
        bytes[1] = UInt8(family >> 8)
        for (index, byte) in path.enumerated() { bytes[2 + index] = byte }
        return bytes.withUnsafeBytes { raw in
            body(raw.baseAddress!.assumingMemoryBound(to: sockaddr.self), Int32(addressSize))
        }
    }

    /// Refuses a path that doesn't fit `sun_path`, before any handle exists to leak.
    private static func checkLength(of url: URL) throws(SocketProblem) {
        guard LocalSocket.fileSystemPath(url).utf8.count < pathCapacity else { throw SocketProblem.pathTooLong }
    }

    public static func listen(at url: URL) throws(SocketProblem) -> LocalSocket {
        try checkLength(of: url)
        let handle = try makeSocket()
        guard try withAddress(url, { bind(handle, $0, $1) }) == 0 else {
            let code = WSAGetLastError()
            closesocket(handle)
            throw SocketProblem.failed("listen at \(url.path)", code)
        }
        guard WinSDK.listen(handle, 8) == 0 else {
            let code = WSAGetLastError()
            closesocket(handle)
            try? removeFile(at: url)
            throw SocketProblem.failed("listen", code)
        }
        return LocalSocket(handle)
    }

    public static func connect(to url: URL) throws(SocketProblem) -> LocalSocket {
        try checkLength(of: url)
        let handle = try makeSocket()
        guard try withAddress(url, { WinSDK.connect(handle, $0, $1) }) == 0 else {
            let code = WSAGetLastError()
            closesocket(handle)
            throw SocketProblem.failed("connect", code)
        }
        return LocalSocket(handle)
    }

    /// Windows has no non-blocking probe here: the plain connect (AF_UNIX connects don't wait on a full queue).
    public static func connect(to url: URL, timeoutMilliseconds: Int32) throws(SocketProblem) -> LocalSocket {
        try connect(to: url)
    }

    /// Whether a file exists at `url`, socket files included. `FileManager.fileExists` says no to an `AF_UNIX` socket on Windows
    /// (it is a reparse point), so the listener's probe would take a live socket for a missing one.
    public static func fileExists(at url: URL) -> Bool {
        fileSystemPath(url).withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) != INVALID_FILE_ATTRIBUTES }
    }

    /// Removes a file (a stale socket) with `DeleteFileW`; a missing one is fine, any other failure is thrown.
    public static func removeFile(at url: URL) throws(SocketProblem) {
        let deleted = fileSystemPath(url).withCString(encodedAs: UTF16.self) { DeleteFileW($0) }
        guard !deleted else { return }
        let code = Int32(GetLastError())
        guard code != 2 && code != 3 else { return }  // ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND
        throw SocketProblem.failed("remove the old socket file", code)
    }

    /// Makes a send give up when the other end stops reading for `milliseconds`. Winsock's `SO_SNDTIMEO` isn't reliably honoured by
    /// `AF_UNIX` sockets, so the socket goes non-blocking and `write(_:)` enforces the deadline itself with a monotonic clock. If
    /// the switch to non-blocking fails, `SO_SNDTIMEO` (a `DWORD` of milliseconds) is the best bound left.
    public func setSendTimeout(milliseconds: Int) {
        sendTimeout.withLock { $0 = milliseconds }
        var nonBlocking: u_long = milliseconds > 0 ? 1 : 0
        let switched = ioctlsocket(handle, Int32(bitPattern: 0x8004_667E), &nonBlocking) == 0  // FIONBIO
        isNonBlocking.withLock { $0 = switched && milliseconds > 0 }
        if !switched, milliseconds > 0 {
            var value = DWORD(clamping: milliseconds)
            _ = withUnsafeBytes(of: &value) { raw in
                setsockopt(handle, SOL_SOCKET, SO_SNDTIMEO, raw.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(raw.count))
            }
        }
    }

    public func waitReadable(milliseconds: Int32) -> Bool {
        var item = WSAPOLLFD(fd: handle, events: Int16(POLLRDNORM), revents: 0)
        return WSAPoll(&item, 1, milliseconds) > 0
    }

    public func accept(timeoutMilliseconds: Int32) throws(SocketProblem) -> LocalSocket? {
        guard waitReadable(milliseconds: timeoutMilliseconds) else { return nil }
        let accepted = WinSDK.accept(handle, nil, nil)
        guard accepted != INVALID_SOCKET else { throw SocketProblem.failed("accept a connection", WSAGetLastError()) }
        return LocalSocket(accepted)
    }

    public func accept() throws(SocketProblem) -> LocalSocket {
        while true {
            if let socket = try accept(timeoutMilliseconds: 1_000) { return socket }
        }
    }

    public func read(into: inout [UInt8]) -> Int {
        let count = into.withUnsafeMutableBytes { bytes in
            recv(handle, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(bytes.count), 0)
        }
        return Int(count)
    }

    /// Sends all of `data`. With a send timeout it gives up (false) once no byte has gone out for that long, judged by a monotonic
    /// clock in this loop rather than by `WSAPoll`'s return (`WSAPoll` is not trusted to wait or to report a full buffer on
    /// `AF_UNIX`). Sends go out in 64 KB pieces so a full buffer is noticed early.
    public func write(_ data: Data) -> Bool {
        let timeout = sendTimeout.withLock { $0 }
        let nonBlocking = isNonBlocking.withLock { $0 }
        let clock = ContinuousClock()
        return data.withUnsafeBytes { bytes in
            var offset = 0
            var lastProgress = clock.now
            while offset < bytes.count {
                let piece = nonBlocking ? min(bytes.count - offset, 65_536) : bytes.count - offset
                let sent = send(handle, bytes.baseAddress!.assumingMemoryBound(to: CChar.self) + offset, Int32(piece), 0)
                if sent > 0 {
                    offset += Int(sent)
                    lastProgress = clock.now
                    continue
                }
                guard sent < 0, nonBlocking, WSAGetLastError() == 10035 else { return false }  // WSAEWOULDBLOCK: wait for room
                let remaining = timeout - lastProgress.duration(to: clock.now).milliseconds
                if remaining <= 0 { return false }
                var item = WSAPOLLFD(fd: handle, events: Int16(POLLWRNORM), revents: 0)
                if WSAPoll(&item, 1, Int32(min(remaining, 50))) < 0 { return false }
                if item.revents & (Int16(POLLERR) | Int16(POLLHUP) | Int16(POLLNVAL)) != 0 { return false }
                Thread.sleep(forTimeInterval: 0.002)  // a poll that says "writable" at once must not make this loop spin
            }
            return true
        }
    }

    public func close() { closesocket(handle) }
}

private extension Duration {
    var milliseconds: Int {
        let parts = components
        return Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}
#endif
