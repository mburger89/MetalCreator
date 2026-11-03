import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// The mesh tools on a mesh that is not closed (mesh import spec, "Downstream: a mesh that isn't closed"): an imported file can be
/// open, have a flipped face or an edge shared by three faces, which a mesher's output never has.
struct ImperfectMeshTests {
    typealias Face = ImportMeshNodeTests.Face
    static let tetra = ImportMeshNodeTests.tetra

    /// The three ways a mesh can fail to be closed, as faces for an STL.
    enum Imperfection: CaseIterable, CustomStringConvertible {
        case open, flipped, overfull

        var faces: [Face] {
            let base = ImportMeshNodeTests.tetra
            switch self {
            case .open: return Array(base.dropLast())
            case .flipped:
                let last = base[base.count - 1]
                return Array(base.dropLast()) + [(last.0, last.2, last.1)]
            case .overfull:
                // A third face on the edge from a to b.
                return base + [(base[0].0, base[0].2, SIMD3<Float>(5, -5, -5))]
            }
        }

        var description: String {
            switch self {
            case .open: "open"
            case .flipped: "flipped"
            case .overfull: "overfull"
            }
        }
    }

    /// An Import Mesh node holding `faces`, a tool node wired to it, and the resolver.
    func graph(_ faces: [Face], tool: any NodeDefinition.Type) -> (Harness, Node, Node, ImageResolver) {
        var h = Harness()
        let data = ImportMeshNodeTests.stl(faces)
        let hash = ImageHash(of: data)
        let source = h.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(.embedded(hash))])
        let node = h.add(tool)
        h.wire(source, "mesh", to: node, "mesh")
        return (h, source, node, ImageResolver(embedded: [hash: data]))
    }

    func triangleMesh(_ report: EvaluationReport, _ node: Node) throws -> TriangleMesh {
        let value = try #require(report.value(node, "mesh"), "\(String(describing: report.state(node)))")
        return try #require(value.items.first.flatMap { if case .mesh(let payload) = $0 { payload as? TriangleMesh } else { nil } })
    }

    // MARK: Refusals

    @Test(arguments: Imperfection.allCases) func checkThinWallsRefuses(_ imperfection: Imperfection) async throws {
        let (h, _, node, images) = graph(imperfection.faces, tool: CheckThinWallsNode.self)
        let report = try await h.run([node], images: images)
        #expect(report.error(node) == "Check Thin Walls needs a closed mesh.", "\(imperfection)")
    }

    @Test(arguments: Imperfection.allCases) func checkTrappedVolumesRefuses(_ imperfection: Imperfection) async throws {
        let (h, _, node, images) = graph(imperfection.faces, tool: CheckTrappedVolumesNode.self)
        let report = try await h.run([node], images: images)
        #expect(report.error(node) == "Check Trapped Volumes needs a closed mesh.", "\(imperfection)")
    }

    @Test(arguments: Imperfection.allCases) func meshToSolidRefuses(_ imperfection: Imperfection) async throws {
        let (h, _, node, images) = graph(imperfection.faces, tool: MeshToSolidNode.self)
        let kernel = FakeKernel()
        let report = try await h.run([node], kernel: kernel, images: images)
        #expect(report.error(node) == "Mesh to Solid needs a closed mesh.", "\(imperfection)")
        #expect(await kernel.operationLog.isEmpty, "the kernel is not asked")
    }

    @Test func aClosedMeshIsUnaffected() async throws {
        let (h1, _, thin, images) = graph(Self.tetra, tool: CheckThinWallsNode.self)
        let thinReport = try await h1.run([thin], images: images)
        #expect(thinReport.error(thin) == nil)
        let (h2, _, trapped, images2) = graph(Self.tetra, tool: CheckTrappedVolumesNode.self)
        let trappedReport = try await h2.run([trapped], images: images2)
        #expect(trappedReport.error(trapped) == nil)
        let (h3, _, solid, images3) = graph(Self.tetra, tool: MeshToSolidNode.self)
        let kernel = FakeKernel()
        let report = try await h3.run([solid], kernel: kernel, images: images3)
        #expect(report.error(solid) == "Mesh to solid isn't supported by this kernel yet.", "the kernel is asked and answers")
    }

    @Test func theMesherAndDecimatesOutputAreClosedAndTheToolsTakeThem() async throws {
        var h = Harness()
        let sphere = h.add(ImplicitSphereNode.self, ["radius": .number(4)])
        let shell = h.add(ImplicitShellNode.self, ["thickness": .number(1)])
        let mesh = h.add(MeshNode.self, ["preview resolution": .number(0.5)])
        let decimate = h.add(DecimateNode.self, ["tolerance": .number(0.05)])
        let thin = h.add(CheckThinWallsNode.self)
        let trapped = h.add(CheckTrappedVolumesNode.self)
        h.wire(sphere, "implicit", to: shell, "implicit")
        h.wire(shell, "implicit", to: mesh, "implicit")
        h.wire(mesh, "mesh", to: decimate, "mesh")
        h.wire(decimate, "mesh", to: thin, "mesh")
        // Check Trapped Volumes takes the mesher's own output: after Decimate its stricter signed-distance test can still refuse
        // (a closed mesh by `EdgeCounts` that has a pinched vertex), which is older than mesh import and not an `EdgeCounts` matter.
        h.wire(mesh, "mesh", to: trapped, "mesh")
        let report = try await h.run([mesh, decimate, thin, trapped])
        #expect(EdgeCounts(try triangleMesh(report, mesh)).isClosed)
        #expect(EdgeCounts(try triangleMesh(report, decimate)).isClosed)
        #expect(report.error(thin) == nil, "\(String(describing: report.error(thin)))")
        #expect(report.error(trapped) == nil, "\(String(describing: report.error(trapped)))")
    }

    // MARK: Decimate

    /// A flat sheet of 8 × 8 cells (two triangles each) in the z = 0 plane, open all round.
    static func sheet() -> (positions: [SIMD3<Float>], triangles: [UInt32]) {
        let n = 9
        var positions: [SIMD3<Float>] = []
        for y in 0..<n { for x in 0..<n { positions.append(SIMD3(Float(x), Float(y), 0)) } }
        var triangles: [UInt32] = []
        for y in 0..<(n - 1) {
            for x in 0..<(n - 1) {
                let (a, b, c, d) = (UInt32(y * n + x), UInt32(y * n + x + 1), UInt32((y + 1) * n + x + 1), UInt32((y + 1) * n + x))
                triangles += [a, b, c, a, c, d]
            }
        }
        return (positions, triangles)
    }

    @Test func decimatePinsOpenEdges() throws {
        let sheet = Self.sheet()
        let output = try MeshDecimator.decimate(positions: sheet.positions, triangles: sheet.triangles, tolerance: 0.01)
        #expect(output.triangles.count < sheet.triangles.count)
        // The border stays where it was: every corner of the sheet is still a vertex.
        for corner in [SIMD3<Float>(0, 0, 0), SIMD3(8, 0, 0), SIMD3(8, 8, 0), SIMD3(0, 8, 0)] {
            #expect(output.positions.contains(corner))
        }
        #expect(output.positions.allSatisfy { $0.z == 0 && $0.x >= 0 && $0.x <= 8 && $0.y >= 0 && $0.y <= 8 })
    }

    @Test func decimateOnAnOverfullEdge() throws {
        // The sheet with a fin of three triangles standing on its middle row: edges with three faces along y = 4.
        var sheet = Self.sheet()
        let base = UInt32(sheet.positions.count)
        sheet.positions += (0..<9).map { SIMD3<Float>(Float($0), 4, 3) }
        for index in 0..<8 {
            let (a, b) = (UInt32(4 * 9 + index), UInt32(4 * 9 + index + 1))
            sheet.triangles += [a, b, base + UInt32(index) + 1, a, base + UInt32(index) + 1, base + UInt32(index)]
        }
        let input = TriangleMesh(positions: sheet.positions, triangles: sheet.triangles)
        #expect(EdgeCounts(input).overfull > 0)
        let output = try MeshDecimator.decimate(positions: sheet.positions, triangles: sheet.triangles, tolerance: 0.01)
        #expect(output.triangles.count < sheet.triangles.count, "the flat parts still simplify")
        // The surface stays within the tolerance: every vertex is on the sheet's plane, or on the fin's (y = 4 ... z up to 3).
        let onSurface = output.positions.allSatisfy { p in
            abs(p.z) < 0.011 || (abs(p.y - 4) < 0.011 && p.z <= 3.011)
        }
        #expect(onSurface)
        // The fin's top is kept: its vertices are pinned with the edge they stand on.
        #expect(output.positions.contains { $0.z == 3 })
        let after = EdgeCounts(TriangleMesh(positions: output.positions, triangles: output.triangles))
        #expect(after.overfull > 0, "the shared edges are still shared")
    }

    // MARK: Section

    /// The section of `imperfection`'s welded mesh by the horizontal plane at `z`.
    func section(_ imperfection: Imperfection, z: Double) -> PlaneSection {
        let welded = ExactWeld.weld(corners: imperfection.faces.flatMap { [$0.0, $0.1, $0.2] })
        let positions = welded.positions.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) }
        let plane = Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitX)
        return MeshSlicer.slice(positions: positions, triangles: welded.triangles, plane: plane)
    }

    @Test func sectionDrawsOpenOutlines() {
        // Closed tetrahedron: one cap, no open outline (the reference for the others).
        let closed = MeshSlicer.slice(positions: ExactWeld.weld(corners: Self.tetra.flatMap { [$0.0, $0.1, $0.2] }).positions
            .map { Vector3(Double($0.x), Double($0.y), Double($0.z)) },
                                      triangles: ExactWeld.weld(corners: Self.tetra.flatMap { [$0.0, $0.1, $0.2] }).triangles,
                                      plane: Plane(origin: Vector3(0, 0, 3), normal: .unitZ, xAxis: .unitX))
        #expect(closed.regions.count == 1 && closed.openOutlines.isEmpty)
        // Open (the slanted face is missing): the hole crosses the plane, so the cut is one open outline of the two faces left.
        let open = section(.open, z: 3)
        #expect(open.regions.isEmpty && open.openOutlines.count == 1, "\(open)")
        // Over-full: the fin lies below the base, so a cut at z = 3 is the tetrahedron's, and a cut at z = -2 goes through the fin alone.
        let throughTetra = section(.overfull, z: 3)
        #expect(throughTetra.regions.count == 1 && throughTetra.openOutlines.isEmpty, "\(throughTetra)")
        let throughFin = section(.overfull, z: -2)
        #expect(throughFin.regions.isEmpty && throughFin.openOutlines.count == 1, "\(throughFin)")
        // Flipped: one face is wound the wrong way; the cut still closes and does not trap or lose an outline.
        let flipped = section(.flipped, z: 3)
        #expect(flipped.regions.count + flipped.openOutlines.count == 1, "\(flipped)")
    }
}
