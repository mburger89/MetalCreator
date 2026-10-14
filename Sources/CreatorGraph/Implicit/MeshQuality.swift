/// How finely a Mesh node works (implicit spec §4.3): `preview` meshes at a coarse resolution that the viewport then refines,
/// `export` at the node's export resolution. `EvalContext.meshQuality` says which one a run wants.
public enum MeshQuality: String, Sendable, Hashable, Codable {
    case preview, export
}
