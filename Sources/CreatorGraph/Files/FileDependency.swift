/// A file a node's run read or looked for, with the stamp it had before the node read it. The evaluator takes a cached result
/// again only while every such file still has that stamp (KiCad import spec, Files found while running), so a file edited,
/// deleted or created on disk makes the node run again, and what is downstream of it.
public struct FileDependency: Sendable, Hashable {
    public var path: String
    public var stamp: ImageStamp

    public init(path: String, stamp: ImageStamp) {
        self.path = path
        self.stamp = stamp
    }

    /// Whether the file at `path` still has the stamp this dependency recorded.
    var isCurrent: Bool { ImageResolver.stamp(ofFileAt: path) == stamp }
}
