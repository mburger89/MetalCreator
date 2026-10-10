import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// A Project click: the host resolves the pick into the edges that can be projected onto the plane (`events.projection`),
    /// and each becomes a fixed `.projected` entity with a fresh reference, all in one undo step with the picks to store. An
    /// edge that is already projected, and any the host left out, are said in words; nothing projectable stores nothing.
    func project(_ target: PickTarget?) {
        refusal = nil
        guard let target else {
            refusal = "Click an edge or a face of the model to project it."
            return
        }
        let resolution = events.projection(target, plane)
        var edited = sketch
        var writes: [ProjectionWrite] = []
        var left = resolution.skipped
        for candidate in resolution.candidates {
            guard !Self.isProjected(candidate.curve, in: edited) else {
                if !left.contains(Self.alreadyProjected) { left.append(Self.alreadyProjected) }
                continue
            }
            let reference = Self.nextReference(in: edited)
            edited.add(SketchEntity(.projected(ProjectionSource(reference: reference, curve: candidate.curve))))
            writes.append(ProjectionWrite(reference: reference, pick: candidate.pick, solid: candidate.solid))
        }
        guard !writes.isEmpty else {
            refusal = left.first ?? "There is nothing there to project."
            return
        }
        commit(edited, "Project", projections: writes)
        if !left.isEmpty { refusal = left.joined(separator: " ") }
    }

    static let alreadyProjected = "That edge is already projected."

    /// Whether the sketch already projects exactly this curve (a re-projected edge gives the very same numbers).
    static func isProjected(_ curve: ProjectedCurve, in sketch: Sketch) -> Bool {
        sketch.entityIDs.contains { id in
            if case .projected(let source)? = sketch.entities[id]?.kind { source.curve == curve && !source.isSuspended } else { false }
        }
    }

    /// "edge1", "edge2", …: the first not used by a projection in the sketch.
    static func nextReference(in sketch: Sketch) -> String {
        let used = Set(sketch.entityIDs.compactMap { id -> String? in
            if case .projected(let source)? = sketch.entities[id]?.kind { source.reference } else { nil }
        })
        var number = 1
        while used.contains("edge\(number)") { number += 1 }
        return "edge\(number)"
    }
}
