import CreatorEditor
import CreatorStyle
import MetalUI

/// The field preview's legend (fields spec §6): the ramp as a bar of the theme's three field roles, its low, middle and high
/// numbers (with "mm" for a distance), a note when the sampling was coarse or failed, the "0…1" toggle and the slice buttons.
/// All behaviour is `FieldPreviewModel`'s; this only draws its `FieldLegend`.
struct FieldLegendView: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The card's inner width in points.
    static let width = 220.0

    var content: some ElementGroup {
        if let legend = model.fieldPreview.legend {
            GlassPanel(.fieldLegend) {
                VStack(alignment: .leading, spacing: Pixels(6)) {
                    if let labels = legend.labels {
                        ramp
                        HStack(spacing: Pixels(0)) {
                            Text(labels.low)
                            Spacer()
                            Text(labels.mid)
                            Spacer()
                            Text(labels.high)
                        }
                        .font(.caption)
                        .foregroundStyle(Palette(themes).primaryText.color)
                    }
                    ForEach(legend.notes, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle((legend.failure == nil ? Palette(themes).statusWarning : Palette(themes).statusError).color)
                    }
                    Toggle("0…1", isOn: Binding(get: { legend.usesUnitRange }, set: { model.fieldPreview.setUnitRange($0) }))
                    Picker("Slice", selection: Binding(get: { legend.selectedOption ?? -1 }, set: { index in
                        if legend.sliceOptions.indices.contains(index) { model.fieldPreview.chooseSlice(legend.sliceOptions[index].choice) }
                    })) {
                        ForEach(legend.sliceOptions.indices, id: \.self) { index in
                            Text(legend.sliceOptions[index].title).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(width: Self.width.px)
            }
        }
    }

    /// The ramp: low, middle and high in the theme's field roles, left to right.
    private var ramp: some ElementGroup {
        let colors = (themes?.current ?? .dracula).colors
        return LinearGradient(colors: [colors.fieldLow.color, colors.fieldMid.color, colors.fieldHigh.color],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: Self.width.px, height: Pixels(10))
            .clipShape(RoundedRectangle(cornerRadius: Pixels(3)))
    }
}
