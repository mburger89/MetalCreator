import CreatorGeometry
import CreatorGraph
import CreatorStyle
import MetalUI

/// One node on the canvas (spec §6.2): a header in its category colour with the name and status
/// badge, then a row per input (with its value when unwired) and per output. Sized by
/// `NodeLayout` so drawing and hit testing agree; input is handled by the canvas, not here.
struct NodeView: Component {
    let shape: NodeShape
    let rows: [NodeRowModel]
    let origin: Vector2
    let flow: CanvasFlow
    let isSelected: Bool
    let state: NodeState?
    /// Horizontal offset while the node shakes after a refused wire; it springs back to 0.
    let shake: Double
    /// Drawn at reduced opacity: an ⌥-drag ghost.
    var isGhost = false
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let size = NodeLayout.size(shape)
        let palette = Palette(themes)
        let accent = shape.accent.map(palette.accent) ?? palette.header(for: shape.category)
        let corner = RoundedRectangle(cornerRadius: Pixels(6))
        return VStack(alignment: .leading, spacing: Pixels(0)) {
            NodeHeaderView(title: shape.isMissing ? "Missing: \(shape.title)" : shape.title, accent: accent, state: state)
            VStack(alignment: .leading, spacing: Pixels(0)) {
                ForEach(rows, id: \.id) { row in
                    NodeRowView(row: row)
                }
            }
            .padding(Edges(top: NodeLayout.bodyPadding.px, right: Pixels(10),
                           bottom: NodeLayout.bodyPadding.px, left: Pixels(10)))
        }
        .frame(width: size.x.px, height: size.y.px, alignment: .topLeading)
        .background(palette.nodeBody.color, in: corner)
        .clipShape(corner)
        .overlay {
            // A group node's border is doubled, both rings in its accent: an outer one and a thin inner one.
            corner.strokeBorder(shape.isGroup || isSelected ? accent.color : palette.hairline.color,
                                lineWidth: Pixels(shape.isGroup ? (isSelected ? 3 : 2) : (isSelected ? 2 : 1)))
        }
        .overlay {
            if shape.isGroup {
                RoundedRectangle(cornerRadius: Pixels(3)).strokeBorder(accent.color, lineWidth: Pixels(1))
                    .padding(Edges(all: Pixels(4)))
            }
        }
        .overlay(alignment: .topLeading) {
            // A Component is legacy content; inside a ZStack it is adopted, so the result stays
            // proposal content and takes the modifiers below.
            ZStack(alignment: .topLeading) { SocketLayer(shape: shape, flow: flow) }
        }
        .opacity(isGhost ? 0.4 : 1)
        .offset(x: (origin.x + shake).px, y: origin.y.px)
        // Only a change of `shake` animates, so dragging and panning stay immediate. The bouncy
        // spring back to 0 is the "brief shake" (spec §6.2); MetalUI has no keyframes.
        .animation(.spring(duration: 0.35, bounce: 0.7), value: shake)
    }
}
