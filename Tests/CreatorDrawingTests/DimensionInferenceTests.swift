import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Dimension inference")
struct DimensionInferenceTests {
    private typealias Fixture = TopologyFixtures

    private func pick(_ id: Int) -> EdgePick {
        EdgePick(key: EdgeKey(Fixture.tags(.side(segment: id)), Fixture.tags(.side(segment: id + 100))), matchCount: 1)
    }

    private func line(_ id: Int, _ a: Vector2, _ b: Vector2) -> PickedAnchor {
        PickedAnchor(target: .edge(pick(id)), shape: .line(a, b))
    }

    private func point(_ id: Int, _ p: Vector2) -> PickedAnchor {
        PickedAnchor(target: .corner(pick(id), pick(id + 50)), shape: .point(p))
    }

    private func circle(_ id: Int, _ center: Vector2, radius: Double = 3, isFull: Bool = true) -> PickedAnchor {
        PickedAnchor(target: .edge(pick(id)), shape: .circle(center: center, radius: radius, isFull: isFull))
    }

    private func make(
        _ tool: DimensionTool, _ picks: [PickedAnchor], placing: Vector2 = .zero, aligned: Bool = false
    ) -> (kind: DrawingDimensionKind, anchors: [AnchorTarget])? {
        if case .success(let made) = DimensionInference.make(tool: tool, picks: picks, placing: placing, aligned: aligned) {
            return made
        }
        return nil
    }

    private func refusal(_ tool: DimensionTool, _ picks: [PickedAnchor], placing: Vector2 = .zero) -> String? {
        if case .failure(let refused) = DimensionInference.make(tool: tool, picks: picks, placing: placing, aligned: false) {
            return refused.sentence
        }
        return nil
    }

    @Test func aHorizontalLine() {
        let made = make(.smart, [line(1, Vector2(0, 5), Vector2(10, 5))])
        #expect(made?.kind == .linear(.horizontal))
        #expect(made?.anchors == [.edge(pick(1))])
        #expect(make(.smart, [line(1, Vector2(2, 0), Vector2(2, 9))])?.kind == .linear(.vertical))
    }

    @Test func aSlantedLineIsAligned() {
        #expect(make(.smart, [line(1, Vector2(0, 0), Vector2(10, 5))])?.kind == .linear(.aligned))
    }

    @Test func aCircleIsADiameter() {
        #expect(make(.smart, [circle(1, Vector2(5, 5))])?.kind == .diameter)
    }

    @Test func anArcIsARadius() {
        #expect(make(.smart, [circle(1, Vector2(5, 5), isFull: false)])?.kind == .radius)
    }

    @Test func aCylinderOutlineIsADiameterOfItsAxis() {
        let face = FacePick(tags: Fixture.tags(.side(segment: 4)))
        let outline = PickedAnchor(
            target: .outline(face, side: Vector2(0, -1)), shape: .cylinder(axisPoint: Vector2(0, 5), direction: Vector2(1, 0), radius: 5))
        let made = make(.smart, [outline])
        #expect(made?.kind == .diameter)
        #expect(made?.anchors == [.axis(face)])
    }

    @Test func twoPointsByWhereTheyArePlaced() {
        let picks = [point(1, Vector2(0, 0)), point(2, Vector2(10, 4))]
        // Above both: the dimension line is horizontal.
        #expect(make(.smart, picks, placing: Vector2(5, 12))?.kind == .linear(.horizontal))
        // To the right: vertical.
        #expect(make(.smart, picks, placing: Vector2(20, 2))?.kind == .linear(.vertical))
        // Shift asks for the distance between them.
        #expect(make(.smart, picks, placing: Vector2(5, 12), aligned: true)?.kind == .linear(.aligned))
    }

    @Test func aCircleWithAPointGivesItsCentre() {
        let picks = [circle(1, Vector2(5, 5)), point(2, Vector2(0, 0))]
        let made = make(.smart, picks, placing: Vector2(2, 20))
        #expect(made?.kind == .linear(.horizontal))
        #expect(made?.anchors == [.centre(pick(1)), picks[1].target])
    }

    @Test func pointAndLine() {
        // A horizontal line and a point: the distance across the line.
        let across = make(.smart, [point(1, Vector2(3, 8)), line(2, Vector2(0, 0), Vector2(10, 0))])
        #expect(across?.kind == .linear(.vertical))
        let vertical = make(.smart, [line(2, Vector2(0, 0), Vector2(0, 9)), point(1, Vector2(6, 3))])
        #expect(vertical?.kind == .linear(.horizontal))
        // A slanted line gives the perpendicular distance.
        #expect(make(.smart, [point(1, Vector2(3, 8)), line(2, Vector2(0, 0), Vector2(10, 4))])?.kind == .linear(.aligned))
    }

    @Test func parallelLines() {
        let top = line(1, Vector2(0, 8), Vector2(10, 8))
        let bottom = line(2, Vector2(0, 0), Vector2(10, 0))
        #expect(make(.smart, [top, bottom])?.kind == .linear(.vertical))
        let slantedA = line(3, Vector2(0, 0), Vector2(10, 5))
        let slantedB = line(4, Vector2(0, 4), Vector2(10, 9))
        #expect(make(.smart, [slantedA, slantedB])?.kind == .linear(.aligned))
    }

    @Test func twoLinesAreAnAngle() {
        let made = make(.smart, [line(1, Vector2(0, 0), Vector2(10, 0)), line(2, Vector2(0, 0), Vector2(0, 10))])
        #expect(made?.kind == .angle)
        #expect(made?.anchors.count == 2)
    }

    private func deepPoint(_ id: Int, _ p: Vector2, depth: Double) -> PickedAnchor {
        PickedAnchor(target: .corner(pick(id), pick(id + 50)), shape: .point(p), depth: depth)
    }

    private func alignedRefusal(_ picks: [PickedAnchor]) -> String? {
        if case .failure(let refused) = DimensionInference.make(tool: .smart, picks: picks, placing: Vector2(5, 12), aligned: true) {
            return refused.sentence
        }
        return nil
    }

    @Test func anAlignedDimensionBetweenPointsAtDifferentDepthsIsRefusedAtThePick() {
        let near = deepPoint(1, Vector2(0, 0), depth: 0)
        let far = deepPoint(2, Vector2(10, 4), depth: 7)
        #expect(
            alignedRefusal([near, far]) == "These points aren't at the same depth in this view, so the length would be foreshortened.")
        // The same depth, a plain horizontal dimension of two depths, and picks with no recorded depth all go through.
        #expect(alignedRefusal([near, deepPoint(2, Vector2(10, 4), depth: 0)]) == nil)
        #expect(make(.smart, [near, far], placing: Vector2(5, 12))?.kind == .linear(.horizontal))
        #expect(alignedRefusal([point(1, Vector2(0, 0)), point(2, Vector2(10, 4))]) == nil)
    }

    @Test func anAlignedDimensionToAnOutlineIsRefusedAtThePick() {
        let face = FacePick(tags: Fixture.tags(.side(segment: 4)))
        let outline = PickedAnchor(
            target: .outline(face, side: Vector2(0, -1)), shape: .cylinder(axisPoint: Vector2(0, 5), direction: Vector2(1, 0), radius: 5))
        #expect(alignedRefusal([outline, point(2, Vector2(10, 4))]) == "An outline can't take an aligned dimension.")
        // Without Shift the outline still gives a horizontal or vertical dimension.
        #expect(make(.smart, [outline, point(2, Vector2(10, 4))], placing: Vector2(5, 12))?.kind == .linear(.horizontal))
    }

    @Test func completionPerTool() {
        let one = line(1, Vector2(0, 0), Vector2(10, 0))
        #expect(!DimensionInference.isComplete([], tool: .smart))
        #expect(DimensionInference.isComplete([one], tool: .smart))
        #expect(DimensionInference.isComplete([circle(1, .zero)], tool: .smart))
        #expect(!DimensionInference.isComplete([point(1, .zero)], tool: .smart))
        #expect(DimensionInference.isComplete([point(1, .zero), one], tool: .smart))
        #expect(!DimensionInference.isComplete([one, one, one], tool: .smart))
        #expect(!DimensionInference.isComplete([point(1, .zero), point(2, .zero)], tool: .baseline))
        #expect(DimensionInference.isComplete([point(1, .zero), point(2, .zero), point(3, .zero)], tool: .chain))
        #expect(!DimensionInference.isComplete([point(1, .zero)], tool: .ordinate))
        #expect(DimensionInference.isComplete([point(1, .zero), point(2, .zero)], tool: .ordinate))
        #expect(DimensionInference.isComplete([one, one], tool: .chamfer))
        #expect(!DimensionInference.isComplete([one, point(2, .zero)], tool: .chamfer))
    }

    @Test func baselineDirectionByPlacement() {
        let picks = [point(1, Vector2(0, 0)), point(2, Vector2(10, 0)), point(3, Vector2(25, 0))]
        #expect(make(.baseline, picks, placing: Vector2(12, -8))?.kind == .baseline(.horizontal))
        #expect(make(.chain, picks, placing: Vector2(40, 0))?.kind == .chain(.vertical))
        #expect(make(.baseline, Array(picks.prefix(2)), placing: .zero) == nil)
    }

    @Test func aLineThatDoesntCrossIsRefused() {
        let along = line(4, Vector2(0, 0), Vector2(10, 0))
        let picks = [point(1, Vector2(0, 0)), point(2, Vector2(10, 5)), along]
        #expect(
            refusal(.baseline, picks, placing: Vector2(5, 20))
                == "A line in a baseline, chain or ordinate dimension must cross the direction it measures.")
        // The same picks measured the other way: the line crosses it.
        #expect(make(.baseline, picks, placing: Vector2(30, 2))?.kind == .baseline(.vertical))
        #expect(refusal(.ordinate, [point(1, .zero), along], placing: Vector2(5, 20)) != nil)
        // A slanted line crosses neither way: its end would depend on the side the dimension is placed.
        let slanted = line(5, Vector2(0, 0), Vector2(10, 4))
        let slantedPicks = [point(1, Vector2(0, 0)), point(2, Vector2(10, 5)), slanted]
        for placing in [Vector2(5, 20), Vector2(30, 2)] {
            #expect(
                refusal(.baseline, slantedPicks, placing: placing)
                    == "A line in a baseline, chain or ordinate dimension must cross the direction it measures.")
        }
    }

    @Test func ordinateTakesTheOriginFirst() {
        let picks = [point(1, Vector2(0, 0)), point(2, Vector2(10, 4)), point(3, Vector2(20, 9))]
        #expect(make(.ordinate, picks, placing: Vector2(10, -10))?.kind == .ordinate(.horizontal))
        #expect(make(.ordinate, picks, placing: Vector2(-12, 3))?.kind == .ordinate(.vertical))
    }

    @Test func chamferNeedsTwoLines() {
        let chamfer = line(1, Vector2(0, 5), Vector2(5, 0))
        let reference = line(2, Vector2(0, 0), Vector2(10, 0))
        #expect(make(.chamfer, [chamfer, reference])?.kind == .chamfer)
        #expect(
            refusal(.chamfer, [chamfer, point(3, .zero)])
                == "A chamfer takes two lines: the chamfer's edge, then a reference edge.")
        #expect(refusal(.chamfer, [chamfer]) != nil)
    }

    // MARK: Placement (R7)

    private let mapping = ViewMapping(scale: 2, offset: Vector2(100, 50))

    @Test func placementFromTheClick() {
        // A horizontal dimension of two points: n is up, the first feature point is the left one, at sheet (100, 50).
        let picks = [point(1, Vector2(0, 0)), point(2, Vector2(10, 0))]
        let above = DimensionInference.placement(
            for: .linear(.horizontal), picks: picks, placing: Vector2(110, 62), mapping: mapping)
        #expect(abs(above.offset - 12) < 1e-9 && above.angle == 0 && above.textShift == nil)
        let below = DimensionInference.placement(
            for: .linear(.horizontal), picks: picks, placing: Vector2(110, 44), mapping: mapping)
        #expect(abs(below.offset + 6) < 1e-9)
        // A vertical one: n is d turned 90 degrees, to the left.
        let tall = [point(1, Vector2(0, 0)), point(2, Vector2(0, 10))]
        let left = DimensionInference.placement(for: .linear(.vertical), picks: tall, placing: Vector2(90, 70), mapping: mapping)
        #expect(abs(left.offset - 10) < 1e-9)
    }

    @Test func aRadialPlacementIsTheClicksDirectionAndDistance() {
        let picks = [circle(1, Vector2(5, 5), radius: 3)]
        // The centre is at sheet (110, 60); the circle's sheet radius is 6.
        let placed = DimensionInference.placement(for: .diameter, picks: picks, placing: Vector2(110, 80), mapping: mapping)
        #expect(abs(placed.angle - .pi / 2) < 1e-9)
        #expect(abs(placed.offset - 14) < 1e-9)
    }

    @Test func anAlignedPlacementMeasuresAlongTheLine() {
        // A line from (0,0) to (10,0) aligned: d along x, n up, from the first end.
        let picks = [line(1, Vector2(0, 0), Vector2(10, 0))]
        let placed = DimensionInference.placement(for: .linear(.aligned), picks: picks, placing: Vector2(110, 58), mapping: mapping)
        #expect(abs(placed.offset - 8) < 1e-9)
    }

    @Test func anAnglePlacementIsAboutTheVertex() {
        let picks = [line(1, Vector2(0, 0), Vector2(10, 0)), line(2, Vector2(0, 0), Vector2(0, 10))]
        let placed = DimensionInference.placement(for: .angle, picks: picks, placing: Vector2(110, 50), mapping: mapping)
        // The vertex is at sheet (100, 50): the click lies 10 mm along +x.
        #expect(abs(placed.offset - 10) < 1e-9 && abs(placed.angle) < 1e-9)
    }
}
