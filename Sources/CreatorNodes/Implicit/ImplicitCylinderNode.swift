import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A cylinder about the origin as an implicit solid, its axis along Z (implicit spec §3.2).
public enum ImplicitCylinderNode: NodeDefinition {
    public static let typeID = "creator.implicitCylinder"
    public static let displayName = "Cylinder"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("radius", .number, defaultValue: .number(5), unit: .millimetres, range: 0.1...1000),
        SocketSpec("height", .number, defaultValue: .number(20), unit: .millimetres, range: 0.1...1000),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let inspector = [InspectorSection(title: "Cylinder", controls: [.slider("radius"), .slider("height")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (radius, height) = (try inputs.number("radius"), try inputs.number("height"))
        guard radius.isFinite, radius > 0 else { throw NodeError.invalidValue("“radius” must be greater than 0 mm.") }
        guard height.isFinite, height > 0 else { throw NodeError.invalidValue("“height” must be greater than 0 mm.") }
        var outputs = NodeOutputs(["implicit": .implicit(ImplicitSolid.cylinder(radius: radius, halfHeight: height / 2).reference)])
        let diameter = DimensionGeometry.radial(center: Vector3(0, 0, height / 2), radius: radius, normal: .unitZ, toward: .unitX,
                                                placement: .standoff)
        let length = DimensionGeometry.linear(from: Vector3(radius, 0, -height / 2), to: Vector3(radius, 0, height / 2),
                                              direction: .unitZ, side: .unitX, placement: .standoff)
        outputs.dimensions = [
            DimensionSpec(.input("radius"), diameter, .diameter, value: radius * 2, inputScale: 0.5),
            DimensionSpec(.input("height"), length, .length, value: height),
        ]
        return outputs
    }
}
