import CreatorGraph
import CreatorKernel
import Foundation

extension InspectorBuilder {
    /// How many values of a list a `.result` row spells out before it says how many there are.
    static let resultValueLimit = 8

    /// The `.result` row: the output's number, or its numbers separated by commas (the first `resultValueLimit`, then the count),
    /// to five decimals as a converted angle needs ("3.14159"). It wraps, so a long list stays inside the panel.
    static func resultRow(_ socket: SocketName, node: Node, results: [NodeID: NodeResult]) -> InspectorRow {
        guard let output = results[node.id]?.outputs?[socket] else { return .readOnly(label: "Result", text: "No result yet") }
        let items = output.items
        guard !items.isEmpty else { return .readOnly(label: "Result", text: "Empty list") }
        func text(_ scalar: Scalar) -> String {
            switch scalar {
            case .number(let number): number.formatted(.number.precision(.fractionLength(0...5)).locale(.messages))
            case .integer(let integer): integer.formatted(.number.locale(.messages))
            default: "—"
            }
        }
        var shown = items.prefix(resultValueLimit).map(text).joined(separator: ", ")
        if items.count > resultValueLimit { shown += " … (\(items.count) values)" }
        return .recipe(label: "Result", text: shown)
    }
}
