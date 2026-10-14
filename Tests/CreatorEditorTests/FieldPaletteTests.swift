import CreatorGraph
import CreatorStyle
import Testing
@testable import CreatorEditor

/// The field socket's colour role and the Fields category (fields spec §2.1). The theme has no field role yet (7b-3 adds the
/// preview ramp's), so the category borrows the Feature header colour; the dot differs from every value socket's.
struct FieldPaletteTests {
    @Test func theFieldsCategoryIsTitledFieldsAndComesLastBeforeOutput() {
        #expect(NodeCategory.fields.title == "Fields")
        #expect(LibrarySection.title(for: .fields) == "Fields")
        #expect(NodeCategory.allCases.suffix(4) == [.fields, .implicit, .mesh, .output])
    }

    @Test func aFieldSocketHasItsCategorysColourAndNotTheValueColour() {
        let palette = Palette.dracula
        #expect(palette.socket(.field) == palette.header(for: .fields))
        #expect(palette.header(for: .fields) == palette.header(for: .feature), "borrowed until the theme gains a role of its own")
        #expect(palette.socket(.field) != palette.socket(.number))
        #expect(palette.socket(.field) != palette.socket(.solid) && palette.socket(.field) != palette.socket(.edgeSet))
    }

    @Test func aFieldNodeIsOutlinedInItsHeaderColour() {
        #expect(Palette.dracula.selection(for: .fields) == Palette.dracula.header(for: .fields))
    }
}
