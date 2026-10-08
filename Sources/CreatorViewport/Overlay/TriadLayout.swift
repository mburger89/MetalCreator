import CreatorGeometry
import Foundation

/// The axis triad at the bottom-left of the model area (spec §6.3): X, Y and Z turning with the camera.
/// `leading` and `bottom` are its distances from the viewport's left and bottom edges.
public struct TriadLayout: Hashable, Sendable {
    public var side: Double
    public var leading: Double
    public var bottom: Double

    public init(side: Double = 64, leading: Double = 16, bottom: Double = 16) {
        self.side = side
        self.leading = leading
        self.bottom = bottom
    }

    static let halfExtent = 1.2
    static let axisLength = 0.8
    static let axes: [(label: String, direction: Vector3)] = [("X", .unitX), ("Y", .unitY), ("Z", .unitZ)]

    /// The widget's top-left corner in a viewport of `size`.
    func origin(in size: ViewportSize) -> ScreenPoint {
        ScreenPoint(leading, size.height - bottom - side)
    }

    func widgetPose(_ pose: CameraPose) -> CameraPose {
        CameraPose(target: .zero, distance: Self.halfExtent / tan(CameraPose.fieldOfView / 2), yaw: pose.yaw,
                   pitch: pose.pitch, projection: .orthographic)
    }

    /// Axis labels just past each tip, relative to the widget's top-left. An axis pointing (almost) at or away
    /// from the camera has none.
    public func labels(pose: CameraPose) -> [ViewportLabel] {
        let widget = widgetPose(pose)
        let size = ViewportSize(width: side, height: side)
        return Self.axes.compactMap { axis in
            guard abs(axis.direction.dot(pose.toEye)) < 0.95,
                  let projected = CameraMath.project(axis.direction * (Self.axisLength + 0.25), widget, size: size,
                                                     sceneRadius: 2) else { return nil }
            return ViewportLabel(text: axis.label, position: projected.point)
        }
    }
}
