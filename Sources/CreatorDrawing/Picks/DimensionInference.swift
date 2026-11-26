import CreatorGeometry
import CreatorKernel
import Foundation

/// The dimension tools whose picks are inferred into a kind (plan R6).
public enum DimensionTool: Sendable {
    case smart, baseline, chain, ordinate, chamfer
}

/// What picks make: the kind and its anchors.
private typealias Made = (kind: DrawingDimensionKind, anchors: [AnchorTarget])

/// What a dimension makes of the things picked for it (plan R6) and where its placing click puts it (R7).
public enum DimensionInference {
    public static let secondPickSentence = "Pick a second point, a line or a circle to measure to."
    public static let seriesNeedsSentence = "A baseline or chain dimension needs at least three points or lines."
    public static let ordinateNeedsSentence = "An ordinate dimension needs an origin and at least one more point."
    public static let crossSentence = "A line in a baseline, chain or ordinate dimension must cross the direction it measures."
    public static let chamferSentence = "A chamfer takes two lines: the chamfer's edge, then a reference edge."
    public static let tooManySentence = "A dimension of this kind takes one or two picks."
    public static let depthSentence = "These points aren't at the same depth in this view, so the length would be foreshortened."
    public static let outlineAlignedSentence = "An outline can't take an aligned dimension."

    /// Whether a click on empty space may place a dimension now (a line also takes a second pick).
    public static func isComplete(_ picks: [PickedAnchor], tool: DimensionTool) -> Bool {
        switch tool {
        case .smart:
            switch picks.count {
            case 1: if case .point = picks[0].shape { false } else { true }
            case 2: true
            default: false
            }
        case .baseline, .chain: picks.count >= 3
        case .ordinate: picks.count >= 2
        case .chamfer: picks.count == 2 && picks.allSatisfy { if case .line = $0.shape { true } else { false } }
        }
    }

    /// The kind and anchors the picks make, with `placing` (a model-plane point) deciding a direction where the picks leave it
    /// open, and `aligned` (⇧) asking for the distance along the measure itself.
    public static func make(
        tool: DimensionTool, picks: [PickedAnchor], placing: Vector2, aligned: Bool
    ) -> Result<(kind: DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal> {
        switch tool {
        case .smart: return smart(picks, placing: placing, aligned: aligned).flatMap(refusingAlignedMismatches(picks))
        case .baseline: return series(picks, placing: placing) { .baseline($0) }
        case .chain: return series(picks, placing: placing) { .chain($0) }
        case .ordinate: return ordinate(picks, placing: placing)
        case .chamfer: return chamfer(picks)
        }
    }

    /// R8: an aligned dimension is refused at the pick when it could only be born lost: to an outline (which has no one point), or
    /// between two points that lie at different depths along the view direction (the length would be foreshortened).
    private static func refusingAlignedMismatches(
        _ picks: [PickedAnchor]
    ) -> (Made) -> Result<Made, DrawingRefusal> {
        { made in
            guard made.kind == .linear(.aligned) else { return .success(made) }
            let outline = picks.contains { if case .outline = $0.target.unwrapped { true } else { false } }
            if outline { return .failure(DrawingRefusal(sentence: outlineAlignedSentence)) }
            if picks.count == 2, case .point(let a) = picks[0].shape, case .point(let b) = picks[1].shape,
                let first = picks[0].depth, let second = picks[1].depth {
                let apart = abs(first - second)
                if apart > 1e-9 * (b - a).length.hypotenuse(with: apart) { return .failure(DrawingRefusal(sentence: depthSentence)) }
            }
            return .success(made)
        }
    }

    // MARK: Features

    /// What a pick contributes: a point, or a line (model plane).
    enum Feature {
        case point(Vector2)
        case line(Vector2, Vector2)
    }

    static func feature(_ pick: PickedAnchor) -> Feature {
        switch pick.shape {
        case .line(let a, let b): return .line(a, b)
        case .point(let p): return .point(p)
        case .circle(let center, _, _): return .point(center)
        case .cylinder(let axisPoint, let direction, let radius):
            let turned = Vector2(-direction.y, direction.x)
            var sign = 1.0
            if case .outline(_, let side) = pick.target.unwrapped { sign = dot(turned, side) >= 0 ? 1 : -1 }
            return .point(axisPoint + turned * (radius * sign))
        }
    }

    /// The anchor a feature is stored as: a circle gives its centre.
    static func target(_ pick: PickedAnchor) -> AnchorTarget {
        if case .circle = pick.shape, case .edge(let edge) = pick.target.unwrapped { return rewrapped(.centre(edge), like: pick.target) }
        return pick.target
    }

    /// `target` inside the same part as `original` (an assembly view's picks are wrapped with their part), or as it is.
    private static func rewrapped(_ target: AnchorTarget, like original: AnchorTarget) -> AnchorTarget {
        original.part.map { .onPart($0, target) } ?? target
    }

    static func points(of picks: [PickedAnchor]) -> [Vector2] {
        picks.flatMap { pick -> [Vector2] in
            switch feature(pick) {
            case .point(let p): [p]
            case .line(let a, let b): [a, b]
            }
        }
    }

    static func dot(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.x + a.y * b.y }

    static func unit(_ v: Vector2) -> Vector2? {
        let length = v.length
        return length > 1e-12 ? v * (1 / length) : nil
    }

    static func turned(_ v: Vector2) -> Vector2 { Vector2(-v.y, v.x) }

    /// Horizontal when the click lies outside the picks' span at least as far above or below as to the side (plan R6).
    static func direction(of placing: Vector2, picks: [PickedAnchor]) -> LinearDirection {
        let all = points(of: picks)
        guard let box = Rect2D(points: all) else { return .horizontal }
        let outsideX = max(0, box.min.x - placing.x, placing.x - box.max.x)
        let outsideY = max(0, box.min.y - placing.y, placing.y - box.max.y)
        return outsideY >= outsideX ? .horizontal : .vertical
    }

    /// Axis-aligned lines run along x or y exactly; the answer is the axis they run along.
    static func axis(of a: Vector2, _ b: Vector2) -> LinearDirection? {
        let along = b - a
        if abs(along.y) <= 1e-9 * along.length { return .horizontal }
        if abs(along.x) <= 1e-9 * along.length { return .vertical }
        return nil
    }

    // MARK: Smart

    private static func smart(
        _ picks: [PickedAnchor], placing: Vector2, aligned: Bool
    ) -> Result<(kind: DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal> {
        switch picks.count {
        case 1: return single(picks[0])
        case 2: return pair(picks[0], picks[1], placing: placing, aligned: aligned)
        default: return .failure(DrawingRefusal(sentence: tooManySentence))
        }
    }

    private static func single(_ pick: PickedAnchor) -> Result<(kind: DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal> {
        switch pick.shape {
        case .line(let a, let b):
            let direction = axis(of: a, b) ?? .aligned
            return .success((.linear(direction), [pick.target]))
        case .circle(_, _, let isFull): return .success((isFull ? .diameter : .radius, [pick.target]))
        case .cylinder:
            guard case .outline(let face, _) = pick.target.unwrapped else { return .success((.diameter, [pick.target])) }
            return .success((.diameter, [rewrapped(.axis(face), like: pick.target)]))
        case .point: return .failure(DrawingRefusal(sentence: secondPickSentence))
        }
    }

    private static func pair(
        _ first: PickedAnchor, _ second: PickedAnchor, placing: Vector2, aligned: Bool
    ) -> Result<(kind: DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal> {
        let anchors = [target(first), target(second)]
        switch (feature(first), feature(second)) {
        case (.point, .point):
            let direction: LinearDirection = aligned ? .aligned : direction(of: placing, picks: [first, second])
            return .success((.linear(direction), anchors))
        case (.point, .line(let a, let b)), (.line(let a, let b), .point):
            let across = axis(of: a, b).map { $0 == .horizontal ? LinearDirection.vertical : .horizontal }
            return .success((.linear(aligned ? .aligned : across ?? .aligned), anchors))
        case (.line(let a, let b), .line(let c, let d)):
            guard let u = unit(b - a), let v = unit(d - c) else { return .failure(DrawingRefusal(sentence: tooManySentence)) }
            guard abs(u.x * v.y - u.y * v.x) <= 1e-9 else { return .success((.angle, anchors)) }
            let across = axis(of: a, b).map { $0 == .horizontal ? LinearDirection.vertical : .horizontal }
            return .success((.linear(aligned ? .aligned : across ?? .aligned), anchors))
        }
    }

    // MARK: Series, ordinate and chamfer

    private static func series(
        _ picks: [PickedAnchor], placing: Vector2, kind: (LinearDirection) -> DrawingDimensionKind
    ) -> Result<(kind: DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal> {
        guard picks.count >= 3 else { return .failure(DrawingRefusal(sentence: seriesNeedsSentence)) }
        let direction = direction(of: placing, picks: picks)
        if let refused = crossing(picks, direction) { return .failure(refused) }
        return .success((kind(direction), picks.map(target)))
    }

    private static func ordinate(
        _ picks: [PickedAnchor], placing: Vector2
    ) -> Result<(kind: DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal> {
        guard picks.count >= 2 else { return .failure(DrawingRefusal(sentence: ordinateNeedsSentence)) }
        let direction = direction(of: placing, picks: picks)
        if let refused = crossing(picks, direction) { return .failure(refused) }
        return .success((.ordinate(direction == .vertical ? .vertical : .horizontal), picks.map(target)))
    }

    /// A line must run square to the direction it measures: along it, or slanted, it has no one end to measure to.
    private static func crossing(_ picks: [PickedAnchor], _ direction: LinearDirection) -> DrawingRefusal? {
        for pick in picks {
            guard case .line(let a, let b) = feature(pick) else { continue }
            let across: LinearDirection = direction == .horizontal ? .vertical : .horizontal
            if axis(of: a, b) != across { return DrawingRefusal(sentence: crossSentence) }
        }
        return nil
    }

    private static func chamfer(_ picks: [PickedAnchor]) -> Result<(kind: DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal> {
        guard isComplete(picks, tool: .chamfer) else { return .failure(DrawingRefusal(sentence: chamferSentence)) }
        return .success((.chamfer, picks.map(\.target)))
    }
}

private extension Double {
    func hypotenuse(with other: Double) -> Double { (self * self + other * other).squareRoot() }
}
