import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// Import Mesh on 3MF files: a list of meshes, the file's unit, detection by bytes and warnings said once.
extension ImportMeshNodeTests {
    // MARK: 3MF

    func meshes(_ report: EvaluationReport, _ node: Node) throws -> [TriangleMesh] {
        let value = try #require(report.value(node, "mesh"), "\(String(describing: report.state(node)))")
        return value.items.compactMap { if case .mesh(let payload) = $0 { payload as? TriangleMesh } else { nil } }
    }

    static let shifted: [Face] = tetra.map { ($0.0 + SIMD3(30, 0, 0), $0.1 + SIMD3(30, 0, 0), $0.2 + SIMD3(30, 0, 0)) }

    @Test func a3MFGivesAListOfMeshes() async throws {
        let (h, node, images) = embedded(try ThreeMFFixtures.package([Self.tetra, Self.shifted]))
        let report = try await h.run([node], images: images)
        let made = try meshes(report, node)
        #expect(made.count == 2 && made.allSatisfy { $0.triangleCount == 4 })
        #expect(made[1].positions.map(\.x).min() == 30)
        #expect(report.isOK(node))
        let (h1, node1, images1) = embedded(try ThreeMFFixtures.package([Self.tetra]))
        #expect(try meshes(await h1.run([node1], images: images1), node1).count == 1)
    }

    @Test func fromFileUsesThe3MFsUnit() async throws {
        let (h, node, images) = embedded(try ThreeMFFixtures.package([Self.tetra], unit: "centimeter"))
        #expect(try meshes(await h.run([node], images: images), node).first?.positions.map(\.x).max() == 100)
        // An STL has no unit: From file reads it as millimetres.
        let (hs, stlNode, stlImages) = embedded(Self.stl(Self.tetra))
        #expect(try mesh(await hs.run([stlNode], images: stlImages), stlNode).positions.map(\.x).max() == 10)
    }

    @Test func anExplicitUnitOverridesIt() async throws {
        let data = try ThreeMFFixtures.package([Self.tetra], unit: "millimeter")
        let (h, node, images) = embedded(data, ["units": .integer(4)])
        #expect(try meshes(await h.run([node], images: images), node).first?.positions.map(\.x).max() == 254)
        let (hc, cm, cmImages) = embedded(try ThreeMFFixtures.package([Self.tetra], unit: "centimeter"), ["units": .integer(1)])
        #expect(try meshes(await hc.run([cm], images: cmImages), cm).first?.positions.map(\.x).max() == 10)
    }

    @Test func aZipIsDetectedByItsBytes() async throws {
        let file = try folder.write(try ThreeMFFixtures.package([Self.tetra, Self.shifted]), to: "really-a-3mf.stl")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(reference)])
        #expect(try meshes(await h.run([node]), node).count == 2)
        // And an STL named .3mf is still an STL.
        let stlFile = try folder.write(Self.stl(Self.tetra), to: "really-an-stl.3mf")
        var h2 = Harness()
        let stlReference = ImageReference.linked(relativePath: nil, absolutePath: stlFile.path(percentEncoded: false))
        let node2 = h2.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(stlReference)])
        #expect(try meshes(await h2.run([node2]), node2).count == 1)
    }

    @Test func aWarningSharedByMeshesIsSaidOnce() async throws {
        let open = Array(Self.tetra.dropLast())
        let openShifted = Array(Self.shifted.dropLast())
        let (h, node, images) = embedded(try ThreeMFFixtures.package([open, openShifted]))
        let message = try #require(try await h.run([node], images: images).warning(node))
        #expect(message.components(separatedBy: "This mesh isn't closed: 3 open edges.").count == 2, "\(message)")
    }
}
