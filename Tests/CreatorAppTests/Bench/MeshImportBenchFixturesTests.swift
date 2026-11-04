import CreatorImplicit
import Foundation
import Testing

/// `MeshImportBench`'s files, small, in the default run: each format reads back to the triangles written, a height field is closed
/// along its interior and a soup shares no vertex.
struct MeshImportBenchFixturesTests {
    @Test func aHeightFieldReadsBackInEveryFormat() throws {
        let source = Fixture.field(2_000)
        for kind in [Fixture.Kind.binary(source), .ascii(source), .threeMF(source)] {
            let url = try Fixture.write(kind)
            defer { try? FileManager.default.removeItem(at: url) }
            let data = try Data(contentsOf: url)
            let imported: ImportedMesh
            if case .threeMF = kind {
                imported = try #require(try ThreeMFReader.read(data, isCancelled: { false }).first)
            } else {
                imported = try STLReader.read(data, isCancelled: { false })
            }
            #expect(imported.mesh.triangleCount == source.count, "\(kind)")
            let side = try #require(source.grid)
            #expect(imported.mesh.vertexCount == side * side, "\(kind)")
            #expect(imported.droppedTriangles == 0)
        }
    }

    @Test func aSoupSharesNoVertex() throws {
        let source = Fixture.soup(500)
        let url = try Fixture.write(.binary(source))
        defer { try? FileManager.default.removeItem(at: url) }
        let imported = try STLReader.read(try Data(contentsOf: url), isCancelled: { false })
        #expect(imported.mesh.triangleCount == 500 && imported.mesh.vertexCount == 1_500)
        let counts = EdgeCounts(imported.mesh)
        #expect(counts.open == 1_500)
    }
}
