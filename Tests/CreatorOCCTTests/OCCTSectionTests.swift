#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// `Kernel.section` on OpenCascade (section analysis part B): a solid cut by a plane through `BRepAlgoAPI_Common` with a planar face.
struct OCCTSectionTests {
    func area(_ region: SectionRegion) -> Double {
        var total = 0.0
        for t in stride(from: 0, to: region.triangles.count, by: 3) {
            let a = region.positions[Int(region.triangles[t])]
            let b = region.positions[Int(region.triangles[t + 1])]
            let c = region.positions[Int(region.triangles[t + 2])]
            total += (b - a).cross(c - a).length / 2
        }
        return total
    }

    func cylinder(_ kernel: OCCTKernel, radius: Double = 5, height: Double = 20) async throws -> Solid {
        try await kernel.extrude(.circle(radius: radius, center: .zero, plane: .xy), distance: height, mode: .oneSided, tag: newTag())
    }

    func plane(z: Double) -> Plane { Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitX) }

    @Test func aBoxCutAcrossGivesOneRectangle() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 10, 6)
        let section = try await kernel.section(solid, by: plane(z: 3), tolerance: 0.01)
        let region = try #require(section.regions.first)
        #expect(section.regions.count == 1 && section.openOutlines.isEmpty)
        #expect(abs(area(region) - 200) < 1e-6)
        #expect(region.boundary.count == 4)
        for piece in region.boundary {
            guard case .line = piece.curve else { Issue.record("not a line: \(String(describing: piece.curve))"); continue }
            let face = try #require(piece.sourceFace.flatMap { solid.topology.face($0) })
            let normal = try #require(face.normal)
            #expect(abs(normal.dot(.unitZ)) < 1e-9, "a side face")
        }
    }

    @Test func aPlateWithAHoleGivesARegionWithAHole() async throws {
        let kernel = OCCTKernel()
        let plate = try await box(kernel, 40, 40, 6)
        let drill = try await cylinder(kernel, radius: 5, height: 10)
        let holed = try await kernel.boolean(.subtract, plate, [drill], tag: newTag())
        let section = try await kernel.section(holed, by: plane(z: 3), tolerance: 0.01)
        let region = try #require(section.regions.first)
        #expect(section.regions.count == 1)
        #expect(abs(area(region) - (1600 - 25 * Double.pi)) < 0.005 * (1600 - 25 * Double.pi))
        let circles = region.boundary.compactMap { piece -> Double? in
            if case .circle(_, _, let radius, _, _)? = piece.curve { radius } else { nil }
        }
        #expect(circles.count == 1 && abs(circles[0] - 5) < 1e-9)
    }

    @Test func aCylinderCutAlongItsAxisGivesARectangle() async throws {
        let kernel = OCCTKernel()
        let solid = try await cylinder(kernel)
        let cut = Plane(origin: .zero, normal: .unitY, xAxis: .unitX)
        let section = try await kernel.section(solid, by: cut, tolerance: 0.01)
        let region = try #require(section.regions.first)
        #expect(section.regions.count == 1)
        #expect(abs(area(region) - 200) < 1e-6)
    }

    @Test func aCylinderCutAcrossGivesADisc() async throws {
        let kernel = OCCTKernel()
        let solid = try await cylinder(kernel)
        let section = try await kernel.section(solid, by: plane(z: 10), tolerance: 0.001)
        let region = try #require(section.regions.first)
        #expect(section.regions.count == 1 && region.boundary.count == 1)
        let piece = try #require(region.boundary.first)
        guard case .circle(_, _, let radius, _, let sweep)? = piece.curve else {
            Issue.record("not a circle"); return
        }
        #expect(abs(radius - 5) < 1e-9 && abs(abs(sweep) - 2 * Double.pi) < 1e-9)
        #expect(abs(area(region) - 25 * Double.pi) < 0.005 * 25 * Double.pi)
        #expect(piece.sourceFace != nil && piece.polyline.count > 8)
    }

    @Test func aPlaneBesideTheSolidGivesNothing() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 10, 6)
        let section = try await kernel.section(solid, by: plane(z: 30), tolerance: 0.01)
        #expect(section.isEmpty)
    }

    @Test func aPlaneJustInsideATopFaceGivesTheWholeFace() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 10, 6)
        let section = try await kernel.section(solid, by: plane(z: 6 - 1e-4), tolerance: 0.01)
        let region = try #require(section.regions.first)
        #expect(section.regions.count == 1)
        #expect(abs(area(region) - 200) < 1e-3)
    }

    @Test func aBadToleranceIsRefused() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 10, 6)
        for bad in [0.0, -1, .nan, .infinity] {
            await #expect(throws: KernelError.self) { _ = try await kernel.section(solid, by: plane(z: 3), tolerance: bad) }
        }
    }
}
#endif
