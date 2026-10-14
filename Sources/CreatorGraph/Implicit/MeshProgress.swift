/// Where a long meshing reports how far it has got (implicit spec §5.3): a fraction from 0 to 1, called from any thread. The export
/// sheet's progress bar listens; a run made by hand ignores it.
public struct MeshProgress: Sendable {
    private let report: @Sendable (Double) -> Void

    public init(_ report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    /// Progress that goes nowhere.
    public static let none = MeshProgress { _ in }

    /// Reports `fraction` held between 0 and 1; a NaN or other non-finite one is 0.
    public func callAsFunction(_ fraction: Double) {
        report(fraction.isFinite ? min(max(fraction, 0), 1) : 0)
    }
}
