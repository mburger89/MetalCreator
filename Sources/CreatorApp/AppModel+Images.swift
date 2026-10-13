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
        guard editor.graph.nodes[node] != nil else { return }
        do {
            switch action {
            case .chooseImage: try await chooseImage(for: node, using: picker)
            case .linkImage: try await linkImage(for: node, using: picker)
            case .relinkImage: try await relinkImage(for: node, using: picker, named: UndoName.relinkImage)
            case .embedImage: try embedImage(for: node)
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

    private func currentImage(of node: NodeID) -> ImageReference? {
        if case .image(let reference)? = editor.graph.nodes[node]?.inputValues[NodeSetting.image] { reference } else { nil }
    }

    private func chooseImage(for node: NodeID, using picker: any FilePicker) async throws {
        guard let url = try await picker.chooseFileToOpen(Self.imageTypes) else { return }
        let bytes = try checkedBytes(of: url)
        try setImage(.embedded(document.addImage(bytes)), on: node, named: UndoName.chooseImage)
    }

    private func linkImage(for node: NodeID, using picker: any FilePicker) async throws {
        guard case .embedded(let hash)? = currentImage(of: node) else {
            return try await relinkImage(for: node, using: picker, named: UndoName.linkImage)
        }
        guard let bytes = document.images[hash] else { throw ImageProblem.embeddedMissing }
        let format = try GreyImageDecoder.inspect(bytes).format
        guard let url = try await picker.chooseDestination(Self.imageTypes, defaultName: "image.\(format.fileExtension)") else { return }
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw AppProblem("“\(url.lastPathComponent)” couldn't be saved", error.localizedDescription)
        }
        try setImage(linkedReference(to: url), on: node, named: UndoName.linkImage)
    }

    private func relinkImage(for node: NodeID, using picker: any FilePicker, named name: String) async throws {
        guard let url = try await picker.chooseFileToOpen(Self.imageTypes) else { return }
        _ = try checkedBytes(of: url)
        try setImage(linkedReference(to: url), on: node, named: name)
    }

    private func embedImage(for node: NodeID) throws {
        guard let reference = currentImage(of: node), !reference.isEmbedded else { return }
        let bytes = try document.imageResolver.bytes(of: reference)
        _ = try GreyImageDecoder.inspect(bytes)
        try setImage(.embedded(document.addImage(bytes)), on: node, named: UndoName.embedImage)
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

    private func setImage(_ reference: ImageReference, on node: NodeID, named name: String) throws {
        do {
            try document.perform(.setInput(node, NodeSetting.image, .image(reference)), at: editor.graphPath, name: name)
        } catch {
            throw AppProblem("The image couldn't be changed", error.message)
        }
    }
}
