import CreatorSketch

extension SketchEditorModel {
    /// The inspector's readout (sketcher spec §8): "Fully constrained", "3 degrees of freedom", the conflicts, or why
    /// the solve failed. An empty sketch says how to start instead (it would read "Fully constrained").
    public var statusText: String {
        guard !sketch.entities.isEmpty else { return "Nothing drawn yet. Pick Line (L), Arc (A) or Circle (C)." }
        switch solution.status {
        case .solved:
            return "Fully constrained"
        case .underConstrained(let dof):
            return dof == 1 ? "1 degree of freedom" : "\(dof.formatted()) degrees of freedom"
        case .overConstrained:
            let messages = solution.conflictMessages.filter { !$0.isEmpty }
            return messages.isEmpty ? "The constraints conflict." : messages.joined(separator: "\n")
        case .failed(let reason):
            return reason
        }
    }

    /// True when the status is a problem to show in the error colour (a conflict or a failed solve).
    public var statusIsProblem: Bool { !solution.status.isUsable }
}
