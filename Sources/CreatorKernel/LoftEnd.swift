/// How a loft leaves a face of the part (loft end conditions spec): Free is today's smooth loft, Tangent (G1) and
/// Curvature (G2) continue the part's adjacent faces across each edge of the face's loop.
public enum LoftContinuity: Int, Sendable, Hashable, Codable, CaseIterable {
    case free = 0
    case tangent = 1
    case curvature = 2
}

/// One end of a loft taken from a face of the part: the face (its outer loop is the loft's first or last section), how
/// the loft leaves it, and the tangency weight (greater than 0; the node offers 0.1 to 2) that scales the across-tangent
/// length as the fillet's weight does. A weight does nothing at `.free`.
public struct LoftEnd: Sendable, Hashable {
    public var face: FaceID
    public var continuity: LoftContinuity
    public var weight: Double

    public init(face: FaceID, continuity: LoftContinuity, weight: Double = 1) {
        self.face = face
        self.continuity = continuity
        self.weight = weight
    }
}

public extension KernelError {
    /// A ruled (straight-sided) loft with a face end: the end conditions are for the smooth loft.
    static let ruledLoftEnds = KernelError.invalidInput("Straight sides can't have end conditions.")
    static let loftCannotMeetTangent = KernelError.invalidInput("The loft can't meet the part tangent (G1) here.")
    static let loftCannotMeetCurvature = KernelError.invalidInput("The loft can't meet the part with matching curvature (G2) here.")
    static let loftWeightTooLarge = KernelError.invalidInput("The tangency weight is too large for this loft.")
    static let loftEndFaceNotFlat = KernelError.invalidInput("The loft's end face must be flat.")
    static let loftFaceVanished = KernelError.invalidInput("That face no longer exists.")

    /// A face end with no part to take it from.
    static func loftEndWithoutPart(start: Bool) -> KernelError {
        .invalidInput("Pick a face of the part for the loft's \(start ? "start" : "end").")
    }

    /// The sentences the loft shim words for a person, which pass through unchanged.
    static let loftShimSentences: Set<String> = [
        "The loft can't meet the part tangent (G1) here.",
        "The loft can't meet the part with matching curvature (G2) here.",
        "The tangency weight is too large for this loft.",
        "The loft's end face must be flat.",
        "That face no longer exists.",
        "Every loft section needs the same number of segments.",
        "The tangency weight must be greater than 0.",
        "A loft can't use profiles with holes yet.",
        "The profile has no segments.",
        "The loft's sections lie on top of each other.",
        "The loft end condition is not known.",
        "The loft could not be built.",
        "A loft needs at least two sections.",
    ]
}

public extension Kernel {
    /// The checks every kernel makes of a loft's ends before it looks at geometry: no face end on a ruled loft, a part
    /// for every face end, a weight above 0 wherever there is a condition, and at least two sections in all.
    static func validateLoftEnds(sections: Int, ruled: Bool, part: Solid?, start: LoftEnd?, end: LoftEnd?) throws {
        let ends = [(start, true), (end, false)].compactMap { end, isStart in end.map { ($0, isStart) } }
        if ruled, !ends.isEmpty { throw KernelError.ruledLoftEnds }
        for (loftEnd, isStart) in ends {
            guard let part else { throw KernelError.loftEndWithoutPart(start: isStart) }
            guard part.topology.faces.contains(where: { $0.id == loftEnd.face }) else { throw KernelError.loftFaceVanished }
            if loftEnd.continuity != .free, !(loftEnd.weight > 0 && loftEnd.weight.isFinite) {
                throw KernelError.weightNotPositive
            }
        }
        guard sections + ends.count >= 2 else { throw KernelError.invalidInput("A loft needs at least two sections.") }
    }
}
