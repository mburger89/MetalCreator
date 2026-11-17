/// The most a board file may ask of the reader (KI spec "Limits").
public struct KiCadLimits: Sendable {
    public var maxFileBytes = 256 << 20
    public var maxDepth = 64
    public var maxStringBytes = 1 << 20
    public var maxFootprints = 100_000
    public var maxPads = 1_000_000
    public var maxEdgeItems = 100_000
    /// Cancellation is asked every this many tokens.
    public var cancelEvery = 65_536

    public static let standard = KiCadLimits()

    public init() {}
}
