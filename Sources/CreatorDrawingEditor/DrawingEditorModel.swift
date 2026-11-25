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
    public internal(set) var tool: DrawingTool = .select
    public var transform = SheetTransform()
    public var canvasSize = Vector2(1000, 700)
    /// The part of the canvas that shows, in canvas points; set by the host.
    public var visibleRect = Rect2D(min: .zero, max: Vector2(1000, 700))
    public var sources: [DrawingSourceOption] = []
    public var contents: [ViewID: ViewContent] = [:] {
        didSet { rebuildPicture() }
    }
    public var facts = TitleBlockFacts() {
        didSet { rebuildPicture() }
    }
    public internal(set) var refusal: String?
    /// The tab being renamed in place; view state, committed as one "Rename Sheet" step.
    public internal(set) var renaming: SheetRename?
    public internal(set) var hoveredStroke: Int?
    /// The current sheet composed by `SheetComposer`.
    public private(set) var picture: SheetPicture?

    let standardUnitsAreInches: Bool
    let today: () -> String
    let events: DrawingEditorEvents

    // Gesture state; not observed.
    @ObservationIgnored var gesture: Gesture?
    @ObservationIgnored var dragSerial = 0
    @ObservationIgnored var pinchStart: (zoom: Double, anchor: Vector2)?
    @ObservationIgnored var pointerIsDown = false
    @ObservationIgnored var middleLast: Vector2?

    enum Gesture {
        case movingViews(base: DrawingSheet, start: Vector2, key: String, roots: [ViewID])
        case projecting(parent: ViewID, start: Vector2)
        case placing
    }

    public init(
        document: DrawingDocument, sheet: SheetID?, standardUnitsAreInches: Bool, today: @escaping () -> String,
        events: DrawingEditorEvents
    ) {
        self.document = document
        self.currentSheet = document.sheet(sheet ?? SheetID()) != nil ? sheet : nil
        self.standardUnitsAreInches = standardUnitsAreInches
        self.today = today
        self.events = events
        rebuildPicture()
    }

    var sheet: DrawingSheet? { currentSheet.flatMap { document.sheet($0) } }

    func rebuildPicture() {
        guard let sheet else {
            picture = nil
            return
        }
        picture = SheetComposer.compose(sheet, in: document, contents: contents, facts: facts)
    }

    /// Undo and redo: takes the drawings the host restored, keeping the sheet and the selection that still exist.
    public func replaceDocument(_ new: DrawingDocument) {
        document = new
        let kept = currentSheet.flatMap { new.sheet($0) != nil ? $0 : nil } ?? new.sheets.first?.id
        if kept != currentSheet {
            currentSheet = kept
            events.sheetChanged(kept)
        }
        let existing = Set(sheet?.views.map(\.id) ?? [])
        selection = selection.intersection(existing)
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
        hoveredStroke = nil
        events.sheetChanged(id)
    }
}
