import CreatorDrawing
import CreatorGeometry

/// Puts copies of views and annotations onto a sheet with new ids (DR-5 R18); `duplicateSheet` and paste share it.
enum SheetCopy {
    static let derivedAloneRefusal = "Copy a section, detail or auxiliary view together with the view it was made from."
    static let otherSheetSentence = "Some annotations belong to a view on another sheet, so they weren't pasted."
    static let partsListSentence = "This sheet has a parts list already."
    static let revisionTableSentence = "This sheet has a revision table already."
    static let symbolSentence = "Some symbols hang on a dimension that wasn't copied, so they weren't pasted."

    /// `sheet` with copies of `views` and `annotations` added, each with a new id.
    ///
    /// Views and annotations on no view are moved by `offset`; an annotation of a view that was not copied but is on `sheet` goes
    /// onto that view, moved by `offset`. An alignment to a view not copied is dropped, a derived view keeps its parent only when
    /// that was copied, and takes a fresh letter unless `keepingLetters`.
    static func copy(
        views: [DrawingView], annotations: [DrawingAnnotation], onto sheet: DrawingSheet, offset: Vector2,
        keepingLetters: Bool = false
    ) -> (sheet: DrawingSheet, views: [ViewID], annotations: [AnnotationID], skipped: [String]) {
        var result = sheet
        var renamed: [ViewID: ViewID] = [:]
        for view in views { renamed[view.id] = ViewID() }
        var newViews: [ViewID] = []
        for original in views {
            guard let view = copied(original, as: renamed, offset: offset, keepingLetters: keepingLetters) else { continue }
            result.setView(view)
            newViews.append(view.id)
        }
        if !keepingLetters {
            for id in newViews {
                guard var view = result.view(id), view.derivation != nil else { continue }
                view.letter = ViewLetters.next(on: result)
                result.setView(view)
            }
        }
        let (made, skipped) = addAnnotations(annotations, renamed: renamed, offset: offset, to: &result, from: sheet)
        return (result, newViews, made, skipped)
    }

    /// The view with its new id, moved, its alignment and derivation pointed at the copies; nil when its parent isn't copied.
    private static func copied(
        _ original: DrawingView, as renamed: [ViewID: ViewID], offset: Vector2, keepingLetters: Bool
    ) -> DrawingView? {
        var view = original
        view.id = renamed[original.id] ?? ViewID()
        view.center += offset
        view.alignment = original.alignment.flatMap { alignment in
            renamed[alignment.parent].map { ViewAlignment(parent: $0, axis: alignment.axis) }
        }
        if let derivation = original.derivation {
            guard let parent = renamed[derivation.parent] else { return nil }
            view.derivation = derivation.withParent(parent)
            if !keepingLetters { view.letter = nil }
        }
        return view
    }

    private static func addAnnotations(
        _ annotations: [DrawingAnnotation], renamed: [ViewID: ViewID], offset: Vector2, to result: inout DrawingSheet,
        from sheet: DrawingSheet
    ) -> (made: [AnnotationID], skipped: [String]) {
        var skipped: [String] = []
        var newIDs: [AnnotationID: AnnotationID] = [:]
        var made: [AnnotationID] = []
        let offered = Set(annotations.map(\.id))
        for annotation in annotations {
            let placed: (view: ViewID?, delta: Vector2)
            if let sentence = refusal(of: annotation, offered: offered, in: result) {
                if !skipped.contains(sentence) { skipped.append(sentence) }
                continue
            }
            if let owner = annotation.view {
                if let copy = renamed[owner] {
                    placed = (copy, .zero)
                } else if sheet.view(owner) != nil {
                    placed = (owner, offset)
                } else {
                    if !skipped.contains(otherSheetSentence) { skipped.append(otherSheetSentence) }
                    continue
                }
            } else {
                placed = (nil, offset)
            }
            var copy = annotation
            copy.id = AnnotationID()
            copy.view = placed.view
            copy.kind = shifted(annotation.kind, by: placed.delta)
            newIDs[annotation.id] = copy.id
            result.setAnnotation(copy)
            made.append(copy.id)
        }
        // A symbol's dimension is now a new one.
        for id in made {
            guard var annotation = result.annotation(id) else { continue }
            annotation.kind = remappingAttachment(of: annotation.kind, newIDs)
            result.setAnnotation(annotation)
        }
        // Annotations come in id order, so the sentences are put in a fixed one.
        let order = [otherSheetSentence, partsListSentence, revisionTableSentence, symbolSentence]
        skipped.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        return (made, skipped)
    }

    /// Why this annotation can't be pasted on `sheet`, if it can't.
    private static func refusal(of annotation: DrawingAnnotation, offered: Set<AnnotationID>, in sheet: DrawingSheet) -> String? {
        if case .dimension(let host)? = annotation.symbolAttachment, !offered.contains(host) { return symbolSentence }
        switch annotation.kind {
        case .partsList where sheet.partsList != nil: return partsListSentence
        case .revisionTable where sheet.revisionTable != nil: return revisionTableSentence
        default: return nil
        }
    }

    /// A symbol on a dimension names the copied dimension (plan R14).
    static func remappingAttachment(of kind: AnnotationKind, _ ids: [AnnotationID: AnnotationID]) -> AnnotationKind {
        func remapped(_ attachment: SymbolAttachment) -> SymbolAttachment {
            if case .dimension(let id) = attachment { return .dimension(ids[id] ?? id) }
            return attachment
        }
        switch kind {
        case .datumFeature(var datum):
            datum.attachment = remapped(datum.attachment)
            return .datumFeature(datum)
        case .featureControl(var frame):
            frame.attachment = remapped(frame.attachment)
            return .featureControl(frame)
        default: return kind
        }
    }

    /// `kind` set `delta` further. Annotations on a view are placed relative to the geometry, so those that were not copied with it
    /// are nudged by the amount their own placement allows; free ones move by the vector.
    private static func shifted(_ kind: AnnotationKind, by delta: Vector2) -> AnnotationKind {
        guard delta != .zero else { return kind }
        switch kind {
        case .note(var note):
            note.position += delta
            return .note(note)
        case .dimension(var dimension):
            dimension.placement.offset += delta.x
            return .dimension(dimension)
        case .holeCallout(var callout):
            callout.placement.offset += delta.x
            return .holeCallout(callout)
        case .datumFeature(var datum):
            datum.distance += delta.x
            return .datumFeature(datum)
        case .featureControl(var frame):
            frame.offset += delta
            return .featureControl(frame)
        case .surfaceTexture(var texture):
            texture.offset = texture.offset.map { $0 + delta }
            return .surfaceTexture(texture)
        case .balloon, .partsList, .revisionTable:
            return shiftedFurniture(kind, by: delta)
        case .centreMark, .centreLine:
            return kind
        }
    }

    private static func shiftedFurniture(_ kind: AnnotationKind, by delta: Vector2) -> AnnotationKind {
        switch kind {
        case .balloon(var balloon):
            balloon.offset += delta
            return .balloon(balloon)
        case .partsList(var list):
            list.bottomRight = list.bottomRight.map { $0 + delta }
            return .partsList(list)
        case .revisionTable(var table):
            table.topRight = table.topRight.map { $0 + delta }
            return .revisionTable(table)
        default:
            return kind
        }
    }
}
