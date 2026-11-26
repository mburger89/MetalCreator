import CreatorDrawing
import CreatorGeometry
import Foundation

extension DrawingEditorModel {
    static let seriesDirectionSentence = "Baseline and chain dimensions run horizontally or vertically."
    static let fitSentence = "Fits apply to sizes: a diameter or a distance between two faces."
    static let toleranceNumberSentence = "A tolerance is a number, such as 0.1."
    static let generalToleranceSentence = "A general tolerance is a number, such as 0.1."
    static let emptyNoteSentence = "A note needs some text; delete it instead."
    static let precisionSentence = "Precision is 0 to 4 decimals."

    // MARK: Dimensions

    /// A linear dimension's direction (a baseline or chain keeps its family), or a circle's radius against diameter.
    public func setDimensionKind(_ kind: DrawingDimensionKind, of id: AnnotationID) {
        guard case .dimension(let current)? = sheet?.annotation(id)?.kind else { return }
        guard let next = nextKind(from: current, asking: kind) else { return }
        if let sheet, current.kind != next, !symbolsAccept(next, on: id, in: sheet) { return refuse(Self.symbolBlocksKindSentence) }
        commitDimension(id, DrawingStepName.changeDimension) { $0.kind = next }
    }

    /// The kind a dimension takes for the one asked, or `nil` after refusing (or when nothing changes).
    private func nextKind(from current: DrawingDimension, asking kind: DrawingDimensionKind) -> DrawingDimensionKind? {
        switch (current.kind, kind) {
        case (.linear, .linear(let direction)), (.linear, .baseline(let direction)), (.linear, .chain(let direction)):
            return .linear(direction)
        case (.baseline, .linear(let direction)), (.baseline, .baseline(let direction)), (.baseline, .chain(let direction)):
            guard direction != .aligned else { return refused(Self.seriesDirectionSentence) }
            return .baseline(direction)
        case (.chain, .linear(let direction)), (.chain, .baseline(let direction)), (.chain, .chain(let direction)):
            guard direction != .aligned else { return refused(Self.seriesDirectionSentence) }
            return .chain(direction)
        case (.radius, .radius), (.radius, .diameter), (.diameter, .radius), (.diameter, .diameter):
            if case .radius = kind, case .fit = current.tolerance { return refused(Self.fitSentence) }
            return kind
        default:
            if !Self.sameFamily(current.kind, kind) { refuse(Self.mismatchedKindSentence) }
            return nil
        }
    }

    private func refused(_ sentence: String) -> DrawingDimensionKind? {
        refuse(sentence)
        return nil
    }

    private static func sameFamily(_ a: DrawingDimensionKind, _ b: DrawingDimensionKind) -> Bool {
        switch (a, b) {
        case (.linear, .linear), (.baseline, .baseline), (.chain, .chain), (.ordinate, .ordinate), (.radius, .radius),
            (.diameter, .diameter), (.angle, .angle), (.chamfer, .chamfer): true
        default: false
        }
    }

    /// Whether every symbol hanging on the dimension would still be accepted once it has kind `next` (plan R2).
    private func symbolsAccept(_ next: DrawingDimensionKind, on id: AnnotationID, in sheet: DrawingSheet) -> Bool {
        guard var changed = sheet.annotation(id), case .dimension(var value) = changed.kind else { return true }
        value.kind = next
        changed.kind = .dimension(value)
        return sheet.symbols(on: id).allSatisfy { symbol in
            switch symbol.kind {
            case .datumFeature: SymbolAttachment.accepts(.datum, on: changed)
            case .featureControl: SymbolAttachment.accepts(.frame, on: changed)
            case .surfaceTexture: SymbolAttachment.accepts(.surface, on: changed)
            default: true
            }
        }
    }

    /// Decimals from 0 to 4, or the document's own (`nil`).
    public func setPrecision(_ precision: Int?, of id: AnnotationID) {
        if let precision, !DocumentUnits.precisionRange.contains(precision) {
            refuse(Self.precisionSentence)
            return
        }
        commitDimension(id, DrawingStepName.changeDimension) { $0.precision = precision }
    }

    public func setPrefix(_ prefix: String, of id: AnnotationID) {
        commitText(id) { $0.prefix = prefix } callout: { $0.prefix = prefix }
    }

    public func setSuffix(_ suffix: String, of id: AnnotationID) {
        commitText(id) { $0.suffix = suffix } callout: { $0.suffix = suffix }
    }

    private func commitText(
        _ id: AnnotationID, dimension: @escaping (inout DrawingDimension) -> Void, callout: @escaping (inout HoleCallout) -> Void
    ) {
        commitSheet(DrawingStepName.changeDimension) { sheet in
            guard var annotation = sheet.annotation(id) else { return }
            switch annotation.kind {
            case .dimension(var value):
                dimension(&value)
                annotation.kind = .dimension(value)
            case .holeCallout(var value):
                callout(&value)
                annotation.kind = .holeCallout(value)
            default:
                return
            }
            sheet.setAnnotation(annotation)
        }
    }

    func commitDimension(_ id: AnnotationID, _ name: String, _ change: @escaping (inout DrawingDimension) -> Void) {
        commitSheet(name) { sheet in
            guard var annotation = sheet.annotation(id), case .dimension(var value) = annotation.kind else { return }
            change(&value)
            annotation.kind = .dimension(value)
            sheet.setAnnotation(annotation)
        }
    }

    // MARK: Tolerances

    /// Sets a dimension's tolerance; a fit applies to sizes only (plan R10).
    public func setTolerance(_ tolerance: DimensionTolerance, of id: AnnotationID) {
        guard case .dimension(let current)? = sheet?.annotation(id)?.kind else { return }
        if case .fit = tolerance, !Self.takesFit(current.kind) {
            refuse(Self.fitSentence)
            return
        }
        commitDimension(id, DrawingStepName.changeTolerance) { $0.tolerance = tolerance }
    }

    /// A symmetric tolerance typed in the document's unit (degrees for an angle).
    public func setTolerance(symmetricText: String, of id: AnnotationID) {
        guard let amount = toleranceAmount(symmetricText, of: id), amount > 0 else {
            refuse(Self.toleranceNumberSentence)
            return
        }
        setTolerance(.symmetric(amount), of: id)
    }

    /// A deviation, or with `limits` the limit sizes, typed in the document's unit (degrees for an angle).
    public func setTolerance(upperText: String, lowerText: String, limits: Bool = false, of id: AnnotationID) {
        guard let upper = toleranceAmount(upperText, of: id), let lower = toleranceAmount(lowerText, of: id) else {
            refuse(Self.toleranceNumberSentence)
            return
        }
        setTolerance(limits ? .limits(upper: upper, lower: lower) : .deviation(upper: upper, lower: lower), of: id)
    }

    /// Millimetres, or radians for an angle, from what was typed; `nil` when it is no number.
    private func toleranceAmount(_ text: String, of id: AnnotationID) -> Double? {
        guard case .dimension(let dimension)? = sheet?.annotation(id)?.kind else { return nil }
        if case .angle = dimension.kind {
            return units.parse(text, quantity: .angle).map { $0 * .pi / 180 }
        }
        return units.parse(text, quantity: .length)
    }

    private static func takesFit(_ kind: DrawingDimensionKind) -> Bool {
        switch kind {
        case .linear, .diameter: true
        case .baseline, .chain, .ordinate, .radius, .angle, .chamfer: false
        }
    }

    // MARK: Notes and view settings

    /// Replaces a note's text; empty text is refused.
    public func setNoteText(_ text: String, of id: AnnotationID) {
        guard case .note? = sheet?.annotation(id)?.kind else { return }
        guard !text.allSatisfy(\.isWhitespace) else {
            refuse(Self.emptyNoteSentence)
            return
        }
        commitSheet(DrawingStepName.editNote) { sheet in
            guard var annotation = sheet.annotation(id), case .note(var note) = annotation.kind else { return }
            note.text = text
            annotation.kind = .note(note)
            sheet.setAnnotation(annotation)
        }
    }

    public func removeLeader(at index: Int, of id: AnnotationID) {
        guard case .note(let current)? = sheet?.annotation(id)?.kind, current.leaders.indices.contains(index) else { return }
        commitSheet(DrawingStepName.removeLeader) { sheet in
            guard var annotation = sheet.annotation(id), case .note(var note) = annotation.kind else { return }
            note.leaders.remove(at: index)
            annotation.kind = .note(note)
            sheet.setAnnotation(annotation)
        }
    }

    public func setShowsCentreMarks(_ shows: Bool, of id: ViewID) {
        commitView(id) { $0.showsCentreMarks = shows }
    }
}
