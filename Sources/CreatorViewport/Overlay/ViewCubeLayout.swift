import CreatorGeometry
import Foundation

/// The view cube widget (spec §6.3): where it sits (the top-left of the model area), how big it is, and the
/// maths for hit-testing and labelling it. Positions are viewport points. The cube spans −1…1 in its own units
/// and turns with the camera.
public struct ViewCubeLayout: Hashable, Sendable {
    public var origin: ScreenPoint
    public var side: Double

    public init(origin: ScreenPoint = ScreenPoint(16, 16), side: Double = 96) {
        self.origin = origin
        self.side = side
    }

    /// Cube units from the widget's centre to its edge: √3 plus a margin, so a corner never leaves the widget.
    static let halfExtent = 1.8

    var center: ScreenPoint { ScreenPoint(origin.x + side / 2, origin.y + side / 2) }
    var widgetSize: ViewportSize { ViewportSize(width: side, height: side) }

    public func contains(_ point: ScreenPoint) -> Bool {
        point.x >= origin.x && point.x <= origin.x + side && point.y >= origin.y && point.y <= origin.y + side
    }

    /// The camera the widget is drawn and hit-tested with: the viewport's orientation, orthographic, centred on
    /// the cube.
    func widgetPose(_ pose: CameraPose) -> CameraPose {
        CameraPose(target: .zero, distance: Self.halfExtent / tan(CameraPose.fieldOfView / 2), yaw: pose.yaw,
                   pitch: pose.pitch, projection: .orthographic)
    }

    /// The region under `point`, or `nil` when the point misses the cube.
    public func region(at point: ScreenPoint, pose: CameraPose) -> ViewCubeRegion? {
        guard contains(point) else { return nil }
        let local = ScreenPoint(point.x - origin.x, point.y - origin.y)
        return Self.region(hitBy: CameraMath.ray(through: local, widgetPose(pose), size: widgetSize))
    }

    /// Face names for the faces turned towards the camera, at their projected centres.
    public func labels(pose: CameraPose) -> [ViewportLabel] {
        let widget = widgetPose(pose)
        return ViewCubeRegion.faces.compactMap { face in
            guard let text = face.label, face.direction.dot(pose.toEye) > 0.2,
                  let projected = CameraMath.project(face.direction, widget, size: widgetSize, sceneRadius: 2) else { return nil }
            return ViewportLabel(text: text, position: ScreenPoint(origin.x + projected.point.x, origin.y + projected.point.y))
        }
    }

    /// The region where `ray` first enters the cube −1…1 (the slab method), or `nil` if it misses.
    static func region(hitBy ray: Ray) -> ViewCubeRegion? {
        let origin = [ray.origin.x, ray.origin.y, ray.origin.z]
        let direction = [ray.direction.x, ray.direction.y, ray.direction.z]
        var enter = -Double.infinity
        var exit = Double.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-12 {
                if abs(origin[axis]) > 1 { return nil }
                continue
            }
            let a = (-1 - origin[axis]) / direction[axis]
            let b = (1 - origin[axis]) / direction[axis]
            enter = max(enter, min(a, b))
            exit = min(exit, max(a, b))
        }
        guard enter <= exit, enter.isFinite else { return nil }
        let hit = (0..<3).map { origin[$0] + direction[$0] * enter }
        let faceAxis = (0..<3).max { abs(hit[$0]) < abs(hit[$1]) } ?? 2
        var parts = hit.map(Self.cell)
        parts[faceAxis] = hit[faceAxis] > 0 ? 1 : -1
        return ViewCubeRegion(x: parts[0], y: parts[1], z: parts[2])
    }

    /// −1, 0 or 1: which third of a side (−1…1) `value` falls in.
    static func cell(_ value: Double) -> Int {
        value > 1.0 / 3 ? 1 : (value < -1.0 / 3 ? -1 : 0)
    }
}
