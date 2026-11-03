extension Graph {
    /// This graph with every `image` and `meshFile` setting replaced by `transform` of it.
    func mappingImages(_ transform: (ImageReference) -> ImageReference) -> Graph {
        var graph = self
        for (id, node) in nodes {
            for (name, value) in node.inputValues {
                switch value {
                case .image(let reference): graph.nodes[id]?.inputValues[name] = .image(transform(reference))
                case .meshFile(let reference): graph.nodes[id]?.inputValues[name] = .meshFile(transform(reference))
                default: continue
                }
            }
        }
        return graph
    }

    /// The hash of every embedded image or mesh file a node of this graph points at.
    public var embeddedImageHashes: Set<ImageHash> {
        var hashes: Set<ImageHash> = []
        for node in nodes.values {
            for value in node.inputValues.values {
                if case .embedded(let hash)? = value.fileReference { hashes.insert(hash) }
            }
        }
        return hashes
    }
}
