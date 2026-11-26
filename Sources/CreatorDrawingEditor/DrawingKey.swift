import CreatorGeometry

/// The keys the drawing canvas answers. `nudge` carries the move in sheet millimetres: the view sends 1 mm per arrow, 10 with Shift; `isRepeat` is a held key's auto-repeat, which joins the run's undo step.
public enum DrawingKey: Hashable, Sendable {
    case fit
    case delete
    case nudge(Vector2, isRepeat: Bool)
    case escape
    /// A tool's letter: D, H, M, L, N, S, E or U.
    case tool(DrawingTool)
    /// Return: finishes a cutting line.
    case finish
}

/// The modifiers the editor reads; graph-free, as `CanvasModifiers` is for the graph. The views map MetalUI's into it.
public struct SheetModifiers: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = SheetModifiers(rawValue: 1)
    public static let primary = SheetModifiers(rawValue: 2)
}
