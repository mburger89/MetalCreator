import CreatorDrawing
import CreatorGeometry
import CreatorKernel

/// The Balloon tool (DR-5 R4, R16): the first click names a line of a part, the next places the circle.
extension DrawingEditorModel {
    static let balloonPartSentence = "A balloon stays on its part; add a new balloon for another part."

    // MARK: Clicks

    /// A press-and-release of the Balloon tool at `point` (sheet millimetres): the target first, then the place.
    func balloonClick(at point: Vector2) {
        if let draft = balloonDraft {
            placeBalloon(draft, at: point)
        } else {
            chooseBalloonTarget(at: point)
        }
    }

    private func chooseBalloonTarget(at point: Vector2) {
        guard let view = viewUnder(point) else { return }
        let context: PickContext
        switch pickContext(of: view) {
        case .failure(let refused):
            refuse(refused.sentence)
            return
        case .success(let found): context = found
        }
        guard let found = candidate(at: point, in: view) else {
            if let refused = freeCurveRefusal(at: point, in: view, purpose: .balloon) { refuse(refused.sentence) }
            return
        }
        let result = DrawingPick.anchor(
            for: found, click: point, purpose: .balloon, topology: context.topology, frame: context.frame, mapping: context.mapping,
            isIsometric: context.isPictorial, parts: context.parts)
        switch result {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let anchor):
            refusal = nil
            balloonDraft = BalloonDraft(view: view, anchor: anchor, hint: context.mapping.model(point))
            updateDraft()
        }
    }

    private func placeBalloon(_ draft: BalloonDraft, at point: Vector2) {
        switch balloonKind(for: draft, placing: point) {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let kind): addAnnotation(kind, view: draft.view, name: DrawingStepName.addBalloon)
        }
    }

    // MARK: The balloon a click would place

    /// The balloon a click at `point` would place for `draft`: the one call the draft picture and the committed annotation share.
    /// The circle's centre lies `offset` from the foot, which the composer finds as it does a note's leader landing.
    func balloonKind(for draft: BalloonDraft, placing point: Vector2) -> Result<AnnotationKind, DrawingRefusal> {
        guard case .success(let context) = pickContext(of: draft.view) else {
            return .failure(DrawingRefusal(sentence: LostReason.noPart.sentence))
        }
        let foot: Vector2
        switch footOf(draft) {
        case .failure(let refused): return .failure(refused)
        case .success(let model): foot = model
        }
        let leader = LeaderEnd(target: draft.anchor.target, hint: draft.hint)
        return .success(.balloon(Balloon(leader: leader, offset: point - context.mapping.sheet(foot))))
    }

    /// The draft's foot in the view's model plane, found by composing a balloon with no offset and read once per draft.
    private func footOf(_ draft: BalloonDraft) -> Result<Vector2, DrawingRefusal> {
        if let cached = balloonFoot, cached.draft == draft { return .success(cached.foot) }
        let leader = LeaderEnd(target: draft.anchor.target, hint: draft.hint)
        let probe = DrawingAnnotation(id: draftID, view: draft.view, kind: .balloon(Balloon(leader: leader, offset: .zero)))
        guard let picture = composed(with: probe), let report = picture.annotationReports[draftID] else {
            return .failure(DrawingRefusal(sentence: LostReason.noPart.sentence))
        }
        if case .lost(let reason) = report.status { return .failure(DrawingRefusal(sentence: reason.sentence)) }
        guard case .leaders(let points)? = report.current?.figure, let foot = points.first else {
            return .failure(DrawingRefusal(sentence: LostReason.missing.sentence))
        }
        balloonFoot = (draft, foot)
        return .success(foot)
    }

    /// The current sheet with `annotation` composed in, in a copy of the document (so item numbers count it). Never committed.
    private func composed(with annotation: DrawingAnnotation) -> SheetPicture? {
        guard let sheet, let index = document.sheets.firstIndex(where: { $0.id == sheet.id }) else { return nil }
        var drafted = sheet
        drafted.setAnnotation(annotation)
        var copy = document
        copy.sheets[index] = drafted
        return SheetComposer.compose(drafted, in: copy, contents: contents, facts: facts, units: units, remembered: remembered)
    }

    // MARK: The draft

    /// The picture with the balloon composed in under the pointer, or none.
    func balloonDraftPicture() -> SheetPicture? {
        guard let draft = balloonDraft, let point = lastPointer, case .success(let kind) = balloonKind(for: draft, placing: point)
        else { return nil }
        return composed(with: DrawingAnnotation(id: draftID, view: draft.view, kind: kind))
    }

    /// After undo or redo: a target whose view is gone goes.
    func pruneBalloonDraft() {
        guard let draft = balloonDraft, sheet?.view(draft.view) == nil else { return }
        balloonDraft = nil
        balloonFoot = nil
        draftPicture = nil
    }
}
