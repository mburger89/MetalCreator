import CreatorDrawing
import CreatorGeometry
import CreatorKernel
import Foundation

/// The Section, Detail and Auxiliary tools: drafts, snapping, constraining and placing (DR-3 R3, R8, R9, R11, R13).
extension DrawingEditorModel {
    static let pictorialParentSentence =
        "A section or auxiliary view is taken from a front, side, top, bottom, section or auxiliary view, not an isometric one."
    static let sectionOnDetailSentence = "Draw the cutting line on the view the detail enlarges."
    static let auxiliaryOnDetailSentence = "Pick the edge for an auxiliary view on the view the detail enlarges."
    static let cutEndSentence = "A stepped cutting line ends with a cut, not a step."
    static let pointsApartSentence = "A cutting line's points must be apart."
    static let tinyDetailSentence = "Drag out the detail's circle from its centre."
    /// The first segment of a cutting line snaps to horizontal or vertical within this angle unless Shift is held (R3).
    static let snapAngle = 5.0 * .pi / 180
    /// A detail circle smaller than this on the sheet is refused (R13), in sheet millimetres.
    static let minimumDetailRadius = 2.0
    /// The scale a detail starts at when no preferred scale is twice its parent's (R8).
    static let largestDetailScale = DrawingScale(numerator: 50, denominator: 1)

    // MARK: Drafts

    var holdsToolDraft: Bool { sectionDraft != nil || detailDraft != nil || auxiliaryDraft != nil }

    /// Drops every draft; `true` when there was one.
    @discardableResult
    func dropToolDrafts() -> Bool {
        let held = holdsToolDraft
        sectionDraft = nil
        detailDraft = nil
        auxiliaryDraft = nil
        return held
    }

    /// After undo or redo: a draft whose parent is gone goes (R13).
    func pruneToolDrafts() {
        if let parent = sectionDraft?.parent, sheet?.view(parent) == nil { sectionDraft = nil }
        if let parent = detailDraft?.parent, sheet?.view(parent) == nil { detailDraft = nil }
        if let parent = auxiliaryDraft?.parent, sheet?.view(parent) == nil { auxiliaryDraft = nil }
    }

    // MARK: Parents

    /// The mapping of a view that has something drawn, or `nil`.
    func parentMapping(of id: ViewID) -> ViewMapping? {
        guard let sheet, let view = sheet.view(id), let content = contents[id], content.projection != nil else { return nil }
        let centre = ViewPlacement.centers(in: sheet)[id] ?? view.center
        let scale = (view.scale ?? sheet.scale).value
        return ViewMapping.of(content: content, center: centre, scale: scale) ?? ViewMapping(scale: scale, offset: centre)
    }

    /// The view and its mapping when a derived view of `tool` may be made from it, else the refusal is shown.
    private func parent(_ id: ViewID, for tool: DrawingTool) -> (view: DrawingView, mapping: ViewMapping)? {
        guard let sheet, let view = sheet.view(id) else { return nil }
        let noun: String
        switch tool {
        case .section:
            if view.kind == .detail {
                refuse(Self.sectionOnDetailSentence)
                return nil
            }
            noun = "cut"
        case .auxiliaryView:
            if view.kind == .detail {
                refuse(Self.auxiliaryOnDetailSentence)
                return nil
            }
            noun = "project from"
        default: noun = "enlarge"
        }
        if tool != .detail, sheet.isPictorial(view) {
            refuse(Self.pictorialParentSentence)
            return nil
        }
        guard let mapping = parentMapping(of: id) else {
            refuse("This view has nothing drawn to \(noun) yet.")
            return nil
        }
        return (view, mapping)
    }

    /// `point` (sheet mm) in `view`'s model plane, snapped to the corner or circle centre under it.
    private func snappedModelPoint(_ point: Vector2, in view: ViewID, mapping: ViewMapping) -> Vector2 {
        switch candidate(at: point, in: view) {
        case .corner(_, let at)?, .centre(_, let at)?: mapping.model(at)
        default: mapping.model(point)
        }
    }

    // MARK: Clicks

    /// A press-and-release of the Section or Auxiliary tool, or the click that places a detail.
    func derivedClick(at point: Vector2, modifiers: SheetModifiers) {
        lastPointer = point
        switch tool {
        case .section: sectionClick(at: point, modifiers: modifiers)
        case .auxiliaryView: auxiliaryClick(at: point)
        case .detail:
            if let draft = detailDraft, draft.isFinished { placeDetail(draft, at: point) }
        default: break
        }
    }

    // MARK: Section

    private func sectionClick(at point: Vector2, modifiers: SheetModifiers) {
        guard let draft = sectionDraft else {
            guard let hit = viewUnder(point), let found = parent(hit, for: .section) else { return }
            sectionDraft = SectionDraft(
                parent: hit, points: [snappedModelPoint(point, in: hit, mapping: found.mapping)])
            return
        }
        guard let mapping = parentMapping(of: draft.parent) else {
            sectionDraft = nil
            return
        }
        if draft.isFinished {
            placeSection(draft, dropAt: point, mapping: mapping)
            return
        }
        if let last = draft.points.last, (mapping.sheet(last) - point).length <= Self.hoverTolerancePoints / transform.zoom {
            if draft.points.count < 2 {
                refuse(Self.pointsApartSentence)
            } else {
                finishSectionDraft()
            }
            return
        }
        let raw = snappedModelPoint(point, in: draft.parent, mapping: mapping)
        switch Self.constrained(raw, after: draft.points, keepsSlant: modifiers.contains(.shift)) {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let next):
            var updated = draft
            updated.points.append(next)
            sectionDraft = updated
        }
    }

    /// Return, or a click on the last point: a line of two or more points with an odd number of segments is finished (R13).
    @discardableResult
    func finishSectionDraft() -> Bool {
        guard var draft = sectionDraft else { return false }
        guard !draft.isFinished else { return true }
        if draft.points.count < 2 {
            refuse("A cutting line needs at least two points.")
        } else if (draft.points.count - 1) % 2 == 0 {
            refuse(Self.cutEndSentence)
        } else {
            draft.isFinished = true
            sectionDraft = draft
        }
        return true
    }

    /// The next point of a cutting line from the clicked one: the first segment snaps to an axis within 5 degrees (not with Shift),
    /// a cut moves only along the first segment's direction and a step only across it (R13).
    static func constrained(
        _ raw: Vector2, after points: [Vector2], keepsSlant: Bool
    ) -> Result<Vector2, DrawingRefusal> {
        guard let last = points.last else { return .success(raw) }
        func apart(_ point: Vector2) -> Result<Vector2, DrawingRefusal> {
            (point - last).length < 1e-6
                ? .failure(DrawingRefusal(sentence: pointsApartSentence)) : .success(point)
        }
        if points.count == 1 {
            var end = raw
            let offset = raw - last
            if !keepsSlant, offset.length > 0 {
                let angle = atan2(abs(offset.y), abs(offset.x))
                if angle <= snapAngle {
                    end.y = last.y
                } else if .pi / 2 - angle <= snapAngle {
                    end.x = last.x
                }
            }
            return apart(end)
        }
        let first = points[1] - points[0]
        let length = first.length
        guard length > 0 else { return .failure(DrawingRefusal(sentence: pointsApartSentence)) }
        let t = first * (1 / length)
        let isCut = (points.count - 1) % 2 == 0
        let along = isCut ? t : Vector2(-t.y, t.x)
        let distance = (raw - last).x * along.x + (raw - last).y * along.y
        if isCut, distance < 0, abs(distance) >= 1e-6 {
            return .failure(
                DrawingRefusal(sentence: "Every cut of a stepped cutting line runs the same way as the first."))
        }
        return apart(last + along * distance)
    }

    private func placeSection(_ draft: SectionDraft, dropAt point: Vector2, mapping: ViewMapping) {
        guard let id = currentSheet, let sheet, let parent = sheet.view(draft.parent), let origin = draft.points.first else { return }
        var cutter = SectionCutter(frame: parent.orientation.frame, points: draft.points, viewing: .zero)
        let t = cutter.direction
        cutter.viewing = SectionFrame.viewing(
            along: t, from: origin, drop: mapping.model(point), standard: document.settings.standard)
        do {
            try cutter.validate()
        } catch {
            refuse(error.userMessage)
            return
        }
        var center = point
        let alignment = SectionFrame.alignment(along: t)
        let parentCenter = ViewPlacement.centers(in: sheet)[parent.id] ?? parent.center
        switch alignment {
        case .vertical?: center.x = parentCenter.x
        case .horizontal?: center.y = parentCenter.y
        case nil: break
        }
        let view = DrawingView(
            kind: .section, source: parent.source, orientation: .custom(SectionFrame.frame(for: cutter)), scale: parent.scale,
            center: center, alignment: alignment.map { ViewAlignment(parent: parent.id, axis: $0) },
            showsHidden: parent.showsHidden, showsTangent: parent.showsTangent, showsLabel: true,
            derivation: .section(SectionLine(parent: parent.id, cutter: cutter)), letter: ViewLetters.next(on: sheet))
        finishPlacing(view, on: id)
        sectionDraft = nil
    }

    // MARK: Detail

    func detailDown(at point: Vector2, hit: ViewID?, modifiers: SheetModifiers) {
        lastPointer = point
        if detailDraft?.isFinished == true {
            gesture = .clicking(modifiers)
            return
        }
        guard let hit, let found = parent(hit, for: .detail) else { return }
        let centre = snappedModelPoint(point, in: hit, mapping: found.mapping)
        detailDraft = DetailDraft(parent: hit, center: centre, radius: 0)
        gesture = .detailing(centerSheet: found.mapping.sheet(centre), scale: found.mapping.scale)
    }

    func continueDetail(from centerSheet: Vector2, scale: Double, to point: Vector2) {
        guard var draft = detailDraft, scale > 0 else { return }
        lastPointer = point
        draft.radius = (point - centerSheet).length / scale
        detailDraft = draft
    }

    func endDetail(from centerSheet: Vector2, scale: Double, at point: Vector2) {
        guard var draft = detailDraft, scale > 0 else { return }
        let sheetRadius = (point - centerSheet).length
        guard sheetRadius >= Self.minimumDetailRadius else {
            detailDraft = nil
            refuse(Self.tinyDetailSentence)
            return
        }
        draft.radius = sheetRadius / scale
        draft.isFinished = true
        detailDraft = draft
    }

    private func placeDetail(_ draft: DetailDraft, at point: Vector2) {
        guard let id = currentSheet, let sheet, let parent = sheet.view(draft.parent) else { return }
        let wanted = 2 * (parent.scale ?? sheet.scale).value - 1e-9
        let scale = DrawingScale.preferred.reversed().first { $0.value >= wanted } ?? Self.largestDetailScale
        let view = DrawingView(
            kind: .detail, source: parent.source, orientation: parent.orientation, scale: scale, center: point,
            showsHidden: parent.showsHidden, showsTangent: parent.showsTangent, showsLabel: true,
            derivation: .detail(DetailCircle(parent: parent.id, center: draft.center, radius: draft.radius)),
            letter: ViewLetters.next(on: sheet))
        finishPlacing(view, on: id)
        detailDraft = nil
    }

    // MARK: Auxiliary

    private func auxiliaryClick(at point: Vector2) {
        if let draft = auxiliaryDraft {
            placeAuxiliary(draft, at: point)
            return
        }
        guard let hit = viewUnder(point), parent(hit, for: .auxiliaryView) != nil else { return }
        let context: PickContext
        switch pickContext(of: hit) {
        case .failure(let refused):
            refuse(refused.sentence)
            return
        case .success(let found): context = found
        }
        guard let found = candidate(at: point, in: hit) else {
            refuse(AuxiliaryRule.lineSentence)
            return
        }
        switch AuxiliaryRule.arrow(
            for: found, click: point, topology: context.topology, frame: context.frame, mapping: context.mapping) {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let edge): auxiliaryDraft = AuxiliaryDraft(parent: hit, at: edge.at, along: edge.along)
        }
    }

    private func placeAuxiliary(_ draft: AuxiliaryDraft, at point: Vector2) {
        guard let id = currentSheet, let sheet, let parent = sheet.view(draft.parent), let mapping = parentMapping(of: parent.id)
        else { return }
        let viewing = SectionFrame.viewing(
            along: draft.along, from: draft.at, drop: mapping.model(point), standard: document.settings.standard)
        let parentFrame = parent.orientation.frame
        let frame = SectionFrame.frame(parent: parentFrame, along: draft.along, viewing: viewing)
        let arrow = AuxiliaryArrow(parent: parent.id, parentFrame: parentFrame, at: draft.at, viewing: viewing)
        let view = DrawingView(
            kind: .auxiliary, source: parent.source, orientation: .custom(frame), scale: parent.scale, center: point,
            showsHidden: parent.showsHidden, showsTangent: parent.showsTangent, showsLabel: true, derivation: .auxiliary(arrow),
            letter: ViewLetters.next(on: sheet))
        finishPlacing(view, on: id)
        auxiliaryDraft = nil
    }

    /// Adds the derived view as one "Add View" step, selects it and goes back to Select.
    private func finishPlacing(_ view: DrawingView, on sheet: SheetID) {
        commitSheet(sheet, DrawingStepName.addView) { $0.setView(view) }
        selection = [view.id]
        selectedAnnotations = []
        tool = .select
    }

    // MARK: The draft's picture

    /// The sheet's picture with the marks of the draft in progress, or `nil` when it has nothing to show yet.
    func derivedDraftPicture() -> SheetPicture? {
        guard var drafted = picture else { return nil }
        let standard = document.settings.standard
        let letter = sheet.map { ViewLetters.next(on: $0) } ?? "A"
        let pieces: SectionMarks.Pieces
        if let draft = sectionDraft, let found = draftParent(draft.parent) {
            var points = draft.points
            if !draft.isFinished, let pointer = lastPointer,
                case .success(let next) = Self.constrained(found.mapping.model(pointer), after: points, keepsSlant: false) {
                points.append(next)
            }
            guard points.count >= 2 else { return nil }
            var cutter = SectionCutter(frame: found.view.orientation.frame, points: points, viewing: .zero)
            let t = cutter.direction
            let drop = lastPointer.map { found.mapping.model($0) } ?? points[0] + Vector2(-t.y, t.x)
            cutter.viewing = SectionFrame.viewing(along: t, from: points[0], drop: drop, standard: standard)
            pieces = SectionMarks.cuttingLine(
                cutter, letter: letter, mapping: found.mapping, parent: found.view.id, mark: draftViewID, standard: standard)
        } else if let draft = detailDraft, let found = draftParent(draft.parent), draft.radius > 0 {
            pieces = SectionMarks.detailCircle(
                DetailCircle(parent: draft.parent, center: draft.center, radius: draft.radius), letter: letter,
                mapping: found.mapping, parent: found.view.id, mark: draftViewID, standard: standard)
        } else if let draft = auxiliaryDraft, let found = draftParent(draft.parent) {
            let drop = lastPointer.map { found.mapping.model($0) } ?? draft.at + Vector2(-draft.along.y, draft.along.x)
            let viewing = SectionFrame.viewing(along: draft.along, from: draft.at, drop: drop, standard: standard)
            pieces = SectionMarks.auxiliaryArrow(
                AuxiliaryArrow(parent: draft.parent, parentFrame: found.view.orientation.frame, at: draft.at, viewing: viewing),
                letter: letter, mapping: found.mapping, parent: found.view.id, mark: draftViewID, standard: standard)
        } else {
            return nil
        }
        drafted.strokes += pieces.strokes
        drafted.fills += pieces.fills
        drafted.texts += pieces.texts
        return drafted
    }

    private func draftParent(_ id: ViewID) -> (view: DrawingView, mapping: ViewMapping)? {
        guard let view = sheet?.view(id), let mapping = parentMapping(of: id) else { return nil }
        return (view, mapping)
    }
}
