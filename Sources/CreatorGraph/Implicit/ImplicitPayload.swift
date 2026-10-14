import CreatorGeometry

/// What `CreatorGraph` knows of an implicit solid (implicit spec §2.1). The solid itself, `ImplicitSolid`, lives in
/// `CreatorImplicit`, which depends on this module for `Field`; a value that flows along a wire, or sits in a field leaf,
/// can't name it, so it is held as this protocol and read back with `ImplicitReference.solid` in `CreatorImplicit`.
public protocol ImplicitPayload: Sendable {
    /// A one-line recipe such as `sphere(radius 10 mm)`, like `Field.description` (implicit spec §2.1).
    var summary: String { get }
    /// 64 plus 32 per node, plus any baked distance blocks (implicit spec §2.1).
    var estimatedBytes: Int { get }
    /// A box that contains the surface.
    var payloadBounds: BoundingBox { get }
    /// A constant L with |f(a) − f(b)| ≤ L · |a − b| for all a and b; at least 1.
    var lipschitz: Double { get }
    /// The signed distance in millimetres at `point`: negative inside, 0 on the surface (the reference evaluation, in Double).
    func signedDistance(at point: Vector3) -> Double
    /// The same at each of `points`. A payload that has set-up work to share between points overrides it.
    func signedDistances(at points: [Vector3]) -> [Double]
    /// What the inspector shows besides the recipe: for a solid made by To Implicit, how long the bake took and how much memory it
    /// holds (implicit spec §5.2).
    var inspectorFacts: [PayloadFact] { get }
    /// Whether `other` is the same solid (the previews ask "is this what I last sampled?").
    func isEqual(to other: any ImplicitPayload) -> Bool
    func hashPayload(into hasher: inout Hasher)
}

extension ImplicitPayload {
    public var inspectorFacts: [PayloadFact] { [] }
    public func signedDistances(at points: [Vector3]) -> [Double] { points.map { signedDistance(at: $0) } }
}

extension ImplicitPayload where Self: Hashable {
    public func isEqual(to other: any ImplicitPayload) -> Bool { (other as? Self) == self }
    public func hashPayload(into hasher: inout Hasher) { hash(into: &hasher) }
}
