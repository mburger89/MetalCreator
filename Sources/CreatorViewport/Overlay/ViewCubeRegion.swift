import CreatorGeometry

/// A clickable part of the view cube (spec §6.3): a face, an edge or a corner, named by the outward direction
/// of its cell, each component −1, 0 or 1. +X is RIGHT, −Y is FRONT, +Z is TOP.
public struct ViewCubeRegion: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case face, edge, corner
    }

    public let x: Int
    public let y: Int
    public let z: Int

    /// `nil` unless every component is −1, 0 or 1 and at least one isn't 0.
    public init?(x: Int, y: Int, z: Int) {
        guard [x, y, z].allSatisfy({ (-1...1).contains($0) }), (x, y, z) != (0, 0, 0) else { return nil }
        self.init(checkedX: x, y: y, z: z)
    }

    private init(checkedX x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let top = ViewCubeRegion(checkedX: 0, y: 0, z: 1)
    public static let bottom = ViewCubeRegion(checkedX: 0, y: 0, z: -1)
    public static let front = ViewCubeRegion(checkedX: 0, y: -1, z: 0)
    public static let back = ViewCubeRegion(checkedX: 0, y: 1, z: 0)
    public static let left = ViewCubeRegion(checkedX: -1, y: 0, z: 0)
    public static let right = ViewCubeRegion(checkedX: 1, y: 0, z: 0)
    /// The front-right-top corner: the default isometric view.
    public static let isometric = ViewCubeRegion(checkedX: 1, y: -1, z: 1)
    public static let faces: [ViewCubeRegion] = [.top, .bottom, .front, .back, .left, .right]

    public var kind: Kind {
        switch [x, y, z].filter({ $0 != 0 }).count {
        case 1: .face
        case 2: .edge
        default: .corner
        }
    }

    /// The unit vector the region faces.
    public var direction: Vector3 {
        let v = Vector3(Double(x), Double(y), Double(z))
        return v * (1 / v.length)
    }

    public var label: String? {
        switch (x, y, z) {
        case (0, 0, 1): "TOP"
        case (0, 0, -1): "BOTTOM"
        case (0, -1, 0): "FRONT"
        case (0, 1, 0): "BACK"
        case (-1, 0, 0): "LEFT"
        case (1, 0, 0): "RIGHT"
        default: nil
        }
    }

    /// The camera this region asks for. It keeps the target and distance, and looks from `direction`
    /// (TOP and BOTTOM with yaw 0). A face also switches to orthographic. An edge or corner keeps the projection.
    public func pose(from current: CameraPose) -> CameraPose {
        var pose = current
        if let orientation = CameraNavigation.orientation(lookingFrom: direction, fallbackYaw: 0) {
            pose.yaw = orientation.yaw
            pose.pitch = orientation.pitch
        }
        if kind == .face { pose.projection = .orthographic }
        return pose
    }
}
