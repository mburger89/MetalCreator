import CreatorGeometry
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
            case .number(let number): resultNumber(number)
            case .integer(let integer): integer.formatted(.number.locale(.messages))
            default: "—"
            }
        }
        var shown = items.prefix(resultValueLimit).map(text).joined(separator: ", ")
        if items.count > resultValueLimit { shown += " … (\(items.count) values)" }
        return .recipe(label: "Result", text: shown)
    }

    /// A number as the result row shows it: five decimals, a value that rounds to zero as "0" (never "-0"), and a nonzero one too
    /// small for five decimals in scientific notation ("1E-6"), so a read-out never claims a small result is zero.
    static func resultNumber(_ number: Double, locale: Locale = .messages) -> String {
        let places = 5
        if number != 0, number.isFinite, abs(number) < pow(10, -Double(places)) / 2 {
            return number.formatted(.number.notation(.scientific).locale(locale))
        }
        return number.roundedForDisplay(decimals: places).formatted(.number.precision(.fractionLength(0...places)).locale(locale))
    }
}
