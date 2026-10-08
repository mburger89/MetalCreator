import CreatorGeometry
import CreatorGraph

/// Which point of a profile's bounding box sits on the plane origin (the `anchorGrid` control,
/// spec §6.4). Stored as an integer 0…8, row-major from the top-left: 0 top-left, 1 top centre,
/// 2 top-right, 3 middle-left, 4 centre, 5 middle-right, 6 bottom-left, 7 bottom centre, 8 bottom-right.
enum Anchor {
    static let centre = 4

    /// The plane-coordinate offset that moves a box centred on the origin so `index` lands on the origin.
    static func offset(_ index: Int, width: Double, height: Double) throws -> Vector2 {
        guard (0...8).contains(index) else {
            throw NodeError.invalidValue("“anchor” must be 0 to 8 (top-left to bottom-right).")
        }
        let (column, row) = (index % 3, index / 3)
        return Vector2(Double(1 - column) * width / 2, Double(row - 1) * height / 2)
    }
}
