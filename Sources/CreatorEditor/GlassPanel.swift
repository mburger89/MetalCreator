import MetalUI

/// Glass chrome for floating panels (spec §6.1, §6.6): `#21222c` at 86%, a 1-pt `#ffffff1f`
/// hairline and rounded corners. The background blur is a MetalUI gap (materials and `.blur`
/// are not offered; docs/metalui-gaps.md), so the panel is translucent without blur.
struct GlassPanel<Body: ElementGroup>: Component {
    let body: Body

    init(@ElementBuilder _ body: () -> Body) {
        self.body = body()
    }

    var content: some ElementGroup {
        let shape = RoundedRectangle(cornerRadius: Pixels(10))
        return ZStack(alignment: .topLeading) { body }
            .padding(Edges(all: Pixels(10)))
            .background(Palette.glass.color, in: shape)
            .overlay { shape.strokeBorder(Palette.hairline.color, lineWidth: Pixels(1)) }
    }
}
