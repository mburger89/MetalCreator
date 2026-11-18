import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation

/// The file of an Image Field, an Import Mesh or an Import KiCad Board node set from a path: an AI client's `set_file` (top level, like every client edit)
/// and the inspector's buttons, which choose the file with a panel and then come here, so both share the checks and the undo names.
extension AppModel {
    /// Links, or embeds, the picture at `url` on the Image Field `node` of the top level, as one undo step, or throws why not.
    public func setImageFile(_ url: URL, on node: NodeID, embed: Bool) throws(AppProblem) {
        do {
            try attachImage(url, embed: embed, to: topLevelTarget(node))
        } catch let problem as AppProblem {
            throw problem
        } catch {
            throw AppProblem("That image can't be used", Evaluator.message(for: error))
        }
    }

    /// Links, or embeds, the STL or 3MF file at `url` on the Import Mesh `node` of the top level, as one undo step, or throws why not.
    public func setMeshFile(_ url: URL, on node: NodeID, embed: Bool) throws(AppProblem) {
        do {
            try attachMeshFile(url, embed: embed, to: topLevelTarget(node))
        } catch let problem as AppProblem {
            throw problem
        } catch let problem as MeshImportProblem {
            throw AppProblem("That mesh file can't be used", problem.message)
        } catch {
            throw AppProblem("The mesh file couldn't be changed", Evaluator.message(for: error))
        }
    }

    /// Links, or embeds, the STEP or IGES file at `url` on the Import Model `node` of the top level, as one undo step, or throws why not.
    public func setModelFile(_ url: URL, on node: NodeID, embed: Bool) throws(AppProblem) {
        do {
            try attachModelFile(url, embed: embed, to: topLevelTarget(node))
        } catch let problem as AppProblem {
            throw problem
        } catch let problem as ModelImportProblem {
            throw AppProblem("That model file can't be used", problem.message)
        } catch {
            throw AppProblem("The model file couldn't be changed", Evaluator.message(for: error))
        }
    }

    /// Links the KiCad board at `url` on the Import KiCad Board `node` of the top level, as one undo step, or throws why not.
    /// A board is linked only: `embed` is refused.
    public func setBoardFile(_ url: URL, on node: NodeID, embed: Bool) throws(AppProblem) {
        do {
            try attachBoardFile(url, embed: embed, to: topLevelTarget(node))
        } catch let problem as AppProblem {
            throw problem
        } catch let problem as BoardImportProblem {
            throw AppProblem("That board file can't be used", problem.message)
        } catch {
            throw AppProblem("The board file couldn't be changed", Evaluator.message(for: error))
        }
    }

    /// `node` of the document's top level, whatever level the editor shows.
    private func topLevelTarget(_ node: NodeID) -> FileActionTarget {
        FileActionTarget(document: document, path: .root, levels: [], node: node)
    }

    /// The shared core for a picture: checked against the image limits, then linked or embedded.
    func attachImage(_ url: URL, embed: Bool, to target: FileActionTarget, linkName: String = UndoName.linkImage,
                     embedName: String = UndoName.embedImage) throws {
        let bytes = try checkedBytes(of: url)
        if embed {
            try setImage(.embedded(document.addImage(bytes)), on: target, named: embedName)
        } else {
            try setImage(linkedReference(to: url), on: target, named: linkName)
        }
    }

    /// The shared core for a mesh file: only a regular file is accepted (what it holds is the node's to say), then linked or embedded.
    func attachMeshFile(_ url: URL, embed: Bool, to target: FileActionTarget, linkName: String = UndoName.chooseMeshFile) throws {
        let reference = linkedReference(to: url)
        try checkRegularFile(reference)
        if embed {
            try embedMesh(reference, to: target)
        } else {
            try setMeshFile(reference, on: target, named: linkName)
        }
    }

    /// Reads the file `reference` names into the document, up to `MeshImportLimits.maxEmbeddedBytes`.
    func embedMesh(_ reference: ImageReference, to target: FileActionTarget) throws {
        // The size is read from the file's attributes, so a file over the limit is refused without being read.
        if case .file(_, _, let size) = document.imageResolver.stamp(of: reference), size > MeshImportLimits.maxEmbeddedBytes {
            throw AppProblem("That mesh file can't be used", MeshImportLimits.embeddingRefusal)
        }
        let bytes = try document.imageResolver.meshFileBytes(of: reference)
        guard bytes.count <= MeshImportLimits.maxEmbeddedBytes else {
            throw AppProblem("That mesh file can't be used", MeshImportLimits.embeddingRefusal)
        }
        try setMeshFile(.embedded(document.addImage(bytes)), on: target, named: UndoName.embedMeshFile)
    }
}

extension AppModel {
    /// The shared core for a model file: only a regular file is accepted (what it holds is the node's to say), then linked or embedded.
    func attachModelFile(_ url: URL, embed: Bool, to target: FileActionTarget, linkName: String = UndoName.chooseModelFile) throws {
        let reference = linkedReference(to: url)
        try checkModelFile(reference)
        if embed {
            try embedModel(reference, to: target)
        } else {
            try setModelFile(reference, on: target, named: linkName)
        }
    }

    /// Reads the file `reference` names into the document, up to the size an embedded file may be (the mesh files' limit).
    func embedModel(_ reference: ImageReference, to target: FileActionTarget) throws {
        // The size is read from the file's attributes, so a file over the limit is refused without being read.
        if case .file(_, _, let size) = document.imageResolver.stamp(of: reference), size > MeshImportLimits.maxEmbeddedBytes {
            throw AppProblem("That model file can't be used", MeshImportLimits.embeddingRefusal)
        }
        let bytes = try document.imageResolver.modelFileBytes(of: reference)
        guard bytes.count <= MeshImportLimits.maxEmbeddedBytes else {
            throw AppProblem("That model file can't be used", MeshImportLimits.embeddingRefusal)
        }
        try setModelFile(.embedded(document.addImage(bytes)), on: target, named: UndoName.embedModelFile)
    }
}
