import Foundation

/// A kernel failure, with a message written for the person editing the graph.
public enum KernelError: Error, Equatable, Sendable {
    case invalidInput(String)
    case operationFailed(operation: String, reason: String)
    case filletFailed(radius: Double, maxRadius: Double?, reason: String)
    case unsupported(String)
    case exportFailed(String)

    public var userMessage: String {
        switch self {
        case .invalidInput(let message):
            message
        case .operationFailed(let operation, let reason):
            "\(operation.capitalized) failed: \(reason)"
        case .filletFailed(let radius, let maxRadius?, _):
            "Radius \(radius.formatted()) mm is too large for the selected edges (max ≈ \(maxRadius.formatted()) mm)."
        case .filletFailed(let radius, nil, let reason):
            "Radius \(radius.formatted()) mm could not be applied: \(reason)"
        case .unsupported(let operation):
            "\(operation.capitalized) isn't supported by this kernel yet."
        case .exportFailed(let reason):
            "Export failed: \(reason)"
        }
    }
}
