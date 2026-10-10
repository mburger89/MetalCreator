/// The fixed names of the sketch editor's undo steps ("Add Line", "Change Dimension"). Each says what kind of edit it
/// was and never contains text the person typed (a dimension's name) or a number: the host shows it as "Undo Add Line"
/// in the Edit menu. `SketchCommit.description` is the finer, per-edit text ("Rename d1 to Plate width") and is for tests
/// and logs, not for menus.
public enum SketchStepName {
    public static let addPoint = "Add Point"
    public static let addLine = "Add Line"
    public static let addCircle = "Add Circle"
    public static let addArc = "Add Arc"
    public static let addConstraint = "Add Constraint"
    public static let addDimension = "Add Dimension"
    public static let changeDimension = "Change Dimension"
    public static let renameDimension = "Rename Dimension"
    public static let exposeDimension = "Expose Dimension"
    public static let stopExposingDimension = "Stop Exposing Dimension"
    public static let makeDimensionDriving = "Make Dimension Driving"
    public static let makeDimensionReference = "Make Dimension Reference"
    public static let makeConstruction = "Make Construction"
    public static let makeNormalGeometry = "Make Normal Geometry"
    public static let movePoint = "Move Point"
    public static let delete = "Delete"
    public static let trim = "Trim"
    public static let extend = "Extend"
    public static let fillet = "Fillet"
    public static let mirror = "Mirror"
    public static let linearPattern = "Linear Pattern"
    public static let circularPattern = "Circular Pattern"
    public static let project = "Project"
    /// What a commit made without a name is called.
    public static let editSketch = "Edit Sketch"
}
