import CreatorGraph
import Foundation
import MetalUI

extension AppModel {
    /// New: an empty document. With unsaved changes it asks first (`alert`, then `discardChanges()`).
    public func newDocument() {
        guard closeRequest == .idle else { return }
        guard !isEdited else {
            pendingDiscard = .newDocument
            alert = .discardChanges
            return
        }
        load(GraphFile(), from: nil)
    }

    /// Open…: the open panel, then the chosen file. With unsaved changes it asks first.
    public func openDocument(using picker: any FilePicker) async {
        guard closeRequest == .idle else { return }
        guard !isEdited else {
            pendingDiscard = .openDocument(picker)
            alert = .discardChanges
            return
        }
        await chooseAndOpen(using: picker)
    }

    /// The alert's Discard Changes: carries on with what was asked for.
    public func discardChanges() async {
        guard let action = pendingDiscard else { return }
        pendingDiscard = nil
        switch action {
        case .newDocument: load(GraphFile(), from: nil)
        case .openDocument(let picker): await chooseAndOpen(using: picker)
        }
    }

    /// The alert's Cancel: keeps the open document and forgets what was asked for.
    public func keepChanges() {
        pendingDiscard = nil
        alert = nil
    }

    /// Reads a `.mcgraph` file and makes it the open document. A file from a newer MetalCreator, or one that
    /// isn't a graph, is refused with a sentence saying so; the open document is kept.
    public func open(_ url: URL) throws(AppProblem) {
        let title = "“\(url.lastPathComponent)” couldn't be opened"
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AppProblem(title, error.localizedDescription)
        }
        let file: GraphFile
        do {
            file = try GraphFileIO.decode(data, registry: registry)
        } catch let error as GraphFileError {
            throw AppProblem(title, error.message)
        } catch {
            throw AppProblem(title, "It isn't a MetalCreator graph, or it is damaged.")
        }
        load(file, from: url)
    }

    /// Writes the document to `url` and makes it the document's file. A typed but uncommitted inspector value is
    /// committed first, and once the camera has settled its current pose is saved with it.
    public func save(to url: URL) throws(AppProblem) {
        editor.commitPendingEntry()
        if document.viewState.camera != nil { document.viewState.camera = viewport.pose }
        do {
            try document.fileData().write(to: url, options: .atomic)
        } catch {
            throw AppProblem("“\(url.lastPathComponent)” couldn't be saved", error.localizedDescription)
        }
        fileURL = url
        savedContent = document.content
    }

    /// Save: to the document's file, or Save As… for a new document. Returns whether it was saved.
    @discardableResult
    public func saveDocument(using picker: any FilePicker) async -> Bool {
        guard let fileURL else { return await saveDocumentAs(using: picker) }
        do {
            try save(to: fileURL)
            return true
        } catch {
            alert = .problem(error)
            return false
        }
    }

    /// Save As…: the save panel, then the chosen file. Returns whether it was saved.
    @discardableResult
    public func saveDocumentAs(using picker: any FilePicker) async -> Bool {
        do {
            guard let url = try await picker.chooseDestination([.mcgraph], defaultName: fileURL?.lastPathComponent ?? "Untitled.mcgraph")
            else { return false }
            try save(to: url)
            return true
        } catch {
            report(error, title: "The document couldn't be saved")
            return false
        }
    }

    func chooseAndOpen(using picker: any FilePicker) async {
        do {
            guard let url = try await picker.chooseFileToOpen([.mcgraph]) else { return }
            try open(url)
        } catch {
            report(error, title: "The document couldn't be opened")
        }
    }

    /// Shows a failure: an `AppProblem` as it is, a file panel that couldn't be shown in plain words. A cancelled
    /// task shows nothing.
    func report(_ error: any Error, title: String) {
        switch error {
        case let problem as AppProblem: alert = .problem(problem)
        case is CancellationError: break
        case FileDialogError.busy: alert = .problem(AppProblem(title, "Another panel or alert is already open."))
        default: alert = .problem(AppProblem(title, "The file panel couldn't be shown."))
        }
    }
}
