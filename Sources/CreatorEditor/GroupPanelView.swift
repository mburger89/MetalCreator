import CreatorGraph
import CreatorStyle
import MetalUI

/// The inspector's part for a group node, Group Input or Group Output (groups spec §6): the definition's name and
/// accent and how many times it is used; and, for Group Input or Group Output, the sockets of that side with rename,
/// reorder and remove. Edit Group, Make Unique and Ungroup are the group node's own inspector buttons.
struct GroupPanelView: Component {
    let panel: GroupPanel
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return VStack(alignment: .leading, spacing: Pixels(10)) {
            InspectorSectionView(title: "Definition") {
                LabeledRow(label: "Name") {
                    Spacer()
                    TextEntry(model: model, text: panel.name) { model.renameGroup(panel.definition, to: $0, on: panel.node) }
                }
                Picker("Accent", selection: Binding(
                    get: { panel.accent }, set: { model.setGroupAccent(panel.definition, to: $0, on: panel.node) }
                )) {
                    ForEach(AccentRole.allCases, id: \.self) { role in
                        Text(role.rawValue.capitalized).tag(role)
                    }
                }
                .pickerStyle(.menu)
                Text(panel.usesText).font(.callout).foregroundStyle(palette.secondaryText.color)
            }
            if let side = panel.side {
                InspectorSectionView(title: side == .input ? "Inputs" : "Outputs") {
                    if panel.sockets.isEmpty {
                        Text("Drop a wire on + to add one").font(.caption).foregroundStyle(palette.secondaryText.color)
                    }
                    ForEach(panel.sockets, id: \.id) { socket in
                        GroupSocketRowView(panel: panel, side: side, socket: socket, model: model)
                    }
                }
            }
        }
    }
}
