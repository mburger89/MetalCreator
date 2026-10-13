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
        ])
    }

    @Test func everyFieldNodeHasAFieldOutputAndTheFieldsCategory() {
        for definition in BuiltInNodes.all where definition.category == .fields {
            #expect(definition.outputs.contains { $0.type == .field }, "\(definition.displayName)")
        }
    }
}
