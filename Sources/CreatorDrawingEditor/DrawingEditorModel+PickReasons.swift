import CreatorDrawing

extension DrawingEditorModel {
    static func lowered(_ text: String) -> String {
        text.first.map { $0.lowercased() + text.dropFirst() } ?? text
    }

    /// Why a line being picked now can't hold an annotation, worded for the moment of the pick.
    static func pickReason(_ reason: LostReason) -> String {
        switch reason {
        case .notLineOrCircle: "it isn't a straight line or a circle."
        case .foreshortened: "it runs at an angle to the view, so its size here would be foreshortened."
        case .notAHole: "it isn't a plain, counterbored or countersunk hole."
        case .notStraight: "it isn't a straight line."
        case .turnedAway: "this view doesn't show it the way the symbol needs."
        case .partNotShown: "it isn't in this view."
        case .notCylinder: "it isn't a cylinder."
        case .outlineTurned: "the side of its outline can't be told."
        case .cornerGone: "its edges don't meet at one point."
        default: namingReason(reason)
        }
    }

    private static func namingReason(_ reason: LostReason) -> String {
        switch reason {
        case .missing: "nothing in the part matches it."
        case .several(let count): "it fits \(count) edges, and a drawing never guesses which."
        case .severalFaces(let count): "it fits \(count) faces, and a drawing never guesses which."
        case .noPart: "this view shows no part."
        default: lowered(reason.sentence)
        }
    }
}
