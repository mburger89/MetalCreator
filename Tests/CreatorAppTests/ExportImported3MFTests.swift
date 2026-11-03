import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// A 3MF imported with several objects and exported again (mesh import plan, Task 11): the list of meshes from one Import Mesh node,
/// wired to one Output, keeps one 3MF object per mesh.
@MainActor
struct ExportImported3MFTests {
    func package() throws -> Data {
        let url = URL.temporaryDirectory.appending(path: "in-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        for (name, shift) in [("A", Float(0)), ("B", 30)] {
            try writer.beginObject(name: name)
            let faces = ImperfectMeshExportTests.tetra
            let positions = faces.flatMap { [$0.0, $0.1, $0.2] }.map { $0 + SIMD3(shift, 0, 0) }
            try writer.add(MeshWindow(positions: positions, triangles: Array(0..<UInt32(positions.count)), startingAt: 0))
            try writer.endObject()
        }
        try writer.finish()
        return try Data(contentsOf: url)
    }

    @Test func aListOfMeshesFromOneNodeKeepsOneObjectEach() async throws {
        let data = try package()
        let hash = ImageHash(of: data)
        var builder = GraphBuilder()
        let source = builder.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(.embedded(hash))])
        let output = builder.add(OutputNode.self)
        builder.wire(source, "mesh", to: output, "mesh")
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph, images: [hash: data]))
        await app.settle()
        let folder = ExportStreamedTests.Folder()
        try await app.export(.threeMF, to: folder.file("again.3mf"))
        let objects = try ExportStreamedTests().objects(folder.file("again.3mf"))
        #expect(objects.count == 2, "\(objects.count) objects")
        #expect(objects.map { $0.mesh.triangleCount } == [4, 4])
    }
}
