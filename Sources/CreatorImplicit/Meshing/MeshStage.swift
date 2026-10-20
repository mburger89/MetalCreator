/// A step a streamed export applies to every window on its way to the file (implicit spec Errata D12). Decimate is the only one: a
/// check does not change the surface, so it runs on a copy (`MeshCopyForChecks`), not on the stream.
public enum MeshStage: Hashable, Sendable {
    /// Quadric error decimation of each window with the window's edge held still, so the pieces still fit.
    case decimate(tolerance: Double)
}
