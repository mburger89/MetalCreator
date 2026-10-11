import CreatorGeometry

extension Transform {
    /// Throws `KernelError.invalidInput` for a move no kernel can build: a non-finite number, a
    /// rotation without an axis, or an axis without a direction.
    public func validate() throws {
        guard translation.isFinite, rotation.radians.isFinite else {
            throw KernelError.invalidInput("The move or rotation must be a finite number.")
        }
        if rotation.radians != 0, rotationAxis == nil {
            throw KernelError.invalidInput("A rotation needs an axis.")
        }
        if let axis = rotationAxis, axis.direction.normalized == nil {
            throw KernelError.invalidInput("The rotation axis needs a direction.")
        }
    }
}
