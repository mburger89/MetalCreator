import Testing
@testable import CreatorApp

/// A wait the test opens by hand, so no test sleeps. A cancelled wait throws, as `Task.sleep` does.
@MainActor
final class WaitGate {
    private(set) var isOpen = false
    private(set) var waits = 0

    func wait(_ duration: Duration) async throws {
        waits += 1
        while !isOpen {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    func open() { isOpen = true }
}

@MainActor
struct SlowEvaluationModelTests {
    func make() -> (SlowEvaluationModel, WaitGate) {
        let model = SlowEvaluationModel()
        let gate = WaitGate()
        model.wait = { try await gate.wait($0) }
        return (model, gate)
    }

    func yield() async { for _ in 0..<5 { await Task.yield() } }

    @Test func theDelayIsHalfASecond() {
        #expect(SlowEvaluationModel().delay == .milliseconds(500))
    }

    @Test func nothingShowsBeforeTheDelay() async {
        let (model, _) = make()
        model.follow(running: true, names: ["Fillet"])
        await yield()
        #expect(model.text == nil && !model.isDue)
        #expect(model.running == ["Fillet"])
    }

    @Test func itShowsOnceTheDelayHasPassed() async {
        let (model, gate) = make()
        model.follow(running: true, names: ["Fillet"])
        gate.open()
        await model.waitForTimer()
        #expect(model.text == "Building Fillet…")
    }

    @Test func aFastEvaluationNeverShowsIt() async {
        let (model, gate) = make()
        model.follow(running: true, names: ["Fillet"])
        model.follow(running: false, names: [])
        gate.open()
        await model.waitForTimer()
        await yield()
        #expect(model.text == nil && !model.isDue)
    }

    @Test func itGoesWhenTheEvaluationEnds() async {
        // Finished, failed and cancelled all leave no node evaluating: the list is empty.
        let (model, gate) = make()
        model.follow(running: true, names: ["Fillet"])
        gate.open()
        await model.waitForTimer()
        model.follow(running: false, names: [])
        #expect(model.text == nil && !model.isDue && model.running.isEmpty)
    }

    @Test func aRunAfterAnEndedOneWaitsAgain() async {
        let (model, gate) = make()
        model.follow(running: true, names: ["Fillet"])
        gate.open()
        await model.waitForTimer()
        model.follow(running: false, names: [])
        let closed = WaitGate()
        model.wait = { try await closed.wait($0) }
        model.follow(running: true, names: ["Fillet"])
        await yield()
        #expect(model.text == nil, "the second run has not lasted 0.5 s yet")
    }

    @Test func aReplacingEvaluationKeepsTheWaitAndNeverFlickers() async {
        let (model, gate) = make()
        model.follow(running: true, names: ["Fillet"])
        let first = model.timer
        model.follow(running: true, names: ["Fillet"])  // a newer evaluation replaced a cancelled one: the nodes stayed marked
        model.follow(running: true, names: ["Box", "Fillet"])
        #expect(model.timer == first && gate.waits <= 1)
        gate.open()
        await model.waitForTimer()
        #expect(model.text == "Building Box and 1 more…")
        model.follow(running: true, names: ["Fillet"])
        #expect(model.text == "Building Fillet…", "shown once the wait ended, still shown through the replacement")
    }

    @Test func oneNodeIsNamedAlone() async {
        let (model, gate) = make()
        gate.open()
        model.follow(running: true, names: ["Fillet"])
        await model.waitForTimer()
        #expect(model.text == "Building Fillet…")
    }

    @Test func severalNameTheFirstAndCountTheRest() async {
        let (model, gate) = make()
        gate.open()
        model.follow(running: true, names: ["Fillet", "Loft"])
        await model.waitForTimer()
        #expect(model.text == "Building Fillet and 1 more…")
        model.follow(running: true, names: ["Fillet", "Loft", "Box"])
        #expect(model.text == "Building Fillet and 2 more…")
    }

    @Test func resetForgetsTheRun() async {
        let (model, gate) = make()
        gate.open()
        model.follow(running: true, names: ["Fillet"])
        await model.waitForTimer()
        model.reset()
        #expect(model.text == nil && model.running.isEmpty)
    }

    @Test func aRunWithNoNamedNodesReadsBuilding() async {
        let (model, gate) = make()
        model.follow(running: true, names: [])
        await yield()
        #expect(model.text == nil, "not before the delay")
        gate.open()
        await model.waitForTimer()
        #expect(model.text == "Building…")
        model.follow(running: false, names: [])
        #expect(model.text == nil)
    }

    @Test func namesAppearingMidRunChangeTheWordingWithoutRestartingTheWait() async {
        let (model, gate) = make()
        model.follow(running: true, names: [])
        let first = model.timer
        model.follow(running: true, names: ["Fillet"])
        #expect(model.timer == first)
        gate.open()
        await model.waitForTimer()
        #expect(model.text == "Building Fillet…")
        model.follow(running: true, names: [])
        #expect(model.text == "Building…", "names gone, the run is still on, so the chip stays")
    }
}
