/// How finely a Mesh node works (implicit spec §4.3): `preview` meshes at a coarse resolution that the viewport then refines,
/// `export` at the node's export resolution. `streamedExport` is an export that streams to its file (Errata D12): a Mesh node hands
/// over a `MeshStream` that the writer meshes window by window, instead of a mesh in memory. `EvalContext.meshQuality` says which one
/// a run wants.
public enum MeshQuality: String, Sendable, Hashable, Codable {
    case preview, export, streamedExport
}
