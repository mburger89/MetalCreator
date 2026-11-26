import CreatorDrawing
import CreatorGeometry

extension DrawingEditorModel {
    static let otherViewSentence = "A dimension takes its picks from one view."
    static let leaderViewSentence = "A note's leaders point into one view."
    static let sameKindSentence = "Pick the same kind of thing the annotation lost: a line, a circle, a corner or a centre."
    static let stillThereSentence = """
        What it was attached to is still there; it is lost because of what that measures now. Delete it or change the model.
        """
    static let noPartSentence = "Its view has no part to attach it to."
    static let noteText = "Note"

    // MARK: Last good figures

    /// Merges figures read from the model elsewhere (the app's refresh after each evaluation, plan R26): each entry replaces what is
    /// there, nothing is removed.
    public func remember(_ goods: [AnnotationID: LastGood]) {
        var changed = false
        for (id, good) in goods where remembered[id] != good {
            remembered[id] = good
            changed = true
        }
        if changed { rebuildPicture() }
    }

    // MARK: Leaders

    /// The next click is the end of a new leader of `note` (plan R14).
    public func beginLeader(for note: AnnotationID) {
        guard let annotation = sheet?.annotation(note), case .note = annotation.kind else { return }
        dropPicks()
        addingLeader = note
        refusal = nil
    }

    // MARK: Picks and the draft

    /// Forgets the picks and the draft; the tool stays.
    func dropPicks() {
        picks = []
        pickView = nil
        symbolDraft = nil
        draftPicture = nil
    }

    /// Forgets everything an annotation tool was holding: picks, the draft, the hover and a leader being added.
    func cancelAnnotationInput() {
        dropPicks()
        addingLeader = nil
        hoverCandidate = nil
    }

    /// Whether Esc has picks, a draft or a leader to drop.
    var holdsAnnotationInput: Bool { !picks.isEmpty || draftPicture != nil || addingLeader != nil || symbolDraft != nil }

    /// The picture with the annotation under construction composed in at the pointer, or none (plan R17). It is composed under the
    /// model's one draft id and never feeds `remembered`: its figures are nobody's last values.
    func updateDraft() {
        if holdsToolDraft {
            draftPicture = derivedDraftPicture()
            return
        }
        if symbolDraft != nil {
            draftPicture = symbolDraftPicture()
            return
        }
        guard !picks.isEmpty, let sheet, let pickView, let point = lastPointer,
              case .success(let context) = pickContext(of: pickView) else {
            draftPicture = nil
            return
        }
        let draft = AnnotationDraft(tool: tool, picks: picks)
        guard draft.isComplete, case .success(let kind) = draft.kind(placing: point, aligned: false, mapping: context.mapping) else {
            draftPicture = nil
            return
        }
        var drafted = sheet
        drafted.setAnnotation(DrawingAnnotation(id: draftID, view: pickView, kind: kind))
        draftPicture = SheetComposer.compose(
            drafted, in: document, contents: contents, facts: facts, units: units, remembered: remembered)
    }

    /// After undo, redo or a save: what no longer exists is dropped from the selection and the picks (plan R27).
    func pruneAnnotationState() {
        let present = Set(sheet?.annotations.map(\.id) ?? [])
        selectedAnnotations = selectedAnnotations.intersection(present)
        if let view = pickView, sheet?.view(view) == nil {
            dropPicks()
            hoverCandidate = nil
        }
        if let note = addingLeader, !present.contains(note) { addingLeader = nil }
        pruneSymbolDraft()
    }

    // MARK: Committing

    /// Adds `kind` to the current sheet as one step and selects it.
    @discardableResult
    func addAnnotation(_ kind: AnnotationKind, view: ViewID?, name: String) -> Bool {
        let annotation = DrawingAnnotation(view: view, kind: kind)
        guard commitSheet(name, { $0.setAnnotation(annotation) }) else { return false }
        selection = []
        selectedAnnotations = [annotation.id]
        dropPicks()
        return true
    }

    /// A note at `point` (sheet millimetres): in a view's frame it belongs to that view and sits relative to its centre.
    func placeNote(at point: Vector2) {
        guard let sheet, let picture else { return }
        let owner = sheet.views.map(\.id).last { picture.viewFrames[$0]?.contains(point) == true }
        let centre = owner.flatMap { ViewPlacement.centers(in: sheet)[$0] } ?? .zero
        let note = DrawingNote(text: Self.noteText, position: point - centre)
        addAnnotation(.note(note), view: owner, name: DrawingStepName.addNote)
        tool = .select
    }
}
