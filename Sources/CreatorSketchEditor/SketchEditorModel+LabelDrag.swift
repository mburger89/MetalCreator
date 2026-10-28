import CreatorGeometry
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// Begins dragging the label of the sketch dimension `id`. False for another ID (a feature's dimension, the pending one), when
    /// the dimension is gone, or while a dimension is pending or another drag or stroke is under way.
    func beginLabelDrag(_ id: OverlayDimensionID, at p: Vector2?) -> Bool {
        guard pending == nil, dragged == nil, draggedLabel == nil, drawState == .idle,
              let dimensionID = SketchDimensionDrawing.dimensionID(from: id), sketch.dimensions[dimensionID] != nil else { return false }
        draggedLabel = dimensionID
        labelPress = p
        dragOrigin = sketch
        preview = .none
        return true
    }

    /// One drag step: the label goes to `p` on the plane. Nothing is solved or committed (the label is only drawing).
    func dragLabel(to p: Vector2) {
        guard let draggedLabel, sketch.dimensions[draggedLabel] != nil else { return }
        sketch.dimensions[draggedLabel]?.labelPoint = p
    }

    /// The release (at `p`, or off the plane): a label that moved is one "Place Dimension" step; one that ended where it began is none.
    func endLabelDrag(at p: Vector2?) {
        guard draggedLabel != nil else { return }
        // A release where the press was moves nothing: the label keeps its place (a default one stays default).
        if let p, p != labelPress { dragLabel(to: p) }
        let origin = dragOrigin
        draggedLabel = nil
        labelPress = nil
        dragOrigin = nil
        if sketch != origin { commit(sketch, "Place Dimension", named: SketchStepName.placeDimension) }
    }
}
