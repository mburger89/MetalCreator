import CreatorEditor
import CreatorGraph
import CreatorKernel
import Foundation

/// The document, level and node a file action (an Image Field's or Import Mesh's button) began on. A file panel stays open while the
/// person does other things, so the answer is used only if the same node of the same level of the same document is still there.
struct FileActionTarget {
    let document: DocumentModel
    let path: GraphPath
    let levels: [NodeID]
    let node: NodeID
}

extension AppModel {
    /// Runs `body` as the file action of `node` on the level shown, unless the node isn't there or an action of this document is
    /// already running (one at a time per document, so a second press while a panel is open does nothing). A typed value is
    /// committed first. Returns what `body` threw, for the caller to say in its own words.
    func withFileAction(on node: NodeID, _ body: (FileActionTarget) async throws -> Void) async -> (any Error)? {
        editor.commitPendingEntry()
        let key = ObjectIdentifier(document)
        guard editor.graph.nodes[node] != nil, !imageActionDocuments.contains(key) else { return nil }
        imageActionDocuments.insert(key)
        // The target holds the document until the action ends, so its identity cannot be reused meanwhile.
        let target = FileActionTarget(document: document, path: editor.graphPath, levels: editor.levelPath, node: node)
        defer { imageActionDocuments.remove(key) }
        do {
            try await body(target)
            return nil
        } catch {
            return error
        }
    }

    /// Whether `target` is still what the window shows.
    func isCurrent(_ target: FileActionTarget) -> Bool {
        document === target.document && editor.levelPath == target.levels && editor.graph.nodes[target.node] != nil
    }

    /// A link to `url`: its absolute path and, once the document has a folder, the path relative to it.
    func linkedReference(to url: URL) -> ImageReference {
        let file = url.standardizedFileURL
        let relative = document.documentURL.map { ImageResolver.relativePath(from: $0.deletingLastPathComponent(), to: file) }
        return .linked(relativePath: relative, absolutePath: file.path(percentEncoded: false))
    }
}
