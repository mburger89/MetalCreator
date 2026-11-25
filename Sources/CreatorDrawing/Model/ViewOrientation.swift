import CreatorKernel

/// How a drawing view looks at its part: a named direction or a stored frame (a projected view's).
public enum ViewOrientation: Hashable, Sendable, Codable {
    case standard(StandardOrientation)
    case custom(ProjectionFrame)

    public var frame: ProjectionFrame {
        switch self {
        case .standard(let orientation): orientation.frame
        case .custom(let frame): frame
        }
    }

    /// A custom frame is isometric when its direction runs along no axis.
    public var isIsometric: Bool {
        switch self {
        case .standard(let orientation): orientation.isIsometric
        case .custom(let frame):
            max(abs(frame.direction.x), abs(frame.direction.y), abs(frame.direction.z)) < 1 - 1e-9
        }
    }
}
