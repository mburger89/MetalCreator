#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// `Kernel.shortestDistance` on OpenCascade (Measure part A).
struct ShortestDistanceTests {
    func face(_ solid: Solid, normal: Vector3) throws -> FaceID {
        try #require(solid.topology.faces.first { $0.kind == .plane && ($0.normal?.dot(normal) ?? 0) > 1 - 1e-9 }).id
    }

    /// The edge whose midpoint is nearest `point`.
    func edge(_ solid: Solid, near point: Vector3) throws -> EdgeID {
        try #require(solid.topology.edges.min { ($0.midpoint - point).length < ($1.midpoint - point).length }).id
    }

    func expectWitnesses(_ found: ShapeDistance, _ distance: Double) {
        #expect(abs(found.distance - distance) < 1e-9)
        #expect(abs((found.from - found.to).length - found.distance) < 1e-9)
    }

    @Test func oppositeFacesAreTheBoxApart() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 40, 30, 10)
        let left = try face(solid, normal: -.unitX), right = try face(solid, normal: .unitX)
        let found = try await kernel.shortestDistance(between: .face(solid, left), and: .face(solid, right))
        expectWitnesses(found, 40)
        #expect(abs(found.from.x + 20) < 1e-9 && abs(found.to.x - 20) < 1e-9)
    }

    @Test func anEdgeToAFace() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 40, 30, 10)
        let top = try edge(solid, near: Vector3(0, 15, 10))
        let found = try await kernel.shortestDistance(between: .edge(solid, top), and: .face(solid, try face(solid, normal: -.unitZ)))
        expectWitnesses(found, 10)
    }

    @Test func aCornerToAFace() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 40, 30, 10)
        let found = try await kernel.shortestDistance(between: .point(Vector3(-20, -15, 0)),
                                                      and: .face(solid, try face(solid, normal: .unitX)))
        expectWitnesses(found, 40)
    }

    @Test func adjacentFacesAreZeroApart() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 40, 30, 10)
        let found = try await kernel.shortestDistance(between: .face(solid, try face(solid, normal: .unitX)),
                                                      and: .face(solid, try face(solid, normal: .unitZ)))
        #expect(abs(found.distance) < 1e-9)
    }

    @Test func twoSolidsAreMeasuredAgainstEachOther() async throws {
        let kernel = OCCTKernel()
        let one = try await box(kernel, 10, 10, 10)
        let other = try await kernel.transform(try await box(kernel, 10, 10, 10), by: Transform(translation: Vector3(15, 0, 0)),
                                               tag: newTag())
        let found = try await kernel.shortestDistance(between: .face(one, try face(one, normal: .unitX)),
                                                      and: .face(other, try face(other, normal: -.unitX)))
        expectWitnesses(found, 5)
    }

    @Test func aHoleWallToAnOuterFace() async throws {
        let kernel = OCCTKernel()
        let plate = try await box(kernel, 40, 30, 10)
        let drill = try await kernel.extrude(.circle(radius: 4, center: .zero, plane: .xy), distance: 10, mode: .oneSided, tag: newTag())
        let holed = try await kernel.boolean(.subtract, plate, [drill], tag: newTag())
        let wall = try #require(holed.topology.faces.first { $0.kind == .cylinder }).id
        let found = try await kernel.shortestDistance(between: .face(holed, wall), and: .face(holed, try face(holed, normal: -.unitX)))
        expectWitnesses(found, 16)
    }

    @Test func aMissingIDIsRefused() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 40, 30, 10)
        await #expect(throws: KernelError.self) {
            try await kernel.shortestDistance(between: .face(solid, FaceID(99)), and: .point(.zero))
        }
    }
}
#endif
