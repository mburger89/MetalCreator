import CreatorEditor
import CreatorGeometry
import CreatorStyle
import MetalUI

/// The inspector while the control-point mode runs: how many points are selected, the offset of the one selected point, the axis
/// lock (R5) and Done. All behaviour is the session's and `AppModel`'s; it is shown in `SketchChrome(.inspector)`.
struct ControlNetInspector: Component {
    let model: AppModel
    let session: ControlNetSession
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let units = model.units
        return VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Edit Control Points").font(.headline).foregroundStyle(palette.primaryText.color)
            if let problem = model.controlNetProblem {
                Text(problem).font(.caption).foregroundStyle(palette.statusWarning.color)
            } else if session.net.uCount == 0 {
                Text(session.kind == .surface ? "The surface isn't ready." : "The curve isn't ready.")
                    .font(.caption).foregroundStyle(palette.statusWarning.color)
            }
            Text(Self.selectionText(session.selection.count)).font(.callout).foregroundStyle(palette.primaryText.color)
            if session.selection.count == 1, let index = session.selection.first {
                let offset = session.offsets[index] ?? .zero
                ControlNetOffsetField(label: "X", value: offset.x, units: units) { session.setOffset(0, to: $0) }
                ControlNetOffsetField(label: "Y", value: offset.y, units: units) { session.setOffset(1, to: $0) }
                ControlNetOffsetField(label: "Z", value: offset.z, units: units) { session.setOffset(2, to: $0) }
            }
            Text("AXIS LOCK").font(.caption2).foregroundStyle(palette.secondaryText.color)
            HStack(spacing: Pixels(8)) {
                lockToggle("X", .x)
                lockToggle("Y", .y)
                lockToggle("Z", .z)
                if session.kind == .surface { lockToggle("N", .normal) }
            }
            Button("Done") { session.done() }
        }
        .frame(width: Pixels(280))
    }

    private func lockToggle(_ title: String, _ lock: ControlNetSession.AxisLock) -> some ElementGroup {
        Toggle(title, isOn: Binding(get: { session.lock == lock }, set: { _ in session.toggleLock(lock) }))
    }

    static func selectionText(_ count: Int) -> String {
        switch count {
        case 0: "No points selected"
        case 1: "1 point selected"
        default: "\(count) points selected"
        }
    }
}

/// One component of the selected point's offset: a field in the document's length unit, committed on Return or when it loses focus;
/// text that is not a length puts the value back.
struct ControlNetOffsetField: Component {
    let label: String
    let value: Double
    let units: DocumentUnits
    let commit: (Double) -> Void
    @Environment(ThemeStore.self) var themes: ThemeStore?
    @State var draft: String?
    @FocusState var focused: Bool

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: Pixels(6)) {
            Text(label).font(.callout).foregroundStyle(palette.primaryText.color)
            TextField(label, text: draft ?? units.editText(value, quantity: .length), onChange: { draft = $0 })
                .focused($focused)
                .onSubmit { submit() }
            Text(units.suffix(for: .length)).font(.callout).foregroundStyle(palette.secondaryText.color)
        }
        .onChange(of: focused) { wasFocused, nowFocused in
            if wasFocused, !nowFocused { submit() }
        }
        .onChange(of: value) { draft = nil }
    }

    private func submit() {
        guard let text = draft else { return }
        draft = nil
        if let parsed = units.parse(text, quantity: .length), parsed.isFinite { commit(parsed) }
    }
}
