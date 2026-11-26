import CreatorDrawing
import MetalUI

/// The sheet inspector's TEMPLATES rows (DR-5 R10): Save Sheet as Template, then each template's name to edit and Delete. The
/// editor only asks (`DrawingEditorRequest`); the host owns the folder, so a template is never an undo step.
struct TemplatesSection: Component {
    let model: DrawingEditorModel
    let sheet: DrawingSheet
    let colors: DrawingColors

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("TEMPLATES").font(.caption2).foregroundStyle(colors.secondary.color)
            Button("Save Sheet as Template") { model.request(.saveSheetAsTemplate(sheet.id)) }
            ForEach(model.templateChoices, id: \.id) { template in
                HStack(spacing: Pixels(8)) {
                    DrawingField(model: model, text: template.name, width: 150) {
                        model.request(.renameTemplate(template.id, to: $0))
                    }
                    Button("Delete") { model.request(.deleteTemplate(template.id)) }
                }
            }
            if let problem = model.templateProblem {
                Text(problem).font(.caption).foregroundStyle(colors.warning.color)
            }
        }
    }
}
