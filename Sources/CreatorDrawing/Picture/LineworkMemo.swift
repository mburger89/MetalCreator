import CreatorGeometry

/// Each view's mapped linework, kept between composes so a drag that moves a dimension re-maps no view (speed plan R1, R2).
///
/// An entry holds the strokes, the hatch and the frame of one view with the inputs they were mapped from: the `DrawingView`,
/// its `ViewContent`, the centre and scale it was placed at, the standard and the sheet's size (the hatch spacing reads that).
/// Values compare with `==`, so an unchanged `ViewContent` compares by shared storage. A compose through a memo returns the
/// picture a compose without one returns.
public struct LineworkMemo: Sendable {
    private struct Key: Equatable, Sendable {
        var view: DrawingView
        var content: ViewContent
        var center: Vector2
        var scale: Double
        var standard: DrawingStandard
        var size: SheetSize
    }

    private struct Entry: Sendable {
        var key: Key
        var strokes: [SheetStroke]
        var frame: Rect2D
    }

    private var entries: [ViewID: Entry] = [:]
    /// The views the last compose mapped.
    public private(set) var mapped = 0
    /// The views the last compose took from the memo.
    public private(set) var reused = 0

    public init() {}

    mutating func begin() {
        mapped = 0
        reused = 0
    }

    /// The strokes (linework, then hatch) and frame of a view with a projection, mapped only when an input changed.
    mutating func linework(
        of view: DrawingView, content: ViewContent, center: Vector2, scale: Double, sheet: DrawingSheet, style: DrawingStyle
    ) -> (strokes: [SheetStroke], frame: Rect2D) {
        let key = Key(
            view: view, content: content, center: center, scale: scale, standard: style.standard, size: sheet.size)
        if let entry = entries[view.id], entry.key == key {
            reused += 1
            return (entry.strokes, entry.frame)
        }
        mapped += 1
        let strokes =
            ViewLinework.strokes(for: content, view: view, center: center, scale: scale, style: style)
            + SheetComposer.hatch(for: view, content: content, center: center, scale: scale, sheet: sheet, style: style)
        let frame = ViewLinework.frame(for: content, center: center, scale: scale) ?? Rect2D(min: center, max: center)
        entries[view.id] = Entry(key: key, strokes: strokes, frame: frame)
        return (strokes, frame)
    }

    /// Drops the entries of views that are not in `views`.
    mutating func keep(_ views: [DrawingView]) {
        let live = Set(views.map(\.id))
        for id in entries.keys where !live.contains(id) { entries[id] = nil }
    }
}
