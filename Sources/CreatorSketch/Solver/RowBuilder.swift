import CreatorGeometry

/// One residual row: its value and its sparse analytic gradient, in a fixed insertion order
/// (so assembling the dense Jacobian is deterministic).
struct RowBuilder: Sendable {
    var value: Double = 0
    var entries: [(column: Int, value: Double)] = []

    mutating func add(column: Int, _ derivative: Double) {
        entries.append((column, derivative))
    }

    /// Adds a gradient with respect to a point; constants contribute nothing.
    mutating func add(_ point: PointOperand, _ gradient: Vector2) {
        guard case .unknown(let column) = point else { return }
        entries.append((column, gradient.x))
        entries.append((column + 1, gradient.y))
    }

    /// Multiplies the value and every derivative by `factor`.
    mutating func scale(by factor: Double) {
        value *= factor
        for index in entries.indices { entries[index].value *= factor }
    }
}
