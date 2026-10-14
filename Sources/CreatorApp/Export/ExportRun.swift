import Foundation
import Observation

/// An export in progress (implicit spec §5.3): what the export sheet shows, a progress bar and Cancel. The export evaluates the graph
/// at full resolution, which can take a while; `fraction` is how far the meshing that is running has got, and `cancel()` stops it
/// between batches of bricks, leaving no file behind.
@MainActor
@Observable
public final class ExportRun {
    /// What is being exported: "Exporting “Insole”".
    public let title: String
    /// How far the meshing now running has got, from 0 to 1.
    public private(set) var fraction = 0.0
    /// True once Cancel has been pressed and the work has not yet stopped.
    public private(set) var isCancelling = false
    /// What stops the work; set by whoever started it. A Cancel pressed before it is set is replayed when it is.
    @ObservationIgnored var onCancel: (@MainActor () -> Void)? {
        didSet { if isCancelling { onCancel?() } }
    }

    public init(title: String) {
        self.title = title
    }

    func report(_ fraction: Double) {
        guard !isCancelling else { return }
        self.fraction = min(max(fraction, 0), 1)
    }

    /// Stops the export.
    public func cancel() {
        isCancelling = true
        onCancel?()
    }
}
