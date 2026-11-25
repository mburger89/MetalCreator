import CreatorGeometry
import CreatorKernel

public enum ViewKind: String, Sendable, Codable {
    case base
    case projected
    case section
    case detail
    case auxiliary
}

public enum AlignmentAxis: String, Sendable, Codable {
    case horizontal
    case vertical
}

/// A projected view's tie to its parent: the two share a coordinate along `axis`.
public struct ViewAlignment: Hashable, Sendable, Codable {
    public var parent: ViewID
    public var axis: AlignmentAxis

    public init(parent: ViewID, axis: AlignmentAxis) {
        self.parent = parent
        self.axis = axis
    }
}

/// One view of an Output on a sheet. `center` is in sheet millimetres (plan R7); a nil `scale` follows the sheet's.
public struct DrawingView: Hashable, Sendable, Codable, Identifiable {
    public var id: ViewID
    public var kind: ViewKind
    public var source: NodeID
    public var orientation: ViewOrientation
    public var scale: DrawingScale?
    public var center: Vector2
    public var alignment: ViewAlignment?
    public var showsHidden: Bool
    public var showsTangent: Bool
    public var showsLabel: Bool
    /// Whether the view draws its automatic centre marks (missing in an older file reads true).
    public var showsCentreMarks: Bool
    /// What a section, detail or auxiliary view was made from; set exactly for those kinds (DR-3 R10).
    public var derivation: ViewDerivation?
    /// A derived view's letter (R7).
    public var letter: String?

    public init(
        id: ViewID = ViewID(), kind: ViewKind, source: NodeID, orientation: ViewOrientation, scale: DrawingScale? = nil,
        center: Vector2, alignment: ViewAlignment? = nil, showsHidden: Bool = false, showsTangent: Bool = true,
        showsLabel: Bool = false, showsCentreMarks: Bool = true,
        derivation: ViewDerivation? = nil, letter: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.orientation = orientation
        self.scale = scale
        self.center = center
        self.alignment = alignment
        self.showsHidden = showsHidden
        self.showsTangent = showsTangent
        self.showsLabel = showsLabel
        self.showsCentreMarks = showsCentreMarks
        self.derivation = derivation
        self.letter = letter
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, source, orientation, scale, center, alignment, showsHidden, showsTangent, showsLabel, showsCentreMarks
        case derivation, letter
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ViewID.self, forKey: .id)
        kind = try c.decode(ViewKind.self, forKey: .kind)
        source = try c.decode(NodeID.self, forKey: .source)
        orientation = try c.decode(ViewOrientation.self, forKey: .orientation)
        // A damaged override is dropped, so the view follows its sheet's scale.
        scale = try c.decodeIfPresent(DrawingScale.self, forKey: .scale).flatMap { $0.isValid ? $0 : nil }
        center = try c.decode(Vector2.self, forKey: .center)
        alignment = try c.decodeIfPresent(ViewAlignment.self, forKey: .alignment)
        showsHidden = try c.decodeIfPresent(Bool.self, forKey: .showsHidden) ?? false
        showsTangent = try c.decodeIfPresent(Bool.self, forKey: .showsTangent) ?? true
        showsLabel = try c.decodeIfPresent(Bool.self, forKey: .showsLabel) ?? false
        showsCentreMarks = try c.decodeIfPresent(Bool.self, forKey: .showsCentreMarks) ?? true
        // A derivation of an unknown shape reads as missing; the sheet then drops a derived view that lacks one.
        derivation = (try? c.decodeIfPresent(ViewDerivation.self, forKey: .derivation)) ?? nil
        letter = try c.decodeIfPresent(String.self, forKey: .letter)
    }
}
