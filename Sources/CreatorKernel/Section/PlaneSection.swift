import CreatorGeometry

/// The cross-section of a solid or a mesh by a plane (section analysis part B): the regions the plane cuts out of the material, each with
/// its triangles for filling and its boundary for outlining, and any outline that did not close (meshes only).
public struct PlaneSection: Hashable, Sendable {
    public var regions: [SectionRegion]
    /// Loops that did not close (meshes only).
    public var openOutlines: [[Vector3]]

    public init(regions: [SectionRegion] = [], openOutlines: [[Vector3]] = []) {
        self.regions = regions
        self.openOutlines = openOutlines
    }

    /// No regions and no open outlines.
    public var isEmpty: Bool { regions.isEmpty && openOutlines.isEmpty }
}

/// One connected piece of material in a section: a filled area with holes.
public struct SectionRegion: Hashable, Sendable {
    /// Points on the plane.
    public var positions: [Vector3]
    /// Three indices into `positions` per triangle.
    public var triangles: [UInt32]
    /// The outer loop and the holes, in any order.
    public var boundary: [SectionPiece]

    public init(positions: [Vector3], triangles: [UInt32], boundary: [SectionPiece]) {
        self.positions = positions
        self.triangles = triangles
        self.boundary = boundary
    }
}

/// One piece of a region's boundary.
public struct SectionPiece: Hashable, Sendable {
    /// The exact line or circle arc when known.
    public var curve: EdgeCurve?
    /// Always present, for drawing.
    public var polyline: [Vector3]
    /// The solid's face this piece lies on.
    public var sourceFace: FaceID?

    public init(curve: EdgeCurve?, polyline: [Vector3], sourceFace: FaceID?) {
        self.curve = curve
        self.polyline = polyline
        self.sourceFace = sourceFace
    }
}
