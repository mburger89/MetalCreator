import CreatorGraph

extension EditTools {
    /// The batch's `step_name`: nil when absent, a name from the fixed list, else a refusal.
    static func stepName(in arguments: JSONValue) -> Result<String?, Refusal> {
        guard let given = arguments["step_name"], given != .null else { return .success(nil) }
        guard let text = given.string, UndoName.clientBatchNames.contains(text) else {
            return .failure(Refusal("The step name must be one of Build, Rewire, Rearrange, Clean Up, Delete or Edit Graph."))
        }
        return .success(text)
    }

    private enum Kind { case add, remove, rewire, move, other }

    private static func kind(of command: GraphCommand) -> Kind {
        switch command {
        case .addNode: .add
        case .removeNode: .remove
        case .connect, .disconnect: .rewire
        case .move: .move
        default: .other
        }
    }

    /// One operation keeps its own name; several are named for what they do as a whole.
    static func batchName(for plans: [Plan]) -> String {
        if plans.count == 1 { return plans[0].name }
        let kinds = Set(plans.flatMap(\.commands).map(kind(of:)))
        if kinds.contains(.add) { return UndoName.build }
        switch kinds {
        case [.remove]: return UndoName.delete
        case [.rewire]: return UndoName.rewire
        case [.move]: return UndoName.rearrange
        default: return UndoName.editGraph
        }
    }
}
