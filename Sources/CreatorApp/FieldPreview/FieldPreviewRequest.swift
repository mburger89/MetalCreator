import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// What the preview should follow now (`AppModel.fieldPreviewRequest(for:)`): the selected node, the field it shows, the opaque
/// parts the scene holds and the direction the camera looks from (used only to pick the slice's first axis plane).
struct FieldPreviewRequest {
    var node: NodeID
    var field: Field
    var solids: [Solid]
    var toEye: Vector3
    /// False while the zebra shows: it beats the tint, so the tint is not sampled (and is sampled again when this turns true).
    var drawsTints = true
}
