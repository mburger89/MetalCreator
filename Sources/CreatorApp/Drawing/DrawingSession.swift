import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Observation

/// The drawing editor in the app (plan R19 to R21): it owns the editor model and the projection cache, turns the Output nodes'
/// results into what each view shows (`DrawingProjector`), keeps the editor's copy of the drawings level with the document's (undo,
/// redo, New and Open) and keeps the title block's facts. Graph edits go out through `commitHandler`; the app stores them.
///
/// Requests are per view: a view's wanted key (its Output's solids and curves by identity, its frame and its scale) is what a
/// result must still match to be published, so a newer request replaces an older one and the older one's late result is dropped.
@MainActor
@Observable
public final class DrawingSession {
    public let editor: DrawingEditorModel
    public let cache: ProjectionCache
    let kernel: any Kernel
    let document: DocumentModel
    /// Stores one editor commit as an undo step; set by the app.
    @ObservationIgnored var commitHandler: (@MainActor (DrawingCommit) -> Void)?
    /// Records the sheet the editor shows; set by the app.
    @ObservationIgnored var sheetHandler: (@MainActor (SheetID?) -> Void)?
    /// Takes back the undo steps a cancelled drag had made (plan R18); set by the app.
    @ObservationIgnored var discardHandler: (@MainActor (String) -> Void)?
    /// Whether Drawing mode is up: projections are made only then.
    @ObservationIgnored public private(set) var isActive = false

    struct RequestKey: Hashable, Sendable {
        var state: Int
        var solids: [ObjectIdentifier]
        var curves: [ObjectIdentifier]
        var meshCount: Int
        var failure: String?
        var frame: ProjectionFrame
        var scale: Double
        /// The solids themselves, kept alive so that an identity in `solids` can't be reused by a later solid at the same address
        /// (the cache evicting one and an edit allocating the next there would otherwise look like no change). Not part of equality.
        var retained: [Solid] = []

        static func == (lhs: RequestKey, rhs: RequestKey) -> Bool {
            lhs.state == rhs.state && lhs.solids == rhs.solids && lhs.curves == rhs.curves && lhs.meshCount == rhs.meshCount
                && lhs.failure == rhs.failure && lhs.frame == rhs.frame && lhs.scale == rhs.scale
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(state)
            hasher.combine(solids)
            hasher.combine(curves)
            hasher.combine(meshCount)
            hasher.combine(failure)
            hasher.combine(frame)
            hasher.combine(scale)
        }
    }

    struct Flight {
        var key: RequestKey
        var task: Task<Void, Never>
    }

    @ObservationIgnored var wanted: [ViewID: RequestKey] = [:]
    @ObservationIgnored var applied: [ViewID: RequestKey] = [:]
    @ObservationIgnored var flights: [ViewID: Flight] = [:]
    @ObservationIgnored var factsTask: Task<Void, Never>?
    @ObservationIgnored var factsKey: FactsKey?
    /// Volumes by solid identity; the entry keeps its solid alive so an identity can't be reused.
    @ObservationIgnored var volumes: [ObjectIdentifier: (solid: Solid, volume: Double?)] = [:]
    @ObservationIgnored private let relay: Relay
    /// The refresh of the last good values after an evaluation (plan R26): what is read, what is being read.
    @ObservationIgnored var refreshed: [ViewID: RefreshKey] = [:]
    @ObservationIgnored var refreshing: [ViewID: RefreshKey] = [:]
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var refreshGeneration = 0

    /// Hands the editor's events to the session, which doesn't exist yet when the editor is made.
    final class Relay {
        weak var session: DrawingSession?
    }

    init(document: DocumentModel, kernel: any Kernel, today: @escaping () -> String = DrawingSession.today) {
        self.document = document
        self.kernel = kernel
        cache = ProjectionCache()
        let relay = Relay()
        self.relay = relay
        let drawings = document.drawings
        let saved = document.drawingView?.sheet
        let sheet = saved.flatMap { drawings.sheet($0) != nil ? $0 : nil } ?? drawings.sheets.first?.id
        editor = DrawingEditorModel(
            document: drawings, sheet: sheet, units: document.units, today: today,
            events: DrawingEditorEvents(
                committed: { commit in relay.session?.commitHandler?(commit) },
                sheetChanged: { id in relay.session?.editorShowed(sheet: id) },
                discarded: { key in relay.session?.discardHandler?(key) }))
        // Not shown yet: its contents are only as new as the last projection, so its pictures feed nothing (`activate()` turns it on).
        editor.feedsRemembered = false
        relay.session = self
    }

    /// The creation day, ISO 8601, in the Gregorian calendar whatever the locale (plan R15).
    public nonisolated static func today() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Stops every request in flight; the session belongs to a document that is being replaced.
    func stop() {
        isActive = false
        for flight in flights.values { flight.task.cancel() }
        flights = [:]
        factsTask?.cancel()
        factsTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        relay.session = nil
    }

    /// Drawing mode begins: the sheet is fitted and its views are projected.
    func activate() {
        isActive = true
        updateFeedingViews()
        editor.feedsRemembered = true
        editor.requestFit()
        update()
    }

    func deactivate() {
        isActive = false
        editor.feedsRemembered = false
    }

    private func editorShowed(sheet id: SheetID?) {
        sheetHandler?(id)
        editor.requestFit()
        update()
    }

    /// Whether any projection or fact is still being made.
    public var isProjecting: Bool { !flights.isEmpty || factsTask != nil || refreshTask != nil }

    /// Waits until every projection and fact requested so far has landed.
    public func waitForProjections() async {
        while isProjecting {
            let tasks = flights.values.map(\.task) + (factsTask.map { [$0] } ?? []) + (refreshTask.map { [$0] } ?? [])
            for task in tasks { await task.value }
        }
    }

    /// Takes the document's drawings back into the editor when they differ (undo, redo, a refused edit).
    func resync() {
        let drawings = document.drawings
        if editor.document != drawings { editor.replaceDocument(drawings) }
    }

    /// Follows the document: the editor's drawings, its sources, and (in Drawing mode) the projections and the facts.
    func update() {
        resync()
        if editor.units != document.units { editor.units = document.units }
        refreshLastGood()
        updateFeedingViews()
        guard isActive else { return }
        let outputs = document.graph.nodes.values.filter(\.isOutput).map(\.id).sorted()
        let options = outputs.compactMap { id in options(for: id) }
        if editor.sources != options { editor.sources = options }
        guard let sheet = editor.document.sheet(editor.currentSheet ?? SheetID()) else { return }
        request(views: sheet.views, in: sheet)
        followFacts(of: sheet)
    }

    /// The views whose held projection is the one the model wants now: only these may feed the editor's remembered values.
    func updateFeedingViews() {
        var trusted = Set<ViewID>()
        let scaleOf = { (sheet: DrawingSheet, view: DrawingView) in (view.scale ?? sheet.scale).value }
        for sheet in editor.document.sheets {
            for view in sheet.views {
                let source = Self.content(of: view.source, in: document)
                let key = Self.key(of: source, frame: view.orientation.frame, scale: scaleOf(sheet, view))
                if applied[view.id] == key, editor.contents[view.id]?.isPending != true { trusted.insert(view.id) }
            }
        }
        editor.feedingViews = trusted
    }

    private func options(for id: NodeID) -> DrawingSourceOption? {
        guard let node = document.graph.nodes[id] else { return nil }
        guard case .ready(let solids, _, _) = Self.content(of: id, in: document).state else {
            return DrawingSourceOption(id: id, name: node.name, bounds: nil)
        }
        let bounds = solids.map(\.bounds).reduce(nil) { (all: BoundingBox?, next) in all.map { $0.union(next) } ?? next }
        return DrawingSourceOption(id: id, name: node.name, bounds: bounds)
    }

    // MARK: Requests

    private func request(views: [DrawingView], in sheet: DrawingSheet) {
        let projector = DrawingProjector(cache: cache, kernel: kernel)
        for view in views {
            let scale = (view.scale ?? sheet.scale).value
            let source = Self.content(of: view.source, in: document)
            let key = Self.key(of: source, frame: view.orientation.frame, scale: scale)
            wanted[view.id] = key
            if applied[view.id] == key || flights[view.id]?.key == key { continue }
            flights[view.id]?.task.cancel()
            var pending = editor.contents[view.id] ?? ViewContent()
            pending.isPending = true
            editor.feedingViews?.remove(view.id)
            editor.contents[view.id] = pending
            let id = view.id
            let previous = editor.contents[id]
            let task = Task { @MainActor [weak self] in
                let content = await projector.content(for: view, scale: scale, source: source, previous: previous)
                self?.land(content, for: id, key: key)
            }
            flights[id] = Flight(key: key, task: task)
        }
    }

    /// A view's result: published only while it is still what the view wants.
    private func land(_ content: ViewContent, for id: ViewID, key: RequestKey) {
        if flights[id]?.key == key { flights[id] = nil }
        guard wanted[id] == key else { return }
        var shown = content
        // An Output still being rebuilt, or one that failed, hands back the previous lines: they stay faded (a failed one with its
        // sentence under the frame) until a real projection lands. So do the old lines of a ready Output whose projection failed.
        shown.isPending = key.state == Self.evaluatingState
            || ((key.state == Self.failedState || shown.problem != nil) && shown.projection != nil)
        if !shown.isPending { editor.feedingViews?.insert(id) } else { editor.feedingViews?.remove(id) }
        editor.contents[id] = shown
        applied[id] = key
    }

    /// `RequestKey.state` of a source whose result is being made.
    static let evaluatingState = 2
    /// `RequestKey.state` of a source whose evaluation failed.
    static let failedState = 1

    static func key(of source: DrawingSourceContent, frame: ProjectionFrame, scale: Double) -> RequestKey {
        switch source.state {
        case .removed:
            RequestKey(state: 0, solids: [], curves: [], meshCount: 0, failure: nil, frame: frame, scale: scale)
        case .failed(let message):
            RequestKey(state: failedState, solids: [], curves: [], meshCount: 0, failure: message, frame: frame, scale: scale)
        case .evaluating:
            RequestKey(state: evaluatingState, solids: [], curves: [], meshCount: 0, failure: nil, frame: frame, scale: scale)
        case .ready(let solids, let curves, let meshCount):
            RequestKey(
                state: 3, solids: solids.map(ObjectIdentifier.init), curves: curves.map(ObjectIdentifier.init),
                meshCount: meshCount, failure: nil, frame: frame, scale: scale, retained: solids)
        }
    }
}
