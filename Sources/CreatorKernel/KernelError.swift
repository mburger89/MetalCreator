import Foundation

/// A kernel failure, with a message written for the person editing the graph.
public enum KernelError: Error, Equatable, Sendable {
    case invalidInput(String)
    case operationFailed(operation: String, reason: String)
    case filletFailed(radius: Double, maxRadius: Double?, reason: String)
    case unsupported(String)
    case exportFailed(String)

    /// The refusal every kernel gives a loft through profiles with holes, and the Loft node gives it first.
    public static let loftWithHoles = KernelError.invalidInput("A loft can't use profiles with holes yet.")

    public var userMessage: String {
        switch self {
        case .invalidInput(let message):
            message
        case .operationFailed(let operation, let reason):
            "\(operation.sentenceCased) failed: \(reason)"
        case .filletFailed(let radius, let maxRadius?, _):
            "Radius \(radius.formatted(.number.precision(.fractionLength(0...2)))) mm is too large for the selected edges "
                + "(max ≈ \(maxRadius.formatted(.number.precision(.fractionLength(0...2)))) mm)."
        case .filletFailed(let radius, nil, let reason):
            "Radius \(radius.formatted(.number.precision(.fractionLength(0...2)))) mm could not be applied: \(reason)"
        case .unsupported(let operation):
            "\(operation.sentenceCased) isn't supported by this kernel yet."
        case .exportFailed(let reason):
            "Export failed: \(reason)"
        }
    }
}

private extension String {
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}
