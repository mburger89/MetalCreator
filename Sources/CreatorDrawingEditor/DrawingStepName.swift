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
    public static let removeLeader = "Remove Leader"
    public static let moveDimension = "Move Dimension"
    public static let moveNote = "Move Note"
    public static let moveAnnotations = "Move Annotations"
    public static let deleteDimension = "Delete Dimension"
    public static let deleteNote = "Delete Note"
    public static let deleteAnnotations = "Delete Annotations"
    public static let changeDimension = "Change Dimension"
    public static let changeTolerance = "Change Tolerance"
    public static let editNote = "Edit Note"
    public static let changeNumberFormat = "Change Number Format"
    public static let moveCuttingLine = "Move Cutting Line"
    public static let moveDetailCircle = "Move Detail Circle"
    public static let changeDetailCircle = "Change Detail Circle"
    public static let addDatum = "Add Datum"
    public static let addFeatureControlFrame = "Add Feature Control Frame"
    public static let addSurfaceSymbol = "Add Surface Symbol"
    public static let changeDatumLetter = "Change Datum Letter"
    public static let changeFeatureControlFrame = "Change Feature Control Frame"
    public static let changeSurfaceSymbol = "Change Surface Symbol"
    public static let moveSymbol = "Move Symbol"
    public static let deleteSymbol = "Delete Symbol"
    public static let reattachSymbol = "Reattach Symbol"
    public static let editNotes = "Edit Notes"
    public static let changeEdgeBreak = "Change Edge Break"
    public static let changeGeneralSurface = "Change General Surface"

    public static let all: [String] = [
        addSheet, renameSheet, duplicateSheet, deleteSheet, moveSheet, changeSheetSize, editTitleBlock, changeStandard,
        addView, moveView, deleteView, changeScale, changeView, addDimension, addHoleCallout, addCentreMark, addCentreLine,
        addNote, addLeader, reattachDimension, removeLeader, moveDimension, moveNote, moveAnnotations, deleteDimension, deleteNote,
        deleteAnnotations, changeDimension, changeTolerance, editNote, changeNumberFormat, moveCuttingLine, moveDetailCircle,
        changeDetailCircle, addDatum, addFeatureControlFrame, addSurfaceSymbol, changeDatumLetter, changeFeatureControlFrame,
        changeSurfaceSymbol, moveSymbol, deleteSymbol, reattachSymbol, editNotes, changeEdgeBreak, changeGeneralSurface,
    ]
}
