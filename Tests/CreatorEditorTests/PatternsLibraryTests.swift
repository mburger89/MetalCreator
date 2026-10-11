import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// The node library's "Patterns" category (patterns spec §8): between Feature and Output, holding the pattern nodes.
struct PatternsLibraryTests {
    var sections: [LibrarySection] {
        LibrarySection.grouping(BuiltInNodes.all.map {
            PaletteEntry(typeID: $0.typeID, displayName: $0.displayName, category: $0.category)
        })
    }

    @Test func thePatternsSectionFollowsFeatureAndPrecedesOutput() {
        #expect(sections.map(\.title) == ["Value", "Profile", "Solid", "Selection", "Feature", "Patterns", "Output"])
    }

    @Test func thePatternsSectionHoldsThePatternNodes() {
        let names = sections.first { $0.category == .patterns }?.entries.map(\.displayName)
        #expect(names == ["Place", "Points to Placements"])
    }
}
