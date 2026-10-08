extension AppModel {
    /// True while the graph panel's edge is being dragged.
    public var isResizingPanel: Bool { resizeStart != nil }

    /// A drag on the graph panel's inner edge began (spec §6.1: the panel resizes along its inner edge).
    public func beginPanelResize() {
        resizeStart = editor.dock == .bottom ? panelHeight : panelWidth
    }

    /// The drag moved `translation` points along the panel's flow axis: right grows a left-docked panel, up grows
    /// a bottom-docked one. Sizes are kept within `AppLayout.panelWidths` and `panelHeights`.
    public func resizePanel(by translation: Double) {
        guard let start = resizeStart, translation.isFinite else { return }
        switch editor.dock {
        case .left: panelWidth = min(max(start + translation, AppLayout.panelWidths.lowerBound), AppLayout.panelWidths.upperBound)
        case .bottom: panelHeight = min(max(start - translation, AppLayout.panelHeights.lowerBound), AppLayout.panelHeights.upperBound)
        case .hidden: break
        }
    }

    public func endPanelResize() {
        resizeStart = nil
    }
}
