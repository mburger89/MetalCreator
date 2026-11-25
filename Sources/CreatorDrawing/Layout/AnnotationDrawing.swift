import CreatorGeometry
import Foundation

/// A line of lettering placed by the layout: `origin` is the baseline's left end, `angle` radians counter-clockwise.
public struct PlacedText: Hashable, Sendable {
    public var run: TextRun
    public var original: String
    public var origin: Vector2
    public var height: Double
    public var angle: Double

    public init(run: TextRun, original: String, origin: Vector2, height: Double, angle: Double) {
        self.run = run
        self.original = original
        self.origin = origin
        self.height = height
        self.angle = angle
    }
}

/// What one annotation draws, in sheet millimetres: thin solid segments, basic frames, arrowheads and lettering.
public struct AnnotationDrawing: Hashable, Sendable {
    public var segments: [SheetSegment]
    public var boxes: [[Vector2]]
    public var fills: [[Vector2]]
    public var texts: [PlacedText]
    /// The middle of the first label, `nil` with no label.
    public var textCenter: Vector2?
    /// The smallest rectangle holding everything drawn.
    public var frame: Rect2D

    public init(
        segments: [SheetSegment] = [], boxes: [[Vector2]] = [], fills: [[Vector2]] = [], texts: [PlacedText] = [],
        textCenter: Vector2? = nil, frame: Rect2D = Rect2D(min: .zero, max: .zero)
    ) {
        self.segments = segments
        self.boxes = boxes
        self.fills = fills
        self.texts = texts
        self.textCenter = textCenter
        self.frame = frame
    }
}

extension PlacedText {
    /// The corners of the text's box (its cap height by its width), for bounds.
    var corners: [Vector2] {
        let u = Vector2(cos(angle), sin(angle)), up = Vector2(-u.y, u.x)
        return [origin, origin + u * run.width, origin + u * run.width + up * height, origin + up * height]
    }
}

extension AnnotationDrawing {
    /// Sets `frame` from what is drawn.
    mutating func fitFrame() {
        var points: [Vector2] = []
        for segment in segments {
            let bounds = segment.bounds
            points += [bounds.min, bounds.max]
        }
        for box in boxes { points += box }
        for fill in fills { points += fill }
        for text in texts { points += text.corners }
        frame = Rect2D(points: points) ?? Rect2D(min: .zero, max: .zero)
    }
}
