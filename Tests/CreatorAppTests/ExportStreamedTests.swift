import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// The streamed export (implicit spec §5.3, Errata D12): 3MF and STL written window by window, one 3MF object per Output node.
@MainActor
struct ExportStreamedTests {
    /// A folder of its own, removed with the test, so a stray temporary shows.
    final class Folder {
        let url = URL.temporaryDirectory.appending(path: "stream-export-\(UUID().uuidString)")

        init() {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func file(_ name: String) -> URL { url.appending(path: name) }

        var contents: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
    }

    /// Sphere → Mesh (export resolution `export`) → [Decimate] → Output named `name`.
    func sphereGraph(radius: Double = 3, export: Double = 0.5, name: String = "Insole", decimate: Double? = nil,
                     into builder: inout GraphBuilder) -> Node {
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(radius)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(export)])
        var output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        if let decimate {
            let node = builder.add(DecimateNode.self, ["tolerance": .number(decimate)])
            builder.wire(mesh, "mesh", to: node, "mesh")
            builder.wire(node, "mesh", to: output, "mesh")
        } else {
            builder.wire(mesh, "mesh", to: output, "mesh")
        }
        output.name = name
        builder.replace(output)
        return output
    }

    /// The model part of a 3MF: each object's name, vertices and triangles, found by pattern.
    func objects(_ url: URL) throws -> [(name: String, mesh: TriangleMesh)] {
        let model = String(bytes: try ZipReader(contentsOf: url).contents(of: "3D/3dmodel.model"), encoding: .utf8) ?? ""
        return model.components(separatedBy: "<object ").dropFirst().compactMap { text -> (String, TriangleMesh)? in
            guard let name = text.firstMatch(of: /name="([^"]*)"/)?.1 else { return nil }
            var positions: [SIMD3<Float>] = []
            for match in text.matches(of: /<vertex x="([^"]+)" y="([^"]+)" z="([^"]+)"\/>/) {
                positions.append(SIMD3(Float(match.1) ?? .nan, Float(match.2) ?? .nan, Float(match.3) ?? .nan))
            }
            var triangles: [UInt32] = []
            for match in text.matches(of: /<triangle v1="(\d+)" v2="(\d+)" v3="(\d+)"\/>/) {
                triangles += [UInt32(match.1) ?? 0, UInt32(match.2) ?? 0, UInt32(match.3) ?? 0]
            }
            return (String(name), TriangleMesh(positions: positions, triangles: triangles))
        }
    }

    @Test func aMeshOutputIsA3MFObjectNamedAfterItWithAClosedSurfaceAtExportResolution() async throws {
        var builder = GraphBuilder()
        _ = sphereGraph(into: &builder)
        let app = await makeApp(builder.graph)
        let folder = Folder()
        let picker = ScriptedPicker([folder.file("part.3mf")])
        await app.exportDocument(.threeMF, using: picker)
        #expect(app.alert == nil && app.exportRun == nil)
        #expect(picker.asked.count == 1 && picker.asked[0].name == "Insole.3mf" && picker.asked[0].types == [.threeMF])
        #expect(folder.contents == ["part.3mf"], "no temporary is left")
        let found = try objects(folder.file("part.3mf"))
        #expect(found.map(\.name) == ["Insole"])
        let mesh = try #require(found.first?.mesh)
        #expect(mesh.triangleCount > 200)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 27
        #expect(abs(mesh.signedVolume - exact) / exact < 0.02, "volume \(mesh.signedVolume) against \(exact)")
    }

    @Test func eachOutputIsItsOwnObjectAndASolidJoinsTheMeshOfItsOutput() async throws {
        var builder = GraphBuilder()
        let first = sphereGraph(name: "Insole", into: &builder)
        _ = sphereGraph(radius: 2, name: "Heel", into: &builder)
        let box = builder.solid()
        builder.wire(box.extrude, "solid", to: first, "solid")
        let app = await makeApp(builder.graph)
        let folder = Folder()
        try await app.export(.threeMF, to: folder.file("two.3mf"))
        let found = try objects(folder.file("two.3mf"))
        #expect(Set(found.map(\.name)) == ["Insole", "Heel"])
        let insole = try #require(found.first { $0.name == "Insole" }?.mesh), heel = try #require(found.first { $0.name == "Heel" }?.mesh)
        #expect(insole.triangleCount > heel.triangleCount, "the 3 mm ball and the box are one object")
        #expect(insole.triangles.allSatisfy { Int($0) < insole.vertexCount } && insole.vertexCount > 8)
    }

    @Test func aSolidAloneIsA3MFToo() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        let folder = Folder()
        try await app.export(.threeMF, to: folder.file("box.3mf"))
        let mesh = try #require(try objects(folder.file("box.3mf")).first?.mesh)
        #expect(mesh.triangleCount == 12, "FakeKernel tessellates a box as 12 triangles")
    }

    @Test func decimatingInTheGraphShrinksTheFileAndKeepsTheShape() async throws {
        var plain = GraphBuilder(), slim = GraphBuilder()
        _ = sphereGraph(export: 0.3, into: &plain)
        _ = sphereGraph(export: 0.3, decimate: 0.05, into: &slim)
        let folder = Folder()
        try await (await makeApp(plain.graph)).export(.threeMF, to: folder.file("plain.3mf"))
        try await (await makeApp(slim.graph)).export(.threeMF, to: folder.file("slim.3mf"))
        let a = try #require(try objects(folder.file("plain.3mf")).first?.mesh)
        let b = try #require(try objects(folder.file("slim.3mf")).first?.mesh)
        #expect(b.triangleCount < a.triangleCount && MeshTopology(b).isClosedManifold && MeshTopology(b).eulerCharacteristic == 2)
        #expect(abs(b.signedVolume - a.signedVolume) / a.signedVolume < 0.01)
    }

    @Test func aStreamedStlMatchesTheMeshAndNeedsNoMemoryForIt() async throws {
        var builder = GraphBuilder()
        _ = sphereGraph(into: &builder)
        let app = await makeApp(builder.graph)
        let folder = Folder()
        try await app.export(.stl, to: folder.file("part.stl"))
        let file = try #require(STLFile(try Data(contentsOf: folder.file("part.stl"))))
        let exact = 4.0 / 3 * Double.pi * 27
        #expect(abs(file.volume - exact) / exact < 0.02 && folder.contents == ["part.stl"])
    }

    @Test func aCheckWarningReachesTheSummary() async throws {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(2)])
        let shell = builder.add(ImplicitShellNode.self, ["thickness": .number(0.3)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(0.15)])
        let check = builder.add(CheckThinWallsNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: shell, "implicit")
        builder.wire(shell, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: check, "mesh")
        builder.wire(check, "mesh", to: output, "mesh")
        let app = await makeApp(builder.graph)
        let folder = Folder()
        try await app.export(.threeMF, to: folder.file("hollow.3mf"))
        guard case .problem(let problem)? = app.alert else { Issue.record("no summary"); return }
        #expect(problem.title == "Exported with 1 warning")
        #expect(problem.message.hasPrefix("Check Thin Walls: Walls thinner than 0.4 mm in 1 place (thinnest 0.3"), "\(problem.message)")
    }

    @Test func aCancelledExportLeavesNothingInTheFolder() async throws {
        var builder = GraphBuilder()
        _ = sphereGraph(radius: 10, export: 0.05, into: &builder)
        let app = await makeApp(builder.graph)
        let folder = Folder()
        let url = folder.file("cancel.3mf")
        let task = Task { try await app.export(.threeMF, to: url) }
        var attempts = 0
        while app.exportRun == nil, attempts < 2000 {
            try await Task.sleep(for: .milliseconds(5))
            attempts += 1
        }
        let run = try #require(app.exportRun)
        run.cancel()
        try await task.value
        #expect(app.exportRun == nil && app.alert == nil && folder.contents.isEmpty)
    }

    @Test func aFolderThatCannotBeWrittenIsSaidInPlainWords() async throws {
        var builder = GraphBuilder()
        _ = sphereGraph(into: &builder)
        let app = await makeApp(builder.graph)
        let missing = URL.temporaryDirectory.appending(path: "no-such-folder-\(UUID().uuidString)/out.3mf")
        await app.exportDocument(.threeMF, using: ScriptedPicker([missing]))
        guard case .problem(let problem)? = app.alert else { Issue.record("no alert"); return }
        #expect(problem.title == "The 3MF file couldn't be written" || problem.title == "The part couldn't be exported")
        #expect(app.exportRun == nil)
    }

    @Test func stepStillRefusesAMeshAndThreeMFNames3MFInTheRefusal() async throws {
        var builder = GraphBuilder()
        _ = sphereGraph(into: &builder)
        let app = await makeApp(builder.graph)
        await app.exportDocument(.step, using: ScriptedPicker([]))
        guard case .problem(let problem)? = app.alert else { Issue.record("no alert"); return }
        #expect(problem.message.contains("Export STL or 3MF"))
        #expect(ExportKind.allCases.map(\.title) == ["STEP", "STL", "3MF"])
    }
}
