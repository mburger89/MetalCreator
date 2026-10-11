import CreatorGeometry
import CreatorStyle
import MetalUI

/// A node's socket dots, coloured by type, placed by `NodeLayout` for the current flow.
struct SocketLayer: Component {
    let shape: NodeShape
    let flow: CanvasFlow
    /// Tooltips by dot ID ("in.tree", "out.values"): the shape of a tree on the socket (`EditorModel.socketHelp(of:)`).
    var help: [String: String] = [:]
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let size = NodeLayout.size(shape)
        let dots = Self.dots(shape: shape, flow: flow, palette: palette, help: help)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: size.x.px, height: size.y.px)
            ForEach(dots, id: \.id) { dot in
                // `.help` takes any string, so an empty one would still raise an empty bubble: attach it only with text.
                if let text = dot.help {
                    ZStack { SocketDotView(dot: dot, palette: palette) }.offset(x: dot.corner.x.px, y: dot.corner.y.px).help(text)
                } else {
                    ZStack { SocketDotView(dot: dot, palette: palette) }.offset(x: dot.corner.x.px, y: dot.corner.y.px)
                }
            }
        }
    }

    struct Dot: Identifiable {
        var id: String
        var centre: Vector2
        var color: HexColor
        /// The tooltip, or `nil` for a dot with none (most of them).
        var help: String?

        /// Where the dot's top left corner is.
        var corner: Vector2 { Vector2(centre.x - NodeLayout.socketRadius, centre.y - NodeLayout.socketRadius) }
    }

    static func dots(shape: NodeShape, flow: CanvasFlow, palette: Palette, help: [String: String] = [:]) -> [Dot] {
        var dots: [Dot] = []
        for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
            for socket in sockets {
                guard let centre = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                let color = socket.type.map(palette.socket) ?? palette.secondaryText
                let id = (isInput ? "in." : "out.") + socket.name.rawValue
                dots.append(Dot(id: id, centre: centre, color: color, help: help[id]))
            }
        }
        return dots
    }
}
