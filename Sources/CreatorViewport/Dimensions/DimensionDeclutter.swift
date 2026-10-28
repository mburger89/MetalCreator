import CreatorGeometry

/// Keeps dimension labels from overlapping (spec §3.3): a dimension whose text box meets an earlier one's is placed again
/// further out.
enum DimensionDeclutter {
    /// The tiers tried: 0 is the style as given, 1…3 stand off further.
    static let tiers = 4

    /// Places in order; a `.standoff` dimension whose text box (grown by `textGap`) meets an earlier one's is placed again with the
    /// style's `standoff` and `leaderLength` grown by `tier · (PlacedDimension.textHeight + textGap)`, tiers 1…3, keeping the first
    /// tier that meets nothing, else the tier with the least overlapping area. A `.through` placement is never moved.
    /// A dimension that cannot be drawn is left out, as in `DimensionLayout.place`.
    @MainActor
    static func place(_ dimensions: [OverlayDimension], style: DimensionStyle, camera: DimensionCamera,
                      measure: TextMeasure) -> [PlacedDimension] {
        var placed: [PlacedDimension] = []
        for dimension in dimensions {
            guard let first = DimensionLayout.place(dimension, style: style, camera: camera, measure: measure) else { continue }
            guard case .standoff = dimension.geometry.placement else {
                placed.append(first)
                continue
            }
            var best = first
            var bestArea = overlap(first, with: placed, gap: style.textGap)
            var tier = 1
            while bestArea > 0, tier < tiers {
                var grown = style
                let extra = Double(tier) * (PlacedDimension.textHeight + style.textGap)
                grown.standoff += extra
                grown.leaderLength += extra
                if let candidate = DimensionLayout.place(dimension, style: grown, camera: camera, measure: measure) {
                    let area = overlap(candidate, with: placed, gap: style.textGap)
                    if area < bestArea { (best, bestArea) = (candidate, area) }
                }
                tier += 1
            }
            placed.append(best)
        }
        return placed
    }

    /// The total area `candidate`'s text box, grown by `gap` on every side, shares with the earlier text boxes: the boxes must
    /// stay `gap` apart. Touching (within rounding) is not overlap.
    private static func overlap(_ candidate: PlacedDimension, with earlier: [PlacedDimension], gap: Double) -> Double {
        let (x0, y0) = (candidate.textOrigin.x - gap, candidate.textOrigin.y - gap)
        let (x1, y1) = (x0 + candidate.textSize.width + 2 * gap, y0 + candidate.textSize.height + 2 * gap)
        return earlier.reduce(0) { total, other in
            let width = min(x1, other.textOrigin.x + other.textSize.width) - max(x0, other.textOrigin.x)
            let height = min(y1, other.textOrigin.y + other.textSize.height) - max(y0, other.textOrigin.y)
            return width > 1e-6 && height > 1e-6 ? total + width * height : total
        }
    }
}

extension DimensionGeometry {
    fileprivate var placement: DimensionPlacement {
        switch self {
        case let .linear(_, _, _, _, placement), let .radial(_, _, _, _, placement), let .angular(_, _, _, _, placement): placement
        }
    }
}
