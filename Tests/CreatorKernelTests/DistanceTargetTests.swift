import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// `DistanceTarget.identity` is what the field cache keys on (fields spec §2.2): the same solid and the same selection,
/// in any order, are one target; another solid or another selection is another.
struct DistanceTargetTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func cube() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
    }

    @Test func theSameSolidIsTheSameTarget() async throws {
        let solid = try await cube()
        #expect(DistanceTarget.solid(solid).identity == DistanceTarget.solid(solid).identity)
        #expect(DistanceTarget.solid(solid).identity != DistanceTarget.solid(try await cube()).identity, "another solid object")
    }

    @Test func aSelectionIsASetNotAList() async throws {
        let solid = try await cube()
        let a = DistanceTarget.edges(EdgeSet(solid: solid, edges: [EdgeID(2), EdgeID(0), EdgeID(2)])).identity
        let b = DistanceTarget.edges(EdgeSet(solid: solid, edges: [EdgeID(0), EdgeID(2)])).identity
        #expect(a == b)
        #expect(a != DistanceTarget.edges(EdgeSet(solid: solid, edges: [EdgeID(0)])).identity)
    }

    @Test func edgesFacesAndTheWholeSolidAreDifferentTargets() async throws {
        let solid = try await cube()
        let identities = [
            DistanceTarget.solid(solid).identity,
            DistanceTarget.edges(EdgeSet(solid: solid, edges: [EdgeID(0)])).identity,
            DistanceTarget.faces(FaceSet(solid: solid, faces: [FaceID(0)])).identity,
        ]
        #expect(Set(identities).count == 3)
    }

    @Test func theSolidOfATargetIsTheSolidItNames() async throws {
        let solid = try await cube()
        #expect(DistanceTarget.solid(solid).solid === solid)
        #expect(DistanceTarget.edges(EdgeSet(solid: solid, edges: [EdgeID(0)])).solid === solid)
        #expect(DistanceTarget.faces(FaceSet(solid: solid, faces: [FaceID(0)])).solid === solid)
    }
}
