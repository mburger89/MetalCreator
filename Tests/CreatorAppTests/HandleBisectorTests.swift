import CreatorGeometry
import Testing
@testable import CreatorApp

/// A radial handle points along the bisector of the (up to two) faces at its edge, away from the part (spec §6.5).
/// `HandleTests` only reaches the one-face case (FakeKernel's side faces have no normal), so the sum of two normals is
/// pinned here.
struct HandleBisectorTests {
    @Test func aSingleNormalIsTheDirection() {
        #expect(HandleBuilder.bisector(of: [.unitZ]) == .unitZ)
        #expect(HandleBuilder.bisector(of: [Vector3(0, 0, 3)]) == .unitZ, "normalised")
    }

    @Test func twoFacesAtARightAngleGiveTheDiagonalBetweenThem() throws {
        let direction = try #require(HandleBuilder.bisector(of: [.unitX, .unitZ]))
        let root = 0.5.squareRoot()
        #expect((direction - Vector3(root, 0, root)).length < 1e-12)
    }

    @Test func aFlatEdgeBetweenTwoCoplanarFacesPointsAlongTheirNormal() {
        #expect(HandleBuilder.bisector(of: [.unitY, .unitY]) == .unitY)
    }

    /// A thin wall folded flat: the normals cancel, so no direction exists and the handle is not shown (it says nothing
    /// about why, which is the right amount for a case that only a degenerate part reaches).
    @Test func opposingNormalsGiveNoDirection() {
        #expect(HandleBuilder.bisector(of: [.unitX, -.unitX]) == nil)
        #expect(HandleBuilder.bisector(of: []) == nil, "a face without a normal contributes nothing")
    }
}
