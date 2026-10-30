import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorImplicit

/// The plane section of a triangle mesh (section analysis part B): regions with holes, islands, open outlines.
struct MeshSlicerTests {
    /// A closed box from `low` to `high`, twelve outward-facing triangles.
    func box(_ low: Vector3, _ high: Vector3, inward: Bool = false) -> (positions: [Vector3], indices: [UInt32]) {
        let positions = [
            Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z), Vector3(high.x, high.y, low.z), Vector3(low.x, high.y, low.z),
            Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z),
        ]
        let outward: [UInt32] = [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7]
        guard inward else { return (positions, outward) }
        return (positions, stride(from: 0, to: outward.count, by: 3).flatMap { [outward[$0], outward[$0 + 2], outward[$0 + 1]] })
    }

    /// Several meshes in one, indices shifted.
    func merged(_ meshes: [(positions: [Vector3], indices: [UInt32])]) -> (positions: [Vector3], indices: [UInt32]) {
        var positions: [Vector3] = []
        var indices: [UInt32] = []
        for mesh in meshes {
            let base = UInt32(positions.count)
            positions += mesh.positions
            indices += mesh.indices.map { $0 + base }
        }
        return (positions, indices)
    }

    /// Every triangle with its own three vertices.
    func split(_ mesh: (positions: [Vector3], indices: [UInt32])) -> (positions: [Vector3], indices: [UInt32]) {
        (mesh.indices.map { mesh.positions[Int($0)] }, (0..<UInt32(mesh.indices.count)).map { $0 })
    }

    func area(_ region: SectionRegion) -> Double {
        stride(from: 0, to: region.triangles.count, by: 3).reduce(0.0) { sum, index in
            let (a, b, c) = (region.positions[Int(region.triangles[index])], region.positions[Int(region.triangles[index + 1])],
                             region.positions[Int(region.triangles[index + 2])])
            return sum + (b - a).cross(c - a).length / 2
        }
    }

    func slice(_ mesh: (positions: [Vector3], indices: [UInt32]), z: Double) -> PlaneSection {
        let plane = Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitX)
        return MeshSlicer.slice(positions: mesh.positions, triangles: mesh.indices, plane: plane)
    }

    @Test func aClosedCubeCutAcrossGivesOneSquare() {
        let section = slice(box(.zero, Vector3(10, 10, 10)), z: 5)
        #expect(section.regions.count == 1)
        #expect(abs(area(section.regions[0]) - 100) < 1e-9)
        #expect(section.regions[0].boundary.count == 1)
        #expect(section.regions[0].boundary[0].polyline.count == 5)
        #expect(section.regions[0].boundary[0].curve == nil && section.regions[0].boundary[0].sourceFace == nil)
        #expect(section.openOutlines.isEmpty)
    }

    @Test func aCubeWithSplitVerticesStillCloses() {
        let section = slice(split(box(.zero, Vector3(10, 10, 10))), z: 5)
        #expect(section.regions.count == 1)
        #expect(abs(area(section.regions[0]) - 100) < 1e-9)
        #expect(section.regions[0].boundary[0].polyline.count == 5)
        #expect(section.openOutlines.isEmpty)
    }

    @Test func aTubeGivesARegionWithAHole() {
        let tube = merged([box(Vector3(-10, -10, 0), Vector3(10, 10, 10)), box(Vector3(-5, -5, 0), Vector3(5, 5, 10), inward: true)])
        let section = slice(tube, z: 5)
        #expect(section.regions.count == 1)
        #expect(abs(area(section.regions[0]) - 300) < 1e-9)
        #expect(section.regions[0].boundary.count == 2)
    }

    @Test func anIslandInsideAHoleIsItsOwnRegion() {
        let shells = merged([
            box(Vector3(-15, -15, 0), Vector3(15, 15, 10)),
            box(Vector3(-10, -10, 0), Vector3(10, 10, 10), inward: true),
            box(Vector3(-5, -5, 0), Vector3(5, 5, 10)),
        ])
        let section = slice(shells, z: 5)
        #expect(section.regions.count == 2)
        let areas = section.regions.map(area).sorted()
        #expect(abs(areas[0] - 100) < 1e-9)
        #expect(abs(areas[1] - 500) < 1e-9)
    }

    @Test func anOpenMeshGivesAnOutlineWithoutACap() {
        var cube = box(.zero, Vector3(10, 10, 10))
        var kept: [UInt32] = []
        for index in stride(from: 0, to: cube.indices.count, by: 3) {
            let corners = (0..<3).map { cube.positions[Int(cube.indices[index + $0])] }
            if !corners.allSatisfy({ $0.x == 10 }) { kept += cube.indices[index..<index + 3] }
        }
        cube.indices = kept
        let section = slice(cube, z: 5)
        #expect(section.regions.isEmpty)
        #expect(section.openOutlines.count == 1)
        #expect(section.openOutlines[0].count == 4)
    }

    @Test func aPlaneBesideTheMeshGivesNothing() {
        #expect(slice(box(.zero, Vector3(10, 10, 10)), z: 20).isEmpty)
    }

    @Test func aPlaneThroughAVertexIsNotDegenerate() {
        let section = slice(box(.zero, Vector3(10, 10, 10)), z: 0)
        let points = section.regions.flatMap { $0.positions + $0.boundary.flatMap(\.polyline) } + section.openOutlines.flatMap { $0 }
        #expect(points.allSatisfy { $0.isFinite })
        #expect(section.regions.isEmpty || (section.regions.count == 1 && abs(area(section.regions[0]) - 100) < 1e-9))
    }
}
