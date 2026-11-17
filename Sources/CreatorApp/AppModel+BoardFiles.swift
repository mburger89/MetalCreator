import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI

extension AppModel {
    /// The file type the open panel offers for a KiCad board.
    static let boardTypes: [ContentType] = [.kicadPCB]

    /// File ▸ Import KiCad Board… is offered unless a sketch or a pick session is running (the same rule as `canImportMesh`).
    public var canImportKiCadBoard: Bool { sketch == nil && pick == nil }

    /// A board file button of the inspector: nothing happens before the window has given the app its panels (`nil`); otherwise the
    /// task doing it is returned, so a test can wait for exactly that.
    @discardableResult
    func handleBoardFile(_ request: InspectorRequest) -> Task<Void, Never>? {
        guard let filePicker else { return nil }
        return Task { await performBoardFile(request.action, on: request.node, using: filePicker) }
    }

    /// Carries out "Choose File…" or "Relink…" on the Import KiCad Board node `node` of the level shown, as one undo step, or tells
    /// the person why not and changes nothing. A board is linked only, never embedded.
    public func performBoardFile(_ action: InspectorAction, on node: NodeID, using picker: any FilePicker) async {
        let picker = tracked(picker)
        let failure = await withFileAction(on: node) { target in
            switch action {
            case .choosePCBFile: try await chooseBoardFile(target, using: picker, named: UndoName.chooseBoardFile)
            case .relinkPCBFile: try await chooseBoardFile(target, using: picker, named: UndoName.relinkBoardFile)
            case .pickEdgesInView, .pickFacesInView, .pickLoftStartFace, .pickLoftEndFace, .clearLoftStartFace, .clearLoftEndFace,
                 .editSketch, .editGroup, .makeUnique, .ungroup, .chooseImage, .linkImage, .relinkImage, .embedImage,
                 .chooseMeshFile, .relinkMeshFile, .embedMeshFile, .chooseModelFile, .relinkModelFile, .embedModelFile: break
            }
        }
        reportBoardFile(failure, title: "The board file couldn't be changed")
    }

    /// File ▸ Import KiCad Board…: the open panel, then an Import KiCad Board node linked to the chosen file and, at the top level,
    /// an Output node wired to its `board`, as one undo step. Inside a group the node goes in alone. Does nothing while a sketch or
    /// a pick is running.
    public func importKiCadBoard(using picker: any FilePicker) async {
        let picker = tracked(picker)
        guard canImportKiCadBoard, !imageActionDocuments.contains(ObjectIdentifier(document)) else { return }
        editor.commitPendingEntry()
        let (document, levels, path) = (self.document, editor.levelPath, editor.graphPath)
        let key = ObjectIdentifier(document)
        imageActionDocuments.insert(key)
        defer { imageActionDocuments.remove(key) }
        let failure: (any Error)?
        do {
            guard let url = try await picker.chooseFileToOpen(Self.boardTypes),
                  self.document === document, editor.levelPath == levels, sketch == nil, pick == nil else { return }
            let reference = linkedReference(to: url)
            try checkBoardFile(reference)
            insertImportKiCadBoard(reference, at: path)
            failure = nil
        } catch {
            failure = error
        }
        reportBoardFile(failure, title: "The board couldn't be imported")
    }

    private func insertImportKiCadBoard(_ reference: ImageReference, at path: GraphPath) {
        let graph = editor.graph
        let right = graph.nodes.values.map(\.position.x).max()
        let top = graph.nodes.values.map(\.position.y).min() ?? 0
        let origin = Vector2((right ?? -240) + 240, top)
        var board = registry.makeNode(ImportKiCadBoardNode.typeID, at: origin)
        board.inputValues[NodeSetting.pcbFile] = .pcbFile(reference)
        var commands: [GraphCommand] = [.addNode(board)]
        if !editor.isInsideGroup {
            let output = registry.makeNode(OutputNode.typeID, at: origin + Vector2(240, 0))
            commands.append(.addNode(output))
            commands.append(.connect(Link(from: Endpoint(node: board.id, socket: "board"),
                                          to: Endpoint(node: output.id, socket: "solid"))))
        }
        do {
            try document.perform(.batch(commands), at: path, name: UndoName.importKiCadBoard)
            editor.selection = [board.id]
        } catch {
            alert = .problem(AppProblem("The board couldn't be imported", error.message))
        }
    }

    private func chooseBoardFile(_ target: FileActionTarget, using picker: any FilePicker, named name: String) async throws {
        guard let url = try await picker.chooseFileToOpen(Self.boardTypes), isCurrent(target) else { return }
        try attachBoardFile(url, embed: false, to: target, linkName: name)
    }

    /// The shared core for a board file (the buttons and `set_file`): only a regular file is accepted, and only linked.
    func attachBoardFile(_ url: URL, embed: Bool, to target: FileActionTarget, linkName: String = UndoName.chooseBoardFile) throws {
        guard !embed else { throw AppProblem("That board file can't be used", "A KiCad board is always linked, never embedded.") }
        let reference = linkedReference(to: url)
        try checkBoardFile(reference)
        do {
            try document.perform(.setInput(target.node, NodeSetting.pcbFile, .pcbFile(reference)), at: target.path, name: linkName)
        } catch {
            throw AppProblem("The board file couldn't be changed", error.message)
        }
    }

    /// Refuses a link that names a folder, a device or a pipe, or nothing. What the file holds is the node's to say.
    func checkBoardFile(_ reference: ImageReference) throws {
        let name = reference.fileName ?? "file"
        switch document.imageResolver.stamp(of: reference) {
        case .notAFile: throw BoardImportProblem.notAFile(name: name)
        case .missing(let path): throw BoardImportProblem.missing(name: name, folder: ImageResolver.folder(ofPath: path))
        case .file, .embedded: break
        }
    }

    func reportBoardFile(_ failure: (any Error)?, title: String) {
        switch failure {
        case nil: break
        case let problem as AppProblem: alert = .problem(problem)
        case let problem as BoardImportProblem: alert = .problem(AppProblem("That board file can't be used", problem.message))
        case let error?: report(error, title: title)
        }
    }
}
