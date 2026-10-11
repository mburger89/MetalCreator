import CreatorKernel

/// The warning a result in several pieces gets, worded as Boolean words it (`BooleanNode`): parts with several
/// bodies aren't supported yet, so the pieces stay together as one solid. `PatternFeatureNodeTests` pins the two
/// to the same sentence.
enum PieceWarning {
    static func warnings(for result: Solid) -> [String] {
        let pieces = result.topology.pieceCount
        guard pieces > 1 else { return [] }
        return [
            "The result is \(pieces) separate pieces. They stay together as one solid, "
                + "because parts with several bodies aren't supported yet.",
        ]
    }
}
