import CreatorStyle
import Foundation
import Testing

/// The section cap's three theme roles (section spec part B): the cap's fill, its hatch lines and the outline.
struct SectionRoleTests {
    @Test func theSectionRolesAreLastInTheirOwnGroup() {
        #expect(ThemeRole.all.suffix(3).map(\.name) == ["sectionFill", "sectionHatch", "sectionEdge"])
        #expect(ThemeRole.all.suffix(3).allSatisfy { $0.group == .section })
        #expect(ThemeRoleGroup.section.title == "Section")
        #expect(ThemeRoleGroup.allCases.last == .section)
        #expect(ThemeRole.all.suffix(3).map(\.title) == ["Section fill", "Section hatch", "Section edge"])
    }

    @Test func aThemeFileWithoutTheSectionRolesReadsDraculas() throws {
        let file = Data(##"{"version":1,"name":"Old","dark":true,"colors":{"accent":"#112233"}}"##.utf8)
        let theme = try ThemeFile.decode(file, id: "old", fallbackName: "Old")
        let dracula = ColorTheme.dracula.colors.quantized
        #expect(theme.colors.sectionFill == dracula.sectionFill)
        #expect(theme.colors.sectionHatch == dracula.sectionHatch)
        #expect(theme.colors.sectionEdge == dracula.sectionEdge)
    }

    @Test func eachBuiltInHasTheTabledColours() {
        let table: [(ColorTheme, UInt32, UInt32, UInt32)] = [
            (.dracula, 0xbd93f9, 0x282a36, 0xf8f8f2),
            (.alucard, 0x644ac9, 0xfffbeb, 0x1f1f1f),
            (.nord, 0x81a1c1, 0x2e3440, 0xeceff4),
        ]
        for (theme, fill, hatch, edge) in table {
            #expect(theme.colors.sectionFill == HexColor(fill))
            #expect(theme.colors.sectionHatch == HexColor(hatch))
            #expect(theme.colors.sectionEdge == HexColor(edge))
        }
    }
}
