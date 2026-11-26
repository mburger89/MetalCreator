import CreatorStyle
import MetalUI

/// The drawing inspector (plan R22, R20): no selection shows the sheet's own settings, one view its own, several "N views selected"
/// and Delete, and a selected annotation its page (`AnnotationInspector`). With no sheet it says so.
public struct DrawingInspector: Component {
    let model: DrawingEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: DrawingEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let colors = DrawingColors(themes)
        if let sheet = model.sheet {
            let chosen = sheet.views.filter { model.selection.contains($0.id) }
            if !model.selectedAnnotations.isEmpty {
                AnnotationInspector(model: model, sheet: sheet, colors: colors, views: chosen.count)
            } else if chosen.count == 1, let view = chosen.first {
                ViewInspector(model: model, sheet: sheet, view: view, colors: colors)
                    .id(view.id.rawValue.uuidString)
            } else if chosen.count > 1 {
                VStack(alignment: .leading, spacing: Pixels(8)) {
                    Text("\(chosen.count) views selected").font(.headline).foregroundStyle(colors.primary.color)
                    Button("Delete") { model.deleteSelection() }
                }
                .frame(width: drawingInspectorWidth.px)
            } else {
                SheetInspector(model: model, sheet: sheet, colors: colors)
            }
        } else {
            Text("No sheets yet").font(.callout).foregroundStyle(colors.secondary.color)
                .frame(width: drawingInspectorWidth.px, alignment: .leading)
        }
    }
}
