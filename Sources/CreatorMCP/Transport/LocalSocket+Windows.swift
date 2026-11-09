#if os(Windows)
import Foundation
import WinSDK

/// One end of an `AF_UNIX` socket (Windows 10 and later). It holds only its handle, so it can be shared between threads.
public final class LocalSocket: Sendable {
    private let handle: SOCKET

    private init(_ handle: SOCKET) { self.handle = handle }

    /// `afunix.h`'s address, declared here because WinSDK doesn't always expose it.
    private struct UnixAddress {
        var family: UInt16 = UInt16(AF_UNIX)
        // swiftlint:disable:next large_tuple - sun_path is a fixed 108-byte C array, which Swift imports as a tuple.
        var path: (
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
            CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar
        ) = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

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
        var address = UnixAddress()
        let path = Array(url.path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.path)
        guard path.count < capacity else { throw SocketProblem.pathTooLong }
        withUnsafeMutableBytes(of: &address.path) { bytes in
            for (index, byte) in path.enumerated() { bytes[index] = byte }
        }
        let size = Int32(MemoryLayout<UnixAddress>.size)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, size) }
        }
    }

    /// Refuses a path that doesn't fit `sun_path`, before any handle exists to leak.
    private static func checkLength(of url: URL) throws(SocketProblem) {
        let capacity = MemoryLayout.size(ofValue: UnixAddress().path)
        guard url.path.utf8.count < capacity else { throw SocketProblem.pathTooLong }
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
            try? FileManager.default.removeItem(at: url)
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
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = send(handle, bytes.baseAddress!.assumingMemoryBound(to: CChar.self) + offset, Int32(bytes.count - offset), 0)
                if sent <= 0 { return false }
                offset += Int(sent)
            }
            return true
        }
    }

    public func close() { closesocket(handle) }
}
#endif
