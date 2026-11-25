import MetalUI

/// What Drawing shows with no sheet: nothing is added until the button is pressed, so entering never dirties a document (plan R21).
struct EmptyDrawingView: Component {
    let model: DrawingEditorModel
    let colors: DrawingColors

    var content: some ElementGroup {
        VStack(spacing: Pixels(12)) {
            Text("No sheets yet").font(.headline).foregroundStyle(colors.primary.color)
            Button("Add Sheet") { model.addSheet() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surround.color)
    }
}
