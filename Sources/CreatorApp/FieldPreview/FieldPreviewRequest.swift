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
}
