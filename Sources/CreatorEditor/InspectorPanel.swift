import CreatorGraph
import CreatorStyle
import MetalUI

/// The context inspector (spec §6.4): the selected node's header and sections, then the document
/// parameters, which are always listed. The app shell (M6) docks it on the right.
public struct InspectorPanel: Component, Equatable {
    public let model: EditorModel
    /// What the window's height loses round the inspector (margins, the top bar); the app's `AppLayout` knows it. Zero lets the
    /// page grow as it likes, as in the graph panel preview.
    public let reservedHeight: Double
    @Environment(\.windowSize) var windowSize: Size<Pixels>
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: EditorModel, reservedHeight: Double = 0) {
        self.model = model
        self.reservedHeight = reservedHeight
    }

    /// Compares the model by identity: it is a final `@Observable` class, so MetalUI re-evaluates the panel when a property
    /// its content read (the selection, the results, the parameters) changes; the theme comes from the environment, which
    /// MetalUI's environment epoch covers.
    public nonisolated static func == (lhs: InspectorPanel, rhs: InspectorPanel) -> Bool {
        lhs.model === rhs.model && lhs.reservedHeight == rhs.reservedHeight
    }

    /// The page, in a `ScrollView` when the window may not hold it (display finding 1). A scroll view fills the height it is offered,
    /// so a short page stays a plain column (a `ViewThatFits` would pick the fit exactly but is ineligible for MetalUI's retained
    /// replay, which the steady-frame pins in `CanvasContentSkipWindowTests` hold the inspector to) and only a page whose
    /// `estimatedHeight` reaches 60 % of the room (`room`: the window's height less `reservedHeight`) scrolls.
    public var content: some ElementGroup {
        let page = model.inspectorPage
        let room = Double(windowSize.height.value) - reservedHeight - 2 * GraphPanelLayout.glassPadding
        return GlassPanel(.inspector) {
            if reservedHeight > 0, page.estimatedHeight >= 0.6 * room {
                ScrollView { pageBody(page) }
            } else {
                pageBody(page)
            }
        }
    }

    private func pageBody(_ page: InspectorPage) -> some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(10)) {
            if let header = page.header {
                InspectorHeaderView(header: header)
            }
            if let group = page.group {
                GroupPanelView(panel: group, model: model)
            }
            ForEach(page.identifiedSections, id: \.id) { identified in
                let section = identified.section
                InspectorSectionView(title: section.title) {
                    ForEach(section.rows.indices, id: \.self) { index in
                        InspectorRowView(row: section.rows[index], model: model, node: page.header?.node)
                    }
                }
            }
            if let comment = page.comment {
                CommentInspectorView(page: comment, model: model)
            }
            InspectorSectionView(title: "Document Parameters") {
                if page.parameters.isEmpty {
                    Text("No parameters").font(.caption).foregroundStyle(Palette(themes).secondaryText.color)
                }
                ForEach(page.parameters, id: \.id) { row in
                    ParameterRowView(row: row, model: model)
                }
            }
        }
        .frame(width: Pixels(280), alignment: .topLeading)
    }
}
