import CreatorGeometry
import CreatorGraph
import CreatorStyle
import MetalUI

/// Everything drawn under the canvas transform, back to front: wires, nodes, ⌥-drag ghosts, the
/// wire being dragged and the box selection. Positions are display canvas points; the parent
/// applies zoom and pan as render effects.
struct CanvasLayers: Component {
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let flow = model.flow
        let palette = Palette(themes)
        return ZStack(alignment: .topLeading) {
            ForEach(Self.wires(model, palette: palette), id: \.id) { wire in
                WireView(geometry: wire.geometry, color: wire.color)
            }
            ForEach(model.drawOrder, id: \.id) { node in
                let shape = model.shape(of: node)
                NodeView(shape: shape,
                         rows: NodeRowModel.rows(for: node, shape: shape, graph: model.graph, registry: model.registry),
                         origin: model.displayOrigin(of: node), flow: flow,
                         isSelected: model.selection.contains(node.id),
                         state: model.document.results[node.id]?.state,
                         shake: model.isShaking && model.refusal?.node == node.id ? 6 : 0)
            }
            ForEach(Self.ghosts(model), id: \.id) { node in
                let shape = model.shape(of: node)
                NodeView(shape: shape, rows: [], origin: flow.display(node.position), flow: flow,
                         isSelected: true, state: nil, shake: 0, isGhost: true)
            }
            if case .connecting(let drag)? = model.interaction, let anchor = model.anchor(of: drag.from) {
                let geometry = drag.from.isInput
                    ? WireGeometry(from: drag.current, to: anchor, flow: flow)
                    : WireGeometry(from: anchor, to: drag.current, flow: flow)
                WireView(geometry: geometry, color: palette.focus)
            }
            if case .boxSelecting(let start, let current, _)? = model.interaction {
                BoxSelectionView(rect: CanvasRect(corner: start, current))
            }
        }
    }

    struct Wire: Identifiable {
        var id: String
        var geometry: WireGeometry
        var color: HexColor
    }

    /// Every wire whose two sockets are on the canvas, coloured by its source socket's type in `palette`.
    static func wires(_ model: EditorModel, palette: Palette = .dracula) -> [Wire] {
        model.graph.links.compactMap { link in
            let from = SocketRef(link.from, isInput: false), to = SocketRef(link.to, isInput: true)
            guard let start = model.anchor(of: from), let end = model.anchor(of: to),
                  let source = model.graph.nodes[link.from.node] else { return nil }
            let type = model.shape(of: source).outputs.first { $0.name == link.from.socket }?.type
            return Wire(id: "\(link.to.node.rawValue.uuidString).\(link.to.socket.rawValue)",
                        geometry: WireGeometry(from: start, to: end, flow: model.flow),
                        color: type.map(palette.socket) ?? palette.secondaryText)
        }
    }

    /// The ⌥-drag ghosts: copies of the dragged nodes at their would-be positions.
    static func ghosts(_ model: EditorModel) -> [Node] {
        guard case .duplicating(let start, let delta)? = model.interaction else { return [] }
        return start.keys.sorted().compactMap { id in
            guard var node = model.graph.nodes[id], let position = start[id] else { return nil }
            node.position = position + delta
            return node
        }
    }
}
