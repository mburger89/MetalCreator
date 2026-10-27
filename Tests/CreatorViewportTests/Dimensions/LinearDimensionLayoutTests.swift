import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// The linear layout (dimensions spec §5): stand-off, extension lines, a text break, constant-size arrows, the short
/// case, a saved placement, and what is left out.
@MainActor
struct LinearDimensionLayoutTests {
    let style = DimensionStyle.ansi

    func place(_ dimension: OverlayDimension, camera: DimensionCamera = topDownCamera(pointsPerMillimetre: 2)) -> PlacedDimension? {
        DimensionLayout.place(dimension, style: style, camera: camera, measure: .eightPerCharacter)
    }

    func horizontal(_ placed: PlacedDimension) -> [ScreenSegment] {
        placed.segments.filter { abs($0.a.y - $0.b.y) < 1e-9 }
    }

    func vertical(_ placed: PlacedDimension) -> [ScreenSegment] {
        placed.segments.filter { abs($0.a.x - $0.b.x) < 1e-9 }
    }

    func screen(_ point: Vector3, _ camera: DimensionCamera = topDownCamera(pointsPerMillimetre: 2)) throws -> ScreenPoint {
        try #require(camera.project(point))
    }

    @Test func theDimensionLineStandsOffByTheStyle() throws {
        let placed = try #require(place(sixtyMillimetres()))
        let (start, end) = try (screen(.zero), screen(Vector3(60, 0, 0)))
        let lines = horizontal(placed)
        #expect(!lines.isEmpty)
        for line in lines {
            #expect(abs(line.a.y - (start.y - style.standoff)) < 1e-6, "28 points above (smaller y than) the projected ends")
        }
        let xs = lines.flatMap { [$0.a.x, $0.b.x] }
        #expect(abs((xs.min() ?? 0) - start.x) < 1e-6 && abs((xs.max() ?? 0) - end.x) < 1e-6, "both ends sit above the points")
        #expect(abs(start.y - end.y) < 1e-9)
    }

    @Test func extensionLinesLeaveAGapAndRunPastTheLine() throws {
        let placed = try #require(place(sixtyMillimetres()))
        let ends = try [screen(.zero), screen(Vector3(60, 0, 0))]
        let extensions = vertical(placed)
        #expect(extensions.count == 2)
        for end in ends {
            let line = try #require(extensions.first { abs($0.a.x - end.x) < 1e-6 })
            let ys = [line.a.y, line.b.y]
            #expect(abs((ys.max() ?? 0) - (end.y - style.extensionGap)) < 1e-6, "starts 3 points from its point")
            #expect(abs((ys.min() ?? 0) - (end.y - style.standoff - style.extensionOvershoot)) < 1e-6, "ends 6 points past the line")
        }
    }

    @Test func theTextBreaksTheLineAtItsMiddle() throws {
        let placed = try #require(place(sixtyMillimetres()))
        let (start, end) = try (screen(.zero), screen(Vector3(60, 0, 0)))
        let lineY = start.y - style.standoff
        #expect(placed.textSize == ViewportSize(width: 16 + 2 * PlacedDimension.textPadding, height: PlacedDimension.textHeight))
        #expect(placed.textSize.width == 24 && placed.textSize.height == 18)
        let centre = ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2, placed.textOrigin.y + placed.textSize.height / 2)
        #expect(abs(centre.x - (start.x + end.x) / 2) < 1e-6 && abs(centre.y - lineY) < 1e-6)
        #expect(placed.showsText)
        let grown = (minX: placed.textOrigin.x - style.textGap, maxX: placed.textOrigin.x + placed.textSize.width + style.textGap,
                     minY: placed.textOrigin.y - style.textGap, maxY: placed.textOrigin.y + placed.textSize.height + style.textGap)
        for segment in horizontal(placed) {
            for step in 0...100 {
                let t = Double(step) / 100
                let (x, y) = (segment.a.x + (segment.b.x - segment.a.x) * t, segment.a.y + (segment.b.y - segment.a.y) * t)
                let inside = x > grown.minX + 1e-6 && x < grown.maxX - 1e-6 && y > grown.minY + 1e-6 && y < grown.maxY - 1e-6
                #expect(!inside, "the line stays out of the text box grown by the gap")
            }
        }
        #expect(horizontal(placed).count == 2, "the line is two pieces, one each side of the text")
    }

    @Test(arguments: [1.0, 4.0]) func arrowsArePointsSizedWhateverTheZoom(_ ppm: Double) throws {
        let camera = topDownCamera(pointsPerMillimetre: ppm)
        let placed = try #require(place(sixtyMillimetres(), camera: camera))
        #expect(placed.arrows.count == 2)
        let ends = try [screen(.zero, camera), screen(Vector3(60, 0, 0), camera)]
        let tips = placed.arrows.map(\.tip).sorted { $0.x < $1.x }
        for (tip, end) in zip(tips, ends) {
            #expect(abs(tip.x - end.x) < 1e-6 && abs(tip.y - (end.y - style.standoff)) < 1e-6)
        }
        for arrow in placed.arrows {
            #expect(abs(arrow.direction.length - 1) < 1e-9)
            let corners = arrow.corners(length: style.arrowLength, width: style.arrowWidth)
            #expect(corners.count == 3 && corners[0] == arrow.tip)
            let base = ScreenPoint((corners[1].x + corners[2].x) / 2, (corners[1].y + corners[2].y) / 2)
            #expect(abs((base - corners[0]).length - 9) < 1e-9, "9 points along")
            #expect(abs((corners[1] - corners[2]).length - 3) < 1e-9, "3 points across")
        }
        let left = try #require(placed.arrows.first { $0.tip.x == tips[0].x })
        #expect(left.direction.x < 0, "on a line that fits the text, the arrows point out at the ends")
    }

    @Test func aShortDimensionPutsArrowsAndTextOutside() throws {
        let short = OverlayDimension(id: OverlayDimensionID("s"),
                                     geometry: .linear(from: .zero, to: Vector3(5, 0, 0), direction: .unitX, side: .unitY,
                                                       placement: .standoff),
                                     text: "5", tint: .dimensionDriving)
        let placed = try #require(place(short))
        let (left, right) = try (screen(.zero).x, screen(Vector3(5, 0, 0)).x)
        let sorted = placed.arrows.sorted { $0.tip.x < $1.tip.x }
        #expect(sorted.count == 2)
        #expect(abs(sorted[0].tip.x - left) < 1e-6 && abs(sorted[1].tip.x - right) < 1e-6)
        #expect(sorted[0].direction.x > 0 && sorted[1].direction.x < 0, "arrows point inward, from outside")
        let centre = placed.textOrigin.x + placed.textSize.width / 2
        #expect(centre > right, "the text sits right of the right end")
        let reach = placed.textOrigin.x - right
        #expect(reach >= 2 * style.arrowLength + style.textGap - 1e-6)
    }

    @Test func aSavedPlacementPutsTheLineThroughIt() throws {
        let placed = try #require(place(sixtyMillimetres(placement: .through(Vector3(30, 20, 0)))))
        let expected = try screen(Vector3(0, 20, 0)).y
        let lines = horizontal(placed)
        #expect(!lines.isEmpty)
        for line in lines {
            #expect(abs(line.a.y - expected) < 1e-6)
        }
    }

    @Test func aDimensionSeenNearlyEdgeOnIsHidden() {
        func camera(degrees: Double) -> DimensionCamera {
            DimensionCamera(pose: CameraPose(target: Vector3(30, 0, 0), distance: 300, yaw: 0, pitch: degrees * .pi / 180,
                                             projection: .orthographic),
                            size: dimensionTestSize)
        }
        #expect(place(sixtyMillimetres(), camera: camera(degrees: 5)) == nil)
        #expect(place(sixtyMillimetres(), camera: camera(degrees: 15)) != nil)
    }

    @Test func aDegenerateDimensionIsLeftOut() throws {
        func linear(_ from: Vector3, _ to: Vector3, _ direction: Vector3, _ side: Vector3) -> OverlayDimension {
            OverlayDimension(id: OverlayDimensionID("d"),
                             geometry: .linear(from: from, to: to, direction: direction, side: side, placement: .standoff),
                             text: "x", tint: .dimensionDriving)
        }
        #expect(place(linear(.zero, .zero, .unitX, .unitY)) == nil, "from == to")
        #expect(place(linear(.zero, Vector3(60, 0, 0), .zero, .unitY)) == nil, "zero direction")
        #expect(place(linear(.zero, Vector3(60, 0, 0), .unitX, .zero)) == nil, "zero side")
        #expect(place(linear(.zero, Vector3(60, 0, 0), .unitX, .unitX)) == nil, "side along the direction")
        #expect(place(linear(Vector3(.nan, 0, 0), Vector3(60, 0, 0), .unitX, .unitY)) == nil, "not a number")

        let perspective = DimensionCamera(pose: CameraPose(target: .zero, distance: 200, yaw: 0, pitch: 0, projection: .perspective),
                                          size: dimensionTestSize)
        // The eye is at (0, -200, 0) looking along +y: y = -300 is behind it.
        let behind = linear(Vector3(0, -300, 0), Vector3(60, -300, 0), .unitX, .unitZ)
        #expect(place(behind, camera: perspective) == nil, "a point behind a perspective camera")
        let ahead = try #require(place(linear(Vector3(0, 0, 0), Vector3(60, 0, 0), .unitX, .unitZ), camera: perspective))
        let coordinates = ahead.segments.flatMap { [$0.a.x, $0.a.y, $0.b.x, $0.b.y] }
            + ahead.arrows.flatMap { $0.corners(length: 9, width: 3).flatMap { [$0.x, $0.y] } }
            + [ahead.textOrigin.x, ahead.textOrigin.y, ahead.textSize.width, ahead.textSize.height]
        #expect(coordinates.allSatisfy { $0.isFinite })
    }

    @Test func aPinnedDimensionMarksTheTextBoxCorner() throws {
        let plain = try #require(place(sixtyMillimetres()))
        #expect(plain.pinMark == nil)
        let pinned = try #require(place(sixtyMillimetres(isPinned: true)))
        #expect(pinned.pinMark == ScreenPoint(pinned.textOrigin.x + pinned.textSize.width, pinned.textOrigin.y))
    }

    @Test func theTextContainsItsBoxOnly() throws {
        let placed = try #require(place(sixtyMillimetres()))
        let centre = ScreenPoint(placed.textOrigin.x + 12, placed.textOrigin.y + 9)
        #expect(placed.textContains(centre))
        #expect(!placed.textContains(ScreenPoint(placed.textOrigin.x - 1, centre.y)))
        #expect(!placed.textContains(ScreenPoint(centre.x, placed.textOrigin.y + 18.5)))
    }
}
