extension Graph {
    /// The two tie commands (cable ties spec 2026-10-26 §3.2), applied to this graph. Ties never affect evaluation
    /// (`GraphCommand.affectsResults`). `setTie` adds the tie or replaces it whole, so a move and an added wire are each one
    /// command carrying the tie's new value; its inverse carries the old. Refused, changing nothing: a position that isn't
    /// finite, fewer than two wires (I2), a wire that is no link's input here (I1), and removing a tie that isn't there.
    mutating func applyTie(_ command: GraphCommand) throws(GraphError) -> GraphCommand {
        switch command {
        case .setTie(let tie):
            try requireValid(tie)
            let old = ties.updateValue(tie, forKey: tie.id)
            return old.map { .setTie($0) } ?? .removeTie(tie.id)
        case .removeTie(let id):
            guard let old = ties.removeValue(forKey: id) else { throw .invalidValue("That tie is gone.") }
            return .setTie(old)
        default:
            throw .invalidValue("Not a tie edit.")  // `apply` routes only the two tie commands here.
        }
    }

    private func requireValid(_ tie: CableTie) throws(GraphError) {
        guard tie.position.isFinite else { throw .invalidValue("Enter a finite number.") }
        guard tie.wires.count >= CableTie.minimumWires else { throw .invalidValue("A tie holds at least two wires.") }
        guard tie.wires.isSubset(of: Set(links.map(\.to))) else { throw .invalidValue("A tie can only hold wires that are there.") }
    }

    /// The ties a file held, as a graph keeps them (cable ties spec §3.3): the first of a repeated ID, without the wires that
    /// are no input of `links` (I1), and then without the ties that left with fewer than two wires (I2).
    static func repaired(_ decoded: [CableTie], links: [Link]) -> [TieID: CableTie] {
        var ties: [TieID: CableTie] = [:]
        for tie in decoded where ties[tie.id] == nil {
            ties[tie.id] = tie
        }
        let wired = Set(links.map(\.to))
        return ties.compactMapValues { tie in
            var kept = tie
            kept.wires.formIntersection(wired)
            return kept.wires.count >= CableTie.minimumWires ? kept : nil
        }
    }

    /// Takes `wires` out of every tie that holds one, removing a tie left with fewer than two (I2), and returns the
    /// commands that put each touched tie back as it was, in tie-ID order (cable ties spec §3.2). An inverse runs them after
    /// it has restored the wires, so each passes (I1).
    mutating func stripTies(holding wires: Set<Endpoint>) -> [GraphCommand] {
        guard !wires.isEmpty else { return [] }
        var restores: [GraphCommand] = []
        for id in ties.keys.sorted() {
            guard var tie = ties[id], !tie.wires.isDisjoint(with: wires) else { continue }
            restores.append(.setTie(tie))
            tie.wires.subtract(wires)
            ties[id] = tie.wires.count >= CableTie.minimumWires ? tie : nil
        }
        return restores
    }

    /// `inverse`, followed by the tie restores when wires left ties, as one command (one undo step). With none it is
    /// `inverse` itself, so a command that reached no tie undoes exactly as it always did.
    static func restoring(_ inverse: GraphCommand, ties restores: [GraphCommand]) -> GraphCommand {
        restores.isEmpty ? inverse : .batch([inverse] + restores)
    }
}
