import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorMCP
import CreatorNodes
import Foundation

/// The document the AI server drives: the app's open one. Reads go to `model.document`, which New and Open replace (the inner
/// `DocumentModelSession`, which tells the client's undo steps from the person's, is rebuilt when it does); an edit first closes the
/// palette and commits a typed value, as Undo does, and refreshes the editor's level after; files go through the model's own paths.
@MainActor
final class AppDocumentSession: DocumentSession {
    private let model: AppModel
    private var held: DocumentModelSession

    init(model: AppModel) {
        self.model = model
        held = DocumentModelSession(document: model.document)
        hook(held)
    }

    /// The session over the model's current document.
    private var inner: DocumentModelSession {
        if held.document !== model.document {
            held = DocumentModelSession(document: model.document)
            hook(held)
        }
        return held
    }

    private func hook(_ session: DocumentModelSession) {
        session.refusal = { [weak self] in self?.askRefusal() }
        session.willPerform = { [weak self] in
            guard let editor = self?.model.editor else { return }
            if editor.palette != nil { editor.closePalette() }
            editor.commitPendingEntry()
        }
        session.didChange = { [weak self] in self?.model.editor.refreshLevel() }
    }

    var content: GraphContent { inner.content }
    var registry: NodeRegistry { inner.registry }
    var results: [NodeID: NodeResult] { inner.results }
    var units: DocumentUnits { inner.units }
    var displayName: String { model.displayName }
    var isEdited: Bool { model.isEdited }
    var fileURL: URL? { model.fileURL }

    func outputSummary(of node: NodeID, socket: SocketName) -> String? { inner.outputSummary(of: node, socket: socket) }

    /// The sentence saying why an edit can't run now, in the order the person would meet them.
    private func askRefusal() -> String? {
        if model.alert != nil || model.closeRequest != .idle {
            return "MetalCreator is asking you something. Answer it, then try again."
        }
        if model.sketch != nil { return "MetalCreator is editing a sketch. Finish it with Done, then try again." }
        if model.pick != nil { return "MetalCreator is waiting for a pick in the view. Finish or cancel it, then try again." }
        if model.modelDimension != nil { return "MetalCreator is adding a dimension. Finish or cancel it, then try again." }
        switch model.editor.interaction {
        case .moving?, .resizing?, .duplicating?, .connecting?:
            return "The person is moving something on the canvas; try again in a moment."
        default: break
        }
        if model.document.isScrubbing { return "The person is changing a value; try again in a moment." }
        return nil
    }

    func editRefusal() -> String? { askRefusal() }

    func perform(_ command: GraphCommand, name: String) throws(GraphError) {
        try inner.perform(command, name: name)
    }

    func freePosition(for node: Node, in graph: Graph) -> Vector2 {
        let editor = model.editor
        let nodes = graph.nodes.values
        let taken = nodes.map { editor.placedFrame(of: editor.shape(of: $0), at: $0.position) }
        let right = nodes.map(\.position.x).max()
        let top = nodes.map(\.position.y).min() ?? 0
        let preferred = Vector2((right ?? -240) + 240, top)
        return editor.freePosition(for: editor.shape(of: node), near: preferred, taken: taken)
    }

    func settle(within limit: Duration) async -> Bool {
        // One race for the whole wait (the inner settle and the model's own), so the cap holds for both.
        let gate = SettleGate()
        let inner = inner
        let model = model
        let waiter = Task { @MainActor in
            let settled = await inner.settle(within: limit)
            if settled { await model.settle() }
            gate.finish(settled)
        }
        let timer = Task { @MainActor in
            try? await Task.sleep(for: limit)
            gate.finish(false)
        }
        let settled = await gate.outcome()
        waiter.cancel()
        timer.cancel()
        return settled
    }

    func undoClientStep() -> SessionOutcome { inner.undoClientStep() }
    func redoClientStep() -> SessionOutcome { inner.redoClientStep() }

    // MARK: Files

    private static let unsaved = "The document has unsaved changes. Save it first, or pass discard_unsaved."

    func newDocument(discardUnsaved: Bool) -> SessionOutcome {
        if let refusal = askRefusal() { return .refused(refusal) }
        model.editor.commitPendingEntry()  // a typed value not yet committed is unsaved work too
        if model.isEdited, !discardUnsaved { return .refused(Self.unsaved) }
        model.startNewDocument()
        return .done(nil)
    }

    func open(_ url: URL, discardUnsaved: Bool) -> SessionOutcome {
        if let refusal = askRefusal() { return .refused(refusal) }
        model.editor.commitPendingEntry()  // a typed value not yet committed is unsaved work too
        if model.isEdited, !discardUnsaved { return .refused(Self.unsaved) }
        do {
            try model.open(url)
            return .done(nil)
        } catch {
            return .refused(error.message)
        }
    }

    func save(to url: URL?, overwrite: Bool) -> SessionOutcome {
        if let refusal = askRefusal() { return .refused(refusal) }
        let target: URL
        if let url {
            if let refusal = overwriteRefusal(url, overwrite: overwrite, allowing: model.fileURL) { return .refused(refusal) }
            target = url
        } else if let own = model.fileURL {
            target = own
        } else {
            return .refused("The document has never been saved; give a path.")
        }
        do {
            try model.save(to: target)
            return .done("Saved \(target.lastPathComponent).")
        } catch {
            return .refused(error.message)
        }
    }

    func export(_ kind: String, to url: URL, overwrite: Bool, progress: MCPCallContext) async -> SessionOutcome {
        if let refusal = askRefusal() { return .refused(refusal) }
        guard let exportKind = ExportKind(rawValue: kind) else { return .refused("Export kinds are step, stl and 3mf.") }
        if let refusal = overwriteRefusal(url, overwrite: overwrite, allowing: nil) { return .refused(refusal) }
        let model = model
        let report = progress.progress
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                if let run = model.exportRun { report?(run.fraction, 1, nil) }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { watcher.cancel() }
        do {
            let warnings = try await model.exportReturningWarnings(exportKind, to: url)
            guard !warnings.isEmpty else { return .done("Exported \(url.lastPathComponent).") }
            let count = warnings.count.formatted(.number.locale(.messages))
            let heading = "Exported \(url.lastPathComponent) with \(count) \(warnings.count == 1 ? "warning" : "warnings")"
            return .done(([heading + ":"] + warnings).joined(separator: "\n"))
        } catch {
            return .refused(error.message)
        }
    }

    private func overwriteRefusal(_ url: URL, overwrite: Bool, allowing own: URL?) -> String? {
        let same = own.map { $0.standardizedFileURL.path == url.standardizedFileURL.path } ?? false
        guard !same, !overwrite, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return "\(url.lastPathComponent) already exists. Pass overwrite to replace it."
    }

    func setFile(_ url: URL, on node: NodeID, embed: Bool) async -> SessionOutcome {
        if let refusal = askRefusal() { return .refused(refusal) }
        guard let found = model.document.graph.nodes[node] else { return .refused("That node no longer exists.") }
        let model = model
        do {
            switch found.typeID {
            case ImageFieldNode.typeID:
                try inner.performExternal { () throws(AppProblem) in try model.setImageFile(url, on: node, embed: embed) }
            case ImportMeshNode.typeID:
                try inner.performExternal { () throws(AppProblem) in try model.setMeshFile(url, on: node, embed: embed) }
            default:
                return .refused("Only an Image Field or an Import Mesh node holds a file.")
            }
            return .done(nil)
        } catch {
            return .refused(error.message)
        }
    }
}
