import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// The angular layout (dimensions spec §5): an arc over the smaller angle, arrows on its ends, the text at its middle.
@MainActor
struct AngularDimensionLayoutTests {
    let style = DimensionStyle.ansi
    let camera = topDownCamera(pointsPerMillimetre: 2)

    func angular(first: Vector3 = Vector3(10, 0, 0), second: Vector3 = Vector3(0, 10, 0),
                 placement: DimensionPlacement = .standoff) -> OverlayDimension {
        OverlayDimension(id: OverlayDimensionID("g"),
                         geometry: .angular(vertex: .zero, first: first, second: second, normal: .unitZ, placement: placement),
                         text: "90°", tint: .dimensionDriving)
    }

    func place(_ dimension: OverlayDimension) -> PlacedDimension? {
        DimensionLayout.place(dimension, style: style, camera: camera, measure: .eightPerCharacter)
    }

    /// Segments that lie on the circle of `radius` points round `centre`.
    func arc(_ placed: PlacedDimension, round centre: ScreenPoint, radius: Double) -> [ScreenSegment] {
        placed.segments.filter { segment in
            [segment.a, segment.b].allSatisfy { abs(($0 - centre).length - radius) < 1e-6 }
        }
    }

    @Test func anAngleArcSpansTheSmallerAngle() throws {
        let placed = try #require(place(angular()))
        let vertex = try #require(camera.project(.zero))
        let radius = (style.standoff + style.leaderLength) / 2 * 2
        let pieces = arc(placed, round: vertex, radius: radius)
        #expect(!pieces.isEmpty)
        for point in pieces.flatMap({ [$0.a, $0.b] }) {
            #expect(point.x >= vertex.x - 1e-6 && point.y <= vertex.y + 1e-6, "world x >= 0 and y >= 0 (screen y is down)")
        }
        let centre = ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
        let offset = centre - vertex
        #expect(abs(offset.length - radius) < 1e-6, "on the arc")
        #expect(abs(offset.x / offset.length - 1 / 2.0.squareRoot()) < 1e-6 && abs(offset.y / offset.length + 1 / 2.0.squareRoot()) < 1e-6,
                "at 45 degrees")
    }

    @Test func theArcTurnsTheOtherWayForTheOtherOrder() throws {
        let placed = try #require(place(angular(first: Vector3(0, 10, 0), second: Vector3(10, 0, 0))))
        let vertex = try #require(camera.project(.zero))
        for point in placed.segments.flatMap({ [$0.a, $0.b] }) where abs((point - vertex).length - 52) < 1e-6 {
            #expect(point.x >= vertex.x - 1e-6 && point.y <= vertex.y + 1e-6)
        }
    }

    @Test func theTextBreaksTheArc() throws {
        let placed = try #require(place(angular()))
        let vertex = try #require(camera.project(.zero))
        let grown = (minX: placed.textOrigin.x - style.textGap, maxX: placed.textOrigin.x + placed.textSize.width + style.textGap,
                     minY: placed.textOrigin.y - style.textGap, maxY: placed.textOrigin.y + placed.textSize.height + style.textGap)
        for segment in arc(placed, round: vertex, radius: 52) {
            for step in 0...20 {
                let t = Double(step) / 20
                let (x, y) = (segment.a.x + (segment.b.x - segment.a.x) * t, segment.a.y + (segment.b.y - segment.a.y) * t)
                #expect(!(x > grown.minX + 1e-6 && x < grown.maxX - 1e-6 && y > grown.minY + 1e-6 && y < grown.maxY - 1e-6))
            }
        }
    }

    @Test func angleArrowsSitOnTheArcsEnds() throws {
        let placed = try #require(place(angular()))
        let vertex = try #require(camera.project(.zero))
        #expect(placed.arrows.count == 2)
        let onFirst = try #require(placed.arrows.first { abs($0.tip.y - vertex.y) < 1e-6 })
        let onSecond = try #require(placed.arrows.first { abs($0.tip.x - vertex.x) < 1e-6 })
        #expect(abs(onFirst.tip.x - (vertex.x + 52)) < 1e-6, "on the first ray, 52 points out")
        #expect(abs(onSecond.tip.y - (vertex.y - 52)) < 1e-6, "on the second ray")
        // Tangent to the arc and pointing outward: down on screen at the first ray, left at the second.
        #expect(abs(onFirst.direction.x) < 0.05 && onFirst.direction.y > 0.99)
        #expect(onSecond.direction.x < -0.99 && abs(onSecond.direction.y) < 0.05)
    }

    @Test func extensionLinesReachAnArcBeyondTheLines() throws {
        let placed = try #require(place(angular()))
        let vertex = try #require(camera.project(.zero))
        let alongFirst = try #require(placed.segments.first { abs($0.a.y - vertex.y) < 1e-6 && abs($0.b.y - vertex.y) < 1e-6 })
        let xs = [alongFirst.a.x, alongFirst.b.x]
        #expect(abs((xs.min() ?? 0) - (vertex.x + 20 + style.extensionGap)) < 1e-6, "a gap from the measured point")
        #expect(abs((xs.max() ?? 0) - (vertex.x + 52 + style.extensionOvershoot)) < 1e-6, "an overshoot past the arc")
        let alongSecond = try #require(placed.segments.first { abs($0.a.x - vertex.x) < 1e-6 && abs($0.b.x - vertex.x) < 1e-6 })
        let ys = [alongSecond.a.y, alongSecond.b.y]
        #expect(abs((ys.max() ?? 0) - (vertex.y - 20 - style.extensionGap)) < 1e-6)
        #expect(abs((ys.min() ?? 0) - (vertex.y - 52 - style.extensionOvershoot)) < 1e-6)
    }

    @Test func noExtensionLinesWhenTheArcIsWithinTheLines() throws {
        // The rays' points are 40 mm (80 points) out; the 52-point arc lies inside them.
        let placed = try #require(place(angular(first: Vector3(40, 0, 0), second: Vector3(0, 40, 0))))
        let vertex = try #require(camera.project(.zero))
        let lines = placed.segments.filter { abs($0.a.y - vertex.y) < 1e-6 && abs($0.b.y - vertex.y) < 1e-6 }
        #expect(lines.isEmpty)
    }

    @Test func aSavedPlacementSetsTheRadius() throws {
        let placed = try #require(place(angular(placement: .through(Vector3(0, 20, 0)))))
        let vertex = try #require(camera.project(.zero))
        #expect(!arc(placed, round: vertex, radius: 40).isEmpty)
    }

    @Test func aDegenerateAngleIsLeftOut() {
        #expect(place(angular(first: .zero)) == nil, "no first ray")
        #expect(place(angular(second: .zero)) == nil, "no second ray")
        #expect(place(angular(second: Vector3(20, 0, 0))) == nil, "the rays coincide")
        #expect(place(angular(first: Vector3(.nan, 0, 0))) == nil)
        let edgeOn = DimensionCamera(pose: CameraPose(target: .zero, distance: 300, yaw: 0, pitch: 5 * .pi / 180,
                                                      projection: .orthographic), size: dimensionTestSize)
        #expect(DimensionLayout.place(angular(), style: style, camera: edgeOn, measure: .eightPerCharacter) == nil)
    }
}
