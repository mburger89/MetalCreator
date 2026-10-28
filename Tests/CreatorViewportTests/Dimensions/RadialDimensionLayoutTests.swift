import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// The radial layout (dimensions spec §5): an arrow on the circle, a leader, a horizontal shoulder and the text beyond it.
@MainActor
struct RadialDimensionLayoutTests {
    let style = DimensionStyle.ansi
    let camera = topDownCamera(pointsPerMillimetre: 2)

    func radial(radius: Double = 10, toward: Vector3, normal: Vector3 = .unitZ, placement: DimensionPlacement = .standoff,
                text: String = "R10") -> OverlayDimension {
        OverlayDimension(id: OverlayDimensionID("r"),
                         geometry: .radial(center: .zero, radius: radius, normal: normal, toward: toward, placement: placement),
                         text: text, tint: .dimensionDriving)
    }

    func place(_ dimension: OverlayDimension) -> PlacedDimension? {
        DimensionLayout.place(dimension, style: style, camera: camera, measure: .eightPerCharacter)
    }

    @Test func aRadiusLeaderMeetsTheCircleWithAnArrowAndAShoulder() throws {
        let placed = try #require(place(radial(toward: Vector3(1, 1, 0))))
        let centre = try #require(camera.project(.zero))
        let (rx, ry) = (1 / 2.0.squareRoot(), -1 / 2.0.squareRoot())

        let arrow = try #require(placed.arrows.first)
        #expect(placed.arrows.count == 1)
        #expect(abs(arrow.tip.x - (centre.x + 20 * rx)) < 1e-6 && abs(arrow.tip.y - (centre.y + 20 * ry)) < 1e-6,
                "on the circle, 20 points from the centre at 45 degrees")
        #expect(abs(arrow.direction.x + rx) < 1e-6 && abs(arrow.direction.y + ry) < 1e-6, "pointing at the centre side")

        let leaderEnd = ScreenPoint(arrow.tip.x + rx * style.leaderLength, arrow.tip.y + ry * style.leaderLength)
        let leader = try #require(placed.segments.first)
        #expect(abs(leader.a.x - arrow.tip.x) < 1e-6 && abs(leader.a.y - arrow.tip.y) < 1e-6)
        #expect(abs(leader.b.x - leaderEnd.x) < 1e-6 && abs(leader.b.y - leaderEnd.y) < 1e-6, "24 points outward")

        let shoulder = try #require(placed.segments.last)
        #expect(placed.segments.count == 2)
        #expect(abs(shoulder.a.x - leaderEnd.x) < 1e-6 && abs(shoulder.a.y - leaderEnd.y) < 1e-6)
        #expect(abs(shoulder.b.x - (leaderEnd.x + style.shoulderLength)) < 1e-6 && abs(shoulder.b.y - leaderEnd.y) < 1e-6,
                "10 points to the right, horizontal")
        #expect(abs(placed.textOrigin.x - (shoulder.b.x + style.textGap)) < 1e-6, "the text's left edge is 4 points past it")
        #expect(abs(placed.textOrigin.y + placed.textSize.height / 2 - shoulder.b.y) < 1e-6, "centred on the shoulder")
        #expect(placed.showsText)
    }

    @Test func aLeaderOnTheLeftTurnsItsShoulderLeft() throws {
        let placed = try #require(place(radial(toward: Vector3(-1, 0, 0))))
        let shoulder = try #require(placed.segments.last)
        #expect(abs(shoulder.b.x - (shoulder.a.x - style.shoulderLength)) < 1e-6 && abs(shoulder.a.y - shoulder.b.y) < 1e-9)
        #expect(abs(placed.textOrigin.x + placed.textSize.width - (shoulder.b.x - style.textGap)) < 1e-6,
                "the text's right edge is 4 points before the end")
    }

    @Test func aSavedPlacementPutsTheLeaderEndThroughIt() throws {
        let placed = try #require(place(radial(toward: .unitX, placement: .through(Vector3(30, 5, 0)))))
        let target = try #require(camera.project(Vector3(30, 5, 0)))
        let leader = try #require(placed.segments.first)
        #expect(abs(leader.b.x - target.x) < 1e-6 && abs(leader.b.y - target.y) < 1e-6)
    }

    @Test func aCircleSeenEdgeOnIsHidden() {
        let edgeOn = DimensionCamera(pose: CameraPose(target: .zero, distance: 300, yaw: 0, pitch: 5 * .pi / 180,
                                                      projection: .orthographic), size: dimensionTestSize)
        let dimension = radial(toward: .unitX)
        #expect(DimensionLayout.place(dimension, style: style, camera: edgeOn, measure: .eightPerCharacter) == nil)
    }

    @Test func aZeroRadiusIsLeftOut() {
        #expect(place(radial(radius: 0, toward: .unitX)) == nil)
        #expect(place(radial(radius: -3, toward: .unitX)) == nil)
        #expect(place(radial(radius: .nan, toward: .unitX)) == nil)
        #expect(place(radial(toward: .zero)) == nil, "no direction to aim")
        #expect(place(radial(toward: .unitZ)) == nil, "aimed along the normal")
        #expect(place(radial(toward: .unitX, normal: .zero)) == nil, "no plane")
    }
}
