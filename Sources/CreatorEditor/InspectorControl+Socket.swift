import CreatorGraph

extension InspectorControl {
    /// The input socket (or setting) this control edits, or `nil` for a button. Exhaustive, so a
    /// control kind added later fails to compile here instead of drawing nothing.
    public var socket: SocketName? {
        switch self {
        case .slider(let socket), .number(let socket), .integer(let socket), .planePicker(let socket),
             .vector(let socket), .anchorGrid(let socket), .ruleSummary(let socket), .parameterPicker(let socket),
             .text(let socket):
            socket
        case .toggle(let socket, _), .segmented(let socket, _):
            socket
        case .button:
            nil
        }
    }
}
