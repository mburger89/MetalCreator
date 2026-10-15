import CreatorKernel

/// What the Output nodes hold, read from the current results before an export asks where to save (implicit spec §5.3).
struct ExportPlan {
    /// The solids of every Output node, in ID order.
    var solids: [Solid] = []
    /// The names of the Output nodes that hold meshes. A mesh can go to STL and 3MF, never to STEP.
    var meshOutputs: [String] = []

    var hasMeshes: Bool { !meshOutputs.isEmpty }
}
