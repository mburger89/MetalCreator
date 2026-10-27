import CreatorGeometry
import CreatorGraph
import CreatorStyle
import MetalUI

/// Everything drawn under the canvas transform, back to front: comment frames, wires, cable tie bands, notes, nodes (the
/// selected last within each kind), ⌥-drag ghosts, the wire being dragged and the box selection (cable ties spec 2026-10-26
/// §5.1). Positions are display canvas
/// points; the parent applies zoom and pan as render effects. Nodes, comments and wires that can't show aren't built
/// (`EditorModel.drawnNodes`, `drawnNotes`, `drawnFrames`, `drawnCanvasRect`), nor nodes' rows while zoomed out
/// (`drawsNodeRows`). Nodes, comments and ghosts are keyed by their whole UUID: MetalUI's `ForEach` names an element
/// by its id's description and drops a repeat (`DD-L`, gap M7-a), and a `NodeID` prints only 8 hex digits.
struct CanvasLayers: Component {
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
    /// Reduce Motion (MetalUI's `accessibilityReduceMotion`). The canvas passes it to the model, which then never lets a wire
    /// go slack (cable ties spec §5.2).
    @Environment(\.accessibilityReduceMotion) var reducesMotion: Bool

    var content: some ElementGroup {
        let flow = model.flow
        let palette = Palette(themes)
        let selectedComments = model.canvasSelection.comments
        let selectedTies = model.canvasSelection.ties
        let routing = model.wireRouting
        let commentGhosts = Self.commentGhosts(model)
        return ZStack(alignment: .topLeading) {
            ForEach(model.drawnFrames, id: \.id.rawValue) { box in
                CommentFrameView(box: box, rect: model.frame(of: box), isSelected: selectedComments.contains(box.id),
                                 palette: palette)
                    .equatable()
            }
            WireLayer(model: model, routing: routing, palette: palette,
                      animates: Self.animatesWires(model, reducesMotion: reducesMotion))
            ForEach(model.drawnTies(in: routing), id: \.id.rawValue) { layout in
                TieBandView(band: layout.band, isSelected: selectedTies.contains(layout.id), palette: palette).equatable()
            }
            ForEach(model.drawnNotes, id: \.id.rawValue) { note in
                StickyView(note: note, rect: model.frame(of: note), isSelected: selectedComments.contains(note.id),
                           palette: palette)
                    .equatable()
            }
            ForEach(model.drawnNodes, id: \.id.rawValue) { node in
                let shape = model.shape(of: node)
                NodeView(shape: shape,
                         rows: model.drawsNodeRows
                             ? NodeRowModel.rows(for: node, shape: shape, graph: model.graph, registry: model.registry) : [],
                         origin: model.displayOrigin(of: node), flow: flow,
                         isSelected: model.selection.contains(node.id),
                         state: StatusBadge.displayed(model.result(of: node.id)?.state),
                         shakes: model.shakeCount(of: node.id), palette: palette,
                         socketHelp: model.socketHelp(of: node.id))
                    .equatable()
            }
            ForEach(Self.ghosts(model), id: \.id.rawValue) { node in
                let shape = model.shape(of: node)
                NodeView(shape: shape, rows: [], origin: flow.display(node.position), flow: flow,
                         isSelected: true, state: nil, shakes: 0, palette: palette, isGhost: true)
                    .equatable()
            }
            ForEach(commentGhosts.frames, id: \.id.rawValue) { box in
                CommentFrameView(box: box, rect: model.frame(of: box), isSelected: true, palette: palette,
                                 isGhost: true)
                    .equatable()
            }
            ForEach(commentGhosts.notes, id: \.id.rawValue) { note in
                StickyView(note: note, rect: model.frame(of: note), isSelected: true, palette: palette, isGhost: true)
                    .equatable()
            }
            if case .connecting(let drag)? = model.interaction, let anchor = model.anchor(of: drag.from) {
                let geometry = drag.from.isInput
                    ? WireGeometry(from: drag.current, to: anchor, flow: flow)
                    : WireGeometry(from: anchor, to: drag.current, flow: flow)
                WireView(geometry: geometry, color: palette.focus).equatable()
            }
            if let box = model.selectionBox {
                BoxSelectionView(rect: box).equatable()
            }
        }
        .onChange(of: reducesMotion, initial: true) { _, reduces in model.reducesMotion = reduces }
    }

    /// Whether the wires are drawn inside a timeline: only while some wire is slack and Reduce Motion is off.
    static func animatesWires(_ model: EditorModel, reducesMotion: Bool) -> Bool {
        model.isWireMotionActive && !reducesMotion
    }

    struct Wire: Identifiable {
        var id: String
        var route: WireRoute
        var color: HexColor
        var lineWidth: Double
    }

    /// How wide a selected wire is drawn (cable ties spec §4.1).
    static let selectedLineWidth = 4.0

    /// Every wire whose two sockets are on the canvas and some of whose taut route can show (`drawnCanvasRect`), coloured
    /// by its source socket's type in `palette`, or wider in the selection colour when selected. `routing` is
    /// `model.wireRouting` when not given. With `motion`, each route is drawn with its slack; culling still reads the taut route.
    static func wires(_ model: EditorModel, routing: WireRouting? = nil, palette: Palette = .dracula,
                      motion: WireMotion? = nil) -> [Wire] {
        let drawn = model.drawnCanvasRect
        let routing = routing ?? model.wireRouting
        let selected = model.canvasSelection.wires
        return model.graph.links.compactMap { link in
            guard let taut = routing.routes[link.to], let source = model.graph.nodes[link.from.node] else { return nil }
            let isSelected = selected.contains(link.to)
            let width = isSelected ? selectedLineWidth : WireView.defaultLineWidth
            // WireView's frame: the route's bounds padded by twice its stroke.
            if let drawn, !drawn.intersects(taut.bounds(padding: 2 * width)) { return nil }
            let type = model.shape(of: source).outputs.first { $0.name == link.from.socket }?.type
            return Wire(id: "\(link.to.node.rawValue.uuidString).\(link.to.socket.rawValue)",
                        route: motion?.drawn(taut) ?? taut,
                        color: isSelected ? palette.selection : type.map(palette.socket) ?? palette.secondaryText,
                        lineWidth: width)
        }
    }

    /// The ⌥-drag ghosts: copies of the dragged nodes at their would-be positions.
    static func ghosts(_ model: EditorModel) -> [Node] {
        guard case .duplicating(let start, let delta)? = model.interaction else { return [] }
        return start.nodes.keys.sorted().compactMap { id in
            guard var node = model.graph.nodes[id], let position = start.nodes[id] else { return nil }
            node.position = position + delta
            return node
        }
    }

    /// The ⌥-drag ghosts of the dragged comments: copies at their would-be positions.
    static func commentGhosts(_ model: EditorModel) -> (notes: [StickyNote], frames: [CommentFrame]) {
        guard case .duplicating(let start, let delta)? = model.interaction else { return ([], []) }
        let ids = start.comments.keys.sorted()
        let notes = ids.compactMap { id -> StickyNote? in
            guard var note = model.graph.stickies[id], let origin = start.comments[id] else { return nil }
            note.frame.origin = origin + delta
            return note
        }
        let frames = ids.compactMap { id -> CommentFrame? in
            guard var box = model.graph.frames[id], let origin = start.comments[id] else { return nil }
            box.frame.origin = origin + delta
            return box
        }
        return (notes, frames)
    }
}
