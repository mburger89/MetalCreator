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
        while let next = schedule.next(after: resolution, seconds: 0.01, triangles: 0) {
            passes.append(next)
            resolution = next
        }
        #expect(passes.count == 3 && passes.last == 0.2)
        #expect(abs(passes[1] - passes[0] / 2) < 1e-12)
    }

    @Test func automaticKeepsGoingWhileThePassesAreFast() {
        let schedule = PreviewSchedule(.automatic)
        #expect(schedule.next(after: 0.8, seconds: 0.1, triangles: 0) == 0.4)
        #expect(schedule.next(after: 0.8, seconds: 0.3, triangles: 0) == nil, "four times 0.3 s is over a second")
        #expect(schedule.next(after: 0.05, seconds: 0.001, triangles: 0) == nil, "nothing finer than 0.05 mm")
    }

    @Test func automaticStopsBeforeAPassOverTheTriangleCap() {
        let schedule = PreviewSchedule(.automatic)
        #expect(schedule.next(after: 0.8, seconds: 0.01, triangles: 250_000) == 0.4, "four times 250,000 is exactly the cap")
        #expect(schedule.next(after: 0.8, seconds: 0.01, triangles: 250_001) == nil, "over one million triangles (the measured cap, D19)")
        #expect(schedule.next(after: 0.8, seconds: 0.01, triangles: 1_000_000) == nil)
        #expect(PreviewSchedule(.fixed(0.2)).next(after: 0.8, seconds: 0.01, triangles: 5_000_000) == 0.4, "a fixed target is the user's")
        // Both limits apply: a slow pass stops it even when the triangles are few.
        #expect(schedule.next(after: 0.8, seconds: 0.3, triangles: 10) == nil)
    }

    @Test(arguments: [0.0, -1.0, Double.nan, 0.001])
    func aFixedTargetBelowTheFinestIsClampedAndTerminates(wanted: Double) {
        let schedule = PreviewSchedule(.fixed(wanted))
        #expect(schedule.target == .fixed(PreviewSchedule.finest))
        var resolution = schedule.firstResolution(for: box)
        var passes = 1
        while let next = schedule.next(after: resolution, seconds: 0.01, triangles: 0), passes < 100 {
            #expect(next >= PreviewSchedule.finest)
            resolution = next
            passes += 1
        }
        #expect(passes < 100 && resolution >= PreviewSchedule.finest)
    }
}
