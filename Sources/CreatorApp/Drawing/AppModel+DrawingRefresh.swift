import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Refreshing the last good values after every evaluation (drawings plan R26). Composing, and so the editor's `remembered`, happens
/// only in Drawing mode and for the shown sheet. This reads each annotation of every sheet against the model's own results, without
/// projecting or laying anything out, so a dimension whose edge a Model-mode edit takes away still shows what it last measured.
extension DrawingSession {
    /// What one view's refresh was made from: its Output's solids by identity, its frame, the number format and its annotations.
    struct RefreshKey: Hashable, Sendable {
        var solids: [ObjectIdentifier]
        var frame: ProjectionFrame
        var format: NumberFormat
        var annotations: [DrawingAnnotation]
        /// The solids themselves, kept alive so that an identity in `solids` can't be reused by a later solid at the same address.
        /// Not part of the key's equality.
        var retained: [Solid] = []

        static func == (lhs: RefreshKey, rhs: RefreshKey) -> Bool {
            lhs.solids == rhs.solids && lhs.frame == rhs.frame && lhs.format == rhs.format && lhs.annotations == rhs.annotations
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(solids)
            hasher.combine(frame)
            hasher.combine(format)
            hasher.combine(annotations)
        }
    }

    /// One view's refresh: what to read and against what.
    struct RefreshJob: Sendable {
        var view: ViewID
        var output: NodeID
        var solids: [Solid]
        var key: RefreshKey
    }

    /// The views whose source has new results (or whose annotations or format changed). A view whose source isn't ready, or has no
    /// solid, is skipped and keeps what is remembered.
    private func pendingRefreshes() -> [RefreshJob] {
        let drawings = editor.document
        let format = NumberFormat(units: document.units, settings: drawings.settings)
        var pending: [RefreshJob] = []
        for sheet in drawings.sheets {
            for view in sheet.views {
                let annotations = sheet.annotations(of: view.id).filter { annotation in
                    if case .note = annotation.kind { false } else { true }
                }
                let source = Self.content(of: view.source, in: document)
                guard !annotations.isEmpty, case .ready(let solids, _, _) = source.state, !solids.isEmpty else { continue }
                let key = RefreshKey(
                    solids: solids.map(ObjectIdentifier.init), frame: view.orientation.frame, format: format,
                    annotations: annotations, retained: solids)
                if refreshed[view.id] != key {
                    pending.append(RefreshJob(view: view.id, output: source.output, solids: solids, key: key))
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
                let goods = await Self.lastGood(of: job, cache: cache, kernel: kernel)
                if Task.isCancelled { return }
                self?.editor.remember(goods)
                self?.refreshed[job.view] = job.key
            }
            guard let self, generation == self.refreshGeneration else { return }
            refreshTask = nil
            refreshing = [:]
        }
    }

    /// The figures `job`'s annotations hold on the topology of its solids; none when the topology can't be had (a compound the kernel
    /// refuses), in which case what is remembered stays.
    @concurrent
    static func lastGood(of job: RefreshJob, cache: ProjectionCache, kernel: any Kernel) async -> [AnnotationID: LastGood] {
        let tag = NodeTag(node: job.output, item: 0)
        guard let found = try? await cache.topology(of: job.solids, compoundTag: tag, kernel: kernel) else { return [:] }
        var goods: [AnnotationID: LastGood] = [:]
        for annotation in job.key.annotations {
            let good = AnnotationRefresh.lastGood(
                for: annotation, topology: found, frame: job.key.frame, format: job.key.format, standard: job.key.format.standard)
            if let good { goods[annotation.id] = good }
        }
        return goods
    }
}
