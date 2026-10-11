import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// `NodeID.instanceScoped`: the identity a placed copy's tags name (patterns spec §6), made as `NodeID.scoped` makes a
/// group instance's, and told apart from it by its UUID version.
struct InstanceScopedTests {
    let a = NodeID(), b = NodeID()

    @Test func itIsDeterministicAndOrdered() {
        #expect(NodeID.instanceScoped([a, b]) == NodeID.instanceScoped([a, b]))
        #expect(NodeID.instanceScoped([a, b]) != NodeID.instanceScoped([b, a]))
        #expect(NodeID.instanceScoped([a]) != NodeID.instanceScoped([a, b]))
    }

    @Test func itIsAVersionEightIDThatScopedNeverMakes() {
        #expect(NodeID.instanceScoped([a, b]).isInstanceQualified)
        #expect(!NodeID.scoped([a, b]).isInstanceQualified)
        #expect(NodeID.instanceScoped([a, b]) != NodeID.scoped([a, b]))
    }

    @Test func scopedIDsAreUnchanged() {
        // SHA-1 of the namespace and the ID's 16 bytes, computed independently of the code under test (Python's
        // hashlib) from master's algorithm: a stored pick inside a group names faces by these, so the refactor that
        // shares the hashing with `instanceScoped` must not move them.
        let fixed = NodeID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID())
        #expect(NodeID.scoped([fixed]).rawValue.uuidString == "B2C40983-15F9-5EEB-9B29-D9D0F3005D98")
    }
}
