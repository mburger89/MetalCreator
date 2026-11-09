#if os(Windows)
import Foundation
import Synchronization
import WinSDK

/// One end of an `AF_UNIX` socket (Windows 10 and later). It holds only its handle, so it can be shared between threads.
public final class LocalSocket: Sendable {
    private let handle: SOCKET
    /// The write timeout in milliseconds, 0 for none (a plain blocking send).
    private let sendTimeout = Mutex(0)

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

    /// Makes a send give up when the other end stops reading for `milliseconds`. Winsock's `SO_SNDTIMEO` isn't honoured by
    /// `AF_UNIX` sockets, so the socket goes non-blocking and `write(_:)` waits for room itself.
    public func setSendTimeout(milliseconds: Int) {
        sendTimeout.withLock { $0 = milliseconds }
        var nonBlocking: u_long = milliseconds > 0 ? 1 : 0
        _ = ioctlsocket(handle, Int32(bitPattern: 0x8004_667E), &nonBlocking)  // FIONBIO
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

    public func write(_ data: Data) -> Bool {
        let timeout = Int32(clamping: sendTimeout.withLock { $0 })
        return data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = send(handle, bytes.baseAddress!.assumingMemoryBound(to: CChar.self) + offset, Int32(bytes.count - offset), 0)
                if sent > 0 {
                    offset += Int(sent)
                } else if sent < 0, timeout > 0, WSAGetLastError() == 10035 {  // WSAEWOULDBLOCK: wait for room, up to the timeout
                    var item = WSAPOLLFD(fd: handle, events: Int16(POLLWRNORM), revents: 0)
                    if WSAPoll(&item, 1, timeout) <= 0 { return false }
                } else {
                    return false
                }
            }
            return true
        }
    }

    public func close() { closesocket(handle) }
}
#endif
