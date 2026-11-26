import CreatorDrawing
import CreatorGeometry
import CreatorKernel

extension DrawingEditorModel {
    /// Chooses a tool; the next press, drag or click uses it.
    public func press(_ tool: DrawingTool) {
        self.tool = tool
        refusal = nil
        gesture = nil
        cancelAnnotationInput()
    }

    public func setSource(_ source: NodeID, of id: ViewID) {
        commitView(id) { $0.source = source }
    }

    /// Base views only; a projected view's frame follows its parent's drop.
    public func setOrientation(_ orientation: StandardOrientation, of id: ViewID) {
        commitView(id) { if $0.kind == .base { $0.orientation = .standard(orientation) } }
    }

    /// `nil` follows the sheet's scale.
    public func setScale(_ scale: DrawingScale?, of id: ViewID) {
        if let scale, !scale.isValid {
            refuse("A scale is two whole numbers from 1 to 1000.")
            return
        }
        commitView(id, DrawingStepName.changeScale) { $0.scale = scale }
    }

    public func setShowsHidden(_ shows: Bool, of id: ViewID) {
        commitView(id) { $0.showsHidden = shows }
    }

    public func setShowsTangent(_ shows: Bool, of id: ViewID) {
        commitView(id) { $0.showsTangent = shows }
    }

    public func setShowsLabel(_ shows: Bool, of id: ViewID) {
        commitView(id) { $0.showsLabel = shows }
    }

    public func deleteSelection() {
        guard let id = currentSheet, !selection.isEmpty || !selectedAnnotations.isEmpty else { return }
        let doomed = selection, doomedAnnotations = selectedAnnotations
        let name = deleteName(of: doomedAnnotations, withViews: !doomed.isEmpty)
        commitSheet(id, name) { sheet in
            for annotation in doomedAnnotations { sheet.removeAnnotation(annotation) }
            for view in sheet.views where doomed.contains(view.id) {
                sheet = ViewPlacement.removing(view.id, from: sheet)
            }
        }
        selection = []
        selectedAnnotations = []
        hoveredStroke = nil
    }

    func commitView(_ id: ViewID, _ name: String = DrawingStepName.changeView, _ change: (inout DrawingView) -> Void) {
        commitSheet(name) { sheet in
            guard var view = sheet.view(id) else { return }
            change(&view)
            sheet.setView(view)
        }
    }

    // MARK: Placing

    /// A Front view of the first Output at `point` (sheet mm); the first view on a sheet also sets the sheet's scale (plan R8).
    func placeBaseView(at point: Vector2) {
        guard let source = sources.first, let id = currentSheet else {
            refuse("Add an Output node and wire the part into it first.")
            return
        }
        let view = DrawingView(kind: .base, source: source.id, orientation: .standard(.front), center: point)
        let standard = document.settings.standard
        commitSheet(id, DrawingStepName.addView) { sheet in
            if sheet.views.isEmpty {
                let extents = source.bounds.map { ViewExtents.of($0, frame: StandardOrientation.front.frame) }
                sheet.scale = ScaleChooser.firstScale(
                    extents: extents, area: DrawingArea.rect(for: sheet, standard: standard))
            }
            sheet.setView(view)
        }
        selection = [view.id]
        tool = .select
    }

    /// A projected view of `parent` dropped at `drop` (sheet mm), classified by its offset from the parent's centre (plan R6).
    func placeProjectedView(of parentID: ViewID, dropAt drop: Vector2) {
        guard let id = currentSheet, let sheet, let parent = sheet.view(parentID) else { return }
        if let sentence = ProjectedViewRule.refusal(for: parent) {
            refuse(sentence)
            return
        }
        let parentCenter = ViewPlacement.centers(in: sheet)[parentID] ?? parent.center
        let offset = drop - parentCenter
        guard offset.length > 1e-9 else { return }
        let rule = ProjectedViewRule.view(from: parent.orientation.frame, dropOffset: offset, standard: document.settings.standard)
        let center = rule.axis == .horizontal ? Vector2(drop.x, parentCenter.y) : Vector2(parentCenter.x, drop.y)
        let view = DrawingView(
            kind: .projected, source: parent.source, orientation: .custom(rule.frame), scale: parent.scale, center: center,
            alignment: ViewAlignment(parent: parentID, axis: rule.axis), showsHidden: parent.showsHidden,
            showsTangent: parent.showsTangent)
        commitSheet(id, DrawingStepName.addView) { $0.setView(view) }
        selection = [view.id]
        tool = .select
    }
}
