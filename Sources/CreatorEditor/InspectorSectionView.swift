import MetalUI

/// A titled inspector section: a small uppercase title in hint text, then its rows.
struct InspectorSectionView<Rows: ElementGroup>: Component {
    let title: String
    let rows: Rows

    init(title: String, @ElementBuilder rows: () -> Rows) {
        self.title = title
        self.rows = rows()
    }

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(6)) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(Palette.secondaryText.color)
            rows
        }
    }
}
