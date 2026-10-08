import CreatorViewport

/// A viewport handle and the input it edits.
public struct ResolvedHandle {
    public var target: HandleTarget
    public var handle: ViewportHandle

    public init(target: HandleTarget, handle: ViewportHandle) {
        self.target = target
        self.handle = handle
    }
}
