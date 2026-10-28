import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// Labels that would overlap stack apart (spec §3.3): later ones stand off further, a saved placement stays.
@MainActor
struct DimensionDeclutterTests {
    let style = DimensionStyle.ansi
    let camera = topDownCamera(pointsPerMillimetre: 2)

    func place(_ dimensions: [OverlayDimension]) -> [PlacedDimension] {
        DimensionDeclutter.place(dimensions, style: style, camera: camera, measure: .eightPerCharacter)
    }

    /// The y of the dimension line (the horizontal segments).
    func lineY(_ placed: PlacedDimension) throws -> Double {
        try #require(placed.segments.first { abs($0.a.y - $0.b.y) < 1e-9 }).a.y
    }

    /// Whether the boxes are closer than `textGap` (the same rule the declutter applies; touching is apart).
    func meets(_ first: PlacedDimension, _ second: PlacedDimension) -> Bool {
        let gap = style.textGap
        let width = min(first.textOrigin.x + first.textSize.width + gap, second.textOrigin.x + second.textSize.width)
            - max(first.textOrigin.x - gap, second.textOrigin.x)
        let height = min(first.textOrigin.y + first.textSize.height + gap, second.textOrigin.y + second.textSize.height)
            - max(first.textOrigin.y - gap, second.textOrigin.y)
        return width > 1e-6 && height > 1e-6
    }

    @Test func twoParallelDimensionsOnOneEdgeStackApart() throws {
        let placed = place([sixtyMillimetres(id: "a"), sixtyMillimetres(id: "b")])
        try #require(placed.count == 2)
        let step = PlacedDimension.textHeight + style.textGap
        #expect(step == 22)
        #expect(abs(try lineY(placed[0]) - (try lineY(placed[1])) - step) < 1e-6, "the second line is 22 points further out")
        #expect(!meets(placed[0], placed[1]) && !meets(placed[1], placed[0]))
        #expect(placed[0].textOrigin.y + placed[0].textSize.height <= placed[1].textOrigin.y
                    || placed[1].textOrigin.y + placed[1].textSize.height <= placed[0].textOrigin.y, "the boxes are disjoint")
    }

    @Test func dimensionsThatDoNotMeetAreNotMoved() throws {
        let apart = OverlayDimension(
            id: OverlayDimensionID("far"),
            geometry: .linear(from: Vector3(0, 40, 0), to: Vector3(60, 40, 0), direction: .unitX, side: .unitY, placement: .standoff),
            text: "60", tint: .dimensionDriving)
        let placed = place([sixtyMillimetres(id: "a"), apart])
        let alone = try #require(DimensionLayout.place(apart, style: style, camera: camera, measure: .eightPerCharacter))
        #expect(placed.count == 2 && placed[1] == alone)
    }

    @Test func aSavedPlacementIsNeverMoved() throws {
        let saved = sixtyMillimetres(id: "saved", placement: .through(Vector3(0, 14, 0)))
        let alone = try #require(DimensionLayout.place(saved, style: style, camera: camera, measure: .eightPerCharacter))
        let beside = place([sixtyMillimetres(id: "a"), saved])
        #expect(beside.count == 2 && beside[1] == alone, "unmoved even though it meets the first")
        let before = place([saved, sixtyMillimetres(id: "a")])
        #expect(before[0] == alone)
        #expect(!meets(before[0], before[1]), "the standoff one gives way to it")
    }

    @Test func whenNoTierIsFreeTheLeastOverlapWins() throws {
        let five = (0..<5).map { sixtyMillimetres(id: "d\($0)") }
        let placed = place(five)
        #expect(placed.count == 5, "all placed")
        #expect(placed == place(five), "deterministic")
        let ys = try placed.map(lineY)
        let step = PlacedDimension.textHeight + style.textGap
        for tier in 0..<DimensionDeclutter.tiers {
            #expect(abs(ys[0] - ys[tier] - Double(tier) * step) < 1e-6, "the first four take tiers 0…3")
        }
        // Every tier holds one box. Tiers 0 and 3 each have one neighbour, so they tie for least overlap and the nearer wins.
        #expect(abs(ys[4] - ys[0]) < 1e-6, "the fifth stays at the first tier")
    }
}
