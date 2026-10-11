import Foundation

extension Vector3 {
    /// This vector turned by `angle` about the line through the origin along `axis` (Rodrigues' formula). `axis`
    /// needn't be a unit vector; a zero one leaves the vector as it is.
    public func rotated(about axis: Vector3, by angle: Angle) -> Vector3 {
        guard let k = axis.normalized else { return self }
        let (sine, cosine) = (sin(angle.radians), cos(angle.radians))
        return self * cosine + k.cross(self) * sine + k * (k.dot(self) * (1 - cosine))
    }
}

extension Transform {
    /// Where `point` goes: turned about `rotationAxis` first, then moved by `translation`, the order
    /// `Kernel.transform` applies them in.
    public func applied(to point: Vector3) -> Vector3 {
        var moved = point
        if let axis = rotationAxis, rotation.radians != 0 {
            moved = axis.origin + (point - axis.origin).rotated(about: axis.direction, by: rotation)
        }
        return moved + translation
    }
}
