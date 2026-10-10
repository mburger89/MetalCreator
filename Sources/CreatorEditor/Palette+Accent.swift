import CreatorGraph
import CreatorStyle

extension Palette {
    /// The colour of an accent role (groups spec §7): the theme's role it stands for, so it follows theme changes.
    /// Group definitions use it for their header and doubled border (comments, sub-project B, for their fill).
    public func accent(_ role: AccentRole) -> HexColor {
        switch role {
        case .cyan: theme.colors.outputHeader
        case .green: theme.colors.profileHeader
        case .orange: theme.colors.featureHeader
        case .pink: theme.colors.selectionHeader
        case .purple: theme.colors.solidHeader
        case .yellow: theme.colors.warning
        case .muted: theme.colors.valueHeader
        }
    }
}
