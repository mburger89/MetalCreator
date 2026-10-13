import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// The node library's "Fields" category (fields spec §3): after Lists & Trees, before Output.
struct FieldsLibraryTests {
    var sections: [LibrarySection] {
        LibrarySection.grouping(BuiltInNodes.all.map {
            PaletteEntry(typeID: $0.typeID, displayName: $0.displayName, category: $0.category)
        })
    }

    @Test func theFieldsSectionFollowsListsAndTreesAndPrecedesOutput() {
        #expect(sections.map(\.title)
            == ["Value", "Profile", "Solid", "Selection", "Feature", "Patterns", "Lists & Trees", "Fields", "Output"])
    }

    @Test func theFieldsSectionHoldsTheFieldNodesInOrder() {
        let names = sections.first { $0.category == .fields }?.entries.map(\.displayName)
        #expect(names == [
            "Distance Field", "Linear Gradient", "Radial Gradient", "Noise Field",
            "Add", "Multiply", "Min / Max", "Remap", "Clamp", "Smooth Blend",
            "Sample Field", "Cull by Field", "Field Scatter",
        ])
    }

    /// Cull by Field lives under Fields but is found by the palette's search beside the other cull nodes: the patterns ones
    /// first (their category comes earlier), then it.
    @Test func searchingCullFindsCullByFieldBesideTheOtherCullNodes() {
        let found = PaletteSearch.entries(in: BuiltInNodes.registry, matching: "cull")
        #expect(found.map(\.displayName) == ["Cull by Region", "Cull Index", "Cull Pattern", "Cull by Field"])
        #expect(found.last?.category == .fields)
    }

    @Test func everyFieldNodeMakesAFieldExceptTheThreeThatUseOne() {
        let users = ["Sample Field", "Cull by Field", "Field Scatter"]
        for definition in BuiltInNodes.all where definition.category == .fields {
            let makesField = definition.outputs.contains { $0.type == .field }
            let takesField = definition.inputs.contains { $0.type == .field }
            #expect(makesField == !users.contains(definition.displayName), "\(definition.displayName)")
            #expect(takesField || makesField, "\(definition.displayName) works with fields")
        }
    }
}
