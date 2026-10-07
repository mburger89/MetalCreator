/// A titled group of inspector controls, declared as data by a node definition.
public struct InspectorSection: Sendable, Equatable {
    public var title: String
    public var controls: [InspectorControl]

    public init(title: String, controls: [InspectorControl]) {
        self.title = title
        self.controls = controls
    }
}
