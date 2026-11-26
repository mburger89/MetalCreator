import CreatorDrawing
import CreatorGeometry
import CreatorKernel

/// The Datum, Feature Control Frame and Surface Finish tools (DR-4 R15): the first click names a line or a dimension, the next
/// places the symbol.
extension DrawingEditorModel {
    static let attachSymbolSentence = "Attach the symbol to a line of a view or to a dimension."
    static let datumSizeSentence = "A datum symbol goes on a size: a linear dimension, a diameter or a hole callout."
    static let frameSizeSentence = "A tolerance frame goes on a size: a linear dimension, a radius, a diameter or a hole callout."
    static let symbolOnDimensionSentence = "This symbol hangs on a dimension; reattach the dimension and the symbol follows it."

    // MARK: Clicks

    /// A press-and-release of a symbol tool at `point` (sheet millimetres): the target first, then the place.
    func symbolClick(at point: Vector2) {
        if symbolDraft == nil {
            chooseSymbolTarget(at: point)
        } else {
            placeSymbol(at: point)
        }
    }

    private func chooseSymbolTarget(at point: Vector2) {
        guard let sheet, let picture, let kind = tool.symbolKind else { return }
        let order = sheet.annotations.map(\.id)
        // A click on a text is on that annotation; a click on a line is on the line, even inside a dimension's wide frame; a click
        // on nothing but an annotation's frame is on the annotation.
        if let onText = order.last(where: { isOnLabel(point, of: $0) }) {
            attachToAnnotation(onText, kind: kind)
            return
        }
        let framed = SheetHitTest.annotation(at: point, in: picture, order: order)
        guard let view = viewUnder(point), case .success(let context) = pickContext(of: view) else {
            if let framed { attachToAnnotation(framed, kind: kind) }
            return
        }
        if context.isPictorial {
            refuse(DrawingPick.symbolIsometricSentence)
        } else if let found = candidate(at: point, in: view) {
            pickLine(found, at: point, in: view, context: context, kind: kind)
        } else if let framed {
            attachToAnnotation(framed, kind: kind)
        } else if let refused = DrawingPick.refusal(
            at: point, in: picture, view: view, tolerance: Self.hoverTolerancePoints / transform.zoom,
            purpose: PickPurpose(symbol: kind)) {
            refuse(refused.sentence)
        }
    }

    private func pickLine(_ found: PickCandidate, at point: Vector2, in view: ViewID, context: PickContext, kind: SymbolKind) {
        let result = DrawingPick.anchor(
            for: found, click: point, purpose: PickPurpose(symbol: kind), topology: context.topology, frame: context.frame,
            mapping: context.mapping, isIsometric: context.isPictorial,
            parts: context.parts)
        switch result {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let anchor):
            refusal = nil
            symbolDraft = SymbolDraft(tool: tool, view: view, target: .feature(anchor, hint: context.mapping.model(point)))
            updateDraft()
        }
    }

    /// Takes the dimension or hole callout `id` as the target when the tool's kind rules (R2) accept it, else says why not.
    private func attachToAnnotation(_ id: AnnotationID, kind: SymbolKind) {
        guard let annotation = sheet?.annotation(id), let view = annotation.view else {
            refuse(Self.attachSymbolSentence)
            return
        }
        switch annotation.kind {
        case .dimension, .holeCallout: break
        default:
            refuse(Self.attachSymbolSentence)
            return
        }
        guard SymbolAttachment.accepts(kind, on: annotation) else {
            switch kind {
            case .datum: refuse(Self.datumSizeSentence)
            case .frame: refuse(Self.frameSizeSentence)
            case .surface: refuse(DrawingPick.surfaceCircleSentence)
            }
            return
        }
        refusal = nil
        symbolDraft = SymbolDraft(tool: tool, view: view, target: .dimension(id))
        updateDraft()
    }

    // MARK: Placing

    private func placeSymbol(at point: Vector2) {
        guard let draft = symbolDraft else { return }
        switch symbolKind(for: draft, placing: point) {
        case .failure(let refused): refuse(refused.sentence)
        case .success(let kind):
            guard addAnnotation(kind, view: draft.view, name: draft.stepName, id: draft.id) else { return }
            switch kind {
            case .featureControl(let frame): frameTemplate = frame
            case .surfaceTexture(let texture): surfaceTemplate = texture
            default: break
            }
        }
    }

    /// The symbol a click at `point` would place for `draft`: the one call the draft picture and the committed annotation share.
    func symbolKind(for draft: SymbolDraft, placing point: Vector2) -> Result<AnnotationKind, DrawingRefusal> {
        guard case .success(let context) = pickContext(of: draft.view) else {
            return .failure(DrawingRefusal(sentence: LostReason.noPart.sentence))
        }
        switch draft.target {
        case .feature(let anchor, let hint): return onLine(draft, anchor: anchor, hint: hint, click: point, context: context)
        case .dimension(let id): return onDimension(draft, id: id, click: point)
        }
    }

    private func onLine(
        _ draft: SymbolDraft, anchor: PickedAnchor, hint: Vector2, click: Vector2, context: PickContext
    ) -> Result<AnnotationKind, DrawingRefusal> {
        guard case .held(let geometry, _, _) = DrawingAnchorResolver.resolve(anchor.target, in: context.topology, frame: context.frame,
                parts: context.parts ?? []),
            case .success(let found) = SymbolFoot.of(geometry, hint: hint, frame: context.frame) else {
            return .failure(DrawingRefusal(sentence: LostReason.missing.sentence))
        }
        let foot = context.mapping.sheet(found.foot)
        let length = found.along.length
        let along = length > 1e-12 ? found.along * (1 / length) : Vector2(1, 0)
        let end = LeaderEnd(target: anchor.target, hint: hint)
        switch draft.tool {
        case .datum:
            let distance = SymbolPlacing.datumDistance(foot: foot, along: along, click: click)
            return .success(
                .datumFeature(
                    DatumFeature(letter: DatumLetters.next(in: document), attachment: .feature(end), distance: distance)))
        case .featureControlFrame:
            return .success(.featureControl(newFrame(attachment: .feature(end), offset: click - foot)))
        default:
            var texture = newSurface(feature: end)
            let snap = SymbolStyle.of(document.settings.standard).standSnap
            if SymbolPlacing.standsOn(foot: foot, along: along, click: click, snap: snap) {
                // It stands where the person put it: the foot slides to the click.
                texture.feature.hint = context.mapping.model(click)
                texture.offset = nil
            } else {
                texture.offset = click - foot
            }
            return .success(.surfaceTexture(texture))
        }
    }

    private func onDimension(_ draft: SymbolDraft, id: AnnotationID, click: Vector2) -> Result<AnnotationKind, DrawingRefusal> {
        guard let picture, let report = picture.annotationReports[id] else {
            return .failure(DrawingRefusal(sentence: LostReason.noPart.sentence))
        }
        if case .lost(let reason) = report.status { return .failure(DrawingRefusal(sentence: reason.sentence)) }
        guard let rect = report.labelRect else { return .failure(DrawingRefusal(sentence: LostReason.noPart.sentence)) }
        let host = SymbolPlacing.Host(
            labelRect: rect, tips: report.dimensionLine, stackBottom: stackBottom(on: id, before: draft),
            gap: AnnotationStyle.of(document.settings.standard).textGap)
        switch draft.tool {
        case .datum:
            let placed = SymbolPlacing.datumOnHost(host, click: click)
            return .success(
                .datumFeature(
                    DatumFeature(
                        letter: DatumLetters.next(in: document), attachment: .dimension(id), distance: placed.distance,
                        dimensionEnd: placed.end)))
        case .featureControlFrame:
            let offset = SymbolPlacing.frameOffset(on: host, click: click)
            return .success(.featureControl(newFrame(attachment: .dimension(id), offset: offset)))
        default:
            return .failure(DrawingRefusal(sentence: DrawingPick.surfaceCircleSentence))
        }
    }

    /// The lowest y of the symbols the composer stacks on dimension `id` before the draft's (AnnotationPass: frames first, then
    /// hanging datums, each group in id order), or `nil` with none. A frame sits under the frames with smaller ids; a hanging
    /// datum under every frame and the hanging datums with smaller ids.
    private func stackBottom(on id: AnnotationID, before draft: SymbolDraft) -> Double? {
        guard let sheet, let picture else { return nil }
        let hangs = picture.annotationReports[id]?.dimensionLine == nil
        var bottom: Double?
        for symbol in sheet.symbols(on: id) where symbol.id != draft.id {
            switch (draft.tool, symbol.kind) {
            case (.featureControlFrame, .featureControl):
                if symbol.id > draft.id { continue }
            case (.datum, .featureControl):
                break
            case (.datum, .datumFeature):
                if !hangs || symbol.id > draft.id { continue }
            default:
                continue
            }
            guard let report = picture.annotationReports[symbol.id], report.frame.height > 0 || report.frame.width > 0 else { continue }
            bottom = Swift.min(bottom ?? report.frame.min.y, report.frame.min.y)
        }
        return bottom
    }

    // MARK: New symbols

    /// A frame like the last one placed in this session, else flatness 0.05 mm (R15).
    private func newFrame(attachment: SymbolAttachment, offset: Vector2) -> FeatureControlFrame {
        var frame = frameTemplate
            ?? FeatureControlFrame(characteristic: .flatness, rows: [ToleranceRow(zone: .width, value: 0.05)], attachment: attachment)
        frame.attachment = attachment
        frame.offset = offset
        return frame
    }

    /// A surface symbol like the last one placed, else material removal required, Ra 3.2 µm, no lay.
    private func newSurface(feature: LeaderEnd) -> SurfaceTexture {
        var texture = surfaceTemplate
            ?? SurfaceTexture(
                requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 3.2), feature: feature)
        texture.feature = feature
        texture.offset = nil
        return texture
    }

    // MARK: The draft

    /// The picture with the symbol composed in under the pointer, or none.
    func symbolDraftPicture() -> SheetPicture? {
        guard let draft = symbolDraft, let sheet, let point = lastPointer,
            case .success(let kind) = symbolKind(for: draft, placing: point) else { return nil }
        var drafted = sheet
        drafted.setAnnotation(DrawingAnnotation(id: draft.id, view: draft.view, kind: kind))
        return SheetComposer.compose(
            drafted, in: document, contents: contents, facts: facts, units: units, remembered: remembered)
    }

    /// After undo or redo: a target whose view or dimension is gone goes (R16).
    func pruneSymbolDraft() {
        guard let draft = symbolDraft else { return }
        if sheet?.view(draft.view) == nil {
            symbolDraft = nil
            draftPicture = nil
        } else if case .dimension(let id) = draft.target, sheet?.annotation(id) == nil {
            symbolDraft = nil
            draftPicture = nil
        }
    }
}
