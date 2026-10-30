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
            do {
                _ = try await kernel.section(part, by: .xy.offset(by: 5), tolerance: bad)
                Issue.record("tolerance \(bad) was accepted")
            } catch let error as KernelError {
                guard case .invalidInput = error else {
                    Issue.record("expected invalidInput, got \(error)")
                    continue
                }
            }
        }
    }

    /// A 10 x 20 x 30 box whose six faces are written by hand with outward normals (a Fake prism's side faces have none, so only the
    /// caps would match).
    func normalledBox() -> Solid {
        let normals: [Vector3] = [.unitX, -.unitX, .unitY, -.unitY, .unitZ, -.unitZ]
        let faces = normals.enumerated().map { index, normal in
            FaceInfo(id: FaceID(index), kind: .plane, normal: normal, area: 1, centroid: .zero, tags: [])
        }
        return Solid(topology: Topology(faces: faces, edges: []), bounds: BoundingBox(min: .zero, max: Vector3(10, 20, 30)),
                     storage: FakeStorage())
    }

    /// Every piece must name the face on its side: that face's normal is the side's outward direction, and the four faces differ.
    func expectSourceFaces(of region: SectionRegion, in part: Solid) throws {
        var ids: Set<FaceID> = []
        for piece in region.boundary {
            let id = try #require(piece.sourceFace)
            let face = try #require(part.topology.face(id))
            let normal = try #require(face.normal)
            let middle = (try #require(piece.polyline.first) + (try #require(piece.polyline.last))) * 0.5
            let offset = middle - part.bounds.center
            var components = [offset.x, offset.y, offset.z]
            // The plane's own axis is the one every position shares; the side lies along another.
            let flat = components.indices.first { index in
                let values = region.positions.map { [$0.x, $0.y, $0.z][index] }
                return values.allSatisfy { abs($0 - values[0]) < 1e-12 }
            }
            if let flat { components[flat] = 0 }
            let axis = try #require(components.indices.max { abs(components[$0]) < abs(components[$1]) })
            var expected = [0.0, 0.0, 0.0]
            expected[axis] = components[axis] > 0 ? 1 : -1
            #expect((normal - Vector3(expected[0], expected[1], expected[2])).length < 1e-9)
            ids.insert(id)
        }
        #expect(ids.count == 4)
    }

    @Test func eachPieceNamesTheFaceOnItsSide() async throws {
        let kernel = FakeKernel()
        let part = normalledBox()
        let found = try await kernel.section(part, by: .xy.offset(by: 5), tolerance: 0.01)
        try expectSourceFaces(of: try #require(found.regions.first), in: part)
    }

    @Test func aNegativeXNormalCutsTheYZRectangle() async throws {
        let kernel = FakeKernel()
        let part = normalledBox()
        let plane = Plane(origin: part.bounds.center, normal: -.unitX, xAxis: .unitY)
        let found = try await kernel.section(part, by: plane, tolerance: 0.01)
        let region = try #require(found.regions.first)
        #expect(found.regions.count == 1)
        #expect(abs(area(of: region) - 600) < 1e-9)
        #expect(region.positions.allSatisfy { abs($0.x - part.bounds.center.x) < 1e-12 })
        try expectSourceFaces(of: region, in: part)
    }

    @Test func theUnavailableKernelRefusesTheSection() async throws {
        let part = try await box(FakeKernel())
        await #expect(throws: KernelError.unavailable) {
            try await KernelUnavailable().section(part, by: .xy, tolerance: 0.01)
        }
    }
}
