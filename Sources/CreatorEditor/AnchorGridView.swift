import MetalUI

/// A 3×3 anchor picker; cells are numbered 0…8 row-major from the top-left.
struct AnchorGridView: Component {
    let selected: Int?
    let choose: @MainActor (Int) -> Void

    var content: some ElementGroup {
        Grid(horizontalSpacing: Pixels(2), verticalSpacing: Pixels(2)) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(0..<3) { column in
                        AnchorCell(isSelected: selected == row * 3 + column) { choose(row * 3 + column) }
                    }
                }
            }
        }
    }
}
