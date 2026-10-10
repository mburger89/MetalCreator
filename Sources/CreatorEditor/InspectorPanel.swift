import CreatorGraph
import CreatorStyle
import MetalUI

/// The context inspector (spec §6.4): the selected node's header and sections, then the document
/// parameters, which are always listed. The app shell (M6) docks it on the right.
public struct InspectorPanel: Component {
    public let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let page = model.inspectorPage
        return GlassPanel {
            VStack(alignment: .leading, spacing: Pixels(10)) {
                if let header = page.header {
                    InspectorHeaderView(header: header)
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
}
