import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// Exporting and measuring a mesh that is not closed (mesh import spec, "Downstream: a mesh that isn't closed"): STL writes any
/// triangles, a 3MF writes them too and says the format asks for a closed mesh, Measure works on the surface it has.
@MainActor
struct ImperfectMeshExportTests {
    typealias Face = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    static let a = SIMD3<Float>(0, 0, 0), b = SIMD3<Float>(10, 0, 0), c = SIMD3<Float>(0, 10, 0), d = SIMD3<Float>(0, 0, 10)
    /// A tetrahedron wound counter-clockwise seen from outside.
    static let tetra: [Face] = [(a, c, b), (a, b, d), (a, d, c), (b, c, d)]
    static let open = Array(tetra.dropLast())
    static let flipped = open + [(b, d, c)]
    /// A third face on the edge from a to b.
    static let overfull = tetra + [(a, b, SIMD3<Float>(5, -5, -5))]

    /// An ASCII STL of `faces`.
    static func stl(_ faces: [Face]) -> Data {
        var text = "solid t\n"
        for face in faces {
            text += "facet normal 0 0 0\nouter loop\n"
            for p in [face.0, face.1, face.2] { text += "vertex \(p.x) \(p.y) \(p.z)\n" }
            text += "endloop\nendfacet\n"
        }
        return Data((text + "endsolid t\n").utf8)
    }

    /// Import Mesh holding `faces` → an Output named "Part", in an app whose document has the file embedded.
    func app(holding faces: [Face]) async -> AppModel {
        let data = Self.stl(faces)
        let hash = ImageHash(of: data)
        var builder = GraphBuilder()
        let source = builder.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(.embedded(hash))])
        var output = builder.add(OutputNode.self)
        builder.wire(source, "mesh", to: output, "mesh")
        output.name = "Part"
        builder.replace(output)
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph, images: [hash: data]))
        await app.settle()
        return app
    }

    @Test func exportSTLWritesAnOpenMesh() async throws {
        let app = await app(holding: Self.open)
        let folder = ExportStreamedTests.Folder()
        try await app.export(.stl, to: folder.file("open.stl"))
        let file = try #require(STLFile(try Data(contentsOf: folder.file("open.stl"))))
        #expect(file.triangles.count == 3)
        #expect(!(app.alert.map { if case .problem(let p) = $0 { p.message.contains("3MF") } else { false } } ?? false), "no 3MF warning")
    }

    @Test func export3MFWarnsAnOpenMesh() async throws {
        let app = await app(holding: Self.open)
        let folder = ExportStreamedTests.Folder()
        try await app.export(.threeMF, to: folder.file("open.3mf"))
        guard case .problem(let problem)? = app.alert else { Issue.record("no summary"); return }
        #expect(problem.message.contains("This mesh isn't closed, so the 3MF may not print."), "\(problem.message)")
        let written = try #require(try ExportStreamedTests().objects(folder.file("open.3mf")).first?.mesh)
        #expect(written.triangleCount == 3, "it still writes")
    }

    @Test func export3MFWarnsAFlippedAndAnOverfullMesh() async throws {
        for (name, faces) in [("flipped", Self.flipped), ("overfull", Self.overfull)] {
            let app = await app(holding: faces)
            let folder = ExportStreamedTests.Folder()
            try await app.export(.threeMF, to: folder.file("part.3mf"))
            guard case .problem(let problem)? = app.alert else { Issue.record("no summary for \(name)"); continue }
            #expect(problem.message.contains("This mesh isn't closed, so the 3MF may not print."), "\(name)")
        }
    }

    @Test func aClosedMeshIsUnaffected() async throws {
        let app = await app(holding: Self.tetra)
        let folder = ExportStreamedTests.Folder()
        try await app.export(.threeMF, to: folder.file("closed.3mf"))
        let message: String? = if case .problem(let problem)? = app.alert { problem.message } else { nil }
        #expect(message?.contains("isn't closed") != true, "\(message ?? "no alert")")
    }

    @Test func measureOnAnOpenMesh() async throws {
        let fixture = await MeasureAppFixture.open()
        fixture.app.setMeasure(true)
        // Two triangles forming a sheet: every edge on its border is open.
        let mesh = DisplayMesh(positions: [Vector3(-500, -500, 0), Vector3(500, -500, 0), Vector3(500, 500, 0), Vector3(-500, 500, 0)],
                               normals: [.unitZ, .unitZ, .unitZ, .unitZ], indices: [0, 1, 2, 0, 2, 3],
                               triangleFaces: [FaceID(0), FaceID(0)], edgePolylines: [:])
        fixture.app.viewport.show([ViewportItem(solid: Solid(displaying: mesh))])
        await fixture.app.viewport.waitForMeshes()
        let session = try #require(fixture.app.measure)
        session.sceneChanged(fixture.app.measureScene())
        for point in [ScreenPoint(600, 400), ScreenPoint(800, 500)] {
            #expect(session.clickedModel(.face(solid: 0, FaceID(0)), at: point, modifiers: [], projector: fixture.projector))
        }
        await session.waitForDistance()
        let found = try #require(session.distance)
        #expect(session.picks.count == 2 && found.distance > 0)
    }
}
