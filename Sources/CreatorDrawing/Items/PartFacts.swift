/// What the title block's facts know about one part (DR-5 R5): its name, how many solid values its Output holds and whether its
/// Output is gone (the name is then the remembered one, or "?" when none was).
public struct PartFacts: Hashable, Sendable {
    public var name: String
    /// The number of solids and sheets the Output holds; nil ("?") without a result or for a removed part.
    public var quantity: Int?
    public var isRemoved: Bool

    public init(name: String, quantity: Int?, isRemoved: Bool) {
        self.name = name
        self.quantity = quantity
        self.isRemoved = isRemoved
    }
}
