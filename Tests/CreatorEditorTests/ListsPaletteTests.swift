import CreatorGraph
import Testing
@testable import CreatorEditor

struct ListsPaletteTests {
    @Test func listsAndTreesShareTheValueColour() {
        #expect(Palette.dracula.header(for: .lists) == Palette.dracula.header(for: .value))
    }

    @Test func anAnySocketIsDrawnInTheListsColour() {
        #expect(Palette.dracula.socket(.any) == Palette.dracula.header(for: .lists))
    }

    @Test func theLibraryTitlesTheCategory() {
        #expect(LibrarySection.title(for: .lists) == "Lists & Trees")
        #expect(LibrarySection.title(for: .feature) == "Feature")
    }
}
