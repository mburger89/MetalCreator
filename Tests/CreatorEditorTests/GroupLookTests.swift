import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// How group nodes and the boundary nodes look (groups spec §6): the definition's name and accent, a doubled border,
/// and the "+" socket.
@MainActor
struct GroupLookTests {
    @Test func aGroupNodeIsTitledAfterItsDefinitionAndCarriesItsAccent() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let node = try #require(editor.graph.nodes[grouped.group])
        let shape = editor.shape(of: node)
        #expect(shape.title == "Group" && shape.isGroup && shape.accent == .purple)
        try editor.document.perform(GroupCommands.rename(grouped.definition.id, to: "Rib", in: editor.document.content))
        try editor.document.perform(GroupCommands.setAccent(grouped.definition.id, .green, in: editor.document.content))
        let renamed = editor.shape(of: try #require(editor.graph.nodes[grouped.group]))
        #expect(renamed.title == "Rib" && renamed.accent == .green)
        var node2 = try #require(editor.graph.nodes[grouped.group])
        node2.name = "Something else"
        #expect(editor.shape(of: node2).title == "Rib", "the header is the definition's name")
    }

    @Test func otherNodesAreNotGroupsAndHaveNoAccent() throws {
        let grouped = try GroupedEditor()
        let shape = grouped.editor.shape(of: try #require(grouped.editor.graph.nodes[grouped.number.id]))
        #expect(!shape.isGroup && shape.accent == nil)
    }

    @Test func groupInputAndOutputEndWithAPlusSocket() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let input = editor.shape(of: try #require(grouped.definition.inputNode))
        let output = editor.shape(of: try #require(grouped.definition.outputNode))
        #expect(input.outputs.map(\.name) == ["width", "+"] && input.inputs.isEmpty)
        #expect(output.inputs.map(\.name) == ["solid", "+"] && output.outputs.isEmpty)
        #expect(input.outputs.last?.type == nil && output.inputs.last?.type == nil)
        #expect(input.accent == .purple && !input.isGroup && input.title == "Group Input")
        #expect(NodeLayout.size(output).y > NodeLayout.size(NodeShape(title: "x", category: .value, inputs: [output.inputs[0]],
                                                                     outputs: [])).y, "the + takes a row")
        let rows = NodeRowModel.rows(for: try #require(grouped.definition.outputNode), shape: output, graph: editor.graph,
                                     registry: editor.registry)
        #expect(rows.map(\.label) == ["Solid", "+"])
    }

    @Test func eachAccentRoleIsItsOwnColourInEveryTheme() {
        for theme in [ColorTheme.dracula, .alucard, .nord] {
            let palette = Palette(theme)
            #expect(Set(AccentRole.allCases.map { palette.accent($0) }).count == AccentRole.allCases.count, "\(theme.name)")
        }
        #expect(Palette.dracula.accent(.purple) != Palette(.alucard).accent(.purple), "it follows the theme")
    }

    func ringCount(_ scene: Scene) -> Int {
        scene.rects.filter { $0.borderColor.a > 0 && $0.borderWidths.top > 0 }.count
    }

    @Test func aGroupNodeDrawsADoubledBorderInItsAccent() {
        func draw(isGroup: Bool, accent: AccentRole?) -> Scene {
            let shape = NodeShape(title: "Rib", category: .feature, inputs: [], outputs: [], accent: accent, isGroup: isGroup)
            return renderHeadless {
                NodeView(shape: shape, rows: [], origin: Vector2(100, 100), flow: .horizontal, isSelected: false, state: nil,
                         shakes: 0)
            }
        }
        let plain = draw(isGroup: false, accent: nil), group = draw(isGroup: true, accent: .purple)
        #expect(ringCount(group) == ringCount(plain) + 1, "the inner ring")
        // The header is the 24-point strip (48 pixels at the frame's scale of 2) filled in the accent.
        func hue(_ accent: AccentRole) -> Float? {
            draw(isGroup: true, accent: accent).rects
                .first { $0.bounds.size.height == Float(NodeLayout.headerHeight * 2) }?.background.h
        }
        #expect(hue(.purple) != nil && hue(.purple) != hue(.green), "the header takes the accent")
    }

    @Test func theCanvasTitlesAGroupNodeAfterItsDefinitionAndFollowsTheLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let input = GraphPanelInput(model: editor)
        func glyphs() -> Int { renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count }
        let top = glyphs()
        try editor.document.perform(GroupCommands.rename(grouped.definition.id, to: "Hole pattern for ribs",
                                                         in: editor.document.content))
        let renamed = glyphs()
        #expect(renamed > top, "the group node's header reads the definition's name")
        editor.enterGroup(grouped.group)
        #expect(glyphs() != renamed, "the canvas draws the inside, not the top level")
    }
}
