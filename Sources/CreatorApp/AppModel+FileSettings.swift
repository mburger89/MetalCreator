import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation

/// The file of an Image Field or an Import Mesh node set from a path rather than a panel (an AI client's `set_file`; the inspector's
/// buttons choose the file with a panel and share the same checks and undo names). The node is on the level shown.
extension AppModel {
    /// Links, or embeds, the picture at `url` on the Image Field `node`, as one undo step, or throws why not and changes nothing.
    public func setImageFile(_ url: URL, on node: NodeID, embed: Bool) throws(AppProblem) {
        let target = FileActionTarget(document: document, path: editor.graphPath, levels: editor.levelPath, node: node)
        do {
            let bytes = try checkedBytes(of: url)
            if embed {
                try setImage(.embedded(document.addImage(bytes)), on: target, named: UndoName.embedImage)
            } else {
                try setImage(linkedReference(to: url), on: target, named: UndoName.linkImage)
            }
        } catch let problem as AppProblem {
            throw problem
        } catch {
            throw AppProblem("That image can't be used", Evaluator.message(for: error))
        }
    }

    /// Links, or embeds, the STL or 3MF file at `url` on the Import Mesh `node`, as one undo step, or throws why not.
    public func setMeshFile(_ url: URL, on node: NodeID, embed: Bool) throws(AppProblem) {
        let target = FileActionTarget(document: document, path: editor.graphPath, levels: editor.levelPath, node: node)
        let reference = linkedReference(to: url)
        do {
            try checkRegularFile(reference)
            guard embed else { return try setMeshFile(reference, on: target, named: UndoName.chooseMeshFile) }
            if case .file(_, _, let size) = document.imageResolver.stamp(of: reference), size > MeshImportLimits.maxEmbeddedBytes {
                throw AppProblem("That mesh file can't be used", MeshImportLimits.embeddingRefusal)
            }
            let bytes = try document.imageResolver.meshFileBytes(of: reference)
            guard bytes.count <= MeshImportLimits.maxEmbeddedBytes else {
                throw AppProblem("That mesh file can't be used", MeshImportLimits.embeddingRefusal)
            }
            try setMeshFile(.embedded(document.addImage(bytes)), on: target, named: UndoName.embedMeshFile)
        } catch let problem as AppProblem {
            throw problem
        } catch let problem as MeshImportProblem {
            throw AppProblem("That mesh file can't be used", problem.message)
        } catch {
            throw AppProblem("The mesh file couldn't be changed", Evaluator.message(for: error))
        }
    }
}
