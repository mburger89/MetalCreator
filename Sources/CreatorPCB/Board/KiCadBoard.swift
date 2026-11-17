import CreatorGeometry

/// A KiCad board read as values: millimetres, y up (the file's y is negated as it is read).
public struct KiCadBoard: Sendable {
    /// `(version N)`; 20201115 when absent.
    public var version: Int
    /// `(generator …)` or `(host …)`.
    public var generator: String?
    /// nil: the node warns and uses 1.6.
    public var thickness: Double?
    public var copperLayers: Int
    public var auxAxisOrigin: Vector2?
    /// Edge.Cuts items of the board and of its footprints, already placed.
    public var edgeItems: [EdgeItem]
    public var footprints: [Footprint]
    public var vias: [DrilledHole]
    /// The board's `(embedded_files …)` entries of type model, in file order (KiCad 9+; empty before version 20240706).
    public var embeddedModels: [EmbeddedFile]

    public static let newestKnownVersion = 20_261_031

    /// How far apart two outline ends may be and still join (facts §1).
    public var chainingTolerance: Double {
        if version <= KiCadVersion.kicad5 { return 0.005 }
        if version < KiCadVersion.kicad7 { return 0.02 }
        return 0.01
    }

    public init(version: Int = KiCadVersion.missing, generator: String? = nil, thickness: Double? = nil, copperLayers: Int = 0,
                auxAxisOrigin: Vector2? = nil, edgeItems: [EdgeItem] = [], footprints: [Footprint] = [], vias: [DrilledHole] = [],
                embeddedModels: [EmbeddedFile] = []) {
        self.version = version
        self.generator = generator
        self.thickness = thickness
        self.copperLayers = copperLayers
        self.auxAxisOrigin = auxAxisOrigin
        self.edgeItems = edgeItems
        self.footprints = footprints
        self.vias = vias
        self.embeddedModels = embeddedModels
    }
}

public struct EdgeItem: Sendable, Hashable {
    public enum Shape: Sendable, Hashable {
        case line(Vector2, Vector2)
        case arc(start: Vector2, mid: Vector2, end: Vector2)
        case circle(center: Vector2, radius: Double)
        case bezier(Vector2, Vector2, Vector2, Vector2)
    }

    public var shape: Shape
    /// "edge:<uuid or tstamp>", else "edge:<kind>:<coordinates to 1 nm>"; a rectangle's or polygon's pieces add ":<k>".
    public var identity: String

    public init(shape: Shape, identity: String) {
        self.shape = shape
        self.identity = identity
    }
}

public struct Footprint: Sendable {
    public var reference: String
    /// "MountingHole:MountingHole_3.2mm_M3".
    public var libraryID: String
    public var uuid: String?
    public var isBack: Bool
    public var place: Placement2D
    public var holes: [DrilledHole]
    /// Every pad, SMD ones too.
    public var padCount: Int
    public var models: [ModelReference]
    /// The footprint's own `(embedded_files …)` models (a board's footprints usually carry none; the board's table holds them).
    public var embeddedModels: [EmbeddedFile] = []
    /// "fp:<token>" (the reference when unique, else the uuid, else the place in the file), filled by the key assigner; "" when read.
    public var identity = ""

    public init(reference: String, libraryID: String, uuid: String?, isBack: Bool, place: Placement2D,
                holes: [DrilledHole], padCount: Int? = nil, models: [ModelReference]) {
        self.reference = reference
        self.libraryID = libraryID
        self.uuid = uuid
        self.isBack = isBack
        self.place = place
        self.holes = holes
        self.padCount = padCount ?? holes.count
        self.models = models
    }
}

public struct DrilledHole: Sendable, Hashable {
    public var center: Vector2
    /// Round: the drill; oval: the smaller of width and height.
    public var diameter: Double
    /// Oval: the larger of width and height (centre to centre plus the diameter is the overall length); nil for round.
    public var slotLength: Double?
    /// Degrees, the slot's long axis from +x.
    public var angle: Double
    public var isPlated: Bool
    /// "" for none; vias have none.
    public var padNumber: String
    /// Filled by the key assigner; "" when read.
    public var identity: String
    /// A via's `(uuid …)` or `(tstamp …)`; nil for pads and when absent.
    public var uuid: String?

    public init(center: Vector2, diameter: Double, slotLength: Double? = nil, angle: Double = 0, isPlated: Bool,
                padNumber: String = "", identity: String = "", uuid: String? = nil) {
        self.uuid = uuid
        self.center = center
        self.diameter = diameter
        self.slotLength = slotLength
        self.angle = angle
        self.isPlated = isPlated
        self.padNumber = padNumber
        self.identity = identity
    }
}

public struct ModelReference: Sendable, Hashable {
    public var path: String
    public var offset: Vector3
    public var scale: Vector3
    public var rotation: Vector3
    public var isHidden: Bool

    public init(path: String, offset: Vector3, scale: Vector3, rotation: Vector3, isHidden: Bool) {
        self.path = path
        self.offset = offset
        self.scale = scale
        self.rotation = rotation
        self.isHidden = isHidden
    }
}

/// A model stored in the board: its name and its base64 text, undecoded (one copy of the reader's string).
public struct EmbeddedFile: Sendable, Hashable {
    public var name: String
    /// Empty for KiCad 9.0.0's `(data)` writer bug.
    public var base64: String

    public init(name: String, base64: String) {
        self.name = name
        self.base64 = base64
    }
}
