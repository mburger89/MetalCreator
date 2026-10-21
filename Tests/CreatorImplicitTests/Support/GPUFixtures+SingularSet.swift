import CreatorGeometry

extension GPUFixtures {
    /// The Face fixtures whose chart holds a cylinder's axis (`LatticeFixtures.faceAll`): their meshes are compared away from the axis
    /// (`GPUMeshAgreementTests.theGPUMeshAgreesAwayFromTheSingularSet`, spec Errata D20), because within a few millimetres of it the map
    /// stretches the GPU's float rounding into slides along near-tangent mesh edges that are past D17's allowance.
    static let singularSetNames = LatticeFixtures.faceAll.map(\.name)

    /// The radius, in millimetres, of the cylinder about the chart's axis (parallel to Z) that the mesh comparison leaves out. Measured
    /// slides of up to 2e-3 mm were within 2 to 4 mm of the axis; if the first run shows one beyond 4 mm, widen this and Errata D20.
    static let singularSetExclusion: Float = 4

    /// Whether `point` is inside the cylinder of `singularSetExclusion` about the chart's axis, which runs through `LatticeFixtures.crossing`.
    static func nearSingularSet(_ point: SIMD3<Float>) -> Bool {
        let offset = SIMD2(point.x - Float(LatticeFixtures.crossing.x), point.y - Float(LatticeFixtures.crossing.y))
        return (offset * offset).sum().squareRoot() < singularSetExclusion
    }

    /// What `theGPUMeshAgreesAwayFromTheSingularSet` multiplies D17's allowance by for the fixture `name`. The Face-mapped Voronoi
    /// struts differ from the CPU's by up to 6.1e-4 mm along the surface (measured: 6.1 times the allowance, at a point 8.6 mm from the
    /// axis and 5 mm below the skin, so not the singular set's doing; the fixture's values agree within 1e-4 mm in `GPUAgreementTests`),
    /// and are allowed 7 times it. The gyroid and the cubic struts agree within 2.5e-5 mm (spec Errata D20; the cause is not found, see
    /// user decision U11).
    static func singularSetAllowanceFactor(_ name: String) -> Float { name == "voronoi struts, face of a cylinder" ? 7 : 1 }
}
