import Foundation

/// A kernel failure, with a message written for the person editing the graph.
public enum KernelError: Error, Equatable, Sendable {
    case invalidInput(String)
    case operationFailed(operation: String, reason: String)
    case filletFailed(radius: Double, maxRadius: Double?, reason: String)
    /// A curvature-continuous fillet whose strips could not be made G2; `largest` is the largest radius that works.
    case notCurvatureContinuous(radius: Double, largest: Double?)
    case unsupported(String)
    case exportFailed(String)

    /// The refusal every kernel gives a loft through profiles with holes, and the Loft node gives it first.
    public static let loftWithHoles = KernelError.invalidInput("A loft can't use profiles with holes yet.")

    /// What a kernel that only builds lines and arcs says to a profile with a spline.
    public static let splinesUnsupported = KernelError.invalidInput("Splines aren't supported by this kernel yet.")

    /// What `KernelUnavailable` answers to every operation: this platform has no geometry kernel yet.
    public static let unavailable = KernelError.invalidInput("Geometry isn't available on this platform yet.")

    /// What a G2 fillet says when its strips miss the promised continuity (G2 surfacing spec, G-b).
    public static let notCurvatureContinuousSentence = "The fillet can't be made curvature continuous at this radius."

    /// What every kernel says to a curvature-continuous fillet whose tangency weight is not a positive number.
    public static let weightNotPositive = KernelError.invalidInput("The tangency weight must be greater than 0.")

    /// The message, with its numbers in `Locale.messages`.
    public var userMessage: String { message(locale: .messages) }

    /// The message with its numbers written in `locale`. Only `userMessage` and the tests call it.
    func message(locale: Locale) -> String {
        switch self {
        case .invalidInput(let message):
            message
        case .operationFailed(let operation, let reason):
            "\(operation.sentenceCased) failed: \(reason)"
        case .filletFailed(let radius, let maxRadius?, _):
            "Radius \(radius.millimetreText(locale: locale)) mm is too large for the selected edges "
                + "(max ≈ \(maxRadius.millimetreText(locale: locale)) mm)."
        case .filletFailed(let radius, nil, let reason):
            "Radius \(radius.millimetreText(locale: locale)) mm could not be applied: \(reason)"
        case .notCurvatureContinuous(let radius, let largest):
            Self.notCurvatureContinuousSentence + (largest.map {
                " " + KernelError.filletFailed(radius: radius, maxRadius: $0, reason: "").message(locale: locale)
            } ?? "")
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
