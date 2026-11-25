import CreatorDrawing
import CreatorStyle
import MetalUI

/// The inspector's width in points, as the graph inspector's content.
let drawingInspectorWidth = 280.0

/// A text field that keeps its draft while typing and submits it on Return or when it loses focus, one step each; the shown text
/// comes back whenever the model's changes (a refused entry snaps back).
struct DrawingField: Component {
    let text: String
    var placeholder = ""
    var width: Double?
    let submit: @MainActor (String) -> Void
    @State var draft: String?
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        TextField(placeholder, text: draft ?? text, onChange: { draft = $0 })
            .focused($isFocused)
            .onSubmit { commit() }
            .frame(width: width.map { $0.px })
            .onChange(of: text) { draft = nil }
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused, !focused { commit() }
            }
    }

    private func commit() {
        guard let typed = draft else { return }
        draft = nil
        if typed != text { submit(typed) }
    }
}

/// A label and its control, one row.
struct DrawingRow<Control: ElementGroup>: Component {
    let label: String
    let colors: DrawingColors
    let control: Control

    init(_ label: String, colors: DrawingColors, @ElementBuilder control: () -> Control) {
        self.label = label
        self.colors = colors
        self.control = control()
    }

    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) {
            Text(label).font(.callout).foregroundStyle(colors.primary.color)
                .frame(width: Pixels(96), alignment: .leading)
            control
        }
    }
}

/// A choice among options in a pop-up menu (`selected` is `nil` when the value is none of them).
struct DrawingMenu: Component {
    let options: [String]
    let selected: Int?
    let choose: @MainActor (Int) -> Void

    var content: some ElementGroup {
        Picker("", selection: Binding(get: { selected ?? -1 }, set: { choose($0) })) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index]).tag(index)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

/// A choice among a few options as segments.
struct DrawingSegments: Component {
    let options: [String]
    let selected: Int
    let choose: @MainActor (Int) -> Void

    var content: some ElementGroup {
        Picker("", selection: Binding(get: { selected }, set: { choose($0) })) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index]).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// A scale: the preferred list (ISO 5455) and "Custom…" with two whole-number fields. A view also offers "Sheet's", which
/// is `nil`. `choose` takes the new value; the model refuses an invalid one in words.
struct ScaleControl: Component {
    let current: DrawingScale?
    let allowsSheetScale: Bool
    let standard: DrawingStandard
    /// The scale the fields start from while a view still uses its sheet's.
    var sheetScale: DrawingScale?
    let choose: @MainActor (DrawingScale?) -> Void
    @State var isCustom = false

    private var preferred: [DrawingScale] { DrawingScale.preferred }
    private var leading: Int { allowsSheetScale ? 1 : 0 }

    /// The menu's titles: "Sheet's" (a view's), the preferred scales, "Custom…".
    var options: [String] {
        (allowsSheetScale ? ["Sheet's"] : []) + preferred.map { $0.text(for: standard) } + ["Custom…"]
    }

    var selected: Int { Self.selectedIndex(current: current, isCustom: isCustom, allowsSheetScale: allowsSheetScale) }

    /// The menu's selection: "Custom…" once chosen (whatever the scale is now), else "Sheet's" for no scale, else the
    /// preferred scale that matches, else "Custom…".
    static func selectedIndex(current: DrawingScale?, isCustom: Bool, allowsSheetScale: Bool) -> Int {
        let preferred = DrawingScale.preferred
        let last = (allowsSheetScale ? 1 : 0) + preferred.count
        if isCustom { return last }
        guard let current else { return 0 }
        if let index = preferred.firstIndex(of: current) { return (allowsSheetScale ? 1 : 0) + index }
        return last
    }

    var showsFields: Bool { selected == options.count - 1 }

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            DrawingMenu(options: options, selected: selected) { index in
                if allowsSheetScale, index == 0 {
                    isCustom = false
                    choose(nil)
                } else if index == options.count - 1 {
                    isCustom = true
                } else {
                    isCustom = false
                    choose(preferred[index - leading])
                }
            }
            if showsFields {
                let value = current ?? sheetScale ?? DrawingScale(numerator: 1, denominator: 1)
                DrawingField(text: String(value.numerator), width: 44) { typed in
                    if let n = Int(typed) { choose(DrawingScale(numerator: n, denominator: value.denominator)) }
                }
                Text(":")
                DrawingField(text: String(value.denominator), width: 44) { typed in
                    if let d = Int(typed) { choose(DrawingScale(numerator: value.numerator, denominator: d)) }
                }
            }
        }
    }
}
