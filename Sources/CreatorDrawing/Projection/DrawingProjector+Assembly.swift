import CreatorGeometry
import CreatorKernel

extension DrawingProjector {
    public static let partRemovedSentence = "One of this view's parts was removed from the model, so it isn't drawn."

    public static func partFailedSentence(name: String, message: String) -> String {
        "“\(name)” can't be drawn: \(message)"
    }

    public static func partEmptySentence(name: String) -> String {
        "“\(name)” holds nothing to draw, so this view leaves it out."
    }

    public static func partMeshesSentence(name: String, count: Int) -> String {
        let shown = count.formatted(.number.locale(.messages))
        return count == 1
            ? "This view leaves out “\(name)”'s mesh; drawings show solids, sheets and curves."
            : "This view leaves out “\(name)”'s \(shown) meshes; drawings show solids, sheets and curves."
    }

    public static func sharedSolidSentence(name: String, other: String) -> String {
        "“\(name)” shows the same solid as “\(other)”, so this view draws it once."
    }

    private struct SectionRequest {
        var line: SectionLine
        var scale: Double
        var view: DrawingView
        var sources: [PartSolids]
        var indices: [Int]
        var warnings: [String]
    }

    private enum Blocking {
        case failed(String)
        case evaluating
    }

    /// A failed part (the first) or an evaluating one stops the view from changing.
    private static func blocking(_ parts: [DrawingSourceContent]) -> Blocking? {
        var evaluating = false
        for part in parts {
            switch part.state {
            case .failed(let message): return .failed(partFailedSentence(name: part.name, message: message))
            case .evaluating: evaluating = true
            default: break
            }
        }
        return evaluating ? .evaluating : nil
    }

    private struct Gathered {
        var shown: [(index: Int, solids: [Solid], curves: [Curve])] = []
        var warnings: [String] = []
        var meshes = 0
        var anyPart = false
    }

    /// The parts that have something to draw, and the sentences about the ones that don't.
    private static func gather(_ parts: [DrawingSourceContent]) -> Gathered {
        var result = Gathered()
        var anyRemoved = false
        for (index, part) in parts.enumerated() {
            switch part.state {
            case .removed:
                anyRemoved = true
            case .ready(let solids, let curves, let meshCount):
                result.anyPart = true
                result.meshes += meshCount
                if meshCount > 0 { result.warnings.append(partMeshesSentence(name: part.name, count: meshCount)) }
                if solids.isEmpty, curves.isEmpty {
                    if meshCount == 0 { result.warnings.append(partEmptySentence(name: part.name)) }
                } else {
                    result.shown.append((index, solids, curves))
                }
            case .failed, .evaluating:
                break
            }
        }
        if anyRemoved, result.anyPart { result.warnings.insert(partRemovedSentence, at: 0) }
        return result
    }

    /// An assembly view's content (R2): every shown part's solids projected as one compound, with the parts' spans. `parts` are the
    /// view's Outputs' contents in `outputs` order; a part's index there is its hatch angle's.
    public func content(for view: DrawingView, scale: Double, parts: [DrawingSourceContent], previous: ViewContent?) async
        -> ViewContent {
        switch Self.blocking(parts) {
        case .failed(let sentence): return kept(previous, problem: sentence)
        case .evaluating: return kept(previous, problem: previous?.problem, warnings: previous?.warnings ?? [])
        case nil: break
        }
        let gathered = Self.gather(parts)
        var warnings = gathered.warnings
        guard !gathered.shown.isEmpty else {
            let problem =
                gathered.anyPart ? (gathered.meshes > 0 ? Self.onlyMeshesSentence : Self.nothingYetSentence) : Self.removedSentence
            return ViewContent(problem: problem, lastSize: previous?.lastSize)
        }
        let shown = gathered.shown
        var names: [NodeID: String] = [:]
        for part in parts { names[part.output] = part.name }
        let sources = shown.map { PartSolids(output: parts[$0.index].output, solids: $0.solids, curves: $0.curves) }
        let plain = PartSpan.layout(sources)
        for pair in plain.shared {
            warnings.append(Self.sharedSolidSentence(name: names[pair.part] ?? "", other: names[pair.other] ?? ""))
        }
        if case .section(let line)? = view.derivation {
            if sources.contains(where: { !$0.curves.isEmpty }) { warnings.append(Self.curvesLeftOutSentence) }
            let request = SectionRequest(
                line: line, scale: scale, view: view, sources: sources, indices: shown.map(\.index), warnings: warnings)
            return await assemblySection(request, previous: previous)
        }
        do {
            let cached = try await cache.projection(
                of: plain.solids, curves: plain.curves, compoundTag: NodeTag(node: view.source, item: 0),
                frame: view.orientation.frame, options: ProjectionOptions(tolerance: 0.01 / scale), kernel: kernel)
            let size = ViewLinework.frame(for: ViewContent(projection: cached.projection), center: .zero, scale: scale)
                .map { Vector2($0.width, $0.height) }
            return ViewContent(
                projection: cached.projection, topology: cached.topology, warnings: warnings,
                lastSize: size ?? previous?.lastSize, parts: plain.spans)
        } catch {
            return kept(previous, problem: Self.message(for: error), warnings: warnings)
        }
    }

    /// A section of an assembly: each distinct solid cut with its part's index (the hatch angle), the spans built over the remainders.
    private func assemblySection(_ request: SectionRequest, previous: ViewContent?) async -> ViewContent {
        let (line, scale, view, sources, indices) = (request.line, request.scale, request.view, request.sources, request.indices)
        var warnings = request.warnings
        guard sources.contains(where: { !$0.solids.isEmpty }) else {
            return ViewContent(problem: Self.noSolidsToCutSentence, warnings: warnings, lastSize: previous?.lastSize)
        }
        do {
            let tolerance = 0.01 / scale
            var seen = Set<ObjectIdentifier>()
            var remainders: [PartSolids] = []
            var hatch: [HatchRegion] = []
            var hatchFailed = false
            for (source, index) in zip(sources, indices) {
                var cut: [Solid] = []
                for solid in source.solids where seen.insert(ObjectIdentifier(solid)).inserted {
                    let piece = try await cache.sectionCut(
                        of: solid, index: index, cutter: line.cutter, tolerance: tolerance, kernel: kernel)
                    if let remainder = piece.remainder { cut.append(remainder) }
                    hatch += piece.regions
                    hatchFailed = hatchFailed || piece.hatchFailed
                }
                remainders.append(PartSolids(output: source.output, solids: cut, curves: []))
            }
            let layout = PartSpan.layout(remainders)
            if layout.solids.isEmpty {
                return ViewContent(problem: Self.cutAwaySentence, warnings: warnings, lastSize: previous?.lastSize)
            }
            let cached = try await cache.projection(
                of: layout.solids, curves: [], compoundTag: NodeTag(node: view.source, item: 0),
                frame: SectionFrame.frame(for: line.cutter), options: ProjectionOptions(tolerance: tolerance), kernel: kernel)
            let projection = cached.topology.map { SectionLines.droppingSteps(cached.projection, topology: $0) }
                ?? cached.projection
            if hatchFailed { warnings.append(Self.hatchFailedSentence) }
            var result = ViewContent(
                projection: projection, topology: cached.topology, warnings: warnings, hatch: hatch, parts: layout.spans)
            let size = ViewLinework.frame(for: result, center: .zero, scale: scale).map { Vector2($0.width, $0.height) }
            result.lastSize = size ?? previous?.lastSize
            return result
        } catch {
            return kept(previous, problem: Self.message(for: error), warnings: warnings)
        }
    }
}
