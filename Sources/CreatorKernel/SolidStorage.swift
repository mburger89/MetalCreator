/// The kernel-private payload behind a `Solid` (an OCCT shape handle, or fake data).
public protocol SolidStorage: AnyObject, Sendable {
    /// A rough memory cost, used by the evaluator's cache budget.
    var estimatedBytes: Int { get }
}
