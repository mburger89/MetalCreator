import CreatorGeometry

/// How each face name is laid onto the cube (Fusion's convention): seen from outside, a face's text reads upright
/// and unmirrored, left to right along `right` with its top towards `up`, and `right × up` is the face's outward
/// normal.
/// - FRONT, RIGHT, BACK and LEFT read with +Z up: the turntable camera never rolls, so +Z is always up on screen.
/// - TOP reads with +Y up, the way the TOP view (yaw 0, looking down from the front) shows it.
/// - BOTTOM reads with −Y up. Rolling under from FRONT (the BOTTOM view, yaw 0, pitch −90°) turns screen-up from +Z
///   to −Y, so BOTTOM reads upright there and its top edge is the one shared with FRONT.
enum CubeLabelMapping {
    /// Half the text box's width, in face units (a face spans −1…1): the text spans 80% of the face.
    static let halfWidth = 0.8
    /// Half its height, keeping the atlas rect's shape so the text isn't stretched.
    static var halfHeight: Double { halfWidth * CubeLabelAtlas.rectAspect }

    /// The text's reading direction and its up, in world space, or `nil` for an edge or corner.
    static func axes(of face: ViewCubeRegion) -> (right: Vector3, up: Vector3)? {
        switch face {
        case .front: (Vector3(1, 0, 0), Vector3(0, 0, 1))
        case .right: (Vector3(0, 1, 0), Vector3(0, 0, 1))
        case .back: (Vector3(-1, 0, 0), Vector3(0, 0, 1))
        case .left: (Vector3(0, -1, 0), Vector3(0, 0, 1))
        case .top: (Vector3(1, 0, 0), Vector3(0, 1, 0))
        case .bottom: (Vector3(1, 0, 0), Vector3(0, -1, 0))
        default: nil
        }
    }

    /// Where `point` (on `face`, in cube units) falls in the face's text box: u runs 0…1 left to right along the
    /// text and v 0…1 top to bottom, as in the atlas. Points outside the box fall outside 0…1.
    static func uv(of point: Vector3, on face: ViewCubeRegion) -> SIMD2<Float>? {
        guard let axes = axes(of: face) else { return nil }
        let across = point.dot(axes.right) / halfWidth
        let upward = point.dot(axes.up) / halfHeight
        return SIMD2(Float((across + 1) / 2), Float((1 - upward) / 2))
    }
}
