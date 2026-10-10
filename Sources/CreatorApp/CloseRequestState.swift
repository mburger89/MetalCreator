/// Where the unsaved-changes question stands (gap M6-b): MetalUI's window holds a close request open after the
/// handler answered `.later`, so the model must answer it exactly once.
public enum CloseRequestState: Sendable, Equatable {
    /// Nothing has been asked.
    case idle
    /// The alert is up, waiting for Save, Don't Save or Cancel.
    case asking
    /// Save was pressed and the save is running (a Save As… panel may be up).
    case saving
}
