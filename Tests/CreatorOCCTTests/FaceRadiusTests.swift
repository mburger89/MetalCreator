import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct FaceRadiusTests {
    @Test func aHolesCylinderFaceCarriesItsRadiusAndAxisPoint() async throws {
        let plate = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 40, height: 30, plane: .xy).segments,
                              holes: [Profile2D.circle(radius: 4, center: Vector2(5, -3), plane: .xy).segments])
        let solid = try await OCCTKernel().extrude(plate, distance: 10, mode: .oneSided, tag: newTag())
        let cylinders = solid.topology.faces.filter { $0.kind == .cylinder }
        #expect(cylinders.count == 1)
        let hole = try #require(cylinders.first)
        #expect(abs(try #require(hole.radius) - 4) < 1e-9)
        let axisPoint = try #require(hole.axisPoint)
        // The axis runs along Z through (5, -3).
        #expect(abs(axisPoint.x - 5) < 1e-9 && abs(axisPoint.y + 3) < 1e-9)
        let normal = try #require(hole.normal)
        #expect(abs(abs(normal.z) - 1) < 1e-9)
        for face in solid.topology.faces where face.kind == .plane {
            #expect(face.radius == nil && face.axisPoint == nil)
        }
    }
}
