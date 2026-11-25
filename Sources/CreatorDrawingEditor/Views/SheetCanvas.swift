import CreatorDrawing
import CreatorGeometry
import CreatorStyle
import MetalUI

/// The drawing sheet (plan R12, R27): paper-coloured, under the canvas transform. The paper, its border and title block and each
/// view are layers in paper space; only the offset changes with a pan, so no layer evaluates, and each view layer is
/// `.equatable()` and built only while its frame meets the visible rectangle grown by 20 %. The surface is a MetalUI key
/// region (`hoverKeyRegion`): F, Delete, ⌫, the arrows and Esc act while the pointer is over it and nothing is focused.
/// One `DragGesture` carries the press, drag and release, a middle drag and the scroll wheel pan, ⌘-scroll and a pinch zoom,
/// and `onGeometryChange` tells the model the canvas's size.
public struct SheetCanvas: Component {
    let model: DrawingEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: DrawingEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let colors = DrawingColors(themes)
        if let picture = model.picture, let sheet = model.sheet {
            surface(picture, sheet: sheet, colors: colors)
        } else {
            EmptyDrawingView(model: model, colors: colors)
        }
    }

    private func viewLayer(
        _ view: DrawingView, in picture: SheetPicture, hovered: SheetStroke?, zoom: Double, colors: DrawingColors,
        style: DrawingStyle
    ) -> SheetViewLayer {
        SheetViewLayer(
            id: view.id, strokes: picture.strokes.filter { $0.view == view.id },
            texts: picture.texts.filter { $0.view == view.id },
            frame: picture.viewFrames[view.id] ?? Rect2D(min: .zero, max: .zero), zoom: zoom, paperHeight: picture.size.y,
            isPending: model.contents[view.id]?.isPending ?? false, isSelected: model.selection.contains(view.id),
            hovered: hovered?.view == view.id ? hovered : nil, colors: colors, style: style)
    }

    private func surface(_ picture: SheetPicture, sheet: DrawingSheet, colors: DrawingColors) -> some ElementGroup {
        let transform = model.transform
        let zoom = transform.zoom
        let paper = picture.size
        let style = DrawingStyle.of(model.document.settings.standard)
        let visible = model.visibleSheetRect
        let shown = sheet.views.filter { picture.viewFrames[$0.id]?.intersects(visible) ?? true }
        let hovered = model.hoveredStroke.flatMap { picture.strokes.indices.contains($0) ? picture.strokes[$0] : nil }
        let framing = picture.strokes.filter { $0.view == nil }
        let framingTexts = picture.texts.filter { $0.view == nil }
        return colors.surround.color
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(colors.paper.color).frame(width: (paper.x * zoom).px, height: (paper.y * zoom).px)
                    SheetFrameLayer(
                        strokes: framing, texts: framingTexts, zoom: zoom, paperHeight: paper.y, colors: colors, style: style)
                        .equatable()
                    ForEach(shown, id: \.id) { view in
                        viewLayer(view, in: picture, hovered: hovered, zoom: zoom, colors: colors, style: style).equatable()
                    }
                }
                .offset(x: transform.offset.x.px, y: (transform.offset.y - paper.y * zoom).px)
                .allowsHitTesting(false)
            }
            .clipped()
            .gesture(SheetCanvasInput.primaryGesture(model))
            .gesture(SheetCanvasInput.middleGesture(model))
            .gesture(SheetCanvasInput.pinchGesture(model))
            .contentShape(Rectangle())
            .hoverKeyRegion()
            .onKeyPress(phases: [.down, .repeat]) { press in
                guard let key = SheetCanvasInput.key(
                    press.key, modifiers: press.modifiers, isRepeat: press.phase.contains(.repeat)) else { return .ignored }
                return model.keyPressed(key) ? .handled : .ignored
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): model.pointerMoved(to: SheetCanvasInput.vector(point))
                case .ended: model.pointerLeft()
                }
            }
            .onScrollWheel { event in SheetCanvasInput.scrolled(event, model) }
            .onGeometryChange(for: Size<Pixels>.self, of: { $0.size }, action: { size in
                let width = Double(size.width.value), height = Double(size.height.value)
                model.canvasSize = Vector2(width, height)
                model.visibleRect = Rect2D(min: .zero, max: Vector2(width, height))
            })
    }
}
