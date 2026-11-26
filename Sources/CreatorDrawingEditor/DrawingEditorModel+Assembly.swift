import CreatorDrawing
import CreatorGeometry
import CreatorKernel

/// The Assembly View tool and a view's part list (DR-5 R1).
extension DrawingEditorModel {
    static let lastPartSentence = "An assembly view shows at least one part."
    static let noOutputSentence = "Add an Output node and wire the part into it first."

    /// An Assembly View of every Output in `sources`, a Front view at `point`; the first view on a sheet sets the sheet's scale
    /// from the union of the parts' bounds (DR-1 R8).
    func placeAssemblyView(at point: Vector2) {
        guard let first = sources.first, let id = currentSheet else {
            refuse(Self.noOutputSentence)
            return
        }
        let view = DrawingView(
            kind: .base, source: first.id, orientation: .standard(.front), center: point, assembly: sources.map(\.id))
        let standard = document.settings.standard
        var union: BoundingBox?
        for box in sources.compactMap(\.bounds) { union = union.map { $0.union(box) } ?? box }
        commitSheet(id, DrawingStepName.addView) { sheet in
            if sheet.views.isEmpty {
                let extents = union.map { ViewExtents.of($0, frame: StandardOrientation.front.frame) }
                sheet.scale = ScaleChooser.firstScale(
                    extents: extents, area: DrawingArea.rect(for: sheet, standard: standard))
            }
            sheet.setView(view)
        }
        selection = [view.id]
        tool = .select
    }

    /// The parts of an assembly view, in order, and its descendants' with it; `parts` must name at least one (R1).
    public func setParts(_ parts: [NodeID], of id: ViewID) {
        var seen: Set<NodeID> = []
        let unique = parts.filter { seen.insert($0).inserted }
        guard let first = unique.first else {
            refuse(Self.lastPartSentence)
            return
        }
        commitSheet(DrawingStepName.changeParts) { sheet in
            for target in [id] + Self.followers(of: id, in: sheet) {
                guard var view = sheet.view(target) else { continue }
                view.assembly = unique
                view.source = first
                sheet.setView(view)
            }
        }
    }

    /// Shows or hides one part of the view: a shown part is added at the end, a hidden one removed; the last part stays.
    public func setPart(_ part: NodeID, shown: Bool, of id: ViewID) {
        guard let view = sheet?.view(id) else { return }
        var parts = view.outputs
        if shown {
            if !parts.contains(part) { parts.append(part) }
        } else {
            parts.removeAll { $0 == part }
        }
        setParts(parts, of: id)
    }

    /// The views that carry `id`'s parts: those aligned to it (projected) or derived from it, and theirs in turn.
    static func followers(of id: ViewID, in sheet: DrawingSheet) -> [ViewID] {
        var found: [ViewID] = []
        var seen: Set<ViewID> = [id]
        var frontier = [id]
        while !frontier.isEmpty {
            let current = frontier.removeFirst()
            for view in sheet.views
            where (view.alignment?.parent == current || view.derivation?.parent == current) && seen.insert(view.id).inserted {
                found.append(view.id)
                frontier.append(view.id)
            }
        }
        return found
    }
}
