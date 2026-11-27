import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Refreshing the last good values after every evaluation (drawings plan R26). Composing, and so the editor's `remembered`, happens
/// only in Drawing mode and for the shown sheet. This reads each annotation of every sheet against the model's own results, without
/// projecting or laying anything out, so a dimension whose edge a Model-mode edit takes away still shows what it last measured.
extension DrawingSession {
    /// One shown part of a view's refresh: its Output, its place in the view's `outputs` (an assembly's hatch angle) and what it holds.
    struct RefreshPart: Sendable {
        var output: NodeID
        var index: Int
        var solids: [Solid]
        var curves: [Curve]
    }

    /// What one view's refresh was made from: its parts' solids by identity, its frame, the number format and its annotations, each
    /// with its placement fields fixed (`DrawingAnnotation.placementStripped`), so dragging one starts no refresh (drawings speed R5).
    struct RefreshKey: Hashable, Sendable {
        var outputs: [NodeID] = []
        var solidCounts: [Int] = []
        var solids: [ObjectIdentifier]
        var frame: ProjectionFrame
        var format: NumberFormat
        var annotations: [DrawingAnnotation]
        /// A section's cutting line and the tolerance its cut was cached under (R14): its annotations read the cut remainders.
        var cutter: SectionCutter?
        var tolerance: Double = 0
        /// Whether the view is pictorial and so holds no dimension or symbol (DR-5 R21).
        var isPictorial = false
        /// The solids themselves, kept alive so that an identity in `solids` can't be reused by a later solid at the same address.
        /// Not part of the key's equality.
        var retained: [Solid] = []

        static func == (lhs: RefreshKey, rhs: RefreshKey) -> Bool {
            lhs.outputs == rhs.outputs && lhs.solidCounts == rhs.solidCounts && lhs.solids == rhs.solids
                && lhs.frame == rhs.frame && lhs.format == rhs.format && lhs.annotations == rhs.annotations
                && lhs.cutter == rhs.cutter && lhs.tolerance == rhs.tolerance && lhs.isPictorial == rhs.isPictorial
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(outputs)
            hasher.combine(solidCounts)
            hasher.combine(solids)
            hasher.combine(frame)
            hasher.combine(format)
            hasher.combine(annotations)
            hasher.combine(cutter)
            hasher.combine(tolerance)
            hasher.combine(isPictorial)
        }
    }

    /// One view's refresh: what to read and against what.
    struct RefreshJob: Sendable {
        var view: ViewID
        /// The Output the view's compound is tagged by (`view.source`).
        var output: NodeID
        var isAssembly: Bool
        var parts: [RefreshPart]
        var key: RefreshKey
    }

    /// What a refresh read: the figures, and the spans the anchors were judged against (empty for a view of one Output).
    struct RefreshResult: Sendable {
        var goods: [AnnotationID: LastGood] = [:]
        var spans: [PartSpan] = []
    }

    /// The parts of `view` that something is drawn for, or `nil` when the refresh can't read the view now: a part that failed or is
    /// still evaluating holds the whole view, as the projector does (R2), and no part with anything to draw leaves nothing to read.
    private func shownParts(of view: DrawingView) -> [RefreshPart]? {
        var shown: [RefreshPart] = []
        for (index, source) in sources(of: view).enumerated() {
            switch source.state {
            case .failed, .evaluating: return nil
            case .removed: continue
            case .ready(let solids, let curves, _):
                if solids.isEmpty, curves.isEmpty { continue }
                shown.append(RefreshPart(output: source.output, index: index, solids: solids, curves: curves))
            }
        }
        return shown.contains { !$0.solids.isEmpty } ? shown : nil
    }

    /// The views whose source has new results (or whose annotations or format changed). A view whose source isn't ready, or has no
    /// solid, is skipped and keeps what is remembered.
    private func pendingRefreshes() -> [RefreshJob] {
        let drawings = editor.document
        let format = NumberFormat(units: document.units, settings: drawings.settings)
        var pending: [RefreshJob] = []
        // A deleted view's record would keep its solids alive for the whole session.
        let live = Set(drawings.sheets.flatMap { $0.views.map(\.id) })
        for id in refreshed.keys where !live.contains(id) { refreshed[id] = nil }
        for sheet in drawings.sheets {
            for view in sheet.views {
                let annotations = sheet.annotations(of: view.id).filter { annotation in
                    if case .note = annotation.kind { false } else { true }
                }
                guard !annotations.isEmpty, let parts = shownParts(of: view) else { continue }
                // A detail reads what its nearest non-detail ancestor shows (R14); a section, its cut remainders.
                let base = sheet.nearestNonDetail(of: view) ?? view
                var cutter: SectionCutter?
                if case .section(let line)? = base.derivation { cutter = line.cutter }
                let solids = parts.flatMap(\.solids)
                let key = RefreshKey(
                    outputs: parts.map(\.output), solidCounts: parts.map(\.solids.count), solids: solids.map(ObjectIdentifier.init),
                    frame: base.orientation.frame, format: format, annotations: annotations.map(\.placementStripped), cutter: cutter,
                    tolerance: 0.01 / (base.scale ?? sheet.scale).value, isPictorial: sheet.isPictorial(view), retained: solids)
                if refreshed[view.id] != key {
                    pending.append(
                        RefreshJob(view: view.id, output: base.source, isAssembly: base.isAssembly, parts: parts, key: key))
                }
            }
        }
        return pending
    }

    /// Starts reading what `pendingRefreshes()` finds, one task at a time: a newer evaluation cancels the older.
    func refreshLastGood() {
        let pending = pendingRefreshes()
        guard !pending.isEmpty else { return }
        let wanted = Dictionary(pending.map { ($0.view, $0.key) }, uniquingKeysWith: { first, _ in first })
        if refreshTask != nil, wanted.allSatisfy({ refreshing[$0.key] == $0.value }) { return }
        refreshTask?.cancel()
        refreshing = wanted
        refreshGeneration += 1
        let generation = refreshGeneration
        let (cache, kernel) = (self.cache, self.kernel)
        refreshTask = Task { @MainActor [weak self] in
            for job in pending {
                if Task.isCancelled { return }
                let result = await Self.lastGood(of: job, cache: cache, kernel: kernel)
                if Task.isCancelled { return }
                self?.editor.remember(result.goods)
                self?.refreshed[job.view] = job.key
                self?.refreshObserver?(job.view, result.spans)
            }
            guard let self, generation == self.refreshGeneration else { return }
            refreshTask = nil
            refreshing = [:]
        }
    }

    /// The figures `job`'s annotations hold on the topology of its solids; none when the topology can't be had (a compound the kernel
    /// refuses), in which case what is remembered stays. An assembly's solids are laid out by `PartSpan.layout`, the one rule the
    /// projector uses, so an anchor is judged against the spans the sheet shows (DR-5 R2).
    @concurrent
    static func lastGood(of job: RefreshJob, cache: ProjectionCache, kernel: any Kernel) async -> RefreshResult {
        let tag = NodeTag(node: job.output, item: 0)
        var shown = job.parts.flatMap(\.solids)
        var spans: [PartSpan] = []
        if job.isAssembly {
            guard let layout = await assemblyLayout(of: job, cache: cache, kernel: kernel) else { return RefreshResult() }
            shown = layout.solids
            spans = layout.spans
        } else if let cutter = job.key.cutter {
            shown = []
            for (index, solid) in (job.parts.first?.solids ?? []).enumerated() {
                guard let piece = try? await cache.sectionCut(
                    of: solid, index: index, cutter: cutter, tolerance: job.key.tolerance, kernel: kernel)
                else { return RefreshResult() }
                if let remainder = piece.remainder { shown.append(remainder) }
            }
        }
        guard let found = try? await cache.topology(of: shown, compoundTag: tag, kernel: kernel) else {
            return RefreshResult(spans: spans)
        }
        var goods: [AnnotationID: LastGood] = [:]
        AnnotationRefresh.pass {
            for annotation in job.key.annotations {
                let good = AnnotationRefresh.lastGood(
                    for: annotation, topology: found, frame: job.key.frame, format: job.key.format,
                    standard: job.key.format.standard, parts: spans, isPictorial: job.key.isPictorial)
                if let good { goods[annotation.id] = good }
            }
        }
        return RefreshResult(goods: goods, spans: spans)
    }

    /// An assembly's solids laid out as the projector lays them out: each distinct solid cut once for a section, by its part's index in
    /// the view's Outputs (the hatch angle, R2 (b)), then `PartSpan.layout`. `nil` when a cut can't be had.
    private nonisolated static func assemblyLayout(of job: RefreshJob, cache: ProjectionCache, kernel: any Kernel) async -> PartLayout? {
        guard let cutter = job.key.cutter else {
            return PartSpan.layout(job.parts.map { PartSolids(output: $0.output, solids: $0.solids, curves: $0.curves) })
        }
        var seen = Set<ObjectIdentifier>()
        var remainders: [PartSolids] = []
        for part in job.parts {
            var cut: [Solid] = []
            for solid in part.solids where seen.insert(ObjectIdentifier(solid)).inserted {
                guard let piece = try? await cache.sectionCut(
                    of: solid, index: part.index, cutter: cutter, tolerance: job.key.tolerance, kernel: kernel)
                else { return nil }
                if let remainder = piece.remainder { cut.append(remainder) }
            }
            remainders.append(PartSolids(output: part.output, solids: cut, curves: []))
        }
        return PartSpan.layout(remainders)
    }
}
