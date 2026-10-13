import CreatorGraph
import CreatorNodes

/// What a face-menu item that inserts a layout node on a face differs by: the node, the undo step's name and the words of its
/// refusals. "Pattern on Face" makes a Face Pattern, "Scatter on Face" a Field Scatter; both wire the part's producer into the
/// node's `solid` and store the face's pick in its `face` setting.
struct FaceLayout {
    let typeID: String
    let undoName: String
    /// "pattern" or "scatter", as the alerts say it.
    let noun: String
    let insideGroup: String
    let notFlat: String

    var failureTitle: String { "No \(noun) was made" }

    static let pattern = FaceLayout(
        typeID: FacePatternNode.typeID, undoName: UndoName.patternOnFace, noun: "pattern",
        insideGroup: "Patterns on a face can't be made inside a group yet. Make it before grouping, or from the top level.",
        notFlat: "Only a flat face can hold a pattern.")

    static let scatter = FaceLayout(
        typeID: FieldScatterNode.typeID, undoName: UndoName.scatterOnFace, noun: "scatter",
        insideGroup: "A scatter on a face can't be made inside a group yet. Make it before grouping, or from the top level.",
        notFlat: "Only a flat face can hold a scatter.")
}
