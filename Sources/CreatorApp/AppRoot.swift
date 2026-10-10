import CreatorEditor
import CreatorSketchEditor
import CreatorViewport
import MetalUI

/// The window's content (spec §6.1): the viewport fills the window, and the glass top bar, the graph panel in its dock
/// and the inspector float over it. A pick in progress shows its banner over the top. While sketching, the pointer
/// readout is drawn over all of those (it never takes the pointer). The add-node palette and a node-library type
/// being dragged float over everything (spec §6.2), drawn last so nothing clips or covers them. Every view below
/// reads the app's theme from the environment, and the window's MetalUI controls follow its light or dark (spec
/// §6.6). All behaviour is in `AppModel`; this is glue.
public struct AppRoot: Component {
    public let model: AppModel
    public let input: AppInput

    public init(model: AppModel, input: AppInput) {
        self.model = model
        self.input = input
    }

    public var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ViewportView(model: model.viewport)
            VStack(alignment: .leading, spacing: AppLayout.margin.px) {
                ZStack { TopBar(model: model) }
                    .frame(height: AppLayout.topBarHeight.px)
                PanelArea(model: model)
            }
            .padding(Edges(all: AppLayout.margin.px))
            if let pick = model.pick {
                HStack {
                    Spacer()
                    PickBanner(model: model, picked: pick.picked.count)
                    Spacer()
                }
                .padding(Edges(top: (AppLayout.margin * 2 + AppLayout.topBarHeight).px, right: Pixels(0),
                               bottom: Pixels(0), left: Pixels(0)))
            }
            if let session = model.sketch { PointerReadoutView(model: session.editor) }
            PaletteDock(model: model)
            LibraryDragOverlay(model: model.editor)
        }
        .onChange(of: model.editor.inspectorRequest) { _, request in
            if let request { model.handle(request) }
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { shown in
            if !shown { model.alert = nil }
        }), presenting: model.alert) { alert in
            if case .discardChanges = alert {
                Button("Discard Changes", role: .destructive) { Task { await model.discardChanges() } }
                Button("Cancel", role: .cancel) { model.keepChanges() }
            } else if case .saveChanges = alert {
                for answer in SaveChangesAnswer.allCases {
                    Button(answer.title, role: answer.role) { Task { await model.answerSaveChanges(answer) } }
                }
            }
        } message: { alert in
            Text(alert.message)
        }
        .environment(model.themes)
        .preferredColorScheme(model.themes.current.isDark ? .dark : .light)
    }
}
