/// Everything that shapes one slot's tool (patterns spec §5), so slots of one size share one tool (§7).
struct SlotSize: Hashable, Sendable {
    let length: Double
    let width: Double
    let depth: Double

    /// The reason this size can't be made, worded for instance `path`, or `nil` if it can.
    func problem(at path: String) -> String? {
        guard width.isFinite, width > 0 else { return "Slot \(path): the width must be greater than 0 mm." }
        guard length.isFinite, length > width else { return "Slot \(path): the length must be greater than the width." }
        guard depth.isFinite, depth > 0 else { return "Slot \(path): the depth must be greater than 0 mm." }
        return nil
    }
}
