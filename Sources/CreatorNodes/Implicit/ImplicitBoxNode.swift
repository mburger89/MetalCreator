import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A box about the origin as an implicit solid, with rounded edges if asked (implicit spec §3.2).
public enum ImplicitBoxNode: NodeDefinition {
    public static let typeID = "creator.implicitBox"
    public static let displayName = "Box"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("size", .vector, defaultValue: .vector(Vector3(20, 20, 20)), unit: .millimetres),
        SocketSpec("corner radius", .number, defaultValue: .number(0), unit: .millimetres, range: 0...50),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [InspectorSection(title: "Box", controls: [.vector("size"), .slider("corner radius")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let size = try inputs.vector("size")
        let radius = try inputs.number("corner radius")
        guard size.isFinite, size.x > 0, size.y > 0, size.z > 0 else {
            throw NodeError.invalidValue("“size” must be greater than 0 mm on every side.")
        }
        guard radius.isFinite, radius >= 0 else { throw NodeError.invalidValue("“corner radius” must be 0 or more.") }
        guard radius <= min(size.x, size.y, size.z) / 2 else {
            throw NodeError.invalidValue("“corner radius” can't be more than half the smallest side.")
        }
        var outputs = NodeOutputs(["implicit": .implicit(ImplicitSolid.box(halfSize: size * 0.5, cornerRadius: radius).reference)])
        outputs.dimensions = dimensions(size: size)
        return outputs
    }

    private struct Side {
        var from, to, direction, side: Vector3
        var value: Double

        init(_ from: Vector3, _ to: Vector3, _ direction: Vector3, _ side: Vector3, _ value: Double) {
            (self.from, self.to, self.direction, self.side, self.value) = (from, to, direction, side, value)
        }
    }

    /// One length per side, along the edge that starts at the (−x, −y, −z) corner (x, y, z in turn).
    private static func dimensions(size: Vector3) -> [DimensionSpec] {
        let (hx, hy, hz) = (size.x / 2, size.y / 2, size.z / 2)
        let origin = Vector3(-hx, -hy, -hz)
        let sides: [Side] = [
            Side(origin, Vector3(hx, -hy, -hz), .unitX, -.unitY, size.x),
            Side(Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), .unitY, .unitX, size.y),
            Side(Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), .unitZ, .unitX, size.z),
        ]
        return sides.enumerated().map { index, side in
            let geometry = DimensionGeometry.linear(from: side.from, to: side.to, direction: side.direction, side: side.side,
                                                    placement: .standoff)
            return DimensionSpec(.input("size"), geometry, .length, value: side.value, component: index)
        }
    }
}
