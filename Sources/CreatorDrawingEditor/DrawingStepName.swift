/// The undo steps of the drawing editor (plan R26): fixed English names, no numbers, no typed text.
public enum DrawingStepName {
    public static let addSheet = "Add Sheet"
    public static let renameSheet = "Rename Sheet"
    public static let duplicateSheet = "Duplicate Sheet"
    public static let deleteSheet = "Delete Sheet"
    public static let moveSheet = "Move Sheet"
    public static let changeSheetSize = "Change Sheet Size"
    public static let editTitleBlock = "Edit Title Block"
    public static let changeStandard = "Change Standard"
    public static let addView = "Add View"
    public static let moveView = "Move View"
    public static let deleteView = "Delete View"
    public static let changeScale = "Change Scale"
    public static let changeView = "Change View"
    public static let addDimension = "Add Dimension"
    public static let addHoleCallout = "Add Hole Callout"
    public static let addCentreMark = "Add Centre Mark"
    public static let addCentreLine = "Add Centre Line"
    public static let addNote = "Add Note"
    public static let addLeader = "Add Leader"
    public static let reattachDimension = "Reattach Dimension"

    public static let all: [String] = [
        addSheet, renameSheet, duplicateSheet, deleteSheet, moveSheet, changeSheetSize, editTitleBlock, changeStandard,
        addView, moveView, deleteView, changeScale, changeView, addDimension, addHoleCallout, addCentreMark, addCentreLine,
        addNote, addLeader, reattachDimension,
    ]
}
