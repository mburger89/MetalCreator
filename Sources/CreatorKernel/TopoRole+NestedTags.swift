extension TopoRole {
    /// The tags a role carries inside itself: a blend's source edge's faces, a cut side's or cut edge's cutting-face tags.
    public var nestedTags: Set<TopoTag> {
        switch self {
        case .blend(let edge): edge.first.union(edge.second)
        case .cutSide(let name, _), .boundary(.cut(let name)): name.nestedTags
        case .startCap, .endCap, .side, .unnamed, .imported, .boundary: []
        }
    }

    /// This role with every nested tag replaced by `transform` of it (and its own nested tags mapped first, so the whole tree moves).
    public func mappingNestedTags(_ transform: (TopoTag) -> TopoTag) -> TopoRole {
        switch self {
        case .blend(let edge):
            .blend(sourceEdge: EdgeKey(Set(edge.first.map(transform)), Set(edge.second.map(transform))))
        case .cutSide(let name, let side): .cutSide(name.mappingTags(transform), side)
        case .boundary(.cut(let name)): .boundary(.cut(name.mappingTags(transform)))
        case .startCap, .endCap, .side, .unnamed, .imported, .boundary: self
        }
    }
}
