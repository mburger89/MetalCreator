import CreatorDrawing
import CreatorGeometry
import CreatorKernel

extension DrawingEditorModel {
    /// What picking on one view needs: its part, its mapping on the sheet and the frame it was projected in.
    struct PickContext {
        var view: DrawingView
        var topology: Topology
        var mapping: ViewMapping
        var frame: ProjectionFrame
        /// Whether the view is pictorial and so takes no dimensions (R11): the sheet's reading, not the frame's.
        var isPictorial: Bool
    }

    /// The view's pick context, or the sentence for why nothing can be picked on it (plan R25's states).
    func pickContext(of id: ViewID) -> Result<PickContext, DrawingRefusal> {
        func refused(_ reason: LostReason) -> Result<PickContext, DrawingRefusal> {
            .failure(DrawingRefusal(sentence: reason.sentence))
        }
        guard let sheet, let view = sheet.view(id), let content = contents[id], content.projection != nil,
              let topology = content.topology else { return refused(.noPart) }
        if let problem = content.problem, !problem.isEmpty { return refused(.viewFailed(problem)) }
        let centre = ViewPlacement.centers(in: sheet)[id] ?? view.center
        let scale = (view.scale ?? sheet.scale).value
        let mapping = ViewMapping.of(content: content, center: centre, scale: scale)
            ?? ViewMapping(scale: scale, offset: centre)
        return .success(
            PickContext(
                view: view, topology: topology, mapping: mapping, frame: view.orientation.frame, isPictorial: sheet.isPictorial(view)))
    }

    /// The view whose frame holds `point`, the topmost.
    func viewUnder(_ point: Vector2) -> ViewID? {
        guard let sheet, let picture else { return nil }
        return SheetHitTest.view(at: point, in: picture, order: sheet.views.map(\.id))
    }

    /// What lies under `point` on `view`: a circle's centre, a line's end, then the nearest line (plan R17).
    func candidate(at point: Vector2, in view: ViewID) -> PickCandidate? {
        guard let picture else { return nil }
        return DrawingPick.candidate(at: point, in: picture, view: view, tolerance: Self.hoverTolerancePoints / transform.zoom)
    }

    private func freeCurveRefusal(at point: Vector2, in view: ViewID) -> DrawingRefusal? {
        guard let picture else { return nil }
        return DrawingPick.refusal(
            at: point, in: picture, view: view, tolerance: Self.hoverTolerancePoints / transform.zoom)
    }

    /// The hover under the pointer for an annotation tool: picks stay in their one view.
    func updateHover(at point: Vector2) {
        guard tool.isAnnotationTool || addingLeader != nil else {
            if hoverCandidate != nil { hoverCandidate = nil }
            return
        }
        let view = symbolDraft?.view ?? (picks.isEmpty ? viewUnder(point) : pickView)
        let found = view.flatMap { candidate(at: point, in: $0) }
        if found != hoverCandidate { hoverCandidate = found }
    }

    // MARK: Clicks

    /// A press-and-release of an annotation tool, or the click that ends a leader, at `point` (sheet millimetres).
    func annotationClick(at point: Vector2, modifiers: SheetModifiers) {
        lastPointer = point
        if let note = addingLeader {
            leaderClick(note, at: point)
        } else if tool == .note {
            placeNote(at: point)
        } else if tool.isSymbolTool {
            symbolClick(at: point)
        } else if tool.isAnnotationTool {
            pickClick(at: point, modifiers: modifiers)
        }
    }

    private func pickClick(at point: Vector2, modifiers: SheetModifiers) {
        let hit = viewUnder(point)
        let working: ViewID
        if let current = pickView, !picks.isEmpty {
            if let hit, hit != current, candidate(at: point, in: hit) != nil {
                refuse(Self.otherViewSentence)
                return
            }
            working = current
        } else if let hit {
            working = hit
        } else {
            return
        }
        let context: PickContext
        switch pickContext(of: working) {
        case .failure(let refused):
            refuse(refused.sentence)
            return
        case .success(let found): context = found
        }
        if context.isPictorial {
            refuse(DrawingPick.isometricSentence)
            return
        }
        let draft = AnnotationDraft(tool: tool, picks: picks)
        if let found = candidate(at: point, in: working) {
            pick(found, at: point, in: working, context: context, draft: draft)
        } else if let refused = freeCurveRefusal(at: point, in: working) {
            refuse(refused.sentence)
        } else if !picks.isEmpty {
            place(at: point, aligned: modifiers.contains(.shift), in: working, context: context, draft: draft)
        }
    }

    private func pick(
        _ found: PickCandidate, at point: Vector2, in view: ViewID, context: PickContext, draft: AnnotationDraft
    ) {
        var held = picks
        if let limit = draft.maximumPicks, held.count >= limit {
            guard tool == .holeCallout else {
                refuse(DimensionInference.tooManySentence)
                return
            }
            held = []
        }
        let result = DrawingPick.anchor(
            for: found, click: point, purpose: draft.purpose, topology: context.topology, frame: context.frame,
            mapping: context.mapping, isIsometric: context.isPictorial)
        switch result {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let anchor):
            switch tool {
            case .centreMark:
                addAnnotation(.centreMark(CentreMark(anchor: anchor.target)), view: view, name: DrawingStepName.addCentreMark)
            case .centreLine:
                addAnnotation(.centreLine(CentreLine(anchor: anchor.target)), view: view, name: DrawingStepName.addCentreLine)
            default:
                picks = held + [anchor]
                pickView = view
                updateDraft()
            }
        }
    }

    private func place(at point: Vector2, aligned: Bool, in view: ViewID, context: PickContext, draft: AnnotationDraft) {
        guard draft.isComplete else {
            refuse(draft.incompleteSentence)
            return
        }
        switch draft.kind(placing: point, aligned: aligned, mapping: context.mapping) {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let kind): addAnnotation(kind, view: view, name: draft.stepName)
        }
    }

    // MARK: Leaders

    /// The click that ends the leader being added (plan R14): on a line, corner or centre of a view it names it, else it is a free
    /// point. A sheet note whose leader lands on a view joins that view, keeping its place on the sheet.
    private func leaderClick(_ noteID: AnnotationID, at point: Vector2) {
        guard let sheet, let annotation = sheet.annotation(noteID), case .note(var note) = annotation.kind else {
            addingLeader = nil
            return
        }
        let centres = ViewPlacement.centers(in: sheet)
        var landing: (view: ViewID, target: AnchorTarget, hint: Vector2)?
        if let hit = viewUnder(point), case .success(let context) = pickContext(of: hit) {
            if let found = candidate(at: point, in: hit) {
                if let own = annotation.view, own != hit {
                    refuse(Self.leaderViewSentence)
                    return
                }
                let result = DrawingPick.anchor(
                    for: found, click: point, purpose: .leader, topology: context.topology, frame: context.frame,
                    mapping: context.mapping, isIsometric: context.isPictorial)
                switch result {
                case .failure(let refused):
                    refuse(refused.sentence)
                    return
                case .success(let anchor): landing = (hit, anchor.target, context.mapping.model(point))
                }
            } else if let refused = freeCurveRefusal(at: point, in: hit) {
                refuse(refused.sentence)
                return
            }
        }
        var updated = annotation
        if let landing {
            if annotation.view == nil {
                let centre = centres[landing.view] ?? .zero
                note.position -= centre
                note.leaders = note.leaders.map { leader in
                    guard case .point(let p) = leader.target else { return leader }
                    return LeaderEnd(target: .point(p - centre), hint: leader.hint)
                }
                updated.view = landing.view
            }
            note.leaders.append(LeaderEnd(target: landing.target, hint: landing.hint))
        } else {
            let centre = annotation.view.flatMap { centres[$0] } ?? .zero
            note.leaders.append(LeaderEnd(target: .point(point - centre), hint: .zero))
        }
        updated.kind = .note(note)
        commitSheet(DrawingStepName.addLeader) { $0.setAnnotation(updated) }
        addingLeader = nil
    }

    // MARK: Re-attaching

    /// With exactly one lost annotation selected, a click on a line of its view puts that pick where its first lost anchor was
    /// (plan R15). `true` when the click was used, to attach or to refuse; the selection never changes.
    func reattachClick(at point: Vector2) -> Bool {
        guard tool == .select, selectedAnnotations.count == 1, let id = selectedAnnotations.first, let sheet, let picture,
              let annotation = sheet.annotation(id), let viewID = annotation.view,
              let report = picture.annotationReports[id], report.isLost, viewUnder(point) == viewID else { return false }
        // A view with no part has no lines to click, so this is refused before the line guard below.
        // (A symbol hung on a dimension has no anchors of its own; its refusal is below, behind the line guard.)
        var onDimension = false
        if case .dimension? = annotation.symbolAttachment { onDimension = true }
        if report.anchors.isEmpty, !onDimension {
            refuse(Self.noPartSentence)
            return true
        }
        let found = candidate(at: point, in: viewID)
        let tolerance = Self.hoverTolerancePoints / transform.zoom
        // Only a click on a line is refused: any other click selects or drags as usual.
        guard found != nil || SheetHitTest.line(near: point, in: picture, view: viewID, tolerance: tolerance) != nil else {
            return false
        }
        if onDimension {
            refuse(Self.symbolOnDimensionSentence)
            return true
        }
        guard let index = report.firstLostAnchor else {
            refuse(Self.stillThereSentence)
            return true
        }
        guard let found else {
            if let refused = freeCurveRefusal(at: point, in: viewID) { refuse(refused.sentence) }
            return true
        }
        attach(found, at: point, index: index, to: annotation)
        return true
    }

    /// Validates `found` as a fresh pick of the same case as the lost anchor `index` and puts it there in one step.
    private func attach(_ found: PickCandidate, at point: Vector2, index: Int, to annotation: DrawingAnnotation) {
        guard let viewID = annotation.view else { return }
        let context: PickContext
        switch pickContext(of: viewID) {
        case .failure(let refused):
            refuse(refused.sentence)
            return
        case .success(let made): context = made
        }
        let targets = Self.targets(of: annotation.kind)
        guard targets.indices.contains(index) else { return }
        let result = DrawingPick.anchor(
            for: found, click: point, purpose: Self.purpose(of: annotation.kind), topology: context.topology,
            frame: context.frame, mapping: context.mapping, isIsometric: context.isPictorial)
        switch result {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let anchor):
            guard anchor.target.caseName == targets[index].caseName else {
                refuse(Self.sameKindSentence)
                return
            }
            var updated = annotation
            updated.kind = Self.replacing(index, in: annotation.kind, with: anchor.target, hint: context.mapping.model(point))
            // Once the last lost anchor is replaced the annotation must hold; one that would stay lost (a radius on a straight
            // edge) is refused here, since every later click would only say "still there".
            let othersHeld = picture?.annotationReports[annotation.id]?.anchors.enumerated().allSatisfy { other, status in
                if other == index { return true }
                if case .lost = status { return false } else { return true }
            } ?? false
            if othersHeld,
               let reason = AnnotationRefresh.lostReason(
                   of: updated, topology: context.topology, frame: context.frame,
                   format: NumberFormat(units: units, settings: document.settings), standard: document.settings.standard) {
                refuse(reason.sentence)
                return
            }
            let name = annotation.symbolKind == nil ? DrawingStepName.reattachDimension : DrawingStepName.reattachSymbol
            commitSheet(name) { $0.setAnnotation(updated) }
        }
    }

    /// An annotation's anchors in the order `AnnotationReport.anchors` reports them.
    static func targets(of kind: AnnotationKind) -> [AnchorTarget] {
        switch kind {
        case .dimension(let dimension): dimension.anchors
        case .holeCallout(let callout): [callout.anchor]
        case .centreMark(let mark): [mark.anchor]
        case .centreLine(let line): [line.anchor]
        case .note(let note): note.leaders.map(\.target)
        // A symbol on a line has its one anchor; one on a dimension has none of its own.
        case .datumFeature(let datum): Self.lineTargets(of: datum.attachment)
        case .featureControl(let frame): Self.lineTargets(of: frame.attachment)
        case .surfaceTexture(let texture): [texture.feature.target]
        }
    }

    private static func lineTargets(of attachment: SymbolAttachment) -> [AnchorTarget] {
        if case .feature(let end) = attachment { [end.target] } else { [] }
    }

    static func purpose(of kind: AnnotationKind) -> PickPurpose {
        switch kind {
        case .dimension: .dimension
        case .holeCallout: .holeCallout
        case .centreMark: .centreMark
        case .centreLine: .centreLine
        case .note: .leader
        case .datumFeature: PickPurpose(symbol: .datum)
        case .featureControl: PickPurpose(symbol: .frame)
        case .surfaceTexture: PickPurpose(symbol: .surface)
        }
    }

    private static func replacing(_ index: Int, in kind: AnnotationKind, with target: AnchorTarget, hint: Vector2) -> AnnotationKind {
        switch kind {
        case .dimension(var dimension):
            dimension.anchors[index] = target
            return .dimension(dimension)
        case .holeCallout(var callout):
            callout.anchor = target
            return .holeCallout(callout)
        case .centreMark(var mark):
            mark.anchor = target
            return .centreMark(mark)
        case .centreLine(var line):
            line.anchor = target
            return .centreLine(line)
        case .note(var note):
            note.leaders[index] = LeaderEnd(target: target, hint: hint)
            return .note(note)
        case .datumFeature(var datum):
            datum.attachment = .feature(LeaderEnd(target: target, hint: hint))
            return .datumFeature(datum)
        case .featureControl(var frame):
            frame.attachment = .feature(LeaderEnd(target: target, hint: hint))
            return .featureControl(frame)
        case .surfaceTexture(var texture):
            texture.feature = LeaderEnd(target: target, hint: hint)
            return .surfaceTexture(texture)
        }
    }
}
