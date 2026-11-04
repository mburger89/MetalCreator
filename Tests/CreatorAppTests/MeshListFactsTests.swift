import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The inspector's "Mesh" section for a list of meshes (a 3MF's build items): summary rows, through the real node.
@MainActor
struct MeshListFactsTests {
    /// A 3MF of tetrahedra, one per entry of `shifts` (each moved that far along x), written by the app's own writer.
    func package(shifts: [Float]) throws -> Data {
        let url = URL.temporaryDirectory.appending(path: "facts-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        for (index, shift) in shifts.enumerated() {
            try writer.beginObject(name: "Source \(index)")
            let positions = ImperfectMeshExportTests.tetra.flatMap { [$0.0, $0.1, $0.2] }.map { $0 + SIMD3(shift, 0, 0) }
            try writer.add(MeshWindow(positions: positions, triangles: Array(0..<UInt32(positions.count)), startingAt: 0))
            try writer.endObject()
        }
        try writer.finish()
        return try Data(contentsOf: url)
    }

    func rows(for shifts: [Float], through decimate: Bool = false) async throws -> [InspectorRow] {
        let data = try package(shifts: shifts)
        let hash = ImageHash(of: data)
        var builder = GraphBuilder()
        var node = builder.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(.embedded(hash))])
        if decimate {
            let decimated = builder.add(DecimateNode.self)
            builder.wire(node, "mesh", to: decimated, "mesh")
            node = decimated
        }
        var graph = builder.graph
        graph.nodes[node.id]?.isOutput = true  // evaluated for the inspector without an Output node after it
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph, images: [hash: data]))
        await app.settle()
        app.editor.selection = [node.id]
        return app.editor.inspectorPage.sections.first { $0.title == "Mesh" }?.rows ?? []
    }

    func text(_ rows: [InspectorRow], _ label: String) -> String? {
        for case .readOnly(let found, let text) in rows where found == label { return text }
        return nil
    }

    @Test func aListOfTwoMeshesShowsSummaryRows() async throws {
        let rows = try await rows(for: [0, 30])
        #expect(text(rows, "Meshes") == "2")
        #expect(text(rows, "Triangles") == "8")
        #expect(text(rows, "Size") == "40 × 10 × 10 mm", "\(rows)")
        #expect(text(rows, "Closed") == "Yes")
        #expect(text(rows, "File") == "Embedded", "\(rows)")
        #expect(text(rows, "Memory") != nil)
        // Each label once.
        let labels = rows.compactMap { row -> String? in if case .readOnly(let label, _) = row { label } else { nil } }
        #expect(Set(labels).count == labels.count, "\(labels)")
    }

    @Test func oneMeshKeepsItsOwnFacts() async throws {
        let rows = try await rows(for: [0])
        #expect(text(rows, "Meshes") == nil)
        #expect(text(rows, "Triangles") == "4" && text(rows, "Vertices") == "4")
    }

    @Test func aToolsFactIsKeptOnceForAList() async throws {
        let rows = try await rows(for: [0, 30], through: true)
        let labels = rows.compactMap { row -> String? in if case .readOnly(let label, _) = row { label } else { nil } }
        #expect(Set(labels).count == labels.count, "\(labels)")
        #expect(text(rows, "Meshes") == "2")
        #expect(text(rows, "Decimated") != nil, "\(rows)")
    }

    @Test func closedCountsHowManyAreClosed() {
        struct Fake: MeshPayload {
            var closed: String
            var triangleCount: Int { 4 }
            var estimatedBytes: Int { 100 }
            var inspectorFacts: [PayloadFact] { [PayloadFact("Closed", closed)] }
        }
        let rows = InspectorBuilder.listFacts(of: [Fake(closed: "Yes"), Fake(closed: "No"), Fake(closed: "Yes")])
        #expect(text(rows, "Closed") == "2 of 3")
        #expect(text(InspectorBuilder.listFacts(of: [Fake(closed: "No"), Fake(closed: "No")]), "Closed") == "No")
        #expect(text(rows, "Size") == nil, "no bounds, no size")
    }
}
