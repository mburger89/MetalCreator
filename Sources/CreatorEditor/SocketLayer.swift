import CreatorGeometry
import CreatorStyle
import MetalUI

/// A node's socket dots, coloured by type, placed by `NodeLayout` for the current flow.
struct SocketLayer: Component {
    let shape: NodeShape
    let flow: CanvasFlow
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let size = NodeLayout.size(shape)
        let dots = Self.dots(shape: shape, flow: flow, palette: palette)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: size.x.px, height: size.y.px)
            ForEach(dots, id: \.id) { dot in
                Circle()
                    .fill(dot.color.color)
                    .frame(width: (2 * NodeLayout.socketRadius).px, height: (2 * NodeLayout.socketRadius).px)
                    .overlay { Circle().strokeBorder(palette.panelBase.color, lineWidth: Pixels(1.5)) }
                    .offset(x: (dot.centre.x - NodeLayout.socketRadius).px, y: (dot.centre.y - NodeLayout.socketRadius).px)
            }
        }
    }

    struct Dot: Identifiable {
        var id: String
        var centre: Vector2
        var color: HexColor
    }

    static func dots(shape: NodeShape, flow: CanvasFlow, palette: Palette) -> [Dot] {
        var dots: [Dot] = []
        for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
            for socket in sockets {
                guard let centre = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                let color = socket.type.map(palette.socket) ?? palette.secondaryText
                dots.append(Dot(id: (isInput ? "in." : "out.") + socket.name.rawValue, centre: centre, color: color))
            }
        }
        return dots
    }
}
