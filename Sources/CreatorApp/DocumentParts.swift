import CreatorEditor
import CreatorGraph
import CreatorKernel
import CreatorViewport

/// Everything that belongs to one open document, made together and replaced together on New and Open.
@MainActor
struct DocumentParts {
    let document: DocumentModel
    let editor: EditorModel
    let input: GraphPanelInput
    let viewport: ViewportModel

    /// The viewport starts at the file's saved camera and home view; without one it frames the first scene.
    init(_ file: GraphFile, registry: NodeRegistry, kernel: any Kernel) {
        document = DocumentModel(file: file, registry: registry, kernel: kernel)
        editor = EditorModel(document: document)
        input = GraphPanelInput(model: editor)
        viewport = ViewportModel(kernel: kernel, pose: file.viewState.camera)
        viewport.homePose = file.viewState.homeCamera
    }
}
