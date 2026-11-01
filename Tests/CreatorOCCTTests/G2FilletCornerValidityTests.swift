import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 2e of G-b: a corner is a G2 patch, else a G1 refill, else refused; a solid that fails BRepCheck is never returned.
struct G2FilletCornerValidityTests {
    let base = G2FilletTests()
    let coverage = G2FilletCoverageTests()

    static let cornerMessage = "The fillet's corners can't be made smooth at this radius."

    func polygonPrism(_ points: [Vector2], height: Double = 10) throws -> OCCTShape {
        let segments = points.indices.map { Segment2D.line(points[$0], points[($0 + 1) % points.count]) }
        return try OCCTKernel.serialized { try OCCTShape.extrude(Profile2D(plane: .xy, segments: segments), distance: height).0 }
    }

    /// The three edges at the top vertex `vertex` of a prism over `points`: two top edges and the vertical one.
    func topCorner(_ points: [Vector2], at index: Int, height: Double) -> [[Double]] {
        let n = points.count
        let v = points[index], next = points[(index + 1) % n], previous = points[(index + n - 1) % n]
        return [
            [(v.x + next.x) / 2, (v.y + next.y) / 2, height], [(v.x + previous.x) / 2, (v.y + previous.y) / 2, height],
            [v.x, v.y, height / 2],
        ]
    }

    func hexagon() -> [Vector2] {
        (0..<6).map { Vector2(10 * cos(Double($0) * .pi / 3), 10 * sin(Double($0) * .pi / 3)) }
    }

    func triangle() -> [Vector2] { [Vector2(0, 0), Vector2(20, 0), Vector2(10, 20 * 0.8660254037844386)] }

    enum Outcome { case built(G2FilletTests.Built), refused(String) }

    func attempt(_ shape: OCCTShape, midpoints: [[Double]], radius: Double) throws -> Outcome {
        do {
            return .built(try base.build(shape, midpoints: midpoints, radius: radius))
        } catch let error as OCCTError {
            return .refused(error.message)
        }
    }

    /// Builds valid with the corner counted as a G1 refill, or is refused in the corner's words: never an invalid solid.
    func expectValidOrRefused(_ shape: OCCTShape, midpoints: [[Double]], radius: Double, name: String,
                              sourceLocation: SourceLocation = #_sourceLocation) throws {
        switch try attempt(shape, midpoints: midpoints, radius: radius) {
        case .built(let built):
            print("G2VALID \(name): built, g2 \(built.report.g2_corners) g1 \(built.report.g1_corners)")
            #expect(OCCTKernel.serialized { built.shape.validity } == .valid, sourceLocation: sourceLocation)
            #expect(built.report.corners == 1, sourceLocation: sourceLocation)
            #expect(built.report.g1_corners + built.report.g2_corners == 1, sourceLocation: sourceLocation)
            for seam in base.cornerGaps(built.report) {
                #expect(seam.position <= 1e-4 && seam.angle_degrees <= 0.01, sourceLocation: sourceLocation)
            }
        case .refused(let message):
            print("G2VALID \(name): refused \(message)")
            #expect(message == Self.cornerMessage, sourceLocation: sourceLocation)
        }
    }

    @Test func aHexagonalPrismCornerIsValidOrRefused() throws {
        let points = hexagon()
        try expectValidOrRefused(try polygonPrism(points), midpoints: topCorner(points, at: 0, height: 10), radius: 1, name: "hexagon")
    }

    @Test func aTriangularPrismCornerIsValidOrRefused() throws {
        let points = triangle()
        try expectValidOrRefused(try polygonPrism(points), midpoints: topCorner(points, at: 0, height: 10), radius: 1, name: "triangle")
    }

    @Test func aDraftedPrismCornerIsValidOrRefused() throws {
        try expectValidOrRefused(try coverage.draftedPrism(), midpoints: [[0, -8, 10], [-8, 0, 10], [-9, -9, 5]], radius: 1,
                                 name: "drafted")
    }

    /// A drafted wall's edge meets the base 11 degrees off square: its end is built past the base and trimmed by it,
    /// where a square end would leave the plane by 0.1 mm and the solid would fail BRepCheck.
    @Test func aDraftedEdgeMeetingTheBaseIsValid() throws {
        let built = try base.build(try coverage.draftedPrism(), midpoints: [[-9, -9, 5]], radius: 1)
        #expect(OCCTKernel.serialized { built.shape.validity } == .valid)
    }
}
