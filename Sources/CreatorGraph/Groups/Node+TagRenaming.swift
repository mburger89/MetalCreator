import CreatorKernel

extension Node {
    /// This node with the tags of every pick it stores renamed by `names` (`ConstantValue.renamingTags`).
    func renamingTags(_ names: [NodeID: NodeID]) -> Node {
        guard !names.isEmpty else { return self }
        var renamed = self
        for (name, value) in inputValues {
            renamed.inputValues[name] = value.renamingTags(names)
        }
        return renamed
    }
}
