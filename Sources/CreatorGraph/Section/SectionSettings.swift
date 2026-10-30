import CreatorKernel

/// One of the three origin planes a section can be cut along.
public enum SectionOrigin: String, Codable, CaseIterable, Sendable { case xy, yz, xz }

/// What the section plane is measured from: an origin plane, or a picked face (kept by its tags, as a `FacePick` is).
/// Encoded as `{"origin":"xy"}` or `{"face":{…}}`.
public enum SectionReference: Equatable, Sendable, Codable {
    case origin(SectionOrigin)
    case face(FacePick)

    private enum CodingKeys: String, CodingKey { case origin, face }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let origin = try container.decodeIfPresent(SectionOrigin.self, forKey: .origin) {
            self = .origin(origin)
        } else {
            self = .face(try container.decode(FacePick.self, forKey: .face))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .origin(let origin): try container.encode(origin, forKey: .origin)
        case .face(let pick): try container.encode(pick, forKey: .face)
        }
    }
}

/// The section view's settings, saved with the document's view state (never in its content: changing them is no edit
/// and has no undo step, like the camera).
public struct SectionSettings: Equatable, Sendable, Codable {
    public var isOn: Bool
    public var reference: SectionReference
    /// Distance of the plane from its reference, in millimetres.
    public var offset: Double
    public var isFlipped: Bool

    public init(isOn: Bool, reference: SectionReference, offset: Double, isFlipped: Bool) {
        self.isOn = isOn
        self.reference = reference
        self.offset = offset
        self.isFlipped = isFlipped
    }
}
