import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Placements on a grid in a plane (patterns spec §3): `countX` columns along the plane's x axis and `countY` rows along
/// its y axis, `spacingX` and `spacingY` apart, each facing along the plane's normal with the plane's x axis. `centred`
/// puts the middle of the whole grid on the plane's origin; otherwise the first placement is there. `stagger` moves every
/// second row half a pitch along x (hex-style), and the grid is centred with that shift in it. One branch per row, so a
/// placement is `{row;column}` and always a tree, even for one row (a row added later changes no other path).
///
/// More than 2,000 refuses ("Patterns are limited to 2,000 instances.").
public enum GridPatternNode: NodeDefinition {
    public static let typeID = "creator.gridPattern"
    public static let displayName = "Grid Pattern"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("countX", .integer, defaultValue: .integer(4), unit: .count),
        SocketSpec("countY", .integer, defaultValue: .integer(3), unit: .count),
        SocketSpec("spacingX", .number, defaultValue: .number(10), unit: .millimetres, range: 0...200),
        SocketSpec("spacingY", .number, defaultValue: .number(10), unit: .millimetres, range: 0...200),
        SocketSpec("centred", .bool, defaultValue: .bool(true)),
        SocketSpec("stagger", .bool, defaultValue: .bool(false)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }
    public static let inspector = [
        InspectorSection(title: "Grid", controls: [.planePicker("plane"), .integer("countX"), .integer("countY")]),
        InspectorSection(title: "Spacing", controls: [.slider("spacingX"), .slider("spacingY"),
                                                      .toggle("centred", label: "Centred"), .toggle("stagger", label: "Stagger"),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let plane = try inputs.plane("plane")
        guard plane.placement != nil else { throw NodeError.invalidValue("The grid's plane has no usable direction.") }
        let columns = try LayoutChecks.count(try inputs.integer("countX"), "countX")
        let rows = try LayoutChecks.count(try inputs.integer("countY"), "countY")
        _ = try LayoutChecks.product(columns, rows)
        let spacing = Vector2(try LayoutChecks.number(try inputs.number("spacingX"), "spacingX"),
                              try LayoutChecks.number(try inputs.number("spacingY"), "spacingY"))
        let (centred, stagger) = (try inputs.bool("centred"), try inputs.bool("stagger"))
        // The shift every second row gets, and the width and height of the grid, so a centred grid is centred with it.
        let shift = stagger ? spacing.x / 2 : 0
        let width = Double(max(columns - 1, 0)) * spacing.x + (rows > 1 ? shift : 0)
        let height = Double(max(rows - 1, 0)) * spacing.y
        let corner = centred ? Vector2(-width / 2, -height / 2) : .zero
        var branches: [DataTree] = []
        var first: Vector3?
        for row in 0..<rows {
            let offset = row % 2 == 1 ? shift : 0
            let placements = (0..<columns).map { column -> Scalar in
                let local = corner + Vector2(Double(column) * spacing.x + offset, Double(row) * spacing.y)
                if row == 0, column == 0 { first = plane.point(local) }
                return LayoutChecks.placement(plane.point(local), normal: plane.normal, xAxis: plane.xAxis)
            }
            branches.append(.list(placements))
        }
        var outputs = NodeOutputs(trees: ["placements": DataTree(depth: 2, branches: branches) ?? .empty(depth: 2)])
        if let first {
            outputs.dimensions = LayoutDimensions.grid(plane: plane, first: first, spacing: spacing, counts: (columns, rows),
                                                    stagger: stagger)
        }
        return outputs
    }
}
