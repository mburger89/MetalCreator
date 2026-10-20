import CreatorGeometry
import CreatorGraph
import CreatorStyle
import Testing
@testable import CreatorEditor

/// A node's views read no environment and no model: every input is a stored value, and `==` covers all of them, so
/// MetalUI's `.equatable()` (C14) can skip the content of the ones that did not change. Each test changes one
/// input of a view and expects it unequal; `expectEqualityCovers` fails when a view gains a property no variant names.
@MainActor
struct NodeViewEqualityTests {
    let shape = NodeShape(title: "Rib", category: .feature, inputs: [], outputs: [])
    let row = NodeRowModel(socket: "width", isInput: true, label: "Width", value: "10 mm")

    @Test func aNodeViewIsEqualOnlyWhenEveryInputIs() {
        func node(shape: NodeShape? = nil, rows: [NodeRowModel] = [], origin: Vector2 = .zero, flow: CanvasFlow = .horizontal,
                  isSelected: Bool = false, state: NodeState? = nil, shakes: Int = 0, palette: Palette = .dracula,
                  isGhost: Bool = false, socketHelp: [String: String] = [:]) -> NodeView {
            NodeView(shape: shape ?? self.shape, rows: rows, origin: origin, flow: flow, isSelected: isSelected, state: state,
                     shakes: shakes, palette: palette, isGhost: isGhost, socketHelp: socketHelp)
        }
        expectEqualityCovers(node(), equalTo: node(), [
            "shape": node(shape: NodeShape(title: "Rib", category: .solid, inputs: [], outputs: [])),
            "rows": node(rows: [row]),
            "origin": node(origin: Vector2(1, 0)),
            "flow": node(flow: .vertical),
            "isSelected": node(isSelected: true),
            "state": node(state: .evaluating),
            "shakes": node(shakes: 1),
            "palette": node(palette: Palette(.alucard)),
            "isGhost": node(isGhost: true),
            "socketHelp": node(socketHelp: ["in.tree": "3 items"]),
        ])
    }

    /// The box reads the theme from the environment, which MetalUI's environment epoch (C14-c) tracks; `==` is its rect.
    @Test func aBoxSelectionIsEqualOnlyWhenItsRectIs() {
        let rect = CanvasRect(origin: Vector2(1, 2), size: Vector2(30, 40))
        #expect(BoxSelectionView(rect: rect) == BoxSelectionView(rect: rect))
        #expect(BoxSelectionView(rect: rect) != BoxSelectionView(rect: CanvasRect(origin: Vector2(1, 2), size: Vector2(31, 40))))
        #expect(BoxSelectionView(rect: rect) != BoxSelectionView(rect: CanvasRect(origin: Vector2(2, 2), size: Vector2(30, 40))))
    }

    @Test func aHeaderIsEqualOnlyWhenEveryInputIs() {
        func header(title: String = "Rib", accent: HexColor = Palette.dracula.header(for: .feature), state: NodeState? = nil,
                    palette: Palette = .dracula) -> NodeHeaderView {
            NodeHeaderView(title: title, accent: accent, state: state, palette: palette)
        }
        expectEqualityCovers(header(), equalTo: header(), [
            "title": header(title: "Extrude"),
            "accent": header(accent: Palette.dracula.header(for: .solid)),
            "state": header(state: .error("No")),
            "palette": header(palette: Palette(.alucard)),
        ])
    }

    @Test func aRowIsEqualOnlyWhenEveryInputIs() {
        var moved = row
        moved.value = "12 mm"
        expectEqualityCovers(NodeRowView(row: row, palette: .dracula), equalTo: NodeRowView(row: row, palette: .dracula), [
            "row": NodeRowView(row: moved, palette: .dracula),
            "palette": NodeRowView(row: row, palette: Palette(.alucard)),
        ])
    }

    @Test func aBadgeIsEqualOnlyWhenEveryInputIs() {
        expectEqualityCovers(StatusBadgeView(state: nil, palette: .dracula), equalTo: StatusBadgeView(state: nil, palette: .dracula), [
            "state": StatusBadgeView(state: .evaluating, palette: .dracula),
            "palette": StatusBadgeView(state: nil, palette: Palette(.alucard)),
        ])
    }

    @Test func aSocketLayerIsEqualOnlyWhenEveryInputIs() {
        func layer(shape: NodeShape? = nil, flow: CanvasFlow = .horizontal, palette: Palette = .dracula,
                   help: [String: String] = [:]) -> SocketLayer {
            SocketLayer(shape: shape ?? self.shape, flow: flow, palette: palette, help: help)
        }
        expectEqualityCovers(layer(), equalTo: layer(), [
            "shape": layer(shape: NodeShape(title: "Rib", category: .solid, inputs: [], outputs: [])),
            "flow": layer(flow: .vertical),
            "palette": layer(palette: Palette(.alucard)),
            "help": layer(help: ["out.solid": "1 solid"]),
        ])
    }
}
