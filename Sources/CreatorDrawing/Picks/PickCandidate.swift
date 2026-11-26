import CreatorGeometry
import CreatorKernel

/// What a click on a view's linework found (plan R17), in sheet millimetres.
public enum PickCandidate: Hashable, Sendable {
    /// A line or circle edge, by the index of the stroke that drew it.
    case edge(EdgeID, stroke: Int)
    /// An end of a straight edge, where the click fell near it.
    case corner(EdgeID, at: Vector2)
    /// The centre of a full circle.
    case centre(EdgeID, at: Vector2)
    /// A cylinder's silhouette, by the index of the stroke that drew it.
    case outline(FaceID, stroke: Int)
}

extension DrawingPick {
    /// The sentence for a click on a free curve (plan R5).
    public static let freeCurveSentence = "This line is a free curve; dimensions attach to a part's edges."

    /// What lies under a click on `view`, in R17's order: a full circle's centre within `tolerance`, a straight line's end within it
    /// (a corner), then the nearest line. A free curve gives nothing (`refusal(at:in:view:tolerance:)` says why).
    public static func candidate(at point: Vector2, in picture: SheetPicture, view: ViewID, tolerance: Double) -> PickCandidate? {
        if let centre = centre(near: point, in: picture, view: view, tolerance: tolerance) { return centre }
        if let corner = corner(near: point, in: picture, view: view, tolerance: tolerance) { return corner }
        guard let index = SheetHitTest.line(near: point, in: picture, view: view, tolerance: tolerance),
              let source = picture.strokes[index].source else { return nil }
        switch source {
        case .edge(let id): return .edge(id, stroke: index)
        case .face(let id): return .outline(id, stroke: index)
        case .curve: return nil
        }
    }

    /// The sentence for a click that lands on a free curve, else nil.
    public static func refusal(at point: Vector2, in picture: SheetPicture, view: ViewID, tolerance: Double) -> DrawingRefusal? {
        if centre(near: point, in: picture, view: view, tolerance: tolerance) != nil
            || corner(near: point, in: picture, view: view, tolerance: tolerance) != nil {
            return nil
        }
        guard let index = SheetHitTest.line(near: point, in: picture, view: view, tolerance: tolerance),
              case .curve = picture.strokes[index].source else { return nil }
        return DrawingRefusal(sentence: freeCurveSentence)
    }

    /// Strokes of a view that are projected lines: no annotation's and no centre mark.
    private static func lines(of view: ViewID, in picture: SheetPicture) -> [(index: Int, stroke: SheetStroke)] {
        picture.strokes.enumerated().compactMap { index, stroke in
            stroke.view == view && stroke.annotation == nil && stroke.layer != .center ? (index, stroke) : nil
        }
    }

    private static func centre(near point: Vector2, in picture: SheetPicture, view: ViewID, tolerance: Double) -> PickCandidate? {
        var best: (candidate: PickCandidate, distance: Double)?
        for (_, stroke) in lines(of: view, in: picture) {
            guard case .edge(let id)? = stroke.source, stroke.segments.count == 1,
                  case .arc(let center, _, _, let sweep) = stroke.segments[0], abs(sweep) >= 2 * .pi - 1e-9 else { continue }
            let distance = (point - center).length
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (.centre(id, at: center), distance) }
        }
        return best?.candidate
    }

    private static func corner(near point: Vector2, in picture: SheetPicture, view: ViewID, tolerance: Double) -> PickCandidate? {
        var best: (candidate: PickCandidate, distance: Double)?
        for (_, stroke) in lines(of: view, in: picture) {
            guard case .edge(let id)? = stroke.source, stroke.segments.count == 1,
                  case .line(let a, let b) = stroke.segments[0] else { continue }
            for end in [a, b] {
                let distance = (point - end).length
                if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (.corner(id, at: end), distance) }
            }
        }
        return best?.candidate
    }
}
