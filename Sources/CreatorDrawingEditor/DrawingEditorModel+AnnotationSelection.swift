import CreatorDrawing
import CreatorGeometry
import Foundation

/// What a gesture that moves views and annotations holds: the document it started from, the views it moves and the geometry of
/// each annotation it moves, read once at the press.
struct MoveGesture {
    var baseDocument: DrawingDocument
    var base: DrawingSheet
    var start: Vector2
    var key: String
    var roots: [ViewID]
    var seeds: [AnnotationSeed]
}

/// What moving one annotation needs, in sheet millimetres (plan R7): the direction a linear dimension measures along, the centre a
/// radial one turns about, and where its text is.
struct AnnotationSeed {
    var id: AnnotationID
    /// The unit measuring direction of a linear or ordinate dimension.
    var direction: Vector2?
    /// The centre (or vertex) a radial, chamfer, hole or angle dimension is placed about.
    var anchor: Vector2?
    /// The radius of the circle the leader starts on.
    var radius = 0.0
    /// The middle of the text, or of the whole figure when it has none, when the gesture began.
    var handle: Vector2
    /// The middle of a linear dimension's feet.
    var feetMiddle: Vector2?
    /// Whether the press was on the text, which shifts it along the line.
    var onLabel = false
    /// The view's millimetres on the sheet per model millimetre, for a symbol that slides along its line (DR-4 R16).
    var scale = 1.0
    /// The dimension a symbol hangs on and that dimension's dimension line (its two tips on the sheet), when it has one.
    var host: AnnotationID?
    var tips: [Vector2]?
}

extension DrawingEditorModel {
    // MARK: Reading

    /// The annotations of the sheet that lost what they were attached to: their text and why, in sheet order (plan R15).
    public var lostAnnotations: [(id: AnnotationID, label: String, reason: String)] {
        guard let picture else { return [] }
        return picture.lostAnnotations.compactMap { id in
            guard let report = picture.annotationReports[id], case .lost(let reason) = report.status else { return nil }
            return (id: id, label: report.label, reason: reason.sentence)
        }
    }

    /// The drawings as they are saved: each annotation's `last` is the newest held figure the editor remembers, where it has one.
    /// The editor's own document is not changed (plan R15).
    public func documentForSaving() -> DrawingDocument {
        var saved = document
        let wanted = PartItems.wanted(in: document)
        saved.partNames = wanted.compactMap { part in rememberedPartNames[part].map { PartName(part: part, name: $0) } }
            .sorted { $0.part < $1.part }
        for index in saved.sheets.indices {
            for annotation in saved.sheets[index].annotations {
                guard let good = remembered[annotation.id], annotation.last != good else { continue }
                var written = annotation
                written.last = good
                saved.sheets[index].setAnnotation(written)
            }
        }
        return saved
    }

    // MARK: Hitting

    /// How far a press may stray from a text and still be on it, in sheet millimetres (as an annotation's frame is grown).
    static let labelGrowth = 1.0

    /// Whether `point` is on one of the annotation's texts.
    func isOnLabel(_ point: Vector2, of id: AnnotationID) -> Bool {
        guard let picture else { return false }
        let grow = Self.labelGrowth
        for text in picture.texts where text.annotation == id {
            let offset = point - text.origin
            let cosine = cos(-text.angle), sine = sin(-text.angle)
            let local = Vector2(offset.x * cosine - offset.y * sine, offset.x * sine + offset.y * cosine)
            if local.x >= -grow, local.x <= text.run.width + grow, local.y >= -0.3 * text.height - grow,
                local.y <= 1.2 * text.height + grow {
                return true
            }
        }
        return false
    }

    // MARK: Seeds

    /// The geometry of each annotation of `ids` (in the sheet's order) that a drag or a nudge can move.
    func seeds(for ids: Set<AnnotationID>, pressing point: Vector2?) -> [AnnotationSeed] {
        guard let sheet, let picture else { return [] }
        var result: [AnnotationSeed] = []
        for annotation in sheet.annotations where ids.contains(annotation.id) {
            guard let report = picture.annotationReports[annotation.id] else { continue }
            let handle = report.textCenter ?? report.frame.center
            var seed = AnnotationSeed(id: annotation.id, handle: handle)
            if let point, isOnLabel(point, of: annotation.id) { seed.onLabel = true }
            let figure = report.current?.figure ?? remembered[annotation.id]?.figure ?? annotation.last?.figure
            if let figure, let view = annotation.view, case .success(let context) = pickContext(of: view) {
                Self.describe(figure, with: context.mapping, in: &seed)
            }
            if case .dimension(let host)? = annotation.symbolAttachment {
                seed.host = host
                seed.tips = picture.annotationReports[host]?.dimensionLine
            }
            // A table moves its corner: where it stands now, standing on the title block or the frame included (DR-5 R16).
            seed.anchor = tableCorner(of: annotation.kind, in: sheet) ?? seed.anchor
            result.append(seed)
        }
        return result
    }

    /// Where a table stands now: its own corner, else the title block's or the frame's (DR-5 R16).
    private func tableCorner(of kind: AnnotationKind, in sheet: DrawingSheet) -> Vector2? {
        let standard = document.settings.standard
        switch kind {
        case .partsList(let list): return list.bottomRight ?? Self.blockTopRight(of: sheet, standard: standard)
        case .revisionTable(let table): return table.topRight ?? SheetFrame.rect(for: sheet, standard: standard).max
        default: return nil
        }
    }

    private static func describe(_ figure: AnnotationFigure, with mapping: ViewMapping, in seed: inout AnnotationSeed) {
        switch figure {
        case .linear(let points, let direction):
            seed.direction = unit(direction)
            if let first = points.first { seed.feetMiddle = mapping.sheet((first + (points.dropFirst().first ?? first)) * 0.5) }
        case .ordinate(_, _, let direction):
            seed.direction = unit(direction)
        case .radial(let center, let radius, _), .hole(let center, let radius):
            seed.anchor = mapping.sheet(center)
            seed.radius = radius * mapping.scale
        case .angle(let vertex, _, _):
            seed.anchor = mapping.sheet(vertex)
        case .chamfer(let start, let end):
            seed.anchor = mapping.sheet((start + end) * 0.5)
        case .attachment(_, let along, _):
            seed.direction = unit(along)
            seed.scale = mapping.scale
        case .centreMark, .centreLine, .leaders:
            break
        }
    }

    private static func unit(_ vector: Vector2) -> Vector2? {
        vector.length > 1e-12 ? vector * (1 / vector.length) : nil
    }

    // MARK: Moving

    /// `sheet` with the roots moved by `delta` (their aligned views with them) and every seeded annotation of a view that did not
    /// move placed `delta` further (plan R7, R18).
    static func movedSheet(
        _ sheet: DrawingSheet, roots: [ViewID], seeds: [AnnotationSeed], by delta: Vector2
    ) -> DrawingSheet {
        var result = sheet
        for root in roots { result = ViewPlacement.moving(root, by: delta, in: result) }
        let before = ViewPlacement.centers(in: sheet), after = ViewPlacement.centers(in: result)
        for seed in seeds {
            guard let annotation = sheet.annotation(seed.id) else { continue }
            if let view = annotation.view, before[view] != after[view] { continue }
            // A symbol on a dimension is drawn from it: moving the dimension moves the symbol, and moving it again would double it.
            if case .dimension(let host)? = annotation.symbolAttachment, seeds.contains(where: { $0.id == host }) { continue }
            result.setAnnotation(moved(annotation, seed: seed, by: delta))
        }
        return result
    }

    static func moved(_ annotation: DrawingAnnotation, seed: AnnotationSeed, by delta: Vector2) -> DrawingAnnotation {
        var result = annotation
        switch annotation.kind {
        case .note(var note):
            note.position += delta
            result.kind = .note(note)
        case .dimension(var dimension):
            dimension.placement = placement(dimension.placement, of: dimension.kind, seed: seed, by: delta)
            result.kind = .dimension(dimension)
        case .holeCallout(var callout):
            callout.placement = radial(callout.placement, seed: seed, by: delta)
            result.kind = .holeCallout(callout)
        case .centreMark, .centreLine:
            break
        case .datumFeature(var datum):
            movedDatum(&datum, seed: seed, by: delta)
            result.kind = .datumFeature(datum)
        case .featureControl(var frame):
            frame.offset += delta
            result.kind = .featureControl(frame)
        case .surfaceTexture(var texture):
            if let offset = texture.offset {
                texture.offset = offset + delta
            } else if let along = seed.direction {
                texture.feature.hint += along * ((delta.x * along.x + delta.y * along.y) / seed.scale)
            }
            result.kind = .surfaceTexture(texture)
        case .balloon, .partsList, .revisionTable:
            result.kind = movedFurniture(annotation.kind, seed: seed, by: delta)
        }
        return result
    }

    /// A balloon moves its circle about its foot; a table moves its corner, so a standing one becomes free (DR-5 R16).
    private static func movedFurniture(_ kind: AnnotationKind, seed: AnnotationSeed, by delta: Vector2) -> AnnotationKind {
        switch kind {
        case .balloon(var balloon):
            balloon.offset += delta
            return .balloon(balloon)
        case .partsList(var list):
            list.bottomRight = (seed.anchor ?? list.bottomRight ?? .zero) + delta
            return .partsList(list)
        case .revisionTable(var table):
            table.topRight = (seed.anchor ?? table.topRight ?? .zero) + delta
            return .revisionTable(table)
        default:
            return kind
        }
    }

    /// A datum on a line slides its foot along it and changes its distance by the across part; on a dimension line it goes to the
    /// nearer end and the pointer's distance; hanging under a label it changes by the downward part (plan R16).
    private static func movedDatum(_ datum: inout DatumFeature, seed: AnnotationSeed, by delta: Vector2) {
        switch datum.attachment {
        case .feature(var end):
            guard let along = seed.direction else { return }
            let across = Vector2(-along.y, along.x)
            end.hint += along * ((delta.x * along.x + delta.y * along.y) / seed.scale)
            datum.distance += delta.x * across.x + delta.y * across.y
            datum.attachment = .feature(end)
        case .dimension:
            guard let tips = seed.tips, tips.count == 2 else {
                datum.distance = Swift.max(0, datum.distance - delta.y)
                return
            }
            func outward(_ end: Int) -> Vector2 {
                let way = tips[end] - tips[1 - end]
                return way.length > 1e-12 ? way * (1 / way.length) : Vector2(1, 0)
            }
            let end = Swift.min(Swift.max(datum.dimensionEnd, 0), 1)
            let centre = tips[end] + outward(end) * Swift.abs(datum.distance) + delta
            let nearer = (tips[1] - centre).length < (tips[0] - centre).length ? 1 : 0
            let from = centre - tips[nearer]
            datum.dimensionEnd = nearer
            datum.distance = Swift.max(0, from.x * outward(nearer).x + from.y * outward(nearer).y)
        }
    }

    private static func placement(
        _ placement: CreatorDrawing.DimensionPlacement, of kind: DrawingDimensionKind, seed: AnnotationSeed, by delta: Vector2
    ) -> CreatorDrawing.DimensionPlacement {
        switch kind {
        case .linear, .baseline, .chain, .ordinate:
            guard let d = seed.direction else { return placement }
            var result = placement
            result.offset += delta.x * -d.y + delta.y * d.x
            let along = delta.x * d.x + delta.y * d.y
            var isOrdinate = false
            if case .ordinate = kind { isOrdinate = true }
            if seed.onLabel, !isOrdinate, abs(along) > 1e-12 {
                let automatic = seed.feetMiddle.map { (seed.handle - $0).x * d.x + (seed.handle - $0).y * d.y } ?? 0
                result.textShift = (placement.textShift ?? automatic) + along
            }
            return result
        case .radius, .diameter, .chamfer, .angle:
            return radial(placement, seed: seed, by: delta, isAngle: kind == .angle)
        }
    }

    /// A radial, chamfer, hole or angle annotation follows the pointer: its angle is the direction from the centre and its offset
    /// how far out the pointer is (an angle's offset is the arc's radius).
    private static func radial(
        _ placement: CreatorDrawing.DimensionPlacement, seed: AnnotationSeed, by delta: Vector2, isAngle: Bool = false
    ) -> CreatorDrawing.DimensionPlacement {
        guard let centre = seed.anchor else { return placement }
        let reach = seed.handle + delta - centre
        guard reach.length > 1e-9 else { return placement }
        var result = placement
        result.angle = atan2(reach.y, reach.x)
        result.offset = isAngle ? reach.length : Swift.max(0, reach.length - seed.radius)
        return result
    }

    /// The undo step a move is named after (plan R19).
    func moveName(roots: [ViewID], seeds: [AnnotationSeed], in sheet: DrawingSheet) -> String {
        if !roots.isEmpty || seeds.isEmpty { return DrawingStepName.moveView }
        let kinds = seeds.compactMap { sheet.annotation($0.id)?.kind }
        return Self.groupName(of: kinds, names: .moving)
    }

    /// The names one kind of annotation takes for a step; a mix takes `mixed`.
    struct GroupNames {
        var dimension: String
        var note: String
        var symbol: String
        var balloon: String
        var partsList: String
        var revisionTable: String
        var mixed: String

        static let moving = GroupNames(
            dimension: DrawingStepName.moveDimension, note: DrawingStepName.moveNote, symbol: DrawingStepName.moveSymbol,
            balloon: DrawingStepName.moveBalloon, partsList: DrawingStepName.movePartsList,
            revisionTable: DrawingStepName.moveRevisionTable, mixed: DrawingStepName.moveAnnotations)
        static let deleting = GroupNames(
            dimension: DrawingStepName.deleteDimension, note: DrawingStepName.deleteNote, symbol: DrawingStepName.deleteSymbol,
            balloon: DrawingStepName.deleteBalloon, partsList: DrawingStepName.deletePartsList,
            revisionTable: DrawingStepName.deleteRevisionTable, mixed: DrawingStepName.deleteAnnotations)
    }

    /// One name for a set of annotations: all of one kind (dimensions and callouts, notes, symbols, balloons, parts lists or revision
    /// tables), or anything else.
    static func groupName(of kinds: [AnnotationKind], names: GroupNames) -> String {
        func name(of kind: AnnotationKind) -> String {
            switch kind {
            case .dimension, .holeCallout: names.dimension
            case .note: names.note
            case .datumFeature, .featureControl, .surfaceTexture: names.symbol
            case .balloon: names.balloon
            case .partsList: names.partsList
            case .revisionTable: names.revisionTable
            case .centreMark, .centreLine: names.mixed
            }
        }
        guard let first = kinds.first.map(name(of:)), kinds.allSatisfy({ name(of: $0) == first }) else { return names.mixed }
        return first
    }

    // MARK: Gestures

    /// Begins moving what is selected: the views and the annotations; `hit` is the annotation the press landed on.
    func beginMove(at point: Vector2, sheet: DrawingSheet, onLabelOf hit: AnnotationID?) {
        var found = seeds(for: selectedAnnotations, pressing: point)
        for index in found.indices where found[index].id != hit { found[index].onLabel = false }
        let roots = Self.roots(of: selection, in: sheet)
        guard !roots.isEmpty || !found.isEmpty else {
            gesture = nil
            return
        }
        dragSerial += 1
        gesture = .moving(
            MoveGesture(
                baseDocument: document, base: sheet, start: point, key: "drawing-move-\(dragSerial)", roots: roots, seeds: found))
    }

    func continueMove(_ move: MoveGesture, to point: Vector2) {
        guard let id = currentSheet else { return }
        let next = Self.movedSheet(move.base, roots: move.roots, seeds: move.seeds, by: point - move.start)
        let name = moveName(roots: move.roots, seeds: move.seeds, in: move.base)
        commit(name, key: move.key) { document in
            guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
            document.sheets[index] = next
        }
    }

    /// Esc or a dropped press during a move: the document goes back to where the gesture began and the host forgets its steps.
    func cancelMove(_ move: MoveGesture) {
        guard document != move.baseDocument else { return }
        document = move.baseDocument
        events.discarded(move.key)
    }

    // MARK: Deleting

    /// The step name for deleting `ids` and, when `withViews`, views.
    func deleteName(of ids: Set<AnnotationID>, withViews: Bool) -> String {
        if withViews { return DrawingStepName.deleteView }
        let kinds = (sheet?.annotations ?? []).filter { ids.contains($0.id) }.map(\.kind)
        return Self.groupName(of: kinds, names: .deleting)
    }
}
