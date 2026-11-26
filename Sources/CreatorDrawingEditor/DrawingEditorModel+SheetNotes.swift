import CreatorDrawing

/// The sheet inspector's general notes, edge-break note and general surface requirement (DR-4 R12, R15).
extension DrawingEditorModel {
    static let edgeBreakSentence = "An edge break is one or two lengths greater than 0, the smaller first."

    /// One note per line: trailing whitespace trimmed, empty lines dropped.
    public func setGeneralNotes(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
            var trimmed = String(line)
            while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
            return trimmed.isEmpty ? nil : trimmed
        }
        commitSheet(DrawingStepName.editNotes) { $0.notes.lines = lines }
    }

    /// Both empty: none; one empty: the other for both; else the smaller first.
    public func setEdgeBreak(minimumText: String, maximumText: String) {
        let typed = [minimumText, maximumText].filter { !$0.allSatisfy(\.isWhitespace) }
        guard !typed.isEmpty else { return commitEdgeBreak(nil) }
        let lengths = typed.map { units.parse($0, quantity: .length) }
        guard let first = lengths.first ?? nil, first > 0, let last = lengths.last ?? nil, first <= last else {
            return refuse(Self.edgeBreakSentence)
        }
        commitEdgeBreak(EdgeBreak(minimum: first, maximum: last))
    }

    private func commitEdgeBreak(_ edgeBreak: EdgeBreak?) {
        commitSheet(DrawingStepName.changeEdgeBreak) { $0.notes.edgeBreak = edgeBreak }
    }

    public func setGeneralSurface(_ requirement: SurfaceRequirement?) {
        commitSheet(DrawingStepName.changeGeneralSurface) { $0.notes.surface = requirement }
    }

    /// The general requirement's roughness value, typed in µm (µin in an inch document); empty clears it.
    public func setGeneralSurfaceValue(text: String) {
        guard var requirement = sheet?.notes.surface else { return }
        if text.allSatisfy(\.isWhitespace) {
            requirement.value = nil
        } else if let value = roughness(text) {
            requirement.value = value
        } else {
            return refuse(Self.roughnessSentence)
        }
        setGeneralSurface(requirement)
    }
}

extension DrawingEditorModel {
    /// What the sheet's symbols break, one entry per warning: the symbol's text and the sentence, in the sheet's order (R8, R15).
    public var checks: [(id: AnnotationID, label: String, warning: String)] {
        guard let picture else { return [] }
        return picture.checkedAnnotations.flatMap { id -> [(id: AnnotationID, label: String, warning: String)] in
            guard let report = picture.annotationReports[id] else { return [] }
            return report.warnings.map { (id: id, label: report.label, warning: $0) }
        }
    }
}
