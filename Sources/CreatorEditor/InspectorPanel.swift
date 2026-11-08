import CreatorGraph
import CreatorStyle
import MetalUI

/// The context inspector (spec §6.4): the selected node's header and sections, then the document
/// parameters, which are always listed. The app shell (M6) docks it on the right.
public struct InspectorPanel: Component, Equatable {
    public let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: EditorModel) {
        self.model = model
    }

    /// Compares the model by identity: it is a final `@Observable` class, so MetalUI re-evaluates the panel when a property
    /// its content read (the selection, the results, the parameters) changes; the theme comes from the environment, which
    /// MetalUI's environment epoch covers.
    public nonisolated static func == (lhs: InspectorPanel, rhs: InspectorPanel) -> Bool { lhs.model === rhs.model }

    /// The page as it fits the window (display finding 1): the glass is as tall as the page when the window holds it, and else as
    /// tall as the window allows, with the page scrolling inside. A `ScrollView` alone would take the page's full height, and
    /// one with `maxHeight: .infinity` would make every short page a full-height column.
    public var content: some ElementGroup {
        let page = model.inspectorPage
        return GlassPanel(.inspector) {
            ViewThatFits(in: .vertical) {
                pageBody(page)
                ScrollView { pageBody(page) }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
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
            ForEach(page.sections, id: \.title) { section in
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
