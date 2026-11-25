import CreatorGeometry
import CreatorKernel

/// The named views (plan R5), following the viewport's view cube with +Z up.
public enum StandardOrientation: String, Sendable, Codable, CaseIterable {
    case front, back, left, right, top, bottom, isometricFrontRight, isometricFrontLeft

    public var frame: ProjectionFrame {
        let z = Vector3(0, 0, 1)
        let third = 1 / 3.0.squareRoot()
        switch self {
        case .front: return ProjectionFrame(direction: Vector3(0, 1, 0), up: z)
        case .back: return ProjectionFrame(direction: Vector3(0, -1, 0), up: z)
        case .left: return ProjectionFrame(direction: Vector3(1, 0, 0), up: z)
        case .right: return ProjectionFrame(direction: Vector3(-1, 0, 0), up: z)
        case .top: return ProjectionFrame(direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0))
        case .bottom: return ProjectionFrame(direction: Vector3(0, 0, 1), up: Vector3(0, -1, 0))
        case .isometricFrontRight:
            return ProjectionFrame.make(direction: Vector3(-third, third, -third), up: z)
                ?? ProjectionFrame(direction: Vector3(0, 1, 0), up: z)
        case .isometricFrontLeft:
            return ProjectionFrame.make(direction: Vector3(third, third, -third), up: z)
                ?? ProjectionFrame(direction: Vector3(0, 1, 0), up: z)
        }
    }

    public var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        case .isometricFrontRight, .isometricFrontLeft: "Isometric"
        }
    }

    public var isIsometric: Bool { self == .isometricFrontRight || self == .isometricFrontLeft }
}
