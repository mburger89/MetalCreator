#if !os(Windows)
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// One end of a Unix domain socket. It holds only its descriptor, so it can be shared between threads.
public final class LocalSocket: Sendable {
    private let descriptor: Int32

    private init(_ descriptor: Int32) { self.descriptor = descriptor }

    private static func makeSocket() throws(SocketProblem) -> Int32 {
        #if canImport(Darwin)
        let type = SOCK_STREAM
        #else
        let type = Int32(SOCK_STREAM.rawValue)
        #endif
        let fd = socket(AF_UNIX, type, 0)
        guard fd >= 0 else { throw SocketProblem.failed("open a socket", errno) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        #if canImport(Darwin)
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
        return fd
    }

    /// Refuses a path that doesn't fit `sun_path`, before any descriptor exists to leak.
    private static func checkLength(of url: URL) throws(SocketProblem) {
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard LocalSocket.fileSystemPath(url).utf8.count < capacity else { throw SocketProblem.pathTooLong }
    }

    /// Calls `body` with the address of `url`'s path, refusing a path that doesn't fit `sun_path`.
    private static func withAddress<T>(_ url: URL, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws(SocketProblem) -> T {
        var address = sockaddr_un()
        let path = Array(LocalSocket.fileSystemPath(url).utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.count < capacity else { throw SocketProblem.pathTooLong }
        address.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            for (index, byte) in path.enumerated() { bytes[index] = byte }
            bytes[path.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, size) }
        }
    }

    /// Binds `url`, makes the file owner-only and listens. The backlog is 8, not 1: a probe that finds the queue full would read a live listener as stale.
    public static func listen(at url: URL) throws(SocketProblem) -> LocalSocket {
        try checkLength(of: url)
        let fd = try makeSocket()
        // No umask change: it is process-wide. The folder is 0700 (`SocketPath.prepareFolder`), so the file is out of reach
        // until the `chmod` below makes it private as well.
        let bound = try withAddress(url) { bind(fd, $0, $1) }
        let bindError = errno
        guard bound == 0 else {
            systemClose(fd)
            throw SocketProblem.failed("listen at \(url.path)", bindError)
        }
        guard chmod(fileSystemPath(url), 0o600) == 0 else {
            let code = errno
            systemClose(fd)
            unlink(fileSystemPath(url))
            throw SocketProblem.failed("make the socket private", code)
        }
        guard systemListen(fd, 8) == 0 else {
            let code = errno
            systemClose(fd)
            unlink(fileSystemPath(url))
            throw SocketProblem.failed("listen", code)
        }
        return LocalSocket(fd)
    }

    public static func connect(to url: URL) throws(SocketProblem) -> LocalSocket {
        try checkLength(of: url)
        let fd = try makeSocket()
        let connected = try withAddress(url) { systemConnect(fd, $0, $1) }
        guard connected == 0 else {
            let code = errno
            systemClose(fd)
            throw SocketProblem.failed("connect", code)
        }
        return LocalSocket(fd)
    }

    /// Like `connect(to:)`, but never blocks longer than `timeoutMilliseconds`: a full listen queue (Linux answers a
    /// non-blocking connect to one with EAGAIN) or a connect that doesn't finish throws a problem with `isBusy` set.
    public static func connect(to url: URL, timeoutMilliseconds: Int32) throws(SocketProblem) -> LocalSocket {
        try checkLength(of: url)
        let fd = try makeSocket()
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let connected = try withAddress(url) { systemConnect(fd, $0, $1) }
        if connected != 0 {
            var code = errno
            if code == EINPROGRESS {
                var item = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let ready = poll(&item, 1, timeoutMilliseconds)
                if ready == 0 {
                    code = ETIMEDOUT
                } else if ready < 0 {
                    code = errno
                } else {
                    var pending: Int32 = 0
                    var size = socklen_t(MemoryLayout<Int32>.size)
                    _ = getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &size)
                    code = pending
                }
            }
            if code != 0 {
                systemClose(fd)
                throw SocketProblem.failed("connect", code)
            }
        }
        _ = fcntl(fd, F_SETFL, flags)
        return LocalSocket(fd)
    }

    /// Whether a file exists at `url`, a socket file included (the file itself, not what it points to).
    public static func fileExists(at url: URL) -> Bool {
        var info = stat()
        return lstat(fileSystemPath(url), &info) == 0
    }

    /// Removes a file (a stale socket); a missing one is fine, any other failure is thrown, so it is never swallowed.
    public static func removeFile(at url: URL) throws(SocketProblem) {
        let path = fileSystemPath(url)
        guard unlink(path) != 0, errno != ENOENT else { return }
        throw SocketProblem.failed("remove the old socket file", errno)
    }

    /// Makes a write give up when the other end stops reading for `milliseconds` (the write then fails with EAGAIN).
    public func setSendTimeout(milliseconds: Int) {
        var value = timeval(tv_sec: time_t(milliseconds / 1_000), tv_usec: suseconds_t((milliseconds % 1_000) * 1_000))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Whether a read (or, for a listening socket, an accept) would not block, waiting up to `milliseconds`.
    public func waitReadable(milliseconds: Int32) -> Bool {
        var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let result = poll(&item, 1, milliseconds)
        return result > 0
    }

    /// The next waiting connection, or `nil` when none came within `milliseconds`.
    public func accept(timeoutMilliseconds: Int32) throws(SocketProblem) -> LocalSocket? {
        guard waitReadable(milliseconds: timeoutMilliseconds) else { return nil }
        let fd = systemAccept(descriptor, nil, nil)
        guard fd >= 0 else {
            if errno == EAGAIN || errno == EINTR || errno == ECONNABORTED { return nil }
            throw SocketProblem.failed("accept a connection", errno)
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        #if canImport(Darwin)
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
        return LocalSocket(fd)
    }

    /// Blocks until a connection arrives.
    public func accept() throws(SocketProblem) -> LocalSocket {
        while true {
            if let socket = try accept(timeoutMilliseconds: 1_000) { return socket }
        }
    }

    /// Reads up to `into.count` bytes into the array; returns the count, 0 at the end of the stream, -1 on an error.
    public func read(into: inout [UInt8]) -> Int {
        while true {
            let count = into.withUnsafeMutableBytes { systemRecv(descriptor, $0.baseAddress, $0.count, 0) }
            if count < 0, errno == EINTR { continue }
            return count
        }
    }

    /// Writes all of `data`; false when the other end has gone.
    public func write(_ data: Data) -> Bool {
        #if canImport(Darwin)
        let flags: Int32 = 0
        #else
        let flags = Int32(MSG_NOSIGNAL)
        #endif
        return data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = send(descriptor, bytes.baseAddress! + offset, bytes.count - offset, flags)
                if sent < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += sent
            }
            return true
        }
    }

    /// Ends this side's sending (the peer reads what was sent, then the end of the stream) while this side can still read.
    public func shutdownWrite() { _ = shutdown(descriptor, Int32(SHUT_WR)) }

    public func close() { systemClose(descriptor) }
}

// The members above shadow the C functions of the same name inside the class, so these reach the global ones.
private func systemClose(_ fd: Int32) {
    #if canImport(Darwin)
    Darwin.close(fd)
    #else
    Glibc.close(fd)
    #endif
}

private func systemListen(_ fd: Int32, _ backlog: Int32) -> Int32 {
    #if canImport(Darwin)
    Darwin.listen(fd, backlog)
    #else
    Glibc.listen(fd, backlog)
    #endif
}

private func systemConnect(_ fd: Int32, _ address: UnsafePointer<sockaddr>, _ size: socklen_t) -> Int32 {
    #if canImport(Darwin)
    Darwin.connect(fd, address, size)
    #else
    Glibc.connect(fd, address, size)
    #endif
}

private func systemAccept(_ fd: Int32, _ address: UnsafeMutablePointer<sockaddr>?, _ size: UnsafeMutablePointer<socklen_t>?) -> Int32 {
    #if canImport(Darwin)
    Darwin.accept(fd, address, size)
    #else
    Glibc.accept(fd, address, size)
    #endif
}

private func systemRecv(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int, _ flags: Int32) -> Int {
    #if canImport(Darwin)
    Darwin.recv(fd, buffer, count, flags)
    #else
    Glibc.recv(fd, buffer, count, flags)
    #endif
}
#endif
