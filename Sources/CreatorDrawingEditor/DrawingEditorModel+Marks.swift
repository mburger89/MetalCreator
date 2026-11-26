import CreatorDrawing
import CreatorGeometry

/// A cutting line or detail circle being dragged on its parent: the document it started from and the parent's scale.
struct MarkMove {
    var baseDocument: DrawingDocument
    var base: DrawingSheet
    var view: ViewID
    var start: Vector2
    var scale: Double
    var key: String
}

extension DrawingEditorModel {
    static let detailRadiusNumberSentence =
        "A detail's radius is a length such as 12, 12 mm or 0.5 in."
    static let detailRadiusSentence = "A detail's radius is a length greater than 0."

    /// A press on the mark of a derived view (R13): selects the view and, for a cutting line or a detail circle, begins moving the
    /// mark. An auxiliary view's arrow does not move.
    func markDown(_ id: ViewID, at point: Vector2, modifiers: SheetModifiers, sheet: DrawingSheet) {
        if modifiers.contains(.shift) {
            selection.insert(id)
        } else if !selection.contains(id) {
            selection = [id]
            selectedAnnotations = []
        }
        guard let view = sheet.view(id), let parent = view.derivation?.parent, let mapping = parentMapping(of: parent) else {
            gesture = nil
            return
        }
        switch view.derivation {
        case .section?, .detail?:
            dragSerial += 1
            gesture = .movingMark(
                MarkMove(
                    baseDocument: document, base: sheet, view: id, start: point, scale: mapping.scale,
                    key: "drawing-move-mark-\(dragSerial)"))
        case .auxiliary?, nil:
            gesture = nil
        }
    }

    func continueMarkMove(_ move: MarkMove, to point: Vector2) {
        guard let sheetID = currentSheet, move.scale > 0, var view = move.base.view(move.view) else { return }
        let delta = (point - move.start) * (1 / move.scale)
        let name: String
        switch view.derivation {
        case .section(var line)?:
            line.cutter.points = line.cutter.points.map { $0 + delta }
            view.derivation = .section(line)
            name = DrawingStepName.moveCuttingLine
        case .detail(var circle)?:
            circle.center += delta
            view.derivation = .detail(circle)
            name = DrawingStepName.moveDetailCircle
        case .auxiliary?, nil:
            return
        }
        var next = move.base
        next.setView(view)
        commit(name, key: move.key) { document in
            guard let index = document.sheets.firstIndex(where: { $0.id == sheetID }) else { return }
            document.sheets[index] = next
        }
    }

    /// Esc or a dropped press during a mark move: the document goes back and the host forgets the steps.
    func cancelMarkMove(_ move: MarkMove) {
        guard document != move.baseDocument else { return }
        document = move.baseDocument
        events.discarded(move.key)
    }

    /// Sets a detail's radius from what was typed: a number in the document's unit or with a unit suffix; a comma may be the
    /// decimal sign.
    public func setDetailRadius(text: String, of id: ViewID) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if !text.contains("."), text.filter({ $0 == "," }).count == 1 { text = text.replacingOccurrences(of: ",", with: ".") }
        guard let millimetres = units.parse(text, quantity: .length) else {
            refuse(Self.detailRadiusNumberSentence)
            return
        }
        setDetailRadius(units.value(fromMillimetres: millimetres), of: id)
    }

    /// Sets a detail's radius, typed in the document's unit and stored in millimetres on the parent's plane.
    public func setDetailRadius(_ radius: Double, of id: ViewID) {
        guard radius.isFinite, radius > 0 else {
            refuse(Self.detailRadiusSentence)
            return
        }
        let millimetres = units.millimetres(fromValue: radius)
        commitView(id, DrawingStepName.changeDetailCircle) { view in
            guard case .detail(var circle)? = view.derivation else { return }
            circle.radius = millimetres
            view.derivation = .detail(circle)
        }
    }
}
