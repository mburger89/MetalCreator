import CreatorStyle
import MetalUI

/// The active tool's hint and settings in the inspector: the Fillet tool's radius, the Pattern tool's instance count
/// and spacing. Typed values go through the model, which refuses what isn't a size or a count; a refused entry snaps
/// back (`DimensionField`).
struct ToolOptionsView: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let colors = SketchColors(themes)
        let options = model.options
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            if let hint = model.tool.hint {
                Text(hint).font(.caption).foregroundStyle(colors.secondary)
            }
            if model.tool == .fillet {
                HStack(spacing: Pixels(6)) {
                    Text("Radius").font(.callout).foregroundStyle(colors.primary)
                    DimensionField(text: DimensionText.millimetres(options.filletRadius), width: 80) { model.setFilletRadius($0) }
                }
            }
            if model.tool == .pattern {
                HStack(spacing: Pixels(6)) {
                    Text("Instances").font(.callout).foregroundStyle(colors.primary)
                    DimensionField(text: "\(options.patternCount)", width: 48) { model.setPatternCount($0) }
                    Text("Spacing").font(.callout).foregroundStyle(colors.primary)
                    DimensionField(text: DimensionText.millimetres(options.patternSpacing), width: 80) { model.setPatternSpacing($0) }
                }
            }
        }
    }
}
