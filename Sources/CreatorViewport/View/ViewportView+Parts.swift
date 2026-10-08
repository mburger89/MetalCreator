import MetalUI

extension ViewportView {
    /// The surface, its labels and the view cube's controls. The label loops are written inline: MetalUI's builder
    /// can't infer an opaque element returned by a helper inside a `for` (docs/metalui-gaps.md gap M4-b).
    @MainActor
    static func stack(model: ViewportModel, modifiers: ViewportModifierTracker) -> some Element {
        ZStack(alignment: .topLeading) {
            surface(model: model, modifiers: modifiers)
            for label in model.cubeLabels() {
                ProposalText(label.text)
                    .foregroundStyle(ViewportPalette.labelColor)
                    .font(.caption)
                    .frame(width: Pixels(64), height: Pixels(18))
                    .offset(x: Pixels(Float(label.position.x - 32)), y: Pixels(Float(label.position.y - 9)))
                    .allowsHitTesting(false)
            }
            for label in model.handleLabels() {
                ProposalText(label.text)
                    .foregroundStyle(ViewportPalette.labelColor)
                    .font(.caption)
                    .frame(width: Pixels(96), height: Pixels(18), alignment: .leading)
                    .offset(x: Pixels(Float(label.position.x)), y: Pixels(Float(label.position.y - 9)))
                    .allowsHitTesting(false)
            }
            cubeControls(model: model)
        }
        .overlay(alignment: .bottomLeading) {
            triadLabels(model: model)
        }
        .overlay(alignment: .bottomTrailing) {
            ProposalText(model.gridLabel)
                .foregroundStyle(ViewportPalette.hintColor)
                .font(.caption)
                .padding(Edges(all: Pixels(12)))
                .allowsHitTesting(false)
        }
    }

    /// The GPU surface and its input. It redraws on demand when `renderKey` changes, and continuously while the
    /// camera animates. One zero-distance drag carries every press: MetalUI reports a click as a change plus an end.
    @MainActor
    static func surface(model: ViewportModel, modifiers: ViewportModifierTracker) -> some Element {
        MetalView(redraw: model.isAnimating ? .continuous : .onDemand, value: model.renderKey) { context in
            model.draw(context)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !model.isPointerDown {
                        model.pointerDown(at: ScreenPoint(value.startLocation), modifiers: modifiers.held)
                    }
                    model.pointerDragged(to: ScreenPoint(value.location))
                }
                .onEnded { value in
                    if !model.isPointerDown {
                        model.pointerDown(at: ScreenPoint(value.startLocation), modifiers: modifiers.held)
                    }
                    model.pointerUp(at: ScreenPoint(value.location))
                }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): model.pointerHovered(at: ScreenPoint(point))
            case .ended: model.pointerHovered(at: nil)
            }
        }
        .contextMenu {
            for item in model.contextMenuItems() {
                Button(item.title) { model.choose(item) }
            }
        }
    }

    /// Triad axis names in a widget-sized box at the bottom-left, matching where the renderer draws the triad.
    @MainActor
    static func triadLabels(model: ViewportModel) -> some Element {
        ZStack(alignment: .topLeading) {
            for label in model.triadLabels() {
                ProposalText(label.text)
                    .foregroundStyle(ViewportPalette.labelColor)
                    .font(.caption)
                    .frame(width: Pixels(16), height: Pixels(18))
                    .offset(x: Pixels(Float(label.position.x - 8)), y: Pixels(Float(label.position.y - 9)))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Pixels(Float(model.triadLayout.side)), height: Pixels(Float(model.triadLayout.side)),
               alignment: .topLeading)
        .padding(Edges(all: Pixels(Float(model.triadLayout.inset))))
        .allowsHitTesting(false)
    }

    /// The view cube's arrow and home buttons, and its View menu (spec §6.3: projection, shading and home view),
    /// just below the cube.
    @MainActor
    static func cubeControls(model: ViewportModel) -> some Element {
        VStack(alignment: .leading, spacing: Pixels(4)) {
            HStack(spacing: Pixels(4)) {
                Button("◀") { model.perform(.rotate(.left)) }
                    .help("Rotate to the face on the left")
                Button("▲") { model.perform(.rotate(.up)) }
                    .help("Rotate to the face above")
                Button("▼") { model.perform(.rotate(.down)) }
                    .help("Rotate to the face below")
                Button("▶") { model.perform(.rotate(.right)) }
                    .help("Rotate to the face on the right")
                Button("⌂") { model.perform(.home) }
                    .help("Home view")
            }
            Menu("View") {
                Button("Perspective") { model.perform(.projection(.perspective)) }
                Button("Orthographic") { model.perform(.projection(.orthographic)) }
                Divider()
                for mode in ShadingMode.allCases {
                    Button(mode.title) { model.perform(.shading(mode)) }
                }
                Divider()
                Button("Set Home View") { model.perform(.setHome) }
            }
        }
        .offset(x: Pixels(Float(model.cubeLayout.origin.x)),
                y: Pixels(Float(model.cubeLayout.origin.y + model.cubeLayout.side + 6)))
    }
}
