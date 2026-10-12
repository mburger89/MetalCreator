import CreatorEditor

extension AppModel {
    /// Where the graph panel is in the window, as the panel measured it (`EditorModel.panelPlacement`); `nil` before
    /// the first layout and while the panel is hidden. Observed: a resize rebuilds what reads it (the canvas's culling).
    public var panelPlacement: PanelPlacement? { editor.panelPlacement }
}
