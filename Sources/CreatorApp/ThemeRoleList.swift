import CreatorStyle
import MetalUI

/// Every role of the shown theme, under its group's heading, in `ThemeColors`' order.
struct ThemeRoleList: Component {
    let model: ThemeEditorModel

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: ThemeEditorLayout.spacing.px) {
            ForEach(ThemeRoleGroup.allCases, id: \.id) { group in
                ThemeRoleSection(model: model, group: group)
            }
        }
    }
}
