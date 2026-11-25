import CreatorDrawing
import Foundation

/// Writing the document to a file and taking the written file as the open document's.
extension DocumentModel {
    /// The content with every linked image's paths as they will be found from `folder`, resolving each file from where the
    /// document is now: a file that can be found gets its absolute path and a path relative to `folder`, so a first save gains
    /// the relative path and Save As elsewhere makes it again; one that cannot be found keeps the paths it had.
    func contentStoringImages(relativeTo folder: URL?) -> GraphContent {
        let resolver = imageResolver
        let store = { (reference: ImageReference) in resolver.stored(reference, inDocumentFolder: folder) }
        var stored = content
        stored.graph = content.graph.mappingImages(store)
        for (id, definition) in content.definitions { stored.definitions[id]?.graph = definition.graph.mappingImages(store) }
        return stored
    }

    /// The document as a file (always the current format). Only the embedded images a node uses are written, each once; a
    /// linked image's paths are written as they will be found from `destination`, the file about to be written (else from
    /// `documentURL`). The open document is not changed (`didSave(to:)` does that once the file is written).
    public func fileData(savingTo destination: URL? = nil) throws -> Data {
        try fileData(savingTo: destination, drawings: nil)
    }

    /// `fileData(savingTo:)` with the drawings the editor holds written in place of the document's (drawings plan R15: the editor's
    /// remembered last good values go into the file without an edit). Nil writes the document's own.
    public func fileData(savingTo destination: URL?, drawings: DrawingDocument?) throws -> Data {
        var stored = contentStoringImages(relativeTo: (destination ?? documentURL)?.deletingLastPathComponent())
        if let drawings { stored.graph.drawings = drawings }
        let used = stored.definitions.values.reduce(stored.graph.embeddedImageHashes) { $0.union($1.graph.embeddedImageHashes) }
        let file = GraphFile(graph: stored.graph, definitions: stored.definitions, viewState: viewState,
                             images: images.filter { used.contains($0.key) })
        return try GraphFileIO.encode(file)
    }

    /// Makes `url` the document's file after it was written, and brings the open document's linked images into line with what was
    /// saved: their paths become the ones `fileData(savingTo:)` wrote, as a change that is no undo step and no edit. Without
    /// this, a Save As into another folder would keep the old relative paths, which are tried first, so a same-named
    /// picture in the new folder would silently replace the linked one until the file was reopened. A caller that tracks
    /// what is saved (`AppModel.savedContent`) reads `content` again afterwards.
    public func didSave(to url: URL) {
        didSave(to: url, drawings: nil)
    }

    /// `didSave(to:)` for a file written with `drawings` (`fileData(savingTo:drawings:)`): the document takes them too when they
    /// differ, as a change that is no undo step and no edit, so what is saved is what the document holds.
    public func didSave(to url: URL, drawings: DrawingDocument?) {
        var stored = contentStoringImages(relativeTo: url.deletingLastPathComponent())
        if let drawings { stored.graph.drawings = drawings }
        if stored != content { content = stored }
        documentURL = url
    }
}
