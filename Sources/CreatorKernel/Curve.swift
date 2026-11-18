import CreatorGeometry

/// A 3D curve made by a kernel (NURBS spec): one or more pieces joined end to end. Like `Solid`, the geometry lives in
/// kernel-private `storage`; the rest is what the graph and the viewport read.
public final class Curve: Sendable {
    public let pieceCount: Int
    public let isClosed: Bool
    /// The plane a planar curve lies in, else `nil`.
    public let plane: Plane?
    public let length: Double
    public let bounds: BoundingBox
    /// Points for display, within 0.01 mm and 0.5 rad of the curve.
    public let polyline: [Vector3]
    public let storage: any SolidStorage

    public init(pieceCount: Int, isClosed: Bool, plane: Plane?, length: Double, bounds: BoundingBox,
                polyline: [Vector3], storage: any SolidStorage) {
        self.pieceCount = pieceCount
        self.isClosed = isClosed
        self.plane = plane
        self.length = length
        self.bounds = bounds
        self.polyline = polyline
        self.storage = storage
    }

    public var estimatedBytes: Int { 128 + polyline.count * 24 + storage.estimatedBytes }
}

public enum SweepOrientation: Int, Sendable { case frenet = 0, fixedBinormal = 1, secondRail = 2, guideSurface = 3 }

/// What a rail or guide-surface sweep follows besides its path.
public enum SweepGuide: Sendable {
    case rail(Curve)
    case surface(Solid)
}

public struct SweepOptions: Hashable, Sendable {
    public var orientation: SweepOrientation
    public var binormal: Vector3
    public var endScale: Double
    public var makesSolid: Bool
    /// Degrees the profile turns from the path's start to its end (Frenet and Fixed only).
    public var twist: Double

    public init(orientation: SweepOrientation = .frenet, binormal: Vector3 = .unitZ, endScale: Double = 1,
                makesSolid: Bool = false, twist: Double = 0) {
        self.twist = twist
        self.orientation = orientation
        self.binormal = binormal
        self.endScale = endScale
        self.makesSolid = makesSolid
    }
}

/// What a model file holds: solids, sheets (open surfaces) and free curves, read in millimetres. `fileUnitMillimetres` is the length unit the
/// file was written in, in millimetres, or 0 when the file names none OpenCascade can give a factor for.
public struct ImportedShapes: Sendable {
    public var solids: [Solid]
    public var sheets: [Solid]
    public var curves: [Curve]
    public var fileUnitMillimetres: Double

    public init(solids: [Solid] = [], sheets: [Solid] = [], curves: [Curve] = [], fileUnitMillimetres: Double = 1) {
        self.solids = solids
        self.sheets = sheets
        self.curves = curves
        self.fileUnitMillimetres = fileUnitMillimetres
    }
}

/// How a boundary patch meets the surface along its bounding edges (NS-2): position (G0), tangent (G1) or curvature (G2).
public enum PatchContinuity: Int, Sendable { case g0 = 0, g1 = 1, g2 = 2 }

/// What bounds a boundary patch: the edges of `curves` followed by `edges` of `part`, which must chain into one closed loop.
public struct PatchBoundary: Sendable {
    public var curves: [Curve]
    public var edges: [EdgeID]
    public var part: Solid?

    public init(curves: [Curve], edges: [EdgeID], part: Solid?) {
        self.curves = curves
        self.edges = edges
        self.part = part
    }
}

/// A boundary patch: a sheet of one face, and the warnings it earned.
public struct PatchResult: Sendable {
    public var sheet: Solid
    public var warnings: [String]

    public init(sheet: Solid, warnings: [String] = []) {
        self.sheet = sheet
        self.warnings = warnings
    }
}
