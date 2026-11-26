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
    /// Carries out what the editor asks of the host: a template, a logo file (DR-5 R10, R16); set by the app.
    @ObservationIgnored var requestHandler: (@MainActor (DrawingEditorRequest) -> Void)?
    /// Whether Drawing mode is up: projections are made only then.
    @ObservationIgnored public private(set) var isActive = false

    struct RequestKey: Hashable, Sendable {
        var state: Int
        /// The Outputs the view shows, each one's state and how many solids and curves it holds (DR-5 R2): moving a solid from
        /// one part to another, or a part failing, changes the request though the flat lists below might not.
        var outputs: [NodeID] = []
        var partStates: [Int] = []
        var partCounts: [[Int]] = []
        var solids: [ObjectIdentifier]
        var curves: [ObjectIdentifier]
        var meshCount: Int
        var failure: String?
        var frame: ProjectionFrame
        var scale: Double
        /// A section view's cutting line (R14): moving it asks again, and nothing else about the key changes.
        var cutter: SectionCutter?
        /// The solids themselves, kept alive so that an identity in `solids` can't be reused by a later solid at the same address
        /// (the cache evicting one and an edit allocating the next there would otherwise look like no change). Not part of equality.
        var retained: [Solid] = []
        /// The curves, kept alive for the same reason (R14). Not part of equality.
        var retainedCurves: [Curve] = []

        static func == (lhs: RequestKey, rhs: RequestKey) -> Bool {
            lhs.state == rhs.state && lhs.outputs == rhs.outputs && lhs.partStates == rhs.partStates
                && lhs.partCounts == rhs.partCounts && lhs.solids == rhs.solids && lhs.curves == rhs.curves
                && lhs.meshCount == rhs.meshCount
                && lhs.failure == rhs.failure && lhs.frame == rhs.frame && lhs.scale == rhs.scale && lhs.cutter == rhs.cutter
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(state)
            hasher.combine(outputs)
            hasher.combine(partStates)
            hasher.combine(partCounts)
            hasher.combine(solids)
            hasher.combine(curves)
            hasher.combine(meshCount)
            hasher.combine(failure)
            hasher.combine(frame)
            hasher.combine(scale)
            hasher.combine(cutter)
        }
    }

    /// What a detail's content was last made from (R14): its parent's content generation and its circle.
    struct DetailInput: Hashable {
        var parentGeneration: Int
        var circle: DetailCircle
    }

    struct Flight {
        var key: RequestKey
        var task: Task<Void, Never>
    }

    @ObservationIgnored var wanted: [ViewID: RequestKey] = [:]
    @ObservationIgnored var applied: [ViewID: RequestKey] = [:]
    @ObservationIgnored var flights: [ViewID: Flight] = [:]
    /// Counts the contents a view has been given, so a detail knows when its parent's changed (R14).
    @ObservationIgnored var generations: [ViewID: Int] = [:]
    @ObservationIgnored var detailInputs: [ViewID: DetailInput] = [:]
    @ObservationIgnored var factsTask: Task<Void, Never>?
    @ObservationIgnored var factsKey: FactsKey?
    /// The mass the last finished measurement gave the shown sheet.
    @ObservationIgnored var shownMass: String?
    /// Logos decoded or refused by the hash of their bytes (R11), and the decodes running.
    @ObservationIgnored var logoCache: [String: LogoFact] = [:]
    @ObservationIgnored var logoTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var logoDecoder: LogoDecoder = DrawingSession.defaultLogoDecoder
    /// Volumes by solid identity; the entry keeps its solid alive so an identity can't be reused.
    @ObservationIgnored var volumes: [ObjectIdentifier: (solid: Solid, volume: Double?)] = [:]
    @ObservationIgnored private let relay: Relay
    /// The refresh of the last good values after an evaluation (plan R26): what is read, what is being read.
    @ObservationIgnored var refreshed: [ViewID: RefreshKey] = [:]
    @ObservationIgnored var refreshing: [ViewID: RefreshKey] = [:]
    @ObservationIgnored var refreshTask: Task<Void, Never>?
    @ObservationIgnored var refreshGeneration = 0
    /// A test hook: told the spans each refresh judged a view's anchors against (empty for a view of one Output).
    @ObservationIgnored var refreshObserver: (@MainActor (ViewID, [PartSpan]) -> Void)?

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
                discarded: { key in relay.session?.discardHandler?(key) },
                requested: { request in relay.session?.requestHandler?(request) }))
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
        for task in logoTasks.values { task.cancel() }
        logoTasks = [:]
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
    public var isProjecting: Bool { !flights.isEmpty || factsTask != nil || refreshTask != nil || !logoTasks.isEmpty }

    /// Waits until every projection and fact requested so far has landed.
    public func waitForProjections() async {
        while isProjecting {
            let tasks = flights.values.map(\.task) + (factsTask.map { [$0] } ?? []) + (refreshTask.map { [$0] } ?? [])
                + Array(logoTasks.values)
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
        pruneGoneViews()
        if editor.units != document.units { editor.units = document.units }
        followParts()
        refreshLastGood()
        updateFeedingViews()
        guard isActive else { return }
        let outputs = document.graph.nodes.values.filter(\.isOutput).map(\.id).sorted()
        let options = outputs.compactMap { id in options(for: id) }
        if editor.sources != options { editor.sources = options }
        guard let sheet = editor.document.sheet(editor.currentSheet ?? SheetID()) else { return }
        request(views: sheet.viewsParentsFirst, in: sheet)
        followFacts(of: sheet)
    }

    /// The request a view's projection must match: its Output's solids and curves, its frame, its scale and a section's line.
    func requestKey(for view: DrawingView, in sheet: DrawingSheet) -> RequestKey {
        var cutter: SectionCutter?
        if case .section(let line)? = view.derivation { cutter = line.cutter }
        return Self.key(
            of: sources(of: view), frame: view.orientation.frame, scale: (view.scale ?? sheet.scale).value, cutter: cutter)
    }

    /// The views whose held projection is the one the model wants now: only these may feed the editor's remembered values. A
    /// detail is trusted when its parent is and its content was made from the parent's current one.
    func updateFeedingViews() {
        var trusted = Set<ViewID>()
        for sheet in editor.document.sheets {
            for view in sheet.viewsParentsFirst {
                if view.kind == .detail {
                    if let parent = view.derivation?.parent, trusted.contains(parent), detailIsCurrent(view),
                       editor.contents[view.id]?.isPending != true {
                        trusted.insert(view.id)
                    }
                } else if applied[view.id] == requestKey(for: view, in: sheet), editor.contents[view.id]?.isPending != true {
                    trusted.insert(view.id)
                }
            }
        }
        editor.feedingViews = trusted
    }

    func detailIsCurrent(_ view: DrawingView) -> Bool {
        guard case .detail(let circle)? = view.derivation, let input = detailInputs[view.id] else { return false }
        return input == DetailInput(parentGeneration: generations[circle.parent] ?? 0, circle: circle)
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
        for view in views where view.kind != .detail {
            let scale = (view.scale ?? sheet.scale).value
            let parts = sources(of: view)
            let key = requestKey(for: view, in: sheet)
            wanted[view.id] = key
            if applied[view.id] == key || flights[view.id]?.key == key { continue }
            flights[view.id]?.task.cancel()
            var pending = editor.contents[view.id] ?? ViewContent()
            pending.isPending = true
            editor.feedingViews?.remove(view.id)
            setContent(pending, for: view.id)
            let id = view.id
            let previous = editor.contents[id]
            let task = Task { @MainActor [weak self] in
                let content = await Self.projected(projector, view: view, scale: scale, sources: parts, previous: previous)
                self?.land(content, for: id, key: key)
            }
            flights[id] = Flight(key: key, task: task)
        }
        syncDetails(in: sheet)
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
        setContent(shown, for: id)
        applied[id] = key
        if let sheet = editor.document.sheet(editor.currentSheet ?? SheetID()) { syncDetails(in: sheet) }
    }

    /// `RequestKey.state` of a source whose result is being made.
    static let evaluatingState = 2
    /// `RequestKey.state` of a source whose evaluation failed.
    static let failedState = 1

    static func key(
        of source: DrawingSourceContent, frame: ProjectionFrame, scale: Double, cutter: SectionCutter? = nil
    ) -> RequestKey {
        key(of: [source], frame: frame, scale: scale, cutter: cutter)
    }
}
