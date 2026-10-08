import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct ProfileEstimateTests {
    @Test func aProfileEstimateCountsHoleSegments() {
        let outline = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments
        let hole = Profile2D.circle(radius: 1, center: .zero, plane: .xy).segments
        #expect(Scalar.profile(Profile2D(plane: .xy, segments: outline)).estimatedBytes == 64 + 4 * 48)
        #expect(Scalar.profile(Profile2D(plane: .xy, outer: outline, holes: [hole])).estimatedBytes == 64 + 5 * 48)
    }
}
