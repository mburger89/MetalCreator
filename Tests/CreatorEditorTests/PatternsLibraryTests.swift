import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// The node library's "Patterns" category (patterns spec §8): between Feature and Lists & Trees, holding the pattern nodes.
struct PatternsLibraryTests {
    /// The sections the app builds: the registry through the palette's search, then the grouping.
    func sections(_ sort: LibrarySort = .alphabetical) -> [LibrarySection] {
        LibrarySection.grouping(PaletteSearch.entries(in: BuiltInNodes.registry, matching: ""), sort: sort)
    }

    @Test func thePatternsSectionFollowsFeatureAndPrecedesOutput() {
        #expect(sections().map(\.title)
            == ["Value", "Profile", "Solid", "Selection", "Feature", "Patterns", "Lists & Trees", "Fields", "Implicit", "Mesh", "Output"])
    }

    @Test func theAlphabeticalOrderIsTodays() {
        let names = sections(.alphabetical).first { $0.category == .patterns }?.entries.map(\.displayName)
        #expect(names == [
            "Boss / Pin Pattern", "Circular Pattern", "Cull by Region", "Cull Index", "Cull Pattern", "Curve Pattern",
            "Face Pattern", "Grid Pattern", "Hole Pattern", "Jitter", "Linear Pattern", "Pattern Feature", "Place",
            "Points to Placements", "Random Reduce", "Random Values", "Slot Pattern",
        ])
    }

    @Test func groupedPatternsAreLayoutsPlacingShortcutsAndVariation() {
        let section = sections(.grouped).first { $0.category == .patterns }
        #expect(section?.subgroups.map(\.title) == ["Layouts", "Placing", "Shortcuts", "Variation"])
        #expect(section?.subgroups.map { $0.entries.map(\.displayName) } == [
            ["Circular Pattern", "Curve Pattern", "Face Pattern", "Grid Pattern", "Linear Pattern"],
            ["Place", "Points to Placements"],
            ["Boss / Pin Pattern", "Hole Pattern", "Pattern Feature", "Slot Pattern"],
            ["Cull by Region", "Cull Index", "Cull Pattern", "Jitter", "Random Reduce", "Random Values"],
        ])
    }
}
