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

public enum SweepOrientation: Int, Sendable { case frenet = 0, fixedBinormal = 1 }

public struct SweepOptions: Hashable, Sendable {
    public var orientation: SweepOrientation
    public var binormal: Vector3
    public var endScale: Double
    public var makesSolid: Bool

    public init(orientation: SweepOrientation = .frenet, binormal: Vector3 = .unitZ, endScale: Double = 1,
                makesSolid: Bool = false) {
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
