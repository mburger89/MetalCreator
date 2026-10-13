import Foundation

/// A PNG file's chunk chain, walked without decoding anything. ImageIO reads a PNG cut short in the middle of its data as an
/// all-black picture and says nothing, so a file is only trusted when its chunks lead to IEND.
enum PNGStructure {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let end: [UInt8] = Array("IEND".utf8)

    /// Whether `data` is a PNG signature followed by whole chunks up to and including IEND. Bytes after IEND are ignored.
    static func isWhole(_ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            guard bytes.count >= signature.count + 12, bytes.prefix(signature.count).elementsEqual(signature) else { return false }
            var offset = signature.count
            while offset + 12 <= bytes.count {
                let length = (0..<4).reduce(0) { $0 << 8 | Int(bytes[offset + $1]) }
                let next = offset + 12 + length  // length, length of type and CRC; a 32-bit length cannot overflow an Int
                guard next <= bytes.count else { return false }
                if bytes[(offset + 4)..<(offset + 8)].elementsEqual(end) { return true }
                offset = next
            }
            return false
        }
    }
}
