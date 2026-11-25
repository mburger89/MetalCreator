import CreatorGeometry
import CreatorKernel

/// Turns a view and its source into what the sheet draws (plan R9, R20). Stateless: superseding requests is the caller's.
public struct DrawingProjector: Sendable {
    public let cache: ProjectionCache
    public let kernel: any Kernel

    public init(cache: ProjectionCache, kernel: any Kernel) {
        self.cache = cache
        self.kernel = kernel
    }

    public static let removedSentence = "The Output this view showed was removed."
    public static let nothingYetSentence = "This Output holds nothing to draw yet."
    public static let onlyMeshesSentence =
        "Drawings show solids, sheets and curves; this Output holds a mesh. Mesh to Solid makes a solid of a small mesh."

    public static func meshesSentence(count: Int) -> String {
        count == 1
            ? "This view leaves out the Output's mesh; drawings show solids, sheets and curves."
            : "This view leaves out the Output's \(count) meshes; drawings show solids, sheets and curves."
    }

    public func content(for view: DrawingView, scale: Double, source: DrawingSourceContent, previous: ViewContent?)
        async -> ViewContent {
        switch source.state {
        case .removed:
            return ViewContent(problem: Self.removedSentence, lastSize: previous?.lastSize)
        case .failed(let message):
            return ViewContent(projection: previous?.projection, problem: message, lastSize: previous?.lastSize)
        case .evaluating:
            return ViewContent(projection: previous?.projection, lastSize: previous?.lastSize)
        case .ready(let solids, let curves, let meshCount):
            if solids.isEmpty, curves.isEmpty {
                return ViewContent(
                    problem: meshCount > 0 ? Self.onlyMeshesSentence : Self.nothingYetSentence, lastSize: previous?.lastSize)
            }
            let warnings = meshCount > 0 ? [Self.meshesSentence(count: meshCount)] : []
            do {
                let projection = try await cache.projection(
                    of: solids, curves: curves, compoundTag: NodeTag(node: source.output, item: 0),
                    frame: view.orientation.frame, options: ProjectionOptions(tolerance: 0.01 / scale), kernel: kernel)
                let size = ViewLinework.frame(for: projection, center: .zero, scale: scale).map { Vector2($0.width, $0.height) }
                return ViewContent(projection: projection, warnings: warnings, lastSize: size ?? previous?.lastSize)
            } catch {
                return ViewContent(
                    projection: previous?.projection, problem: Self.message(for: error), warnings: warnings,
                    lastSize: previous?.lastSize)
            }
        }
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? KernelError { return error.userMessage }
        if error is CancellationError { return "The view was cancelled." }
        return String(describing: error)
    }
}
