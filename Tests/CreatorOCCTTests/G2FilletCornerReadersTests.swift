import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The mitred G2 corners as readers see them. A mitred side may cut its strip back (hexagon) or carry it on into the hole
/// (triangle), so every pcurve must stay inside its surface's domain, the display mesh must close at both angles,
/// and STEP must round-trip.
struct G2FilletCornerReadersTests {
    let validity = G2FilletCornerValidityTests()

    enum Corner: String, CaseIterable, CustomTestStringConvertible {
        case hexagon, triangle, drafted
        var testDescription: String { rawValue }
    }

    /// The corner's prism through the kernel, with its three corner edges filleted G2 at 1 mm.
    func filleted(_ corner: Corner) async throws -> (OCCTKernel, Solid) {
        let kernel = OCCTKernel()
        let solid: Solid
        let mids: [[Double]]
        switch corner {
        case .hexagon, .triangle:
            let points = corner == .hexagon ? validity.hexagon() : validity.triangle()
            let segments = points.indices.map { Segment2D.line(points[$0], points[($0 + 1) % points.count]) }
            solid = try await kernel.extrude(Profile2D(plane: .xy, segments: segments), distance: 10, mode: .oneSided, tag: newTag())
            mids = validity.topCorner(points, at: 0, height: 10)
        case .drafted:
            let bottom = Profile2D.rectangle(width: 20, height: 20, plane: .xy)
            let top = Profile2D.rectangle(width: 16, height: 16, plane: Plane(origin: Vector3(0, 0, 10), normal: .unitZ, xAxis: .unitX))
            solid = try await kernel.loft([bottom, top], ruled: true, tag: newTag())
            mids = [[0, -8, 10], [-8, 0, 10], [-9, -9, 5]]
        }
        let edges = try mids.map { mid in
            try #require(solid.topology.edges.min { distance($0.midpoint, mid) < distance($1.midpoint, mid) }).id
        }
        let made = try await kernel.fillet(solid, edges: edges, radius: 1, profile: .curvatureContinuous(weight: 1), tag: newTag())
        #expect(made.tangentOnlyCorners == 0)
        return (kernel, made.solid)
    }

    func distance(_ point: Vector3, _ mid: [Double]) -> Double {
        let (dx, dy, dz) = (point.x - mid[0], point.y - mid[1], point.z - mid[2])
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    func shape(of solid: Solid) throws -> OCCTShape {
        try #require((solid.storage as? OCCTSolidStorage)?.shape)
    }

    @Test(arguments: Corner.allCases) func everyPcurveLiesInsideItsSurface(corner: Corner) async throws {
        let (_, solid) = try await filleted(corner)
        let source = try shape(of: solid)
        let excursion = OCCTKernel.serialized { occt_pcurve_domain_excursion(source.raw) }
        print("G2READERS \(corner.rawValue): pcurve excursion \(excursion)")
        // At most one last bit: the drafted prism's strips end on the base through a slanted end whose pcurve starts at
        // v = -5.6e-17 (the base's trim, not the corner). The triangle's sides, carried 0.19 mm past the strips' ends,
        // lie inside because the strips are extended with them.
        #expect(excursion >= 0 && excursion <= 1e-12)
    }

    /// The display mesh, welded at 1e-5 mm, uses every directed edge exactly once and its reverse exactly once:
    /// closed and consistently oriented, at the standard angle and at zebra's.
    @Test(arguments: Corner.allCases) func theDisplayMeshIsClosedAndOriented(corner: Corner) async throws {
        let (kernel, solid) = try await filleted(corner)
        for angle in [DisplayAngle.standard, DisplayAngle.zebra] {
            let mesh = try await kernel.tessellate(solid, tolerance: 0.01, angle: angle)
            let welded = weld(mesh.positions, within: 1e-5)
            var uses: [UInt64: Int] = [:]
            func key(_ a: Int, _ b: Int) -> UInt64 { UInt64(a) << 32 | UInt64(b) }
            for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
                let corners = (0..<3).map { welded[Int(mesh.indices[triangle + $0])] }
                if Set(corners).count < 3 {
                    continue // a sliver whose corners weld together
                }
                for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                    uses[key(corners[a], corners[b]), default: 0] += 1
                }
            }
            let bad = uses.filter { entry in
                let reverse = uses[(entry.key & 0xFFFF_FFFF) << 32 | entry.key >> 32] ?? 0
                return entry.value != 1 || reverse != 1
            }
            print("G2READERS \(corner.rawValue) angle \(angle): \(mesh.indices.count / 3) triangles, \(bad.count) bad edges")
            #expect(!uses.isEmpty)
            #expect(bad.isEmpty)
        }
    }

    /// The vertex each position welds to: the first earlier one within `tolerance`.
    func weld(_ positions: [Vector3], within tolerance: Double) -> [Int] {
        struct Cell: Hashable { let x: Int, y: Int, z: Int }
        func cell(_ p: Vector3) -> Cell {
            func index(_ value: Double) -> Int { Int((value / tolerance).rounded(.down)) }
            return Cell(x: index(p.x), y: index(p.y), z: index(p.z))
        }
        var grid: [Cell: [Int]] = [:]
        var out: [Int] = []
        out.reserveCapacity(positions.count)
        for (index, p) in positions.enumerated() {
            let c = cell(p)
            var found: Int?
            search: for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        let near = grid[Cell(x: c.x + dx, y: c.y + dy, z: c.z + dz)] ?? []
                        for other in near where distance(positions[other], p) <= tolerance {
                            found = other
                            break search
                        }
                    }
                }
            }
            if let found {
                out.append(found)
            } else {
                grid[c, default: []].append(index)
                out.append(index)
            }
        }
        return out
    }

    func distance(_ a: Vector3, _ b: Vector3) -> Double {
        let (dx, dy, dz) = (a.x - b.x, a.y - b.y, a.z - b.z)
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    @Test(arguments: Corner.allCases) func stepRoundTripsTheSolid(corner: Corner) async throws {
        let (kernel, solid) = try await filleted(corner)
        let url = URL.temporaryDirectory.appending(path: "g2-corner-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([solid], format: .step, to: url)
        let (valid, volume, faces) = try OCCTKernel.serialized { () throws -> (Bool, Double, Int) in
            let read = try OCCTShape.readSTEP(url)
            return (read.isValid, try read.properties().volume, try OCCTRawTopology.read(read).faces.count)
        }
        let expected = try await kernel.properties(of: solid).volume
        print("G2READERS \(corner.rawValue): STEP valid \(valid), faces \(faces) of \(solid.topology.faces.count),"
            + " volume \(volume) of \(expected)")
        #expect(valid)
        #expect(faces == solid.topology.faces.count)
        #expect(abs(volume - expected) <= 1e-6 * expected)
    }
}
