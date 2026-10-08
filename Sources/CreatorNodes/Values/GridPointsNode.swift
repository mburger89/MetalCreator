import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A grid of points on the XY plane (z = 0), row by row from −Y, each row from −X (spec §7.1, Values).
///
/// `total`, when set, overrides `countX`: the grid keeps `countY` rows and gets just enough
/// columns for `total` points, and the last row is left short when `total` doesn't fill it.
/// That lets one integer such as "Hole count" drive a 2-row grid (4 → 2×2, 6 → 3×2; spec §7.2).
/// `centred` puts the full grid's middle on the origin; otherwise the first point is at the origin.
public enum GridPointsNode: NodeDefinition {
    public static let typeID = "creator.gridPoints"
    public static let displayName = "Grid Points"
    public static let category = NodeCategory.value
    public static let inputs = [
        SocketSpec("countX", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("countY", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("spacingX", .number, defaultValue: .number(10), unit: .millimetres, range: 0...200),
        SocketSpec("spacingY", .number, defaultValue: .number(10), unit: .millimetres, range: 0...200),
        SocketSpec("centred", .bool, defaultValue: .bool(true)),
        SocketSpec("total", .integer, unit: .count, optional: true),
    ]
    public static let outputs = [SocketSpec("points", .vector)]
    public static let inspector = [
        InspectorSection(title: "Grid", controls: [.integer("countX"), .integer("countY"), .integer("total")]),
        InspectorSection(title: "Spacing", controls: [.slider("spacingX"), .slider("spacingY"), .toggle("centred", label: "Centred")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let rows = try inputs.integer("countY")
        try GeneratorLimit.check(rows, "countY")
        var columns = try inputs.integer("countX")
        var limit: Int?
        if inputs.has("total") {
            let total = try inputs.integer("total")
            try GeneratorLimit.check(total, "total")
            guard rows > 0 || total == 0 else { throw NodeError.invalidValue("Set “countY” to at least 1 to lay out “total” points.") }
            columns = rows == 0 ? 0 : (total + rows - 1) / rows
            limit = total
        }
        try GeneratorLimit.check(columns, "countX")
        guard columns * rows <= GeneratorLimit.maximumItems else {
            throw NodeError.invalidValue("The grid can have at most \(GeneratorLimit.maximumItems.display) points.")
        }
        let (spacingX, spacingY) = (try inputs.number("spacingX"), try inputs.number("spacingY"))
        let centred = try inputs.bool("centred")
        let originX = centred ? -Double(columns - 1) / 2 * spacingX : 0
        let originY = centred ? -Double(rows - 1) / 2 * spacingY : 0
        var points: [Scalar] = []
        for row in 0..<rows {
            for column in 0..<columns {
                points.append(.vector(Vector3(originX + Double(column) * spacingX, originY + Double(row) * spacingY, 0)))
            }
        }
        if let limit { points = Array(points.prefix(limit)) }
        return NodeOutputs(lists: ["points": points])
    }
}
