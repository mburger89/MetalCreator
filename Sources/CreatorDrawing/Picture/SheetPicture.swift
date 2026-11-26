import CreatorGeometry
import CreatorKernel

/// How a stroke is dashed.
public enum StrokePattern: Hashable, Sendable {
    case solid
    case hidden
    /// Chain line: long dash, gap, short dash, gap (plan R13), by the page's standard.
    case centre
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
    public var annotation: AnnotationID?
    public var isLost: Bool
    /// The projected line this stroke draws, when it draws one.
    public var source: ProjectionSource?
    /// The derived view whose cutting line, arrow or detail circle this stroke is (DR-3 R6), `nil` for everything else.
    public var mark: ViewID?

    public init(
        segments: [SheetSegment], width: Double, pattern: StrokePattern = .solid, layer: DrawingLayer, view: ViewID? = nil,
        annotation: AnnotationID? = nil, isLost: Bool = false, source: ProjectionSource? = nil, mark: ViewID? = nil
    ) {
        self.mark = mark
        self.annotation = annotation
        self.isLost = isLost
        self.source = source
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
    /// Radians about `origin`, counter-clockwise.
    public var angle: Double
    public var annotation: AnnotationID?
    public var isLost: Bool
    /// The derived view whose letter this is (DR-3 R6), `nil` for everything else.
    public var mark: ViewID?

    public init(
        run: TextRun, original: String, origin: Vector2, height: Double, layer: DrawingLayer = .text, view: ViewID? = nil,
        isNotice: Bool = false, angle: Double = 0, annotation: AnnotationID? = nil, isLost: Bool = false, mark: ViewID? = nil
    ) {
        self.mark = mark
        self.angle = angle
        self.annotation = annotation
        self.isLost = isLost
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
    /// Closed filled polygons: arrowheads.
    public var fills: [SheetFill]
    /// The page's standard, so the writers dash by its style.
    public var standard: DrawingStandard
    /// What each annotation of the sheet turned out to be (plan R15). Read by lookup only, never iterated into output.
    public var annotationReports: [AnnotationID: AnnotationReport]
    /// The annotations that lost what they were attached to, in the sheet's order.
    public var lostAnnotations: [AnnotationID]
    /// The annotations whose report has warnings, in the sheet's order (plan R11).
    public var checkedAnnotations: [AnnotationID]
    /// Each view's frame grown to hold its annotations and centre marks. Read by lookup only.
    public var viewExtents: [ViewID: Rect2D]

    public init(
        size: Vector2, strokes: [SheetStroke] = [], texts: [SheetText] = [], viewFrames: [ViewID: Rect2D] = [:],
        fills: [SheetFill] = [], standard: DrawingStandard = .iso, annotationReports: [AnnotationID: AnnotationReport] = [:],
        lostAnnotations: [AnnotationID] = [], viewExtents: [ViewID: Rect2D] = [:], checkedAnnotations: [AnnotationID] = []
    ) {
        self.checkedAnnotations = checkedAnnotations
        self.annotationReports = annotationReports
        self.lostAnnotations = lostAnnotations
        self.viewExtents = viewExtents
        self.fills = fills
        self.standard = standard
        self.size = size
        self.strokes = strokes
        self.texts = texts
        self.viewFrames = viewFrames
    }

    /// Adds another picture's strokes and texts after this one's.
    public mutating func append(_ other: SheetPicture) {
        strokes += other.strokes
        texts += other.texts
        fills += other.fills
        for (id, frame) in other.viewFrames.sorted(by: { $0.key < $1.key }) { viewFrames[id] = frame }
    }
}
