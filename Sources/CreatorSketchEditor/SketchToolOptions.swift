/// What the command tools use besides the clicks (sketcher spec §3: "the count is a command argument"), typed in the
/// inspector while the tool is active. Not saved: each new sketch session starts from these defaults.
public struct SketchToolOptions: Hashable, Sendable {
    /// The Fillet tool's radius, in millimetres; the arc's radius dimension starts at it.
    public var filletRadius = 5.0
    /// How many instances the Pattern tool makes, the selection included.
    public var patternCount = 3
    /// A linear pattern's step between instances, in millimetres.
    public var patternSpacing = 20.0

    public init() {}
}
