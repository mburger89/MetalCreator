import CreatorDrawing
import CreatorGeometry
import Foundation

extension DrawingEditorModel {
    static let hoverTolerancePoints = 4.0
    static let wheelZoomScale = 200.0

    // MARK: Pointer (canvas points in, sheet millimetres inside)

    public func pointerDown(at canvas: Vector2, modifiers: SheetModifiers) {
        refusal = nil
        guard let sheet else { return }
        let point = transform.sheetPoint(canvas)
        let order = sheet.views.map(\.id)
        let hit = picture.flatMap { SheetHitTest.view(at: point, in: $0, order: order) }
        if addingLeader != nil || tool.isAnnotationTool {
            lastPointer = point
            gesture = .annotating(modifiers)
            return
        }
        switch tool {
        case .baseView:
            gesture = .placing
        case .projectedView:
            if let hit { gesture = .projecting(parent: hit, start: point) }
        case .section, .auxiliaryView:
            lastPointer = point
            gesture = .clicking(modifiers)
        case .detail:
            detailDown(at: point, hit: hit, modifiers: modifiers)
        case .dimension, .baselineDimension, .chainDimension, .ordinateDimension, .chamferDimension, .holeCallout, .centreMark,
            .centreLine, .note, .datum, .featureControlFrame, .surfaceFinish:
            break
        case .select:
            selectDown(at: point, hit: hit, modifiers: modifiers, sheet: sheet)
        }
    }

    /// A press with Select: a click that re-attaches or refuses stays out of the selection; else it selects the annotation or view
    /// under it (annotations first, plan R18) and begins moving what is selected.
    private func selectDown(at point: Vector2, hit: ViewID?, modifiers: SheetModifiers, sheet: DrawingSheet) {
        if reattachClick(at: point) {
            gesture = nil
            return
        }
        if let picture,
            let annotation = SheetHitTest.annotation(at: point, in: picture, order: sheet.annotations.map(\.id)) {
            if modifiers.contains(.shift) {
                selectedAnnotations.insert(annotation)
            } else if !selectedAnnotations.contains(annotation) {
                selectedAnnotations = [annotation]
                selection = []
            }
            beginMove(at: point, sheet: sheet, onLabelOf: annotation)
            return
        }
        if let picture, let mark = SheetHitTest.mark(at: point, in: picture, tolerance: Self.hoverTolerancePoints / transform.zoom),
            sheet.view(mark) != nil {
            markDown(mark, at: point, modifiers: modifiers, sheet: sheet)
            return
        }
        guard let hit else {
            if !modifiers.contains(.shift) {
                selection = []
                selectedAnnotations = []
            }
            gesture = nil
            return
        }
        if modifiers.contains(.shift) {
            selection.insert(hit)
        } else if !selection.contains(hit) {
            selection = [hit]
            selectedAnnotations = []
        }
        beginMove(at: point, sheet: sheet, onLabelOf: nil)
    }

    public func pointerDragged(to canvas: Vector2) {
        let point = transform.sheetPoint(canvas)
        switch gesture {
        case .moving(let move): continueMove(move, to: point)
        case .movingMark(let move): continueMarkMove(move, to: point)
        case .detailing(let centerSheet, let scale): continueDetail(from: centerSheet, scale: scale, to: point)
        default: break
        }
    }

    public func pointerUp(at canvas: Vector2) {
        let ended = gesture
        gesture = nil
        let point = transform.sheetPoint(canvas)
        switch ended {
        case .placing: placeBaseView(at: point)
        case let .projecting(parent, _): placeProjectedView(of: parent, dropAt: point)
        case .annotating(let modifiers): annotationClick(at: point, modifiers: modifiers)
        case .clicking(let modifiers): derivedClick(at: point, modifiers: modifiers)
        case .detailing(let centerSheet, let scale): endDetail(from: centerSheet, scale: scale, at: point)
        case .moving, .movingMark, nil: break
        }
    }

    public func pointerCancelled() {
        let ended = gesture
        gesture = nil
        switch ended {
        case .moving(let move)?: cancelMove(move)
        case .movingMark(let move)?: cancelMarkMove(move)
        case .detailing?: detailDraft = nil
        default: break
        }
    }

    /// Hover: the nearest stroke within 4 points at the current zoom.
    public func pointerMoved(to canvas: Vector2) {
        guard let sheet, let picture else {
            hoveredStroke = nil
            return
        }
        let point = transform.sheetPoint(canvas)
        lastPointer = point
        updateHover(at: point)
        if !picks.isEmpty || holdsToolDraft || symbolDraft != nil { updateDraft() }
        let tolerance = Self.hoverTolerancePoints / transform.zoom
        var found: Int?
        for view in sheet.views.reversed() {
            if let index = SheetHitTest.line(near: point, in: picture, view: view.id, tolerance: tolerance) {
                found = index
                break
            }
        }
        if found != hoveredStroke { hoveredStroke = found }
    }

    // MARK: Canvas

    /// Fits the sheet in the visible rectangle at 90 %, centred.
    public func fit() {
        guard let sheet else { return }
        let paper = sheet.paperSize
        let rect = visibleRect
        guard paper.x > 0, paper.y > 0, rect.width > 0, rect.height > 0 else { return }
        let zoom = SheetTransform.clamped(Swift.min(rect.width / paper.x, rect.height / paper.y) * 0.9)
        let centre = rect.center
        transform = SheetTransform(
            offset: Vector2(centre.x - paper.x / 2 * zoom, centre.y + paper.y / 2 * zoom), zoom: zoom)
    }

    /// A scroll pans, or zooms about the pointer when `zooming`.
    public func scrolled(by delta: Vector2, at canvas: Vector2, zooming: Bool) {
        if zooming {
            transform = transform.zoomed(to: transform.zoom * exp(delta.y / Self.wheelZoomScale), about: canvas)
        } else {
            transform = SheetTransform(offset: transform.offset + delta, zoom: transform.zoom)
        }
    }

    /// `factor` is the gesture's magnification since it began.
    public func pinchChanged(_ factor: Double, at canvas: Vector2) {
        if pinchStart == nil { pinchStart = (transform.zoom, transform.sheetPoint(canvas)) }
        guard let start = pinchStart else { return }
        let zoom = SheetTransform.clamped(start.zoom * factor)
        transform = SheetTransform(
            offset: Vector2(canvas.x - start.anchor.x * zoom, canvas.y + start.anchor.y * zoom), zoom: zoom)
    }

    public func pinchEnded() {
        pinchStart = nil
    }

    public func middleDragged(by delta: Vector2) {
        transform = SheetTransform(offset: transform.offset + delta, zoom: transform.zoom)
    }
}
