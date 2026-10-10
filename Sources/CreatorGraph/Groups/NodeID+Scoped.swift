import CreatorKernel
import CryptoKit
import Foundation

extension NodeID {
    /// The identity a node inside a group evaluates under (groups spec §5): a name-based UUID (version 5, SHA-1)
    /// of `path`, the group nodes from the top level down followed by the inner node's own ID. Deterministic, so a
    /// tag made inside a group, and a pick that names it, stay the same as long as those IDs do: across evaluations,
    /// saves and edits to the definition. Two instances of a definition have different paths, so their tags differ.
    public static func scoped(_ path: [NodeID]) -> NodeID {
        var bytes = namespace
        for id in path {
            withUnsafeBytes(of: id.rawValue.uuid) { bytes += $0 }
        }
        var digest = Array(Insecure.SHA1.hash(data: bytes).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50  // Version 5: name-based, SHA-1.
        digest[8] = (digest[8] & 0x3F) | 0x80  // The RFC 4122 variant.
        return NodeID(rawValue: digest.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) })
    }

    /// The namespace of scoped IDs: MetalCreator's own, so they never equal a UUID named under another namespace.
    private static let namespace: [UInt8] = [
        0x6D, 0x63, 0x2E, 0x67, 0x72, 0x6F, 0x75, 0x70, 0x2E, 0x73, 0x63, 0x6F, 0x70, 0x65, 0x2E, 0x31,
    ]
}
