import CreatorKernel
import CryptoKit
import Foundation

extension NodeID {
    /// The identity a node inside a group evaluates under (groups spec §5): a name-based UUID (version 5, SHA-1)
    /// of `path`, the group nodes from the top level down followed by the inner node's own ID. Deterministic, so a
    /// tag made inside a group, and a pick that names it, stay the same as long as those IDs do: across evaluations,
    /// saves and edits to the definition. Two instances of a definition have different paths, so their tags differ.
    public static func scoped(_ path: [NodeID]) -> NodeID {
        named(path, namespace: namespace, version: 0x50)  // Version 5: name-based, SHA-1.
    }

    /// The identity a placed copy's tags name (patterns spec §6), made as `scoped` makes a group instance's: a
    /// name-based UUID of `path`, the node that placed the copy and then the tool's own node, in a namespace of its
    /// own and with the custom version 8, so `NodeID.isInstanceQualified` tells it from every other identity. The
    /// copy's index is the tag's item, not part of the path, so every copy of a tool shares this one identity.
    public static func instanceScoped(_ path: [NodeID]) -> NodeID {
        named(path, namespace: instanceNamespace, version: 0x80)
    }

    private static func named(_ path: [NodeID], namespace: [UInt8], version: UInt8) -> NodeID {
        var bytes = namespace
        for id in path {
            withUnsafeBytes(of: id.rawValue.uuid) { bytes += $0 }
        }
        var digest = Array(Insecure.SHA1.hash(data: bytes).prefix(16))
        digest[6] = (digest[6] & 0x0F) | version
        digest[8] = (digest[8] & 0x3F) | 0x80  // The RFC 4122 variant.
        return NodeID(rawValue: digest.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) })
    }

    /// The namespace of scoped IDs: MetalCreator's own, so they never equal a UUID named under another namespace.
    private static let namespace: [UInt8] = [
        0x6D, 0x63, 0x2E, 0x67, 0x72, 0x6F, 0x75, 0x70, 0x2E, 0x73, 0x63, 0x6F, 0x70, 0x65, 0x2E, 0x31,
    ]

    /// The namespace of instance-qualified IDs: scoped IDs' with the last byte changed, so the two never collide.
    private static let instanceNamespace: [UInt8] = [
        0x6D, 0x63, 0x2E, 0x67, 0x72, 0x6F, 0x75, 0x70, 0x2E, 0x73, 0x63, 0x6F, 0x70, 0x65, 0x2E, 0x32,
    ]
}
