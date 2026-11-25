import CreatorDrawing
import CreatorGeometry

/// The annotation a tool is making: what it has picked so far and, given where the pointer is, the annotation the next click would
/// place (plan R17). The draft preview and the committed annotation come from the same call, so they cannot differ.
struct AnnotationDraft {
    let tool: DrawingTool
    let picks: [PickedAnchor]

    /// The dimension tool this tool is, for `DimensionInference`; `nil` for the others.
    var dimensionTool: DimensionTool? {
        switch tool {
        case .dimension: .smart
        case .baselineDimension: .baseline
        case .chainDimension: .chain
        case .ordinateDimension: .ordinate
        case .chamferDimension: .chamfer
        default: nil
        }
    }

    /// What the tool's picks are for.
    var purpose: PickPurpose {
        switch tool {
        case .holeCallout: .holeCallout
        case .centreMark: .centreMark
        case .centreLine: .centreLine
        default: .dimension
        }
    }

    /// The most picks the tool takes, or `nil` for as many as the person likes.
    var maximumPicks: Int? {
        switch tool {
        case .dimension, .chamferDimension: 2
        case .holeCallout: 1
        default: nil
        }
    }

    /// Whether a click on empty space may place the annotation now.
    var isComplete: Bool {
        if let dimensionTool { return DimensionInference.isComplete(picks, tool: dimensionTool) }
        return tool == .holeCallout && picks.count == 1
    }

    /// The sentence for a placing click that comes before the picks are enough.
    var incompleteSentence: String {
        switch tool {
        case .baselineDimension, .chainDimension: DimensionInference.seriesNeedsSentence
        case .ordinateDimension: DimensionInference.ordinateNeedsSentence
        case .chamferDimension: DimensionInference.chamferSentence
        default: DimensionInference.secondPickSentence
        }
    }

    /// The undo step the placed annotation is.
    var stepName: String {
        tool == .holeCallout ? DrawingStepName.addHoleCallout : DrawingStepName.addDimension
    }

    /// The annotation placed by a click at `placing` (sheet millimetres) on a view at `mapping`; `aligned` is Shift on the click.
    func kind(placing: Vector2, aligned: Bool, mapping: ViewMapping) -> Result<AnnotationKind, DrawingRefusal> {
        if let dimensionTool {
            switch DimensionInference.make(tool: dimensionTool, picks: picks, placing: mapping.model(placing), aligned: aligned) {
            case .failure(let refusal): return .failure(refusal)
            case .success(let made):
                let placement = DimensionInference.placement(for: made.kind, picks: picks, placing: placing, mapping: mapping)
                return .success(
                    .dimension(DrawingDimension(kind: made.kind, anchors: made.anchors, placement: placement)))
            }
        }
        guard tool == .holeCallout, let pick = picks.first else {
            return .failure(DrawingRefusal(sentence: DimensionInference.secondPickSentence))
        }
        let placement = DimensionInference.placement(for: .diameter, picks: [pick], placing: placing, mapping: mapping)
        return .success(.holeCallout(HoleCallout(anchor: pick.target, placement: placement)))
    }
}
