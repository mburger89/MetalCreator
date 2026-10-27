import CreatorViewport

/// The dimensions drawn over the viewport (DIM-1): the open sketch's, as ANSI dimensions.
extension AppModel {
    /// What the viewport should show now: the open sketch's dimensions, none when no sketch is being followed.
    public func shownDimensions() -> [OverlayDimension] {
        guard let session = sketch, session.isFollowing else { return [] }
        return session.editor.dimensions
    }

    /// Hands the viewport the dimensions it should show (`shownDimensions()`). A value box whose dimension is gone closes.
    public func refreshDimensions() {
        viewport.showDimensions(shownDimensions())
    }
}
