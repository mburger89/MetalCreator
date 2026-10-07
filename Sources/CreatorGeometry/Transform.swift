/// A rigid move: rotate about `rotationAxis` by `rotation`, then translate.
public struct Transform: Hashable, Sendable, Codable {
    public var translation: Vector3
    public var rotationAxis: Axis?
    public var rotation: Angle

    public init(translation: Vector3 = .zero, rotationAxis: Axis? = nil, rotation: Angle = Angle(radians: 0)) {
        self.translation = translation
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }

    public static let identity = Transform()
}
