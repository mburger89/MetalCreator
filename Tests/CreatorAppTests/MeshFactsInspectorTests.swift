import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The Mesh node's inspector shows the "Mesh" facts (triangles, resolution, meshing time, memory) in Final preview, as the field
/// check found it missing for a Sphere and a Box placed, merged, unioned, shelled and meshed.
@MainActor
struct MeshFactsInspectorTests {
    @Test func theMeshNodeShowsItsFactsInFinalPreview() async throws {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(20)])
        let box = builder.add(ImplicitBoxNode.self, ["size": .vector(Vector3(30, 30, 30)), "corner radius": .number(3)])
        let plane = builder.add(PlaneNode.self, ["orientation": .integer(2), "offset": .number(15)])
        let place = builder.add(PlaceNode.self)
        let merge = builder.add(MergeNode.self)
        let union = builder.add(ImplicitUnionNode.self, ["blend radius": .number(4)])
        let shell = builder.add(ImplicitShellNode.self, ["thickness": .number(2)])
        let mesh = builder.add(MeshNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(box, "implicit", to: place, "implicit")
        builder.wire(plane, "plane", to: place, "placements")
        builder.wire(sphere, "implicit", to: merge, "a")
        builder.wire(place, "implicits", to: merge, "b")
        builder.wire(merge, "list", to: union, "shapes")
        builder.wire(union, "implicit", to: shell, "implicit")
        builder.wire(shell, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        app.previewMode = .final
        await app.settle()
        app.editor.selection = [mesh.id]
        let sections = app.editor.inspectorPage.sections
        let facts = sections.filter { $0.title == "Mesh" }.flatMap(\.rows)
        let labels = facts.compactMap { row -> String? in if case .readOnly(let label, _) = row { label } else { nil } }
        #expect(labels.contains("Triangles"), "\(sections.map(\.title)) \(facts)")
        // The node's own "Mesh" section (its resolutions) and the facts share a title; the panel keys its sections by
        // `identifiedSections`, and a repeated key drops the later section from the view (the facts were the ones lost).
        let ids = app.editor.inspectorPage.identifiedSections.map(\.id)
        #expect(sections.filter { $0.title == "Mesh" }.count == 2)
        #expect(Set(ids).count == ids.count, "\(ids)")
    }
}
