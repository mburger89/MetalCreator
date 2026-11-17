import Foundation

/// Why a gzip file was not read.
public enum GzipError: Error, Equatable {
    /// The bytes do not start with a gzip header (`1F 8B 08`).
    case notGzip
    /// The header, the deflate stream or the trailer is damaged, cut short, or followed by a second member.
    case malformed
    /// The file says it holds more than `limit` bytes.
    case tooLarge(limit: Int)
    /// The content's CRC-32 is not the trailer's.
    case checksumMismatch
    /// `isCancelled` answered true.
    case cancelled
    /// The declared size could not be allocated.
    case allocationFailed
}

/// A gzip file (RFC 1952) of one member, read in plain Swift on every platform. The input is untrusted: the size the trailer declares is
/// checked against the caller's limit before anything is allocated, and the content is checked against the trailer's CRC-32 and size.
public enum Gzip {
    /// Whether `data` starts like a gzip file (`1F 8B 08`).
    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 3 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B && data[data.startIndex + 2] == 0x08
    }

    /// The content of the one member `data` holds. FEXTRA, FNAME, FCOMMENT and FHCRC are honoured (the header CRC is verified); a second
    /// member is `malformed`. The size is the trailer's ISIZE (modulo 2^32, so a file of 4 GB or more is refused by any limit under it).
    public static func decompress(_ data: Data, limit: Int, isCancelled: () -> Bool) throws(GzipError) -> Data {
        guard isGzip(data) else { throw .notGzip }
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { throw .malformed }
        let position = try headerEnd(of: bytes)
        let trailer = bytes.count - 8
        guard position <= trailer else { throw .malformed }
        let crc = word(bytes, trailer)
        let size = Int(word(bytes, trailer + 4))
        guard size <= limit else { throw .tooLarge(limit: limit) }
        let content: Data
        let consumed: Int
        do {
            (content, consumed) = try bytes.withUnsafeBytes { raw in
                let stream = UnsafeRawBufferPointer(rebasing: raw[position..<trailer])
                return try Inflate.inflateMeasuring(stream, size: size, isCancelled: isCancelled)
            }
        } catch InflateError.cancelled {
            throw .cancelled
        } catch InflateError.allocationFailed {
            throw .allocationFailed
        } catch {
            throw .malformed
        }
        guard position + consumed == trailer else { throw .malformed }
        guard CRC32.checksum(content) == crc else { throw .checksumMismatch }
        return content
    }

    /// Where the deflate stream starts: past the fixed header and whichever of the extra field, name, comment and header CRC it has.
    private static func headerEnd(of bytes: [UInt8]) throws(GzipError) -> Int {
        let flags = bytes[3]
        guard flags & 0xE0 == 0 else { throw .malformed }
        var position = 10
        if flags & 4 != 0 {
            guard position + 2 <= bytes.count else { throw .malformed }
            position += 2 + Int(bytes[position]) + (Int(bytes[position + 1]) << 8)
        }
        for flag: UInt8 in [8, 16] where flags & flag != 0 {
            guard let zero = bytes[min(position, bytes.count)...].firstIndex(of: 0) else { throw .malformed }
            position = zero + 1
        }
        if flags & 2 != 0 {
            guard position + 2 <= bytes.count else { throw .malformed }
            let stored = UInt32(bytes[position]) | UInt32(bytes[position + 1]) << 8
            guard CRC32.checksum(bytes[0..<position]) & 0xFFFF == stored else { throw .malformed }
            position += 2
        }
        return position
    }

    private static func word(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
