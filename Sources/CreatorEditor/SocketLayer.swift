import CreatorGeometry
import CreatorStyle
import MetalUI

/// A node's socket dots, coloured by type, placed by `NodeLayout` for the current flow.
struct SocketLayer: Component, Equatable {
    let shape: NodeShape
    let flow: CanvasFlow
    let palette: Palette

    var content: some ElementGroup {
        let size = NodeLayout.size(shape)
        let dots = Self.dots(shape: shape, flow: flow, palette: palette)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: size.x.px, height: size.y.px)
            ForEach(dots, id: \.id) { dot in
                ZStack { SocketDotView(dot: dot, palette: palette) }.offset(x: dot.corner.x.px, y: dot.corner.y.px)
            }
        }
    }

    struct Dot: Identifiable {
        var id: String
        var centre: Vector2
        var color: HexColor

        /// Where the dot's top left corner is.
        var corner: Vector2 { Vector2(centre.x - NodeLayout.socketRadius, centre.y - NodeLayout.socketRadius) }
    }

    static func dots(shape: NodeShape, flow: CanvasFlow, palette: Palette) -> [Dot] {
        var dots: [Dot] = []
        for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
            for socket in sockets {
                guard let centre = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                let color = socket.type.map(palette.socket) ?? palette.secondaryText
                let id = (isInput ? "in." : "out.") + socket.name.rawValue
                dots.append(Dot(id: id, centre: centre, color: color))
            }
        }
        return dots
    }
}
