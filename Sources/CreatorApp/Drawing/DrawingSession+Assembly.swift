import CreatorDrawing
import CreatorKernel

/// Requests for assembly views (DR-5 R2): a view shows one or several Outputs, projected as one compound; its request key tells each
/// part's state and what it holds, so a part failing, going or changing asks again.
extension DrawingSession {
    /// What each of the view's Outputs holds now, in the view's order (a view of one Output has one).
    func sources(of view: DrawingView) -> [DrawingSourceContent] {
        view.outputs.map { Self.content(of: $0, in: document) }
    }

    /// The content of `view`: one Output is DR-1's path, an assembly's parts are projected as one compound (DR-5 R2).
    nonisolated static func projected(
        _ projector: DrawingProjector, view: DrawingView, scale: Double, sources: [DrawingSourceContent], previous: ViewContent?
    ) async -> ViewContent {
        if view.isAssembly || sources.count != 1 {
            return await projector.content(for: view, scale: scale, parts: sources, previous: previous)
        }
        return await projector.content(for: view, scale: scale, source: sources[0], previous: previous)
    }

    /// The key of a view of one or several Outputs: the flat lists run over every part in order, and the per-part counts and states
    /// tell which part holds what. Any failed part makes the key a failed one, else any evaluating part an evaluating one, and
    /// every part removed a removed one.
    static func key(
        of sources: [DrawingSourceContent], frame: ProjectionFrame, scale: Double, cutter: SectionCutter? = nil
    ) -> RequestKey {
        var key = RequestKey(
            state: 3, solids: [], curves: [], meshCount: 0, failure: nil, frame: frame, scale: scale, cutter: cutter)
        key.outputs = sources.map(\.output)
        var failed: String?
        var evaluating = false
        var removed = 0
        for source in sources {
            switch source.state {
            case .removed:
                removed += 1
                key.partStates.append(0)
                key.partCounts.append([0, 0, 0])
            case .failed(let message):
                if failed == nil {
                    failed = sources.count == 1 ? message : DrawingProjector.partFailedSentence(name: source.name, message: message)
                }
                key.partStates.append(failedState)
                key.partCounts.append([0, 0, 0])
            case .evaluating:
                evaluating = true
                key.partStates.append(evaluatingState)
                key.partCounts.append([0, 0, 0])
            case .ready(let solids, let curves, let meshCount):
                key.solids += solids.map(ObjectIdentifier.init)
                key.curves += curves.map(ObjectIdentifier.init)
                key.retained += solids
                key.retainedCurves += curves
                key.meshCount += meshCount
                key.partStates.append(3)
                key.partCounts.append([solids.count, curves.count, meshCount])
            }
        }
        if let failed {
            key.state = failedState
            key.failure = failed
        } else if evaluating {
            key.state = evaluatingState
        } else if removed == sources.count {
            key.state = 0
        }
        if key.state != 3 {
            key.solids = []
            key.curves = []
            key.meshCount = 0
            key.retained = []
            key.retainedCurves = []
        }
        return key
    }
}
