import CreatorGeometry

/// The preview window's layout numbers. The window keeps one size and `PreviewRoot` is framed to these; the panel
/// tells the editor where it is itself (`EditorModel.panelPlacement`, gap EP-a).
enum PreviewLayout {
    static let window = Vector2(1280, 800)
    static let margin = 12.0
    static let leftPanelWidth = 380.0
    static let bottomPanelHeight = 300.0
}
