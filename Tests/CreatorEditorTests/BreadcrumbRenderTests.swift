import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// The header's breadcrumbs draw one label per level (groups spec §6).
@MainActor
struct BreadcrumbRenderTests {
    @Test func theHeaderGrowsALabelAndASeparatorPerLevelEntered() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let top = renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count
        editor.enterGroup(grouped.group)
        let inside = renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count
        #expect(inside > top, "Group and › join Graph")
        editor.exitGroup()
        #expect(renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count == top)
    }

    @Test func nestedLevelsAllShow() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let oneDeep = renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        editor.enterGroup(try #require(editor.selection.first))
        #expect(renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count > oneDeep)
        #expect(editor.breadcrumbs.map(\.title) == ["Graph", "Group", "Group 2"])
    }
}
