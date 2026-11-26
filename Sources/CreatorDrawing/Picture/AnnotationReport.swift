import CreatorGeometry

/// Whether an annotation still holds what it measures (plan R15).
public enum AnnotationStatus: Hashable, Sendable {
    case held
    case lost(LostReason)
}

/// Whether one anchor of an annotation still resolves.
public enum AnchorStatus: Hashable, Sendable {
    case held
    case lost(LostReason)
}

/// What composing one annotation found: its state, its anchors', the figure and values it holds now and the text it shows.
public struct AnnotationReport: Hashable, Sendable {
    public var status: AnnotationStatus
    /// One per anchor in the annotation's order (a note's leader targets); empty when the view has no part (plan R25).
    public var anchors: [AnchorStatus]
    /// The newest values, when held.
    public var current: LastGood?
    /// Plain text: the first label, "25?" when lost, "?" with no value to show.
    public var label: String
    /// What was drawn, in sheet millimetres (a zero rectangle when nothing was).
    public var frame: Rect2D
    public var textCenter: Vector2?

    public init(
        status: AnnotationStatus, anchors: [AnchorStatus] = [], current: LastGood? = nil, label: String = "",
        frame: Rect2D = Rect2D(min: .zero, max: .zero), textCenter: Vector2? = nil
    ) {
        self.status = status
        self.anchors = anchors
        self.current = current
        self.label = label
        self.frame = frame
        self.textCenter = textCenter
    }

    /// The index of the first anchor that is lost.
    public var firstLostAnchor: Int? {
        anchors.firstIndex { if case .lost = $0 { true } else { false } }
    }

    public var isLost: Bool {
        if case .lost = status { true } else { false }
    }
}
