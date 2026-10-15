import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// The node library's "Implicit" category (implicit spec §3): after Fields, before Output.
struct ImplicitLibraryTests {
    var sections: [LibrarySection] {
        LibrarySection.grouping(BuiltInNodes.all.map {
            PaletteEntry(typeID: $0.typeID, displayName: $0.displayName, category: $0.category)
        })
    }

    @Test func theImplicitSectionFollowsFieldsAndPrecedesOutput() {
        let titles = sections.map(\.title)
        #expect(titles.suffix(4) == ["Fields", "Implicit", "Mesh", "Output"])
    }

    @Test func theImplicitSectionHoldsTheImplicitNodesInOrder() {
        let names = sections.first { $0.category == .implicit }?.entries.map(\.displayName)
        #expect(names == [
            "Sphere", "Box", "Cylinder", "Union", "Subtract", "Intersect", "Shell",
            "Offset", "To Implicit", "Isosurface", "TPMS", "Strut Lattice", "Voronoi Lattice",
        ])
    }

    @Test func theMeshSectionHoldsTheMeshNode() {
        let names = sections.first { $0.category == .mesh }?.entries.map(\.displayName)
        #expect(names == ["Mesh"])
    }
}
