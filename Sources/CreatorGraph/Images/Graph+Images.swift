extension Graph {
    /// This graph with every `image` setting replaced by `transform` of it.
    func mappingImages(_ transform: (ImageReference) -> ImageReference) -> Graph {
        var graph = self
        for (id, node) in nodes {
            for (name, value) in node.inputValues {
                guard case .image(let reference) = value else { continue }
                graph.nodes[id]?.inputValues[name] = .image(transform(reference))
            }
        }
        return graph
    }

    /// The hash of every embedded image a node of this graph points at.
    var embeddedImageHashes: Set<ImageHash> {
        var hashes: Set<ImageHash> = []
        for node in nodes.values {
            for value in node.inputValues.values {
                if case .image(.embedded(let hash)) = value { hashes.insert(hash) }
            }
        }
        return hashes
    }
}
