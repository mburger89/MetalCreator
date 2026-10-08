import CreatorGraph
import CreatorKernel

/// An inspector button the viewport must act on, such as "Pick edges in view…".
/// `serial` distinguishes two presses of the same button.
public struct InspectorRequest: Equatable, Sendable {
    public var node: NodeID
    public var action: InspectorAction
    public var serial: Int
}
