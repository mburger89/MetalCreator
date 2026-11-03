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
    func package(shifts: [Float] = [0, 30]) throws -> Data {
        let url = URL.temporaryDirectory.appending(path: "in-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        for (index, shift) in shifts.enumerated() {
            let name = "Source \(index)"
            try writer.beginObject(name: name)
            let faces = ImperfectMeshExportTests.tetra
            let positions = faces.flatMap { [$0.0, $0.1, $0.2] }.map { $0 + SIMD3(shift, 0, 0) }
            try writer.add(MeshWindow(positions: positions, triangles: Array(0..<UInt32(positions.count)), startingAt: 0))
            try writer.endObject()
        }
        try writer.finish()
        return try Data(contentsOf: url)
    }

    /// An app holding an Import Mesh node on `data`, wired to an Output named `name` (and a box too when `withSolid`).
    func app(importing data: Data, name: String = "Part", withSolid: Bool = false) async -> AppModel {
        let hash = ImageHash(of: data)
        var builder = GraphBuilder()
        let source = builder.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(.embedded(hash))])
        var output = builder.add(OutputNode.self)
        output.name = name
        builder.replace(output)
        builder.wire(source, "mesh", to: output, "mesh")
        if withSolid {
            let (_, extrude) = builder.solid()
            builder.wire(extrude, "solid", to: output, "solid")
        }
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph, images: [hash: data]))
        await app.settle()
        return app
    }

    @Test func aListOfMeshesFromOneNodeKeepsOneObjectEach() async throws {
        let app = await app(importing: try package())
        let folder = ExportStreamedTests.Folder()
        try await app.export(.threeMF, to: folder.file("again.3mf"))
        let objects = try ExportStreamedTests().objects(folder.file("again.3mf"))
        #expect(objects.count == 2, "\(objects.count) objects")
        #expect(objects.map { $0.mesh.triangleCount } == [4, 4])
        #expect(objects.map(\.name) == ["Part 1", "Part 2"])
    }

    @Test func oneMeshKeepsItsOutputsName() async throws {
        let one = try package(shifts: [0])
        let app = await app(importing: one, name: "Bracket")
        let folder = ExportStreamedTests.Folder()
        try await app.export(.threeMF, to: folder.file("one.3mf"))
        let objects = try ExportStreamedTests().objects(folder.file("one.3mf"))
        #expect(objects.map(\.name) == ["Bracket"] && objects.map { $0.mesh.triangleCount } == [4])
    }

    @Test func aSolidAndAListShareTheFirstObject() async throws {
        let app = await app(importing: try package(), withSolid: true)
        let folder = ExportStreamedTests.Folder()
        try await app.export(.threeMF, to: folder.file("both.3mf"))
        let objects = try ExportStreamedTests().objects(folder.file("both.3mf"))
        #expect(objects.map(\.name) == ["Part 1", "Part 2"])
        #expect(objects[0].mesh.triangleCount > 4, "the box's triangles and the first mesh's four")
        #expect(objects[1].mesh.triangleCount == 4)
    }

    @Test func anSTLOfAListIsOneFileOfEveryTriangle() async throws {
        let app = await app(importing: try package())
        let folder = ExportStreamedTests.Folder()
        try await app.export(.stl, to: folder.file("list.stl"))
        let data = try Data(contentsOf: folder.file("list.stl"))
        #expect(data.count == 84 + 8 * 50, "binary STL: header, count and 8 triangles")
        #expect(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) } == 8)
    }
}
