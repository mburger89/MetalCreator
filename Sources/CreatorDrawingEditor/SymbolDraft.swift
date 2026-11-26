import CreatorDrawing
import CreatorGeometry

/// What a symbol tool has been pointed at (plan R15): a line of the view, held with the hint the foot is found from, or a
/// dimension (or hole callout) of the same view.
public enum SymbolTarget: Hashable, Sendable {
    case feature(PickedAnchor, hint: Vector2)
    case dimension(AnnotationID)
}

/// A datum, frame or surface symbol that has its target and waits for the placing click. View state: never saved.
public struct SymbolDraft: Hashable, Sendable {
    public var tool: DrawingTool
    public var view: ViewID
    public var target: SymbolTarget

    public init(tool: DrawingTool, view: ViewID, target: SymbolTarget) {
        self.tool = tool
        self.view = view
        self.target = target
    }

    /// The undo step the placed symbol is.
    var stepName: String {
        switch tool {
        case .datum: DrawingStepName.addDatum
        case .featureControlFrame: DrawingStepName.addFeatureControlFrame
        default: DrawingStepName.addSurfaceSymbol
        }
    }
}

extension DrawingTool {
    /// The symbol the tool makes, or `nil` for any other tool.
    var symbolKind: SymbolKind? {
        switch self {
        case .datum: .datum
        case .featureControlFrame: .frame
        case .surfaceFinish: .surface
        default: nil
        }
    }
}

/// Where a symbol goes for a placing click (plan R15), in sheet millimetres: pure arithmetic over what the composer drew.
enum SymbolPlacing {
    /// What a dimension drew that a symbol hangs on: its first label's rectangle, its dimension line's tips when it has one, and
    /// the lowest y the symbols already on it reach.
    struct Host {
        var labelRect: Rect2D
        var tips: [Vector2]?
        var stackBottom: Double?
        var gap: Double
    }

    /// The side and length of a datum symbol on a line: the click's component along the line's normal.
    static func datumDistance(foot: Vector2, along: Vector2, click: Vector2) -> Double {
        let normal = Vector2(-along.y, along.x)
        return (click - foot).x * normal.x + (click - foot).y * normal.y
    }

    /// The end of the dimension line a datum stands on and how far out (never negative) for a click at `click`; on a dimension
    /// with no line, end 0 and how far under its label.
    static func datumOnHost(_ host: Host, click: Vector2) -> (end: Int, distance: Double) {
        if let tips = host.tips, tips.count == 2 {
            let end = (tips[1] - click).length < (tips[0] - click).length ? 1 : 0
            let way = tips[end] - tips[1 - end]
            guard way.length > 1e-12 else { return (end, 0) }
            let outward = way * (1 / way.length)
            let delta = click - tips[end]
            return (end, Swift.max(0, delta.x * outward.x + delta.y * outward.y))
        }
        return (0, Swift.max(0, hangingTop(host) - click.y))
    }

    /// Where a hanging datum's triangle starts, under the label and any symbols stacked there.
    static func hangingTop(_ host: Host) -> Double {
        host.stackBottom.map { $0 - host.gap } ?? host.labelRect.min.y
    }

    /// The frame's offset from its default top left on a dimension: under the label and the symbols stacked there.
    static func frameOffset(on host: Host, click: Vector2) -> Vector2 {
        let defaultTopLeft = Vector2(host.labelRect.min.x, (host.stackBottom ?? host.labelRect.min.y) - host.gap)
        return click - defaultTopLeft
    }

    /// Whether a surface symbol placed by `click` stands on its line: the line is horizontal on the sheet and the click lies above
    /// it within `snap` (plan R6, R15).
    static func standsOn(foot: Vector2, along: Vector2, click: Vector2, snap: Double) -> Bool {
        guard Swift.abs(along.y) <= 1e-9 else { return false }
        let rise = click.y - foot.y
        return rise >= 0 && rise <= snap
    }
}
