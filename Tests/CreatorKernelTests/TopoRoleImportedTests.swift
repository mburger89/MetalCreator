import Foundation
import Testing
@testable import CreatorKernel

struct TopoRoleImportedTests {
    @Test func theImportedRoleRoundTripsAsJSON() throws {
        let role = TopoRole.imported(face: 42)
        let data = try JSONEncoder().encode(role)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["role"] as? String == "imported" && object["face"] as? Int == 42 && object.count == 2)
        #expect(try JSONDecoder().decode(TopoRole.self, from: data) == role)
        let negative = TopoRole.imported(face: -7)
        #expect(try JSONDecoder().decode(TopoRole.self, from: JSONEncoder().encode(negative)) == negative)
    }

    @Test func itsSortKeyAndStability() {
        #expect(TopoRole.imported(face: 3).sortKey == "imported(3)")
        #expect(!TopoRole.imported(face: 3).isUnstable)
        #expect(TopoRole.unnamed(face: 3).isUnstable)
        #expect(TopoRole.imported(face: 1) != TopoRole.imported(face: 2))
    }
}
