/// What a `FacePick` names in a topology now (`Topology.resolution(of:)`).
public struct FaceResolution: Equatable, Sendable {
    /// The faces the pick names, in ID order; after narrowing, only the part chosen.
    public var faces: [FaceInfo]
    /// True when no face had all the pick's tags and `faces` is a part of the face the pick was made on, one
    /// operand's share of it.
    public var isNarrowed: Bool
    /// True when narrowed and the part is a guess: the pick recorded no position, or no single part lies in the
    /// plane the face was in. A caller says so, never silently (spec §5.3, rule 6).
    public var isAmbiguous: Bool

    public init(faces: [FaceInfo], isNarrowed: Bool = false, isAmbiguous: Bool = false) {
        self.faces = faces
        self.isNarrowed = isNarrowed
        self.isAmbiguous = isAmbiguous
    }
}
