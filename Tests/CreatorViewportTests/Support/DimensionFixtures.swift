// Test fixture file: cameras and a deterministic measure for the dimension layout tests.
import CreatorGeometry
import Foundation
@testable import CreatorViewport

/// The size every dimension test draws in.
let dimensionTestSize = ViewportSize(width: 400, height: 300)

/// A camera looking straight down at the origin plane (+x right, +y up on screen), orthographic, at the given scale.
@MainActor
func topDownPose(pointsPerMillimetre: Double) -> CameraPose {
    let visibleHeight = dimensionTestSize.height / pointsPerMillimetre
    let distance = visibleHeight / (2 * tan(CameraPose.fieldOfView / 2))
    return CameraPose(target: Vector3(30, 10, 0), distance: distance, yaw: 0, pitch: .pi / 2, projection: .orthographic)
}

@MainActor
func topDownCamera(pointsPerMillimetre: Double) -> DimensionCamera {
    DimensionCamera(pose: topDownPose(pointsPerMillimetre: pointsPerMillimetre), size: dimensionTestSize)
}

extension TextMeasure {
    /// 8 points a character and 12 tall: "60" is 16 wide, so its dimension box is 16 + 2 * 4.
    static var eightPerCharacter: TextMeasure { TextMeasure { text in ViewportSize(width: Double(text.count) * 8, height: 12) } }
}

/// 60 mm from the origin along +x, side +y.
func sixtyMillimetres(id: String = "a", text: String = "60", placement: DimensionPlacement = .standoff,
                      isPinned: Bool = false) -> OverlayDimension {
    OverlayDimension(id: OverlayDimensionID(id),
                     geometry: .linear(from: .zero, to: Vector3(60, 0, 0), direction: .unitX, side: .unitY, placement: placement),
                     text: text, tint: .dimensionDriving, isPinned: isPinned)
}
