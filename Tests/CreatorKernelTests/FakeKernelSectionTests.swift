import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Section analysis part B: `Kernel.section` on the Fake (a solid is its bounding box) and the default.
struct FakeKernelSectionTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    /// A 10 x 20 profile extruded 30 mm up from the origin plane.
    func box(_ kernel: FakeKernel) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 30, mode: .oneSided, tag: tag)
    }

    func area(of region: SectionRegion) -> Double {
        stride(from: 0, to: region.triangles.count, by: 3).reduce(0) { sum, index in
            let corners = (0..<3).map { region.positions[Int(region.triangles[index + $0])] }
            return sum + (corners[1] - corners[0]).cross(corners[2] - corners[0]).length / 2
        }
    }

    @Test func aBoxCutAcrossGivesOneRectangle() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let found = try await kernel.section(part, by: Plane(origin: Vector3(0, 0, 5), normal: .unitZ, xAxis: .unitX), tolerance: 0.01)
        #expect(found.regions.count == 1)
        let region = try #require(found.regions.first)
        #expect(abs(area(of: region) - 200) < 1e-9)
        #expect(region.boundary.count == 4)
        for piece in region.boundary {
            guard case .line = piece.curve else {
                Issue.record("a piece is not a line")
                continue
            }
            #expect(piece.polyline.count == 2)
            #expect(piece.polyline.allSatisfy { abs($0.z - 5) < 1e-12 })
        }
        #expect(await kernel.operationLog.contains("section"))
    }

    @Test func aPlaneBesideTheBoxGivesNothing() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let found = try await kernel.section(part, by: Plane(origin: Vector3(0, 0, 40), normal: .unitZ, xAxis: .unitX), tolerance: 0.01)
        #expect(found.isEmpty)
    }

    @Test func aTiltedPlaneIsRefused() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let tilted = Plane(origin: Vector3(0, 0, 5), normal: Vector3(1, 0, 1).normalized ?? .unitZ,
                           xAxis: Vector3(1, 0, -1).normalized ?? .unitX)
        await #expect(throws: KernelError.unsupported("section on a tilted plane")) {
            try await kernel.section(part, by: tilted, tolerance: 0.01)
        }
    }

    @Test func aBadToleranceIsRefused() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        for bad in [0, Double.nan] {
            await #expect(throws: KernelError.self) { try await kernel.section(part, by: .xy.offset(by: 5), tolerance: bad) }
        }
    }

    @Test func eachPieceNamesTheFaceOnItsSide() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let found = try await kernel.section(part, by: .xy.offset(by: 5), tolerance: 0.01)
        let region = try #require(found.regions.first)
        for piece in region.boundary {
            guard let id = piece.sourceFace, let face = part.topology.face(id), let normal = face.normal else { continue }
            let middle = (piece.polyline[0] + piece.polyline[1]) * 0.5
            #expect(abs(normal.z) < 1e-9)
            #expect(normal.dot(middle - part.bounds.center) > 0)
        }
    }

    @Test func theUnavailableKernelRefusesTheSection() async throws {
        let part = try await box(FakeKernel())
        await #expect(throws: KernelError.unavailable) {
            try await KernelUnavailable().section(part, by: .xy, tolerance: 0.01)
        }
    }
}
