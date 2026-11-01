import CreatorGeometry

public struct FaceInfo: Hashable, Sendable {
    public var id: FaceID
    public var kind: SurfaceKind
    /// The normal of a planar face, or the axis direction of a cylinder or cone.
    public var normal: Vector3?
    public var area: Double
    public var centroid: Vector3
    public var tags: Set<TopoTag>
    /// A cylinder's radius in millimetres; nil for every other face.
    public var radius: Double?
    /// A point on a cylinder's axis; nil for every other face.
    public var axisPoint: Vector3?

    public init(id: FaceID, kind: SurfaceKind, normal: Vector3?, area: Double, centroid: Vector3, tags: Set<TopoTag>,
                radius: Double? = nil, axisPoint: Vector3? = nil) {
        self.id = id
        self.kind = kind
        self.normal = normal
        self.area = area
        self.centroid = centroid
        self.tags = tags
        self.radius = radius
        self.axisPoint = axisPoint
    }
}
