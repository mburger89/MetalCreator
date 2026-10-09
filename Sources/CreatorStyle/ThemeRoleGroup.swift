/// The headings the theme editor lists roles under, in `ThemeColors`' order.
public enum ThemeRoleGroup: String, CaseIterable, Identifiable, Sendable {
    case surfaces, text, interaction, nodes, status, model, widgets, sketcher

    public var id: String { rawValue }

    /// The heading shown in the theme editor.
    public var title: String {
        switch self {
        case .surfaces: "Surfaces"
        case .text: "Text"
        case .interaction: "Interaction"
        case .nodes: "Node categories"
        case .status: "Status"
        case .model: "The model"
        case .widgets: "Viewport widgets"
        case .sketcher: "Sketcher"
        }
    }

    /// This group's roles, in order.
    public var roles: [ThemeRole] { ThemeRole.all.filter { $0.group == self } }
}
