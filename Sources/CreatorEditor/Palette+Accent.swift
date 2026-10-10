import CreatorGraph
import CreatorStyle

extension Palette {
    /// The colour a theme gives an accent role (canvas comments spec 2026-10-09 §7; group definitions use the same
    /// roles). A role names a theme colour, never a hue, so comments follow theme changes: each accent is the header
    /// colour of a node category (Dracula's cyan is Output's, green Profile's, orange Feature's, pink Selection's,
    /// purple Solid's), yellow is the warning colour and muted is Value's.
    public func accent(_ role: AccentRole) -> HexColor {
        switch role {
        case .cyan: header(for: .output)
        case .green: header(for: .profile)
        case .orange: header(for: .feature)
        case .pink: header(for: .selection)
        case .purple: header(for: .solid)
        case .yellow: statusWarning
        case .muted: header(for: .value)
        }
    }
}
