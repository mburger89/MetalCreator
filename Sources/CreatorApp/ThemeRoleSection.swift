import CreatorEditor
import CreatorStyle
import MetalUI

/// One group's heading and its roles' rows.
struct ThemeRoleSection: Component {
    let model: ThemeEditorModel
    let group: ThemeRoleGroup
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(2)) {
            Text(group.title.uppercased())
                .font(.caption2)
                .foregroundStyle(Palette(themes).secondaryText.color)
            ForEach(group.roles, id: \.id) { role in
                ThemeRoleRow(model: model, role: role)
            }
        }
    }
}
