import CreatorKernel

extension ViewportModel {
    /// The tessellation the viewport holds for `solid`, at `displayTolerance`: its vertices are what a host samples a field at
    /// for `ViewportItem.fieldValues`. It is there once a scene holding the solid has loaded (`waitForMeshes()`), and `nil`
    /// for a solid the viewport has not been shown.
    public func displayMesh(of solid: Solid) -> DisplayMesh? {
        cache.mesh(for: solid)?.mesh
    }
}
