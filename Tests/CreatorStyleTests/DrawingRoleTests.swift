import CreatorStyle
import Foundation
import Testing

/// The drawing sheet's three theme roles (drawings spec): paper, ink and the highlight, last in their own group.
struct DrawingRoleTests {
    @Test func theDrawingRolesAreFixed() {
        #expect(ThemeRole.all.suffix(3).map(\.name) == ["drawingPaper", "drawingInk", "drawingHighlight"])
        #expect(ThemeRole.all.suffix(3).map(\.title) == ["Paper", "Ink", "Highlight"])
        #expect(ThemeRole.all.suffix(3).allSatisfy { $0.group == .drawing })
        #expect(ThemeRoleGroup.drawing.title == "Drawing")
        #expect(ThemeRoleGroup.allCases.last == .drawing)
        for theme in [ColorTheme.dracula, .alucard, .nord] {
            #expect(theme.colors.drawingPaper == HexColor(0xffffff))
            #expect(theme.colors.drawingInk == HexColor(0x000000))
            #expect(theme.colors.drawingHighlight == HexColor(0x1f6feb))
        }
    }

    @Test func aThemeFileWithoutThemReadsTheDefaults() throws {
        let file = Data(##"{"version":1,"name":"Old","dark":true,"colors":{"accent":"#112233"}}"##.utf8)
        let theme = try ThemeFile.decode(file, id: "old", fallbackName: "Old")
        let dracula = ColorTheme.dracula.colors.quantized
        #expect(theme.colors.drawingPaper == dracula.drawingPaper)
        #expect(theme.colors.drawingInk == dracula.drawingInk)
        #expect(theme.colors.drawingHighlight == dracula.drawingHighlight)
    }
}
