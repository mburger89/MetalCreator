extension Graph {
    /// This graph with every `image`, `meshFile`, `pcbFile` and `modelFile` setting replaced by `transform` of it.
    func mappingImages(_ transform: (ImageReference) -> ImageReference) -> Graph {
        var graph = self
        for (id, node) in nodes {
            for (name, value) in node.inputValues {
                switch value {
                case .image(let reference): graph.nodes[id]?.inputValues[name] = .image(transform(reference))
                case .meshFile(let reference): graph.nodes[id]?.inputValues[name] = .meshFile(transform(reference))
                case .pcbFile(let reference): graph.nodes[id]?.inputValues[name] = .pcbFile(transform(reference))
                case .modelFile(let reference): graph.nodes[id]?.inputValues[name] = .modelFile(transform(reference))
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
        // A drawing's title block logos (DR-5 R11): the document's defaults and every sheet's.
        let logos = [drawings.settings.titleBlockDefaults.logo] + drawings.sheets.map(\.titleBlock.logo)
        for case let text? in logos {
            if let hash = ImageHash(hex: text) { hashes.insert(hash) }
        }
        return hashes
    }
}
