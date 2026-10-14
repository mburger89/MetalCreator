import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Smooth fractal noise in 0…1 (fields spec §3.1), seeded: the same seed, scale and octaves give the same field on every
/// machine (`FieldNoise`, hashed with `SeededRandom`). `scale` is the size of the biggest features in millimetres; each of
/// the `octaves` (1 to 6) halves the size and the strength of the one before.
public enum NoiseFieldNode: NodeDefinition {
    public static let typeID = "creator.noiseField"
    public static let displayName = "Noise Field"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
        SocketSpec("scale", .number, defaultValue: .number(10), unit: .millimetres, range: 0.1...100),
        SocketSpec("octaves", .integer, defaultValue: .integer(1), unit: .count, range: 1...6),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [InspectorSection(title: "Noise", controls: [.integer("seed"), .slider("scale"), .integer("octaves")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let scale = try inputs.number("scale")
        let octaves = try inputs.integer("octaves")
        guard scale.isFinite, scale > 0 else { throw NodeError.invalidValue("“scale” must be greater than 0 mm.") }
        guard (1...6).contains(octaves) else { throw NodeError.invalidValue("“octaves” must be from 1 to 6.") }
        return NodeOutputs(["field": .field(.noise(seed: try inputs.integer("seed"), scale: scale, octaves: octaves))])
    }
}
