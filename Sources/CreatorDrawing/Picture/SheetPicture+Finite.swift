import CreatorGeometry

extension SheetSegment {
    /// True when every coordinate, radius and angle is a number (drawings minors R3).
    var isFinite: Bool {
        switch self {
        case let .line(a, b): a.isFinite && b.isFinite
        case let .polyline(points): points.allSatisfy(\.isFinite)
        case let .arc(center, radius, start, sweep): center.isFinite && radius.isFinite && start.isFinite && sweep.isFinite
        case let .ellipse(center, axis, major, minor, start, sweep):
            center.isFinite && axis.isFinite && major.isFinite && minor.isFinite && start.isFinite && sweep.isFinite
        }
    }
}

private extension Vector2 {
    var isFinite: Bool { x.isFinite && y.isFinite }
}

extension SheetPicture {
    /// The sentence a file's warnings carry once when some item had a coordinate that isn't a number (drawings minors R3).
    public static let notANumberSentence = "Some lines couldn't be drawn because a measurement isn't a number."

    /// How many strokes, fills and texts have a coordinate, width or height that isn't a number.
    public var nonFiniteCount: Int {
        strokes.filter { !$0.isFinite }.count + fills.filter { !$0.isFinite }.count + texts.filter { !$0.isFinite }.count
    }

    /// The picture without those items: what every writer writes, so a NaN never reaches a file (drawings minors R3).
    public var finite: SheetPicture {
        guard nonFiniteCount > 0 else { return self }
        var page = self
        page.strokes = strokes.filter(\.isFinite)
        page.fills = fills.filter(\.isFinite)
        page.texts = texts.filter(\.isFinite)
        return page
    }

    /// What a file says about the picture itself: the views with nothing drawn (R2), then, once, the items left out (R3).
    /// `view` limits the first to one view.
    public func fileWarnings(view: ViewID? = nil) -> [String] {
        var sentences = emptyViews.filter { view == nil || $0.id == view }.map(\.sentence)
        if nonFiniteCount > 0 { sentences.append(Self.notANumberSentence) }
        return sentences
    }
}

extension SheetStroke {
    var isFinite: Bool { width.isFinite && segments.allSatisfy(\.isFinite) }
}

extension SheetFill {
    var isFinite: Bool { points.allSatisfy { $0.x.isFinite && $0.y.isFinite } }
}

extension SheetText {
    var isFinite: Bool { origin.x.isFinite && origin.y.isFinite && height.isFinite && angle.isFinite && run.width.isFinite }
}
