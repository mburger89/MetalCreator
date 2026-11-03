import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI

extension AppModel {
    /// The file types the open panel offers for a mesh. The node tells the two apart by the file's bytes, not its name.
    static let meshTypes: [ContentType] = [.stl, .threeMF]

    /// File ▸ Import Mesh… is offered unless a sketch or a pick session is running. This answers those two only: whether another file
    /// panel of this document is open is unobserved state, so the menu item doesn't read it, and `importMesh` guards a second panel itself.
    public var canImportMesh: Bool { sketch == nil && pick == nil }

    /// A mesh file button of the inspector (`EditorModel.inspectorRequest`): nothing happens before the window has given the app its
    /// panels (`nil`); otherwise the task doing it is returned, so a test can wait for exactly that.
    @discardableResult
    func handleMeshFile(_ request: InspectorRequest) -> Task<Void, Never>? {
        guard let filePicker else { return nil }
        return Task { await performMeshFile(request.action, on: request.node, using: filePicker) }
    }

    /// Carries out a mesh file button for the Import Mesh node `node` on the level shown, as one undo step, or tells the person why
    /// not and changes nothing:
    /// - `chooseMeshFile`: a file is chosen and **linked**;
    /// - `relinkMeshFile`: another file for a link (the node's error offers this when the file is gone);
    /// - `embedMeshFile`: the linked file is read into the document, up to `MeshImportLimits.maxEmbeddedBytes`.
    /// A choice is refused only when the path isn't a regular file; a file that isn't a usable mesh is chosen, and the node says what
    /// is wrong with it.
    public func performMeshFile(_ action: InspectorAction, on node: NodeID, using picker: any FilePicker) async {
        let failure = await withFileAction(on: node) { target in
            switch action {
            case .chooseMeshFile: try await chooseMeshFile(target, using: picker, named: UndoName.chooseMeshFile)
            case .relinkMeshFile: try await chooseMeshFile(target, using: picker, named: UndoName.relinkMeshFile)
            case .embedMeshFile: try embedMeshFile(target)
            case .pickEdgesInView, .pickFacesInView, .pickLoftStartFace, .pickLoftEndFace, .clearLoftStartFace, .clearLoftEndFace,
                 .editSketch, .editGroup, .makeUnique, .ungroup, .chooseImage, .linkImage, .relinkImage, .embedImage: break
            }
        }
        reportMeshFile(failure, title: "The mesh file couldn't be changed")
    }

    /// File ▸ Import Mesh…: the open panel, then an Import Mesh node linked to the chosen file and, at the top level, an Output node
    /// wired to it, as one undo step. Inside a group the node goes in alone (an Output node can't live in a group). Does nothing
    /// while a sketch or a pick is running.
    public func importMesh(using picker: any FilePicker) async {
        guard canImportMesh, !imageActionDocuments.contains(ObjectIdentifier(document)) else { return }
        editor.commitPendingEntry()
        let (document, levels, path) = (self.document, editor.levelPath, editor.graphPath)
        // One file panel at a time per document, shared with the inspector's file buttons.
        let key = ObjectIdentifier(document)
        imageActionDocuments.insert(key)
        defer { imageActionDocuments.remove(key) }
        let failure: (any Error)?
        do {
            guard let url = try await picker.chooseFileToOpen(Self.meshTypes),
                  self.document === document, editor.levelPath == levels, sketch == nil, pick == nil else { return }
            let reference = linkedReference(to: url)
            try checkRegularFile(reference)
            insertImportMesh(reference, at: path)
            failure = nil
        } catch {
            failure = error
        }
        reportMeshFile(failure, title: "The mesh couldn't be imported")
    }

    private func insertImportMesh(_ reference: ImageReference, at path: GraphPath) {
        let graph = editor.graph
        let right = graph.nodes.values.map(\.position.x).max()
        let top = graph.nodes.values.map(\.position.y).min() ?? 0
        let origin = Vector2((right ?? -240) + 240, top)
        var mesh = registry.makeNode(ImportMeshNode.typeID, at: origin)
        mesh.inputValues[NodeSetting.meshFile] = .meshFile(reference)
        var commands: [GraphCommand] = [.addNode(mesh)]
        if !editor.isInsideGroup {
            let output = registry.makeNode(OutputNode.typeID, at: origin + Vector2(240, 0))
            commands.append(.addNode(output))
            commands.append(.connect(Link(from: Endpoint(node: mesh.id, socket: "mesh"),
                                          to: Endpoint(node: output.id, socket: "mesh"))))
        }
        do {
            try document.perform(.batch(commands), at: path, name: UndoName.importMesh)
            editor.selection = [mesh.id]
        } catch {
            alert = .problem(AppProblem("The mesh couldn't be imported", error.message))
        }
    }

    private func chooseMeshFile(_ target: FileActionTarget, using picker: any FilePicker, named name: String) async throws {
        guard let url = try await picker.chooseFileToOpen(Self.meshTypes), isCurrent(target) else { return }
        let reference = linkedReference(to: url)
        try checkRegularFile(reference)
        try setMeshFile(reference, on: target, named: name)
    }

    private func embedMeshFile(_ target: FileActionTarget) throws {
        guard case let reference? = editor.graph.nodes[target.node]?.inputValues[NodeSetting.meshFile]?.fileReference,
              !reference.isEmbedded else { return }
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

    /// Refuses a link that names a folder, a device or a pipe, or nothing. What the file holds is the node's to say.
    private func checkRegularFile(_ reference: ImageReference) throws {
        let name = reference.fileName ?? "file"
        switch document.imageResolver.stamp(of: reference) {
        case .notAFile: throw MeshImportProblem.notAFile(name: name)
        case .missing(let path): throw MeshImportProblem.missing(name: name, folder: ImageResolver.folder(ofPath: path))
        case .file, .embedded: break
        }
    }

    private func setMeshFile(_ reference: ImageReference, on target: FileActionTarget, named name: String) throws {
        do {
            try document.perform(.setInput(target.node, NodeSetting.meshFile, .meshFile(reference)), at: target.path, name: name)
        } catch {
            throw AppProblem("The mesh file couldn't be changed", error.message)
        }
    }

    private func reportMeshFile(_ failure: (any Error)?, title: String) {
        switch failure {
        case nil: break
        case let problem as AppProblem: alert = .problem(problem)
        case let problem as MeshImportProblem: alert = .problem(AppProblem("That mesh file can't be used", problem.message))
        case let error?: report(error, title: title)
        }
    }
}
