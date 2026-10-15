import Foundation

/// Writes a zip file entry by entry, streaming (implicit spec §5.3): each entry's data goes to the file as it is given, with its
/// sizes and CRC in a data descriptor after it, so an entry of any length needs no memory. Entries are deflated where Apple's
/// Compression framework exists (`defaultMethod`) and stored everywhere else; both are plain zip that any reader opens. The file
/// is written to a temporary beside the destination and moved into place by `finish()`, so a cancelled export leaves nothing, and
/// dates are fixed, so the same entries give the same bytes. A file, an entry or an offset that reaches 4 GB is written as Zip64, so a
/// 3MF of tens of gigabytes of XML (implicit spec Errata D12's case) is a valid zip: only the fields that overflow change, and a small
/// file is the plain zip every reader knows.
public struct ZipWriter {
    public enum Method: UInt16, Sendable {
        case stored = 0
        case deflated = 8
    }

    /// Deflated where the Compression framework exists, else stored. Stored blocks need no code and run anywhere, but a 3MF's XML is
    /// about ten times larger stored.
    public static var defaultMethod: Method {
        #if canImport(Compression)
        .deflated
        #else
        .stored
        #endif
    }

    private struct Entry {
        var name: String
        var method: Method
        var crc: UInt32
        var compressedSize: UInt64
        var size: UInt64
        var offset: UInt64
    }

    private struct Current {
        var name: String
        var method: Method
        var crc: UInt32 = 0
        var compressedSize: UInt64 = 0
        var size: UInt64 = 0
        var offset: UInt64
        #if canImport(Compression)
        var deflater: RawDeflater?
        #endif
    }

    /// The value from which a size, an offset or a count no longer fits its 32-bit (or 16-bit) field and is written as Zip64. A field
    /// holding all ones means "see the Zip64 extra", so 4 GB less one is already too large. The tests lower it.
    public let zip64At: UInt64
    private let destination: URL
    private let partial: URL
    private var handle: FileHandle?
    private var offset: UInt64 = 0
    private var entries: [Entry] = []
    private var current: Current?
    private var buffer: [UInt8] = []

    /// Starts a zip that `finish()` will put at `destination`.
    public init(destination: URL, zip64At: UInt64 = 0xFFFF_FFFF) throws {
        self.zip64At = zip64At
        self.destination = destination
        partial = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).partial")
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            throw ZipError.writeFailed("the folder can't be written to.")
        }
        handle = try FileHandle(forWritingTo: partial)
    }

    /// Opens an entry; what is `write`n until `endEntry()` is its content.
    public mutating func beginEntry(_ name: String, method: Method = ZipWriter.defaultMethod) throws {
        guard current == nil else { throw ZipError.misuse("the last entry is still open") }
        let nameBytes = Array(name.utf8)
        var header: [UInt8] = []
        header.append(contentsOf: Self.u32(0x0403_4B50))
        header.append(contentsOf: Self.u16(20))
        header.append(contentsOf: Self.u16(0x0808))  // sizes follow the data; the name is UTF-8
        header.append(contentsOf: Self.u16(method.rawValue))
        header.append(contentsOf: Self.u16(0))  // time: midnight
        header.append(contentsOf: Self.u16(0x0021))  // date: 1980-01-01
        header.append(contentsOf: Self.u32(0) + Self.u32(0) + Self.u32(0))
        header.append(contentsOf: Self.u16(UInt16(nameBytes.count)))
        header.append(contentsOf: Self.u16(0))
        header.append(contentsOf: nameBytes)
        current = Current(name: name, method: method, offset: offset)
        #if canImport(Compression)
        if method == .deflated { current?.deflater = try RawDeflater() }
        #endif
        try put(header)
    }

    /// Adds to the open entry.
    public mutating func write(_ bytes: [UInt8]) throws {
        guard var entry = current else { throw ZipError.misuse("no entry is open") }
        entry.crc = CRC32.update(entry.crc, bytes)
        entry.size += UInt64(bytes.count)
        current = entry
        switch entry.method {
        case .stored:
            current?.compressedSize += UInt64(bytes.count)
            try put(bytes)
        case .deflated:
            try deflate(bytes, finish: false)
        }
    }

    /// Ends the open entry, with its descriptor.
    public mutating func endEntry() throws {
        guard let entry = current else { throw ZipError.misuse("no entry is open") }
        if entry.method == .deflated { try deflate([], finish: true) }
        guard let done = current else { return }
        // The descriptor holds 8-byte sizes when either size needs them (Zip64); readers go by the central directory.
        if done.compressedSize >= zip64At || done.size >= zip64At {
            try put(Self.u32(0x0807_4B50) + Self.u32(done.crc) + Self.u64(done.compressedSize) + Self.u64(done.size))
        } else {
            try put(Self.u32(0x0807_4B50) + Self.u32(done.crc) + Self.u32(UInt32(done.compressedSize)) + Self.u32(UInt32(done.size)))
        }
        entries.append(Entry(name: done.name, method: done.method, crc: done.crc, compressedSize: done.compressedSize,
                             size: done.size, offset: done.offset))
        current = nil
    }

    /// Writes the central directory, closes the file and moves it to its destination.
    public mutating func finish() throws {
        guard current == nil else { throw ZipError.misuse("the last entry is still open") }
        let start = offset
        for entry in entries { try put(centralRecord(for: entry)) }
        let size = offset - start
        if entries.count >= 0xFFFF || start >= zip64At || size >= zip64At {
            let recordOffset = offset
            try put(Self.u32(0x0606_4B50) + Self.u64(44) + Self.u16(45) + Self.u16(45) + Self.u32(0) + Self.u32(0)
                + Self.u64(UInt64(entries.count)) + Self.u64(UInt64(entries.count)) + Self.u64(size) + Self.u64(start))
            try put(Self.u32(0x0706_4B50) + Self.u32(0) + Self.u64(recordOffset) + Self.u32(1))
        }
        let count = UInt16(min(entries.count, 0xFFFF))
        try put(Self.u32(0x0605_4B50) + Self.u16(0) + Self.u16(0) + Self.u16(count) + Self.u16(count)
            + Self.u32(size >= zip64At ? 0xFFFF_FFFF : UInt32(size)) + Self.u32(start >= zip64At ? 0xFFFF_FFFF : UInt32(start))
            + Self.u16(0))
        try flush()
        try handle?.close()
        handle = nil
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: partial, to: destination)
    }

    /// An entry's record in the central directory; the sizes and the offset that overflow say so with all ones and are given in full in
    /// the Zip64 extra field (RFC-style order: size, compressed size, offset).
    private func centralRecord(for entry: Entry) -> [UInt8] {
        let nameBytes = Array(entry.name.utf8)
        let wide = [entry.size, entry.compressedSize, entry.offset].map { $0 >= zip64At }
        var extra: [UInt8] = []
        if wide.contains(true) {
            var body: [UInt8] = []
            if wide[0] { body += Self.u64(entry.size) }
            if wide[1] { body += Self.u64(entry.compressedSize) }
            if wide[2] { body += Self.u64(entry.offset) }
            extra = Self.u16(0x0001) + Self.u16(UInt16(body.count)) + body
        }
        let field = { (value: UInt64, isWide: Bool) in Self.u32(isWide ? 0xFFFF_FFFF : UInt32(value)) }
        var record: [UInt8] = []
        record += Self.u32(0x0201_4B50) + Self.u16(extra.isEmpty ? 20 : 45) + Self.u16(extra.isEmpty ? 20 : 45) + Self.u16(0x0808)
        record += Self.u16(entry.method.rawValue) + Self.u16(0) + Self.u16(0x0021) + Self.u32(entry.crc)
        record += field(entry.compressedSize, wide[1]) + field(entry.size, wide[0])
        record += Self.u16(UInt16(nameBytes.count)) + Self.u16(UInt16(extra.count)) + Self.u16(0)
        record += Self.u16(0) + Self.u16(0) + Self.u32(0) + field(entry.offset, wide[2]) + nameBytes + extra
        return record
    }

    /// Throws away what was written.
    public mutating func cancel() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: partial)
    }

    // MARK: Output

    private mutating func put(_ bytes: [UInt8]) throws {
        buffer += bytes
        offset += UInt64(bytes.count)
        if buffer.count >= 1 << 20 { try flush() }
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        do {
            try handle?.write(contentsOf: buffer)
        } catch {
            throw ZipError.writeFailed(error.localizedDescription)
        }
        buffer.removeAll(keepingCapacity: true)
    }

    private mutating func deflate(_ bytes: [UInt8], finish: Bool) throws {
        #if canImport(Compression)
        guard let deflater = current?.deflater else { return }
        var pieces: [[UInt8]] = []
        try bytes.withUnsafeBytes { input in
            try deflater.process(input, finish: finish) { pieces.append(Array($0)) }
        }
        for piece in pieces {
            current?.compressedSize += UInt64(piece.count)
            try put(piece)
        }
        #else
        throw ZipError.compressionFailed
        #endif
    }

    static func u16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }

    static func u32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) } }

    static func u64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) } }
}
