import CreatorGeometry

/// The keys the drawing canvas answers. `nudge` carries the move in sheet millimetres: the view sends 1 mm per arrow, 10 with Shift.
public enum DrawingKey: Hashable, Sendable {
    case fit
    case delete
    case nudge(Vector2)
    case escape
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
