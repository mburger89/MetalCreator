import CreatorGeometry
import Foundation

extension ViewportModel {
    /// The camera input is made in now, for the tool.
    var projector: ViewportProjector { ViewportProjector(pose: currentPose(), size: viewSize) }

    /// True while the tool asks for planar navigation: nothing turns the camera.
    var isPlanar: Bool { tool?.navigation == .planar }

    /// Whether the view cube, its arrows and its View menu are shown: not while navigation is planar.
    public var showsViewCube: Bool { !isPlanar }

    /// Offers a primary drag's press to the tool; true when the tool took it.
    func toolTakesDrag(at point: ScreenPoint, modifiers: ViewportModifiers) -> Bool {
        tool?.dragBegan(at: point, modifiers: modifiers, projector: projector) ?? false
    }

    /// Looks straight at `plane` (sketcher spec §8, entering a sketch): orthographic, from the plane's front, turned so
    /// the plane's x axis points right wherever the turntable camera allows (a plane whose x axis isn't horizontal
    /// still shows it rotated), framed on `bounds` in the model area. It animates, as Look At does.
    public func lookAt(_ plane: Plane, framing bounds: BoundingBox) {
        var target = currentPose()
        let yaw = atan2(plane.xAxis.y, plane.xAxis.x)
        guard let orientation = CameraNavigation.orientation(lookingFrom: plane.normal, fallbackYaw: yaw) else { return }
        target.yaw = orientation.yaw
        target.pitch = orientation.pitch
        target.projection = .orthographic
        animate(to: CameraNavigation.frame(bounds, target, size: viewSize, insets: modelArea))
    }
}
