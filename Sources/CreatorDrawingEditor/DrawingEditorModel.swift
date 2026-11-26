import CreatorDrawing
import CreatorGeometry
import CreatorKernel
import MetalUI
import Observation

/// The drawing editor's behaviour: sheets, views, selection, moving and the sheet's canvas transform. Graph-free; the host stores
/// each `DrawingCommit` and calls `replaceDocument(_:)` when undo or redo changes the drawings.
@MainActor
@Observable
public final class DrawingEditorModel {
    public internal(set) var document: DrawingDocument {
        didSet { rebuildPicture() }
    }
    public internal(set) var currentSheet: SheetID? {
        didSet { rebuildPicture() }
    }
    public var selection: Set<ViewID> = []
    /// The annotations chosen on the current sheet.
    public var selectedAnnotations: Set<AnnotationID> = []
    public internal(set) var tool: DrawingTool = .select
    public var transform = SheetTransform() {
        // A pan or a zoom is the person's: the sheet is no longer waiting to be fitted to the canvas's first real size.
        didSet { fitsOnNextSize = false }
    }
    public var canvasSize = Vector2(1000, 700)
    /// The part of the canvas that shows, in canvas points; set by the host.
    public var visibleRect = Rect2D(min: .zero, max: Vector2(1000, 700)) {
        didSet {
            if fitsOnNextSize, visibleRect != oldValue {
                fit()
                fitsOnNextSize = false
            }
        }
    }
    public var sources: [DrawingSourceOption] = []
    public var contents: [ViewID: ViewContent] = [:] {
        didSet { rebuildPicture() }
    }
    public var facts = TitleBlockFacts() {
        didSet { rebuildPicture() }
    }
    public internal(set) var refusal: String?
    /// What lies under the pointer for an annotation tool (plan R17): a centre, a corner or a line.
    public internal(set) var hoverCandidate: PickCandidate?
    /// The things picked so far for the annotation being made, in the order they were picked.
    public internal(set) var picks: [PickedAnchor] = []
    /// The view the picks were made in.
    public internal(set) var pickView: ViewID?
    /// The current picture with the annotation being made composed in under the pointer; `nil` without one. Never committed.
    public internal(set) var draftPicture: SheetPicture?
    /// The note whose next click is a leader end (plan R14).
    public internal(set) var addingLeader: AnnotationID?
    /// The cutting line being drawn, the detail circle being dragged out and the auxiliary edge picked (DR-3 R13); view state, never
    /// saved. Each is drawn into `draftPicture` and dropped by Esc, a tool change, a sheet change or an undo that removes its parent.
    public internal(set) var sectionDraft: SectionDraft? {
        didSet { if sectionDraft != oldValue { updateDraft() } }
    }
    public internal(set) var detailDraft: DetailDraft? {
        didSet { if detailDraft != oldValue { updateDraft() } }
    }
    public internal(set) var auxiliaryDraft: AuxiliaryDraft? {
        didSet { if auxiliaryDraft != oldValue { updateDraft() } }
    }
    /// The newest held figures of every annotation seen, for drawing a lost one from its last good value (plan R15). View state:
    /// never an edit, and never fed by a draft.
    @ObservationIgnored public internal(set) var remembered: [AnnotationID: LastGood] = [:]
    /// Whether the pictures the editor builds feed `remembered`. The host turns it off while the editor isn't shown: its contents are
    /// then as old as the last projection, and the host reads the model itself (`remember(_:)`, plan R26).
    @ObservationIgnored public var feedsRemembered = true
    /// The views whose contents the host has confirmed are current with the model; only their pictures feed `remembered`. `nil`
    /// (a standalone editor) means every view is trusted. An old held projection, however many sheets or views are written in a row,
    /// never overwrites what the host's refresh read from the model (plan R26).
    @ObservationIgnored public var feedingViews: Set<ViewID>?
    /// The document's units: lengths in labels read in them. Changing them rebuilds the picture.
    public var units: DocumentUnits {
        didSet { if units != oldValue { rebuildPicture() } }
    }
    /// The tab being renamed in place; view state, committed as one "Rename Sheet" step.
    public internal(set) var renaming: SheetRename?
    public internal(set) var hoveredStroke: Int?
    /// The current sheet composed by `SheetComposer`.
    public private(set) var picture: SheetPicture?

    var standardUnitsAreInches: Bool { units.length == .inches }
    let today: () -> String
    let events: DrawingEditorEvents

    // Gesture state; not observed.
    @ObservationIgnored var gesture: Gesture?
    @ObservationIgnored var dragSerial = 0
    /// The coalescing key of the arrow-key run in progress: a press that isn't an auto-repeat starts a new one.
    @ObservationIgnored var nudgeKey: String?
    /// Text typed into an inspector field and not yet submitted (see `commitPendingEntry()`).
    @ObservationIgnored var pendingDraft: PendingDraft?
    @ObservationIgnored var pinchStart: (zoom: Double, anchor: Vector2)?
    @ObservationIgnored var pointerIsDown = false
    @ObservationIgnored var middleLast: Vector2?
    /// Set by `requestFit()`: the canvas has not reported its size since, so the next size fits the sheet again.
    @ObservationIgnored var fitsOnNextSize = false

    enum Gesture {
        case moving(MoveGesture)
        case projecting(parent: ViewID, start: Vector2)
        case placing
        /// A press with an annotation tool, or a leader end; the click acts on release, with the modifiers of the press.
        case annotating(SheetModifiers)
        /// A press with the Section or Auxiliary tool, or the click that places a detail; the click acts on release.
        case clicking(SheetModifiers)
        /// A detail circle being dragged out from `centerSheet` over a parent mapped at `scale`.
        case detailing(centerSheet: Vector2, scale: Double)
        /// A cutting line or detail circle being dragged on its parent.
        case movingMark(MarkMove)
    }

    /// Where the pointer last was, in sheet millimetres: the draft follows it.
    @ObservationIgnored var lastPointer: Vector2?
    /// The draft's id, one per model: a draft is composed under it and never saved.
    @ObservationIgnored let draftID = AnnotationID()
    /// The id a derived view's draft marks are drawn under.
    @ObservationIgnored let draftViewID = ViewID()

    public init(
        document: DrawingDocument, sheet: SheetID?, units: DocumentUnits = .millimetres, today: @escaping () -> String,
        events: DrawingEditorEvents
    ) {
        self.document = document
        self.currentSheet = document.sheet(sheet ?? SheetID()) != nil ? sheet : nil
        self.units = units
        self.today = today
        self.events = events
        rebuildPicture()
    }

    var sheet: DrawingSheet? { currentSheet.flatMap { document.sheet($0) } }

    func rebuildPicture() {
        defer { updateDraft() }
        guard let sheet else {
            picture = nil
            return
        }
        let composed = SheetComposer.compose(
            sheet, in: document, contents: contents, facts: facts, units: units, remembered: remembered)
        picture = composed
        // The newest held figure of each annotation is what a lost one is drawn from (plan R15).
        // A view still being projected, or one the host isn't showing, is held against the topology it had: what it reports is what
        // is remembered already, or older than what the host's refresh read from the model (plan R25, R26), so it feeds nothing.
        guard feedsRemembered else { return }
        for (id, report) in composed.annotationReports where report.status == .held {
            if let view = sheet.annotation(id)?.view {
                if contents[view]?.isPending == true { continue }
                if let trusted = feedingViews, !trusted.contains(view) { continue }
            }
            if let current = report.current, remembered[id] != current { remembered[id] = current }
        }
    }

    /// Fits the sheet now, and again when the canvas reports its real size, unless the person pans or zooms first (entering Drawing,
    /// showing another sheet).
    public func requestFit() {
        fit()
        fitsOnNextSize = true
    }

    /// Undo and redo: takes the drawings the host restored, keeping the sheet and the selection that still exist.
    public func replaceDocument(_ new: DrawingDocument) {
        document = new
        let kept = currentSheet.flatMap { new.sheet($0) != nil ? $0 : nil } ?? new.sheets.first?.id
        if kept != currentSheet {
            currentSheet = kept
            events.sheetChanged(kept)
            // What was being made on another sheet is gone with it (plan R27).
            dropPicks()
            hoverCandidate = nil
            dropToolDrafts()
        }
        let existing = Set(sheet?.views.map(\.id) ?? [])
        selection = selection.intersection(existing)
        pruneAnnotationState()
        pruneToolDrafts()
        gesture = nil
    }

    // MARK: Committing

    /// Applies `change` to a copy of the document and commits it under `name` when it differs.
    @discardableResult
    func commit(_ name: String, key: String? = nil, _ change: (inout DrawingDocument) -> Void) -> Bool {
        var next = document
        change(&next)
        guard next != document else { return false }
        document = next
        refusal = nil
        events.committed(DrawingCommit(document: next, name: name, coalescingKey: key))
        return true
    }

    /// Commits a change to the current sheet.
    @discardableResult
    func commitSheet(_ name: String, key: String? = nil, _ change: (inout DrawingSheet) -> Void) -> Bool {
        guard let id = currentSheet else { return false }
        return commitSheet(id, name, key: key, change)
    }

    /// Commits a change to one sheet.
    @discardableResult
    func commitSheet(_ id: SheetID, _ name: String, key: String? = nil, _ change: (inout DrawingSheet) -> Void) -> Bool {
        commit(name, key: key) { document in
            guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
            change(&document.sheets[index])
        }
    }

    func refuse(_ sentence: String) {
        refusal = sentence
    }

    func show(sheet id: SheetID?) {
        guard id != currentSheet else { return }
        currentSheet = id
        selection = []
        selectedAnnotations = []
        hoveredStroke = nil
        dropPicks()
        dropToolDrafts()
        events.sheetChanged(id)
    }
}
