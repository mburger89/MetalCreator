import CreatorStyle
import Foundation
import Testing

/// The field preview's ramp (fields spec §6, D13): three theme roles, not a fixed palette.
struct FieldRampRoleTests {
    @Test func theThreeRolesShareOneGroupAheadOfTheDimensionRoles() {
        let names = ThemeRole.all.dropLast(5).suffix(3).map(\.name)
        #expect(names == ["fieldLow", "fieldMid", "fieldHigh"])
        #expect(ThemeRoleGroup.fieldPreview.roles.map(\.name) == names)
        #expect(ThemeRoleGroup.fieldPreview.title == "Field preview")
        #expect(ThemeRoleGroup.allCases.dropLast(2).last == .fieldPreview)
        #expect(ThemeRole.named("fieldMid")?.title == "Field middle")
        #expect(ThemeRole.all.dropLast(5).suffix(3).allSatisfy { !$0.allowsOpacity })
    }

    @Test(arguments: ColorTheme.builtIns)
    func everyBuiltInGivesThreeDistinctRampColours(_ theme: ColorTheme) {
        let colours = [theme.colors.fieldLow, theme.colors.fieldMid, theme.colors.fieldHigh]
        #expect(Set(colours).count == 3, "\(theme.name): a ramp of two equal colours shows nothing")
        #expect(colours.allSatisfy { $0.opacity == 1 })
    }

    @Test func draculasRampRunsCoolToWarm() {
        let colors = ColorTheme.dracula.colors
        #expect(colors.fieldLow == HexColor(0x8be9fd) && colors.fieldMid == HexColor(0xf1fa8c) && colors.fieldHigh == HexColor(0xff5555))
    }

    @Test func aThemeFileWithoutTheRolesReadsDraculasValues() throws {
        let file = Data(##"{"version":1,"name":"Old","dark":true,"colors":{"accent":"#112233"}}"##.utf8)
        let theme = try ThemeFile.decode(file, id: "old", fallbackName: "Old")
        let dracula = ColorTheme.dracula.colors.quantized
        #expect(theme.colors.accent == HexColor(0x112233))
        #expect(theme.colors.fieldLow == dracula.fieldLow && theme.colors.fieldMid == dracula.fieldMid)
        #expect(theme.colors.fieldHigh == dracula.fieldHigh)
    }

    @Test func aThemeFileKeepsTheRolesItHolds() throws {
        var custom = ColorTheme.nord
        custom.colors.fieldLow = HexColor(0x010203)
        custom.colors.fieldHigh = HexColor(0xa0b0c0)
        let bytes = try ThemeFile.encode(custom)
        #expect(String(bytes: bytes, encoding: .utf8)?.contains("\"fieldLow\"") == true)
        let back = try ThemeFile.decode(bytes, id: "custom", fallbackName: "x")
        #expect(back.colors.fieldLow == HexColor(0x010203) && back.colors.fieldHigh == HexColor(0xa0b0c0))
        #expect(back.colors.fieldMid == ColorTheme.nord.colors.fieldMid.quantized)
    }
}
