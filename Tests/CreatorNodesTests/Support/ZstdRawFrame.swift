import CreatorPCB
import Foundation

/// A minimal zstd encoder for tests: one single-segment frame of raw blocks (at most 128 KB each), with the content size and,
/// when asked, the XXH64 content checksum. It compresses nothing; it makes a frame the node's decoder must unpack.
enum ZstdRawFrame {
    static func encode(_ content: Data, checksum: Bool = true, corruptingChecksum: Bool = false,
                       dictionary: UInt8? = nil, claiming size: UInt32? = nil) -> Data {
        var frame = Data([0x28, 0xB5, 0x2F, 0xFD])
        // Descriptor: a 4-byte content size (flag 2), single segment, no dictionary, the checksum bit.
        frame.append(0x80 | 0x20 | (checksum ? 0x04 : 0) | (dictionary == nil ? 0 : 1))
        if let dictionary { frame.append(dictionary) }
        withUnsafeBytes(of: (size ?? UInt32(content.count)).littleEndian) { frame.append(contentsOf: $0) }
        let blockSize = 128 * 1024
        var start = 0
        repeat {
            let end = min(start + blockSize, content.count)
            let isLast = end == content.count
            let header = UInt32(end - start) << 3 | (isLast ? 1 : 0)
            frame.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16 & 0xFF)])
            frame.append(content[content.startIndex + start..<content.startIndex + end])
            start = end
        } while start < content.count
        if checksum {
            let hash = content.withUnsafeBytes { XXH64.hash($0) }
            var low = UInt32(truncatingIfNeeded: hash)
            if corruptingChecksum { low ^= 1 }
            withUnsafeBytes(of: low.littleEndian) { frame.append(contentsOf: $0) }
        }
        return frame
    }

    static func base64(_ content: Data, checksum: Bool = true, corruptingChecksum: Bool = false, wrapped: Bool = false,
                       dictionary: UInt8? = nil, claiming size: UInt32? = nil) -> String {
        let text = encode(content, checksum: checksum, corruptingChecksum: corruptingChecksum, dictionary: dictionary, claiming: size)
        return wrapped ? text.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]) : text.base64EncodedString()
    }
}
