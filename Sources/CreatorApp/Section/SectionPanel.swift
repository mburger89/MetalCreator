import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorStyle
import MetalUI

/// The section's panel (section spec §5): which plane, the offset from it, Flip and Close. It shows while a section is on and no
/// sketch is open. All behaviour is `AppModel`'s (`setSectionOrigin`, `commitSectionOffset`, `flipSection`, `setSection`).
struct SectionPanel: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?
    /// What the Offset field holds while it is being typed in; `nil` shows the document's value.
    @State var draft: String?
    @FocusState var offsetFocused: Bool

    /// The card's inner width in points.
    static let width = 220.0

    var content: some ElementGroup {
        if let settings = model.document.section, settings.isOn, model.sketch == nil {
            let palette = Palette(themes)
            let units = model.units
            GlassPanel(.sectionPanel) {
                VStack(alignment: .leading, spacing: Pixels(8)) {
                    Text("Section")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText.color)
                    Picker("Plane", selection: Binding(get: { Self.index(of: settings.reference) }, set: { index in
                        if SectionOrigin.panelOrder.indices.contains(index) { model.setSectionOrigin(SectionOrigin.panelOrder[index]) }
                    })) {
                        ForEach(SectionOrigin.panelOrder.indices, id: \.self) { index in
                            Text(SectionOrigin.panelOrder[index].title).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let title = model.section.shown?.faceTitle, case .face = settings.reference {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                    }
                    if let note = model.section.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(palette.statusWarning.color)
                    }
                    HStack(spacing: Pixels(6)) {
                        Text("Offset").font(.callout).foregroundStyle(palette.primaryText.color)
                        TextField("Offset", text: draft ?? units.editText(settings.offset, quantity: .length), onChange: { draft = $0 })
                            .focused($offsetFocused)
                            .onSubmit { commit() }
                        Text(units.suffix(for: .length)).font(.callout).foregroundStyle(palette.secondaryText.color)
                    }
                    .onChange(of: offsetFocused) { wasFocused, focused in
                        if wasFocused, !focused { commit() }
                    }
                    .onChange(of: settings.offset) { draft = nil }
                    HStack(spacing: Pixels(8)) {
                        Button("Flip") { model.flipSection() }
                        Button("Close") { model.setSection(false) }
                    }
                }
                .frame(width: Self.width.px)
            }
        }
    }

    /// Commits what was typed; text that is not a length puts the document's value back.
    private func commit() {
        guard let text = draft else { return }
        draft = nil
        _ = model.commitSectionOffset(text: text)
    }

    private static func index(of reference: SectionReference) -> Int {
        if case .origin(let origin) = reference, let index = SectionOrigin.panelOrder.firstIndex(of: origin) { return index }
        return -1
    }
}

extension SectionOrigin {
    /// The segments' order, as the spec's "XY / YZ / XZ" has it.
    static let panelOrder: [SectionOrigin] = [.xy, .yz, .xz]

    var title: String {
        switch self {
        case .xy: "XY"
        case .yz: "YZ"
        case .xz: "XZ"
        }
    }
}
