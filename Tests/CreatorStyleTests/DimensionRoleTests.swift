import CreatorStyle
import Foundation
import Testing

/// The dimension annotations' two theme roles (dimensions spec §5): driving dimensions take the focus colour,
/// reference dimensions the comment colour.
struct DimensionRoleTests {
    @Test func theDimensionRolesAreLastInTheirOwnGroup() {
        #expect(ThemeRole.all.suffix(2).map(\.name) == ["dimensionDriving", "dimensionReference"])
        #expect(ThemeRoleGroup.dimensions.title == "Dimensions")
        #expect(ThemeRoleGroup.allCases.last == .dimensions)
        #expect(ThemeRoleGroup.dimensions.roles.map(\.name) == ["dimensionDriving", "dimensionReference"])
    }

    @Test(arguments: [ColorTheme.dracula, .alucard, .nord])
    func builtInsGiveDrivingTheFocusColourAndReferenceTheComment(_ theme: ColorTheme) {
        #expect(theme.colors.dimensionDriving == theme.colors.focus)
        #expect(theme.colors.dimensionReference == theme.colors.comment)
    }

    @Test func aThemeFileWithoutThemReadsDraculas() throws {
        let file = Data(##"{"version":1,"name":"Old","dark":true,"colors":{"accent":"#112233"}}"##.utf8)
        let theme = try ThemeFile.decode(file, id: "old", fallbackName: "Old")
        let dracula = ColorTheme.dracula.colors.quantized
        #expect(theme.colors.dimensionDriving == dracula.dimensionDriving)
        #expect(theme.colors.dimensionReference == dracula.dimensionReference)
        #expect(theme.colors.dimensionDriving == HexColor(0x8be9fd) && theme.colors.dimensionReference == HexColor(0x6272a4))
    }
}
