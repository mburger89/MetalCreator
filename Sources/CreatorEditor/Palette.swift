import CreatorGraph

/// The Dracula palette of spec §6.6, defined once and used everywhere by token.
public enum Palette {
    // Surfaces
    public static let backgroundTop = HexColor(0x3a3d4e)
    public static let backgroundBottom = HexColor(0x191a21)
    /// Glass panels: `#21222c` at about 86%. Blur is a MetalUI gap (docs/metalui-gaps.md).
    public static let glass = HexColor(0x21222c, opacity: 0.86)
    /// The 1-pt hairline around glass panels, `#ffffff1f`.
    public static let hairline = HexColor(0xffffff, opacity: Double(0x1f) / 255)
    /// Panel base, and the text colour on every accent fill.
    public static let panelBase = HexColor(0x282a36)
    public static let nodeBody = HexColor(0x343746)
    /// Fields, tracks and dividers.
    public static let field = HexColor(0x44475a)
    public static let primaryText = HexColor(0xf8f8f2)
    public static let secondaryText = HexColor(0x6272a4)

    // Accents
    public static let green = HexColor(0x50fa7b)
    public static let purple = HexColor(0xbd93f9)
    public static let pink = HexColor(0xff79c6)
    public static let orange = HexColor(0xffb86c)
    public static let comment = HexColor(0x6272a4)
    public static let cyan = HexColor(0x8be9fd)
    public static let yellow = HexColor(0xf1fa8c)
    public static let red = HexColor(0xff5555)

    /// Text drawn on any accent fill (headers, primary buttons, badges) is `#282a36`.
    public static let textOnAccent = panelBase
    /// Primary buttons and slider fill.
    public static let primaryButton = purple
    /// Focus outside the graph (keyboard focus, viewport hover).
    public static let focus = cyan

    public static let statusOK = green
    public static let statusWarning = yellow
    public static let statusError = red

    /// A node's header colour, by category.
    public static func header(for category: NodeCategory) -> HexColor {
        switch category {
        case .value: comment
        case .profile: green
        case .solid: purple
        case .selection: pink
        case .feature: orange
        case .output: cyan
        }
    }

    /// A selected node's outline and glow: always its own header colour (spec §6.6).
    public static func selection(for category: NodeCategory) -> HexColor { header(for: category) }

    /// A socket's colour, and the colour of wires leaving it, by type.
    public static func socket(_ type: SocketType) -> HexColor {
        switch type {
        case .profile: green
        case .solid: purple
        case .edgeSet, .faceSet: pink
        case .number, .integer, .bool, .vector, .plane: comment
        }
    }

    /// The colour for a node's status badge.
    public static func status(_ state: NodeState) -> HexColor {
        switch state {
        case .ok: statusOK
        case .warning: statusWarning
        case .error: statusError
        case .idle, .evaluating: secondaryText
        }
    }
}
