import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A picture as a field (fields spec §3.1, §5): the image is projected along the plane's normal, centred on the plane's origin
/// and stretched over `width` × `height` millimetres, and a point's value is the picture's grey there, 0 black to 1 white,
/// bilinear between pixels. Row 0 of the picture is at the top (the plane's +y). Outside the rectangle the picture repeats
/// (Tile) or holds its edge pixels (Clamp). The picture is the node's `NodeSetting.image` setting, embedded or linked.
public enum ImageFieldNode: NodeDefinition {
    public static let typeID = "creator.imageField"
    public static let displayName = "Image Field"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("width", .number, defaultValue: .number(100), unit: .millimetres, range: 0.1...1000),
        SocketSpec("height", .number, defaultValue: .number(100), unit: .millimetres, range: 0.1...1000),
        SocketSpec("edges", .integer, defaultValue: .integer(ImageEdges.tile.rawValue)),
    ]
    public static let outputs = [SocketSpec("field", .field)]
    public static let inspector = [
        InspectorSection(title: "Image", controls: [.image(NodeSetting.image)]),
        InspectorSection(title: "Projection", controls: [
            .planePicker("plane"), .slider("width"), .slider("height"), .segmented("edges", options: ImageEdges.options),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .image(let reference)? = context.node.inputValues[NodeSetting.image] else { throw ImageProblem.notChosen }
        let width = try inputs.number("width"), height = try inputs.number("height")
        guard width.isFinite, width > 0 else { throw NodeError.invalidValue("“width” must be greater than 0 mm.") }
        guard height.isFinite, height > 0 else { throw NodeError.invalidValue("“height” must be greater than 0 mm.") }
        let plane = try inputs.plane("plane")
        guard plane.origin.isFinite, let normal = plane.normal.normalized, let across = plane.xAxis.normalized,
              normal.cross(across).normalized != nil else { throw NodeError.invalidValue("“plane” has no direction.") }
        guard let edges = ImageEdges(rawValue: try inputs.integer("edges")) else {
            throw NodeError.invalidValue("“edges” must be Tile or Clamp.")
        }
        let image = try await ImageLoader.image(for: reference, resolver: context.images)
        let unit = Plane(origin: plane.origin, normal: normal, xAxis: across)
        return NodeOutputs(["field": .field(.image(image, plane: unit, width: width, height: height, edges: edges))])
    }
}
