import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

struct ViewCubeTests {
    let layout = ViewCubeLayout()
    let front = CameraPose(target: .zero, distance: 100, yaw: 0, pitch: 0)
    var iso: CameraPose {
        var pose = front
        let o = CameraNavigation.orientation(lookingFrom: ViewCubeRegion.isometric.direction, fallbackYaw: 0)
        pose.yaw = o?.yaw ?? 0
        pose.pitch = o?.pitch ?? 0
        return pose
    }
    /// Points per cube unit in the default 96-point widget.
    var unit: Double { layout.side / 2 / ViewCubeLayout.halfExtent }

    @Test func regionsAreFacesEdgesAndCorners() {
        #expect(ViewCubeRegion.top.kind == .face)
        #expect(ViewCubeRegion(x: 1, y: 0, z: 1)?.kind == .edge)
        #expect(ViewCubeRegion.isometric.kind == .corner)
        #expect(ViewCubeRegion(x: 0, y: 0, z: 0) == nil)
        #expect(ViewCubeRegion(x: 2, y: 0, z: 0) == nil)
        #expect(ViewCubeRegion.faces.compactMap(\.label) == ["TOP", "BOTTOM", "FRONT", "BACK", "LEFT", "RIGHT"])
        #expect(ViewCubeRegion(x: 1, y: 0, z: 1)?.label == nil)
    }

    @Test func aFaceLooksStraightAtItInOrthographic() {
        let top = ViewCubeRegion.top.pose(from: iso)
        #expect(top.projection == .orthographic)
        #expect(isClose(top.toEye, .unitZ))
        #expect(top.yaw == 0, "TOP is shown with +Y up")
        #expect(isClose(ViewCubeRegion.right.pose(from: front).toEye, .unitX))
    }

    @Test func edgesAndCornersKeepTheProjection() throws {
        let edge = try #require(ViewCubeRegion(x: 1, y: 0, z: 1))
        let pose = edge.pose(from: front)
        #expect(pose.projection == .perspective)
        #expect(isClose(pose.toEye, Vector3(1, 0, 1) * (1 / 2.0.squareRoot())))
        #expect(isClose(ViewCubeRegion.isometric.pose(from: front).pitch, atan(1 / 2.0.squareRoot())))
    }

    @Test func hitTestingFindsTheRegionUnderThePointer() {
        let c = layout.center
        #expect(layout.region(at: c, pose: front) == .front)
        #expect(layout.region(at: ScreenPoint(c.x + 0.8 * unit, c.y), pose: front) == ViewCubeRegion(x: 1, y: -1, z: 0))
        #expect(layout.region(at: ScreenPoint(c.x, c.y - 0.8 * unit), pose: front) == ViewCubeRegion(x: 0, y: -1, z: 1))
        #expect(layout.region(at: ScreenPoint(c.x + 1.5 * unit, c.y), pose: front) == nil, "inside the widget, off the cube")
        #expect(layout.region(at: ScreenPoint(c.x + 200, c.y), pose: front) == nil, "outside the widget")
        #expect(layout.region(at: c, pose: iso) == .isometric)
    }

    @Test func labelsShowOnlyFacesTurnedToTheCamera() {
        let frontLabels = layout.labels(pose: front)
        #expect(frontLabels.map(\.text) == ["FRONT"])
        #expect(isClose(frontLabels[0].position, layout.center, tolerance: 1e-9))
        #expect(Set(layout.labels(pose: iso).map(\.text)) == ["TOP", "FRONT", "RIGHT"])
    }

    @Test func tilesCoverTheCubeOncePerRegionCell() {
        #expect(ViewCubeCell.all.count == 54)
        var counts: [ViewCubeRegion: Int] = [:]
        for cell in ViewCubeCell.all { counts[cell.region, default: 0] += 1 }
        #expect(counts.count == 26)
        for (region, count) in counts {
            let expected = switch region.kind { case .face: 1; case .edge: 2; case .corner: 3 }
            #expect(count == expected, "region \(region) has \(count) tiles")
        }
        for cell in ViewCubeCell.all {
            let c = cell.corners
            #expect((c[1] - c[0]).cross(c[2] - c[0]).dot(cell.normal) > 0, "tiles wind counter-clockwise from outside")
        }
    }

    @Test func theTriadLabelsTheAxesThatAreNotEndOn() {
        let triad = TriadLayout()
        let labels = triad.labels(pose: front)
        #expect(labels.map(\.text) == ["X", "Z"])
        let centre = triad.side / 2
        #expect(labels[0].position.x > centre, "X points right")
        #expect(labels[1].position.y < centre, "Z points up")
        #expect(triad.origin(in: ViewportSize(width: 800, height: 600)) == ScreenPoint(16, 600 - 16 - 64))
    }

    @Test(arguments: [(0.01, 1.0), (0.05, 1.0), (0.1, 10.0), (0.5, 10.0), (5.0, 100.0), (50.0, 100.0)])
    func gridSpacingStepsWithZoom(_ millimetresPerPoint: Double, _ spacing: Double) {
        #expect(GridSpacing.spacing(millimetresPerPoint: millimetresPerPoint) == spacing)
    }

    @Test func gridLabelNamesUnitAndSpacing() {
        #expect(GridSpacing.label(spacing: 10) == "mm · grid 10 mm")
        #expect(GridSpacing.spacing(millimetresPerPoint: .nan) == 100)
    }
}
