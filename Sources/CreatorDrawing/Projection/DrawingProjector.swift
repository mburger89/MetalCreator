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
        let shown = count.formatted(.number.locale(.messages))
        return count == 1
            ? "This view leaves out the Output's mesh; drawings show solids, sheets and curves."
            : "This view leaves out the Output's \(shown) meshes; drawings show solids, sheets and curves."
    }

    public func content(for view: DrawingView, scale: Double, source: DrawingSourceContent, previous: ViewContent?)
        async -> ViewContent {
        switch source.state {
        case .removed:
            return ViewContent(problem: Self.removedSentence, lastSize: previous?.lastSize)
        case .failed(let message):
            return kept(previous, problem: message)
        case .evaluating:
            return kept(previous, problem: previous?.problem, warnings: previous?.warnings ?? [])
        case .ready(let solids, let curves, let meshCount):
            if solids.isEmpty, curves.isEmpty {
                return ViewContent(
                    problem: meshCount > 0 ? Self.onlyMeshesSentence : Self.nothingYetSentence, lastSize: previous?.lastSize)
            }
            var warnings = meshCount > 0 ? [Self.meshesSentence(count: meshCount)] : []
            if case .section(let line)? = view.derivation {
                if !curves.isEmpty { warnings.append(Self.curvesLeftOutSentence) }
                return await sectionContent(
                    line, scale: scale, solids: solids, output: source.output, warnings: warnings, previous: previous)
            }
            do {
                let cached = try await cache.projection(
                    of: solids, curves: curves, compoundTag: NodeTag(node: source.output, item: 0),
                    frame: view.orientation.frame, options: ProjectionOptions(tolerance: 0.01 / scale), kernel: kernel)
                let projection = cached.projection
                let size = ViewLinework.frame(for: ViewContent(projection: projection), center: .zero, scale: scale)
                    .map { Vector2($0.width, $0.height) }
                return ViewContent(
                    projection: projection, topology: cached.topology, warnings: warnings, lastSize: size ?? previous?.lastSize)
            } catch {
                return kept(previous, problem: Self.message(for: error), warnings: warnings)
            }
        }
    }

    /// What a failed or pending request keeps of the last good content: the drawing travels with its projection (DR-2 R25).
    func kept(_ previous: ViewContent?, problem: String?, warnings: [String] = []) -> ViewContent {
        ViewContent(
            projection: previous?.projection, topology: previous?.topology, problem: problem, warnings: warnings,
            lastSize: previous?.lastSize, hatch: previous?.hatch ?? [], hatchClips: previous?.hatchClips ?? [],
            framing: previous?.framing, parts: previous?.parts ?? [])
    }

    public static let curvesLeftOutSentence =
        "This section leaves out the Output's curves; a section shows what the cut leaves of solids and sheets."
    public static let assemblyCurvesLeftOutSentence =
        "This section leaves out the parts' curves; a section shows what the cut leaves of solids and sheets."
    public static let cutAwaySentence = "The cutting line leaves nothing of the part on the side it looks toward."
    public static let noSolidsToCutSentence =
        "A section shows what the cut leaves of solids and sheets, and this Output has none."
    public static let hatchFailedSentence = "The cut faces of a part couldn't be hatched."

    /// A section view (R14): each solid cut by the line, the remainders projected in the section's frame, step lines dropped, the
    /// cut faces carried as hatch.
    private func sectionContent(
        _ line: SectionLine, scale: Double, solids: [Solid], output: NodeID, warnings: [String], previous: ViewContent?
    ) async -> ViewContent {
        var warnings = warnings
        if solids.isEmpty {
            return ViewContent(problem: Self.noSolidsToCutSentence, warnings: warnings, lastSize: previous?.lastSize)
        }
        do {
            let tolerance = 0.01 / scale
            var remainders: [Solid] = []
            var hatch: [HatchRegion] = []
            var hatchFailed = false
            for (index, solid) in solids.enumerated() {
                let piece = try await cache.sectionCut(
                    of: solid, index: index, cutter: line.cutter, tolerance: tolerance, kernel: kernel)
                if let remainder = piece.remainder { remainders.append(remainder) }
                hatch += piece.regions
                hatchFailed = hatchFailed || piece.hatchFailed
            }
            if remainders.isEmpty {
                return ViewContent(problem: Self.cutAwaySentence, warnings: warnings, lastSize: previous?.lastSize)
            }
            let cached = try await cache.projection(
                of: remainders, curves: [], compoundTag: NodeTag(node: output, item: 0),
                frame: SectionFrame.frame(for: line.cutter), options: ProjectionOptions(tolerance: tolerance), kernel: kernel)
            let projection = cached.topology.map { SectionLines.droppingSteps(cached.projection, topology: $0) }
                ?? cached.projection
            if hatchFailed { warnings.append(Self.hatchFailedSentence) }
            let content = ViewContent(
                projection: projection, topology: cached.topology, warnings: warnings, hatch: hatch)
            let size = ViewLinework.frame(for: content, center: .zero, scale: scale).map { Vector2($0.width, $0.height) }
            var result = content
            result.lastSize = size ?? previous?.lastSize
            return result
        } catch {
            return kept(previous, problem: Self.message(for: error), warnings: warnings)
        }
    }

    public static let unprojectableSentence = "The view couldn't be projected."

    static func message(for error: any Error) -> String {
        if let error = error as? KernelError { return error.userMessage }
        if error is CancellationError { return "The view was cancelled." }
        return Self.unprojectableSentence
    }
}
