import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI

extension AppModel {
    /// The file types the open panel offers for a model. The node tells STEP and IGES apart by the file's bytes, not its name.
    static let modelTypes: [ContentType] = [.step, .iges]

    /// File ▸ Import Model… is offered unless a sketch or a pick session is running (the same rule as `canImportMesh`).
    public var canImportModel: Bool { sketch == nil && pick == nil }

    /// A model file button of the inspector (`EditorModel.inspectorRequest`): nothing happens before the window has given the app its
    /// panels (`nil`); otherwise the task doing it is returned, so a test can wait for exactly that.
    @discardableResult
    func handleModelFile(_ request: InspectorRequest) -> Task<Void, Never>? {
        guard let filePicker else { return nil }
        return Task { await performModelFile(request.action, on: request.node, using: filePicker) }
    }

    /// Carries out a model file button for the Import Model node `node` on the level shown, as one undo step, or tells the person why
    /// not and changes nothing:
    /// - `chooseModelFile`: a file is chosen and **linked**;
    /// - `relinkModelFile`: another file for a link (the node's error offers this when the file is gone);
    /// - `embedModelFile`: the linked file is read into the document, up to `MeshImportLimits.maxEmbeddedBytes`.
    public func performModelFile(_ action: InspectorAction, on node: NodeID, using picker: any FilePicker) async {
        let picker = tracked(picker)
        let failure = await withFileAction(on: node) { target in
            switch action {
            case .chooseModelFile: try await chooseModelFile(target, using: picker, named: UndoName.chooseModelFile)
            case .relinkModelFile: try await chooseModelFile(target, using: picker, named: UndoName.relinkModelFile)
            case .embedModelFile: try embedModelFile(target)
            case .pickEdgesInView, .pickFacesInView, .pickLoftStartFace, .pickLoftEndFace, .clearLoftStartFace, .clearLoftEndFace,
                 .editSketch, .editGroup, .makeUnique, .ungroup, .editControlPoints, .chooseImage, .linkImage, .relinkImage, .embedImage,
                 .chooseMeshFile, .relinkMeshFile, .embedMeshFile, .choosePCBFile, .relinkPCBFile: break
            }
        }
        reportModelFile(failure, title: "The model file couldn't be changed")
    }

    /// File ▸ Import Model…: the open panel, then an Import Model node linked to the chosen file and, at the top level, an Output node
    /// wired to its `solids` and `curves`, as one undo step. Inside a group the node goes in alone (an Output node can't live in a group). Does
    /// nothing while a sketch or a pick is running.
    public func importModel(using picker: any FilePicker) async {
        let picker = tracked(picker)
        guard canImportModel, !imageActionDocuments.contains(ObjectIdentifier(document)) else { return }
        editor.commitPendingEntry()
        let (document, levels, path) = (self.document, editor.levelPath, editor.graphPath)
        let key = ObjectIdentifier(document)
        imageActionDocuments.insert(key)
        defer { imageActionDocuments.remove(key) }
        let failure: (any Error)?
        do {
            guard let url = try await picker.chooseFileToOpen(Self.modelTypes),
                  self.document === document, editor.levelPath == levels, sketch == nil, pick == nil else { return }
            let reference = linkedReference(to: url)
            try checkModelFile(reference)
            insertImportModel(reference, at: path)
            failure = nil
        } catch {
            failure = error
        }
        reportModelFile(failure, title: "The model couldn't be imported")
    }

    private func insertImportModel(_ reference: ImageReference, at path: GraphPath) {
        let graph = editor.graph
        let right = graph.nodes.values.map(\.position.x).max()
        let top = graph.nodes.values.map(\.position.y).min() ?? 0
        let origin = Vector2((right ?? -240) + 240, top)
        var model = registry.makeNode(ImportModelNode.typeID, at: origin)
        model.inputValues[NodeSetting.modelFile] = .modelFile(reference)
        var commands: [GraphCommand] = [.addNode(model)]
        if !editor.isInsideGroup {
            let output = registry.makeNode(OutputNode.typeID, at: origin + Vector2(240, 0))
            commands.append(.addNode(output))
            commands.append(.connect(Link(from: Endpoint(node: model.id, socket: "solids"),
                                          to: Endpoint(node: output.id, socket: "solid"))))
            commands.append(.connect(Link(from: Endpoint(node: model.id, socket: "curves"),
                                          to: Endpoint(node: output.id, socket: "curve"))))
        }
        do {
            try document.perform(.batch(commands), at: path, name: UndoName.importModel)
            editor.selection = [model.id]
        } catch {
            alert = .problem(AppProblem("The model couldn't be imported", error.message))
        }
    }

    private func chooseModelFile(_ target: FileActionTarget, using picker: any FilePicker, named name: String) async throws {
        guard let url = try await picker.chooseFileToOpen(Self.modelTypes), isCurrent(target) else { return }
        try attachModelFile(url, embed: false, to: target, linkName: name)
    }

    private func embedModelFile(_ target: FileActionTarget) throws {
        guard case let reference? = editor.graph.nodes[target.node]?.inputValues[NodeSetting.modelFile]?.fileReference,
              !reference.isEmbedded else { return }
        try embedModel(reference, to: target)
    }

    /// Refuses a link that names a folder, a device or a pipe, or nothing. What the file holds is the node's to say.
    func checkModelFile(_ reference: ImageReference) throws {
        let name = reference.fileName ?? "file"
        switch document.imageResolver.stamp(of: reference) {
        case .notAFile: throw ModelImportProblem.notAFile(name: name)
        case .missing(let path): throw ModelImportProblem.missing(name: name, folder: ImageResolver.folder(ofPath: path))
        case .file, .embedded: break
        }
    }

    func setModelFile(_ reference: ImageReference, on target: FileActionTarget, named name: String) throws {
        do {
            try document.perform(.setInput(target.node, NodeSetting.modelFile, .modelFile(reference)), at: target.path, name: name)
        } catch {
            throw AppProblem("The model file couldn't be changed", error.message)
        }
    }

    func reportModelFile(_ failure: (any Error)?, title: String) {
        switch failure {
        case nil: break
        case let problem as AppProblem: alert = .problem(problem)
        case let problem as ModelImportProblem: alert = .problem(AppProblem("That model file can't be used", problem.message))
        case let error?: report(error, title: title)
        }
    }
}
