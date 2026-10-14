import CreatorGeometry
import Testing
@testable import CreatorImplicit

struct PreviewScheduleTests {
    let box = BoundingBox(min: .zero, max: Vector3(100, 50, 20))

    @Test func theFirstPassIsOneHundredTwentyEightCellsAcross() {
        #expect(PreviewSchedule(.automatic).firstResolution(for: box) == 100.0 / 128)
        #expect(PreviewSchedule(.fixed(2)).firstResolution(for: box) == 2, "a coarse target is the only pass")
        #expect(PreviewSchedule(.fixed(0.1)).firstResolution(for: box) == 100.0 / 128)
    }

    @Test func aFixedTargetHalvesUntilItIsReached() {
        let schedule = PreviewSchedule(.fixed(0.2))
        var resolution = schedule.firstResolution(for: box)
        var passes = [resolution]
        while let next = schedule.next(after: resolution, seconds: 0.01) {
            passes.append(next)
            resolution = next
        }
        #expect(passes.count == 3 && passes.last == 0.2)
        #expect(abs(passes[1] - passes[0] / 2) < 1e-12)
    }

    @Test func automaticKeepsGoingWhileThePassesAreFast() {
        let schedule = PreviewSchedule(.automatic)
        #expect(schedule.next(after: 0.8, seconds: 0.1) == 0.4)
        #expect(schedule.next(after: 0.8, seconds: 0.3) == nil, "four times 0.3 s is over a second")
        #expect(schedule.next(after: 0.05, seconds: 0.001) == nil, "nothing finer than 0.05 mm")
    }
}
