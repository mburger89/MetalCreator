import CreatorStyle
import MetalUI

/// A labelled choice among a few options, laid out to fit `width` (the inspector's content width).
///
/// MetalUI's segmented `Picker` is one row, title then options, 8 apart, and its segments are as wide as the widest option
/// (`textW + 24` each): the picker never narrows, so a row wider than its panel runs off the edge while the title (the only
/// part that can shrink) wraps a letter at a time. That is the layout contract of MetalUI's control, so the row has to
/// choose a form that fits, and measures the text to do it (never a character count):
/// 1. everything fits in one line: the label, then the segments (as before);
/// 2. the segments fit alone: the label on its own line above them;
/// 3. they don't (Loft's "Free / Tangent (G1) / Curvature (G2)", Import Mesh's five units): a pop-up showing the selected
///    option, which lists every option whatever its width, beside the label when that fits, else under it.
struct SegmentedRow: Component {
    let label: String
    let options: [String]
    let selected: Int?
    var width = SegmentedRow.inspectorWidth
    let choose: @MainActor (Int) -> Void
    @Environment(\.textMeasurer) var measurer
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The inspector's content width in points (`InspectorPanel`).
    static let inspectorWidth = 280.0

    /// The ways a row can be laid out.
    enum Form: Equatable { case inline, stacked, menuBeside, menuBelow }

    /// Picks the form from measured widths (points): the label, the widest option, the option count and the room.
    static func form(labelWidth: Double, widestOption: Double, count: Int, width: Double) -> Form {
        let margin = 6.0
        let segments = Double(count) * (widestOption + 24) + margin
        if labelWidth + 8 + segments <= width { return .inline }
        if segments <= width { return .stacked }
        // The pull-down button: the widest option, its padding and the indicator.
        let menu = widestOption + 48
        return labelWidth + 8 + menu + margin <= width ? .menuBeside : .menuBelow
    }

    private func measured(_ text: String, _ font: Font? = nil) -> Double {
        var proposal = ProposalText(text)
        if let font { proposal = proposal.font(font) }
        return Double(measurer.resolve(proposal).measure(in: Size(width: .infinity, height: .infinity)).width.value)
    }

    private var form: Form {
        Self.form(labelWidth: measured(label, .callout), widestOption: options.map { measured($0) }.max() ?? 0,
                  count: options.count, width: width)
    }

    private var binding: Binding<Int> {
        Binding(get: { selected ?? -1 }, set: { choose($0) })
    }

    private var tagged: some ElementGroup {
        ForEach(options.indices, id: \.self) { index in
            Text(options[index]).tag(index)
        }
    }

    var content: some ElementGroup {
        switch form {
        case .inline:
            Picker(label, selection: binding) { tagged }.pickerStyle(.segmented)
        case .stacked:
            VStack(alignment: .leading, spacing: Pixels(4)) {
                Text(label).font(.callout).foregroundStyle(Palette(themes).primaryText.color)
                Picker(label, selection: binding) { tagged }.pickerStyle(.segmented).labelsHidden()
            }
        case .menuBeside:
            Picker(label, selection: binding) { tagged }.pickerStyle(.menu)
        case .menuBelow:
            VStack(alignment: .leading, spacing: Pixels(4)) {
                Text(label).font(.callout).foregroundStyle(Palette(themes).primaryText.color)
                Picker(label, selection: binding) { tagged }.pickerStyle(.menu).labelsHidden()
            }
        }
    }
}
