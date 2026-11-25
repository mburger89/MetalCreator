import CreatorGeometry

/// How a stroke is dashed.
public enum StrokePattern: Hashable, Sendable {
    case solid
    case hidden
}

/// The layers a drawing's strokes and texts are written on (the DXF's layer names).
public enum DrawingLayer: String, CaseIterable, Sendable {
    case visible = "VISIBLE"
    case hidden = "HIDDEN"
    case tangent = "TANGENT"
    case center = "CENTER"
    case dimension = "DIMENSION"
    case text = "TEXT"
    case hatch = "HATCH"
    case frame = "FRAME"
}

/// A connected run of segments drawn with one weight and pattern, in sheet millimetres.
public struct SheetStroke: Hashable, Sendable {
    public var segments: [SheetSegment]
    public var width: Double
    public var pattern: StrokePattern
    public var layer: DrawingLayer
    public var view: ViewID?

    public init(
        segments: [SheetSegment], width: Double, pattern: StrokePattern = .solid, layer: DrawingLayer, view: ViewID? = nil
    ) {
        self.segments = segments
        self.width = width
        self.pattern = pattern
        self.layer = layer
        self.view = view
    }

    /// The bounds of all the stroke's segments (a zero rectangle when it has none).
    public var bounds: Rect2D {
        let all = segments.map(\.bounds)
        guard let first = all.first else { return Rect2D(min: .zero, max: .zero) }
        return all.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// A line of lettering placed on the sheet: `origin` is the baseline's left end.
public struct SheetText: Hashable, Sendable {
    public var run: TextRun
    /// The text as typed, before any replacement.
    public var original: String
    public var origin: Vector2
    public var height: Double
    public var layer: DrawingLayer
    public var view: ViewID?
    /// A sentence about the view (its problem or a warning), drawn on screen in the warning colour and never written to a file.
    public var isNotice: Bool

    public init(
        run: TextRun, original: String, origin: Vector2, height: Double, layer: DrawingLayer = .text, view: ViewID? = nil,
        isNotice: Bool = false
    ) {
        self.run = run
        self.original = original
        self.origin = origin
        self.height = height
        self.layer = layer
        self.view = view
        self.isNotice = isNotice
    }
}

/// Everything drawn on one sheet, in sheet millimetres with the origin at the bottom left.
public struct SheetPicture: Hashable, Sendable {
    public var size: Vector2
    public var strokes: [SheetStroke]
    public var texts: [SheetText]
    /// Each view's frame on the sheet. Read by lookup only, never iterated into output.
    public var viewFrames: [ViewID: Rect2D]

    public init(size: Vector2, strokes: [SheetStroke] = [], texts: [SheetText] = [], viewFrames: [ViewID: Rect2D] = [:]) {
        self.size = size
        self.strokes = strokes
        self.texts = texts
        self.viewFrames = viewFrames
    }

    /// Adds another picture's strokes and texts after this one's.
    public mutating func append(_ other: SheetPicture) {
        strokes += other.strokes
        texts += other.texts
        for (id, frame) in other.viewFrames.sorted(by: { $0.key < $1.key }) { viewFrames[id] = frame }
    }
}
