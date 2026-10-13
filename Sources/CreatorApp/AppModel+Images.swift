import CreatorEditor
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import MetalUI

extension AppModel {
    /// The file types an Image Field reads (fields spec §10: PNG and JPEG).
    static let imageTypes: [ContentType] = [.png, .jpeg]

    /// An image button of the inspector (`EditorModel.inspectorRequest`): the app shell owns the file panels, so it carries
    /// these out. Nothing happens before the window has given the app its panels (`nil`); otherwise the task doing it is
    /// returned, so a test can wait for exactly that and nothing else.
    @discardableResult
    func handleImage(_ request: InspectorRequest) -> Task<Void, Never>? {
        guard let filePicker else { return nil }
        return Task { await performImage(request.action, on: request.node, using: filePicker) }
    }

    /// Carries out an image button for the Image Field `node` on the level shown (fields spec §5), as one undo step, or tells
    /// the person why not and changes nothing:
    /// - `chooseImage`: a file is chosen and **embedded**;
    /// - `linkImage`: an embedded picture is saved to a file the person chooses and the node links to it; with no picture, an
    ///   existing file is linked;
    /// - `relinkImage`: another file for a link (the node's error offers this when the file is gone);
    /// - `embedImage`: the linked file is read into the document.
    /// A file is checked when it is chosen (`ImageResolver.bytes(ofFileAt:)`, `GreyImageDecoder.inspect`): over 16 MB, over
    /// 8,192 px on a side, or not a PNG or JPEG, and the setting stays as it was (fields spec D10).
    public func performImage(_ action: InspectorAction, on node: NodeID, using picker: any FilePicker) async {
        editor.commitPendingEntry()
        guard editor.graph.nodes[node] != nil, !isImageActionInFlight else { return }
        isImageActionInFlight = true
        defer { isImageActionInFlight = false }
        let target = ImageTarget(document: document, path: editor.graphPath, levels: editor.levelPath, node: node)
        do {
            switch action {
            case .chooseImage: try await chooseImage(target, using: picker)
            case .linkImage: try await linkImage(target, using: picker)
            case .relinkImage: try await relinkImage(target, using: picker, named: UndoName.relinkImage)
            case .embedImage: try embedImage(target)
            case .pickEdgesInView, .pickFacesInView, .editSketch, .editGroup, .makeUnique, .ungroup: break
            }
        } catch let problem as AppProblem {
            alert = .problem(problem)
        } catch let problem as ImageProblem {
            alert = .problem(AppProblem("That image can't be used", problem.message))
        } catch {
            report(error, title: "The image couldn't be changed")
        }
    }

    /// The document, level and node an image action began on. A file panel stays open while the person does other things,
    /// so the answer is used only if the same node of the same level of the same document is still there.
    private struct ImageTarget {
        let document: DocumentModel
        let path: GraphPath
        let levels: [NodeID]
        let node: NodeID
    }

    /// Whether `target` is still what the window shows.
    private func isCurrent(_ target: ImageTarget) -> Bool {
        document === target.document && editor.levelPath == target.levels && editor.graph.nodes[target.node] != nil
    }

    private func currentImage(of node: NodeID) -> ImageReference? {
        if case .image(let reference)? = editor.graph.nodes[node]?.inputValues[NodeSetting.image] { reference } else { nil }
    }

    private func chooseImage(_ target: ImageTarget, using picker: any FilePicker) async throws {
        guard let url = try await picker.chooseFileToOpen(Self.imageTypes), isCurrent(target) else { return }
        let bytes = try checkedBytes(of: url)
        try setImage(.embedded(document.addImage(bytes)), on: target, named: UndoName.chooseImage)
    }

    private func linkImage(_ target: ImageTarget, using picker: any FilePicker) async throws {
        guard case .embedded(let hash)? = currentImage(of: target.node) else {
            return try await relinkImage(target, using: picker, named: UndoName.linkImage)
        }
        guard let bytes = document.images[hash] else { throw ImageProblem.embeddedMissing }
        let format = try GreyImageDecoder.inspect(bytes).format
        guard let url = try await picker.chooseDestination(Self.imageTypes, defaultName: "image.\(format.fileExtension)"),
              isCurrent(target), currentImage(of: target.node) == .embedded(hash) else { return }
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw AppProblem("“\(url.lastPathComponent)” couldn't be saved", error.localizedDescription)
        }
        try setImage(linkedReference(to: url), on: target, named: UndoName.linkImage)
    }

    private func relinkImage(_ target: ImageTarget, using picker: any FilePicker, named name: String) async throws {
        guard let url = try await picker.chooseFileToOpen(Self.imageTypes), isCurrent(target) else { return }
        _ = try checkedBytes(of: url)
        try setImage(linkedReference(to: url), on: target, named: name)
    }

    private func embedImage(_ target: ImageTarget) throws {
        guard let reference = currentImage(of: target.node), !reference.isEmbedded else { return }
        let bytes = try document.imageResolver.bytes(of: reference)
        _ = try GreyImageDecoder.inspect(bytes)
        try setImage(.embedded(document.addImage(bytes)), on: target, named: UndoName.embedImage)
    }

    /// The bytes of the file at `url` once they pass the image limits, else a sentence naming the file.
    private func checkedBytes(of url: URL) throws -> Data {
        do {
            let bytes = try ImageResolver.bytes(ofFileAt: url)
            _ = try GreyImageDecoder.inspect(bytes)
            return bytes
        } catch {
            throw AppProblem("“\(url.lastPathComponent)” can't be used as an image", error.message)
        }
    }

    /// A link to `url`: its absolute path and, once the document has a folder, the path relative to it.
    private func linkedReference(to url: URL) -> ImageReference {
        let file = url.standardizedFileURL
        let relative = document.documentURL.map { ImageResolver.relativePath(from: $0.deletingLastPathComponent(), to: file) }
        return .linked(relativePath: relative, absolutePath: file.path(percentEncoded: false))
    }

    private func setImage(_ reference: ImageReference, on target: ImageTarget, named name: String) throws {
        do {
            try document.perform(.setInput(target.node, NodeSetting.image, .image(reference)), at: target.path, name: name)
        } catch {
            throw AppProblem("The image couldn't be changed", error.message)
        }
    }
}
