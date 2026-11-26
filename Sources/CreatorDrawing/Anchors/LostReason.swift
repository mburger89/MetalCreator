import CreatorKernel
import Foundation

/// Why an annotation can no longer be measured or drawn (plan R4).
public enum LostReason: Error, Hashable, Sendable {
    case missing
    case several(Int)
    case severalFaces(Int)
    case notLineOrCircle
    case cornerGone
    case notCylinder
    case outlineTurned
    case foreshortened
    case notAHole
    case sourceRemoved
    case viewFailed(String)
    case noPart
    case refused(String)

    public var sentence: String {
        switch self {
        case .missing: "What it was attached to is no longer in the part."
        case .several(let count): "What it was attached to now fits \(Self.number(count)) edges, and a dimension never guesses which."
        case .severalFaces(let count): "What it was attached to now fits \(Self.number(count)) faces, and a dimension never guesses which."
        case .notLineOrCircle: "What it measured is no longer a straight line or a circle."
        case .cornerGone: "The two edges that met at its corner no longer meet at one point."
        case .notCylinder: "The face it was attached to is no longer a cylinder."
        case .outlineTurned: "The cylinder it was attached to has turned, so the side of its outline can't be told."
        case .foreshortened: "What it measures now runs at an angle to the view, so its size here would be foreshortened."
        case .notAHole: "The hole it called out is no longer a plain, counterbored or countersunk hole."
        case .sourceRemoved: DrawingProjector.removedSentence
        case .viewFailed(let message): message
        case .noPart: "This view has no part to measure."
        case .refused(let sentence): sentence
        }
    }

    private static func number(_ count: Int) -> String { count.formatted(.number.locale(.messages)) }
}
