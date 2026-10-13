import CryptoKit
import Foundation

/// The SHA-256 of an image file's bytes, as 64 lowercase hexadecimal digits: the key of the document's `images` table
/// (fields spec §5), so two nodes that use one picture store it once. It is a content address, never a secret.
public struct ImageHash: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    /// The 64 digits.
    public let hex: String

    /// The hash of `data`.
    public init(of data: Data) {
        hex = SHA256.hash(data: data).map { byte in
            let digits = String(byte, radix: 16)
            return byte < 16 ? "0" + digits : digits
        }.joined()
    }

    /// The hash written as `hex`, or `nil` unless it is exactly 64 lowercase hexadecimal digits (anything else in a file
    /// is damage, not a hash).
    public init?(hex: String) {
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }) else { return nil }
        self.hex = hex
    }

    /// The first eight digits, enough to tell two embedded images apart in the inspector.
    public var short: String { String(hex.prefix(8)) }

    public var description: String { hex }

    public static func < (lhs: ImageHash, rhs: ImageHash) -> Bool { lhs.hex < rhs.hex }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let hash = ImageHash(hex: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an image hash."))
        }
        self = hash
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
