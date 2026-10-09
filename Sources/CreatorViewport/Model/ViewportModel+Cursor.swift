extension ViewportModel {
    /// The pointer's shape over the viewport, or `nil` for the platform's arrow: a closed hand while a drag orbits
    /// or pans (the cube's drag orbits too), else a crosshair while the host is picking edges (`isPicking`) or a tool
    /// is set (sketching).
    public var cursor: ViewportCursor? {
        switch activeDragMode {
        case .orbit?, .pan?, .cube?: .grabbing
        case .zoom?, .handle?, .tool?, nil: isPicking || tool != nil ? .crosshair : nil
        }
    }
}
