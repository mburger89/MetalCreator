import CreatorDrawing

/// The sheet picture cut into the buckets the canvas draws, built once per compose (drawings speed R3).
///
/// A pan filters nothing, and a layer compares its bucket's `revision` where it compared whole arrays. A bucket keeps its
/// previous revision when its contents are `==` to the previous bucket's and takes the next one otherwise, so a dimension
/// drag changes only the annotations bucket of its view. The buckets:
/// - `frame`: everything with no view (border, title block, free notes), as `SheetFrameLayer` draws it;
/// - `linework[view]`: the view's projected lines, hatching, marks and the like (no annotation, no notice);
/// - `annotations[view]`: the view's annotations and its notices, which draw over the linework.
///
/// `SheetPicture.strokes` keeps its flat order for the hover indices; the buckets are copies, not a replacement.
struct SheetLayers: Sendable {
    struct Bucket: Sendable {
        var strokes: [SheetStroke] = []
        var fills: [SheetFill] = []
        var texts: [SheetText] = []
        /// 0 for an empty bucket that never held anything; unique across the buckets of one `SheetLayers` lineage otherwise.
        var revision = 0

        static let empty = Bucket()

        var isEmpty: Bool { strokes.isEmpty && fills.isEmpty && texts.isEmpty }

        func sameContent(as other: Bucket) -> Bool {
            strokes == other.strokes && fills == other.fills && texts == other.texts
        }
    }

    /// An element with its index in the flat picture, so a selection keeps the picture's order.
    struct Indexed<Element: Sendable>: Sendable {
        let index: Int
        let element: Element
    }

    struct Items: Sendable {
        var strokes: [Indexed<SheetStroke>] = []
        var fills: [Indexed<SheetFill>] = []
        var texts: [Indexed<SheetText>] = []
    }

    private(set) var frame = Bucket.empty
    private(set) var linework: [ViewID: Bucket] = [:]
    private(set) var annotations: [ViewID: Bucket] = [:]
    private var byAnnotation: [AnnotationID: Items] = [:]
    private var byMark: [ViewID: Items] = [:]
    private var lastRevision = 0

    /// A view's linework bucket; empty when it has none.
    func linework(of view: ViewID) -> Bucket { linework[view] ?? .empty }
    /// A view's annotations bucket; empty when it has none.
    func annotations(of view: ViewID) -> Bucket { annotations[view] ?? .empty }

    static func built(from picture: SheetPicture, previous: SheetLayers?) -> SheetLayers {
        var layers = SheetLayers()
        var frame = Bucket()
        var linework: [ViewID: Bucket] = [:]
        var annotations: [ViewID: Bucket] = [:]
        // The three element kinds classify alike: no view is the frame, an annotation or a notice is an annotation, the rest linework.
        func place(
            view: ViewID?, annotation: AnnotationID?, mark: ViewID?, isNotice: Bool,
            into add: (inout Bucket) -> Void, item: (inout Items) -> Void
        ) {
            if let annotation { item(&layers.byAnnotation[annotation, default: Items()]) }
            if let mark { item(&layers.byMark[mark, default: Items()]) }
            guard let view else { return add(&frame) }
            if annotation != nil || isNotice {
                add(&annotations[view, default: Bucket()])
            } else {
                add(&linework[view, default: Bucket()])
            }
        }
        for (index, stroke) in picture.strokes.enumerated() {
            place(
                view: stroke.view, annotation: stroke.annotation, mark: stroke.mark, isNotice: false,
                into: { $0.strokes.append(stroke) }, item: { $0.strokes.append(Indexed(index: index, element: stroke)) })
        }
        for (index, fill) in picture.fills.enumerated() {
            place(
                view: fill.view, annotation: fill.annotation, mark: fill.mark, isNotice: false,
                into: { $0.fills.append(fill) }, item: { $0.fills.append(Indexed(index: index, element: fill)) })
        }
        for (index, text) in picture.texts.enumerated() {
            place(
                view: text.view, annotation: text.annotation, mark: text.mark, isNotice: text.isNotice,
                into: { $0.texts.append(text) }, item: { $0.texts.append(Indexed(index: index, element: text)) })
        }
        var next = previous?.lastRevision ?? 0
        func numbered(_ bucket: Bucket, after old: Bucket) -> Bucket {
            var bucket = bucket
            if bucket.sameContent(as: old) {
                bucket.revision = old.revision
            } else {
                next += 1
                bucket.revision = next
            }
            return bucket
        }
        layers.frame = numbered(frame, after: previous?.frame ?? .empty)
        layers.linework = linework.reduce(into: [:]) { $0[$1.key] = numbered($1.value, after: previous?.linework(of: $1.key) ?? .empty) }
        layers.annotations = annotations.reduce(into: [:]) {
            $0[$1.key] = numbered($1.value, after: previous?.annotations(of: $1.key) ?? .empty)
        }
        layers.lastRevision = next
        return layers
    }

    /// What the selection layer draws of the selected annotations and the selected derived views' marks, in the picture's order
    /// within each part (annotations first, then marks), as filtering the flat picture would give.
    func selection(
        annotations chosen: Set<AnnotationID>, marks: Set<ViewID>
    ) -> (strokes: [SheetStroke], fills: [SheetFill], texts: [SheetText]) {
        let parts = [chosen.compactMap { byAnnotation[$0] }, marks.compactMap { byMark[$0] }]
        var strokes: [SheetStroke] = []
        var fills: [SheetFill] = []
        var texts: [SheetText] = []
        for part in parts {
            strokes += part.flatMap(\.strokes).sorted { $0.index < $1.index }.map(\.element)
            fills += part.flatMap(\.fills).sorted { $0.index < $1.index }.map(\.element)
            texts += part.flatMap(\.texts).sorted { $0.index < $1.index }.map(\.element)
        }
        return (strokes, fills, texts)
    }
}
