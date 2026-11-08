import CreatorGraph
import CreatorNodes
import CreatorStyle
import CreatorViewport
import MetalUI
import Testing
@testable import CreatorEditor

/// No label or title clips on the canvas (display findings 2 and 4): `NodeLayout` computes the node's width, so the width is
/// held to the text of every built-in node, measured and drawn.
@MainActor
struct NodeFitTests {
    let palette = Palette.dracula

    func glyphs<Content: ElementGroup>(_ content: Content, width: Double) -> [MUIGlyph] {
        renderFrame({ ZStack(alignment: .topLeading) { content } }, size: Size(width: Pixels(Float(width + 100)), height: Pixels(100)),
                    scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024)).glyphs
    }

    func shapes() -> [(type: any NodeDefinition.Type, node: Node, graph: Graph, shape: NodeShape)] {
        BuiltInNodes.registry.all.map { type in
            let node = BuiltInNodes.registry.makeNode(type.typeID)
            var graph = Graph()
            graph.nodes[node.id] = node
            return (type, node, graph, NodeShape(node, in: graph, registry: BuiltInNodes.registry))
        }
    }

    /// Every input row: the label, the value and the two gaps the row's spring leaves fit the body's width.
    @Test func everyBuiltInRowFits() throws {
        let measure = try TextMeasure.real()
        let room = NodeLayout.width - 20
        for (type, node, graph, shape) in shapes() {
            for row in NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: BuiltInNodes.registry) {
                let needed = measure(row.label).width + (row.value.map { measure($0).width + 12 } ?? 0)
                #expect(needed <= room, "\(type.displayName): \(row.label) \(row.value ?? "") needs \(needed) of \(room)")
            }
        }
    }

    /// A row's text is drawn whole at the node's width: one glyph per visible character, no ellipsis in place of some.
    @Test func aWideRowDrawsEveryCharacter() {
        let row = NodeRowModel(socket: "x", isInput: true, label: "Countersink diameter", value: "10 mm")
        let view = NodeRowView(row: row, palette: palette).frame(width: Pixels(Float(NodeLayout.width - 20)))
        let drawn = glyphs(view, width: NodeLayout.width)
        #expect(drawn.count == "Countersink diameter10 mm".filter { !$0.isWhitespace }.count)
    }

    /// The header keeps its title on one line beside the badge, whatever its length: a title too long for the width is cut with an
    /// ellipsis instead of wrapping to a second line (which the header's height clips).
    @Test func aLongTitleStaysOnOneLine() {
        let title = "A node title far too long to share the header with its badge"
        let header = NodeHeaderView(title: title, accent: palette.header(for: .solid), state: .ok(duration: .milliseconds(123)),
                                    palette: palette)
        let drawn = glyphs(header, width: NodeLayout.width)
        let top = drawn.map { Double($0.bounds.origin.y) / 2 }.min() ?? 0
        let bottom = drawn.map { Double($0.bounds.origin.y + $0.bounds.size.height) / 2 }.max() ?? 0
        #expect(!drawn.isEmpty && bottom - top < 20, "one line, a second would stand 14 points lower: \(bottom - top)")
    }

    /// Every built-in title is drawn whole beside the typical badge ("123 ms").
    @Test func everyBuiltInTitleFitsBesideItsBadge() {
        for (type, _, _, shape) in shapes() {
            let header = NodeHeaderView(title: shape.title, accent: palette.header(for: .solid),
                                        state: .ok(duration: .milliseconds(123)), palette: palette)
            let drawn = glyphs(header, width: NodeLayout.width).count
            #expect(drawn == (shape.title + "123 ms").filter { !$0.isWhitespace }.count, "\(type.displayName) is cut")
        }
    }
}
