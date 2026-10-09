import MetalUI

extension ViewportView {
    /// The surface, the handle labels and the view cube's controls (the renderer paints the cube's face names on
    /// it). The label loop is written inline: MetalUI's builder can't infer an opaque element returned by a helper
    /// inside a `for` (docs/metalui-gaps.md gap M4-b).
    @MainActor
    static func stack(model: ViewportModel) -> some Element {
        ZStack(alignment: .topLeading) {
            surface(model: model)
            for label in model.handleLabels() {
                ProposalText(label.text)
                    .foregroundStyle(model.labelColor)
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
                .foregroundStyle(model.hintColor)
                .font(.caption)
                .padding(Edges(top: Pixels(0), right: Pixels(Float(model.modelArea.trailing + 12)),
                               bottom: Pixels(Float(model.modelArea.bottom + 12)), left: Pixels(0)))
                .allowsHitTesting(false)
        }
    }

    /// The GPU surface and its input. It redraws on demand when `renderKey` changes, and continuously while the
    /// camera animates. A zero-distance primary drag carries every primary press: MetalUI reports a click as a
    /// change plus an end. The right and middle buttons drag in their own arenas (MetalUI `CI-F`).
    @MainActor
    static func surface(model: ViewportModel) -> some Element {
        MetalView(redraw: model.isAnimating ? .continuous : .onDemand, value: model.renderKey) { context in
            model.draw(context)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(drag(.primary, minimumDistance: 0, model: model))
        .gesture(drag(.secondary, minimumDistance: ViewportInputMap.dragThreshold, model: model))
        .gesture(drag(.middle, minimumDistance: ViewportInputMap.dragThreshold, model: model))
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

    /// A drag with `button` that reports its values, and the modifiers held at each, to the model.
    @MainActor
    static func drag(_ button: ViewportPointerButton, minimumDistance: Double, model: ViewportModel) -> DragGesture {
        DragGesture(minimumDistance: Pixels(Float(minimumDistance)), button: button.mouseButton)
            .onChanged { value in
                model.dragChanged(from: ScreenPoint(value.startLocation), to: ScreenPoint(value.location),
                                  modifiers: ViewportModifiers(value.modifiers), button: button)
            }
            .onEnded { value in
                model.dragEnded(from: ScreenPoint(value.startLocation), at: ScreenPoint(value.location),
                                modifiers: ViewportModifiers(value.modifiers), button: button)
            }
    }

    /// Triad axis names in a widget-sized box at the bottom-left, matching where the renderer draws the triad.
    @MainActor
    static func triadLabels(model: ViewportModel) -> some Element {
        ZStack(alignment: .topLeading) {
            for label in model.triadLabels() {
                ProposalText(label.text)
                    .foregroundStyle(model.labelColor)
                    .font(.caption)
                    .frame(width: Pixels(16), height: Pixels(18))
                    .offset(x: Pixels(Float(label.position.x - 8)), y: Pixels(Float(label.position.y - 9)))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Pixels(Float(model.triadLayout.side)), height: Pixels(Float(model.triadLayout.side)),
               alignment: .topLeading)
        .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: Pixels(Float(model.triadLayout.bottom)),
                       left: Pixels(Float(model.triadLayout.leading))))
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
