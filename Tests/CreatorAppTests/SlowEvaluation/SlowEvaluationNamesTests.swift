import CreatorKernel
import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorApp

/// Which node names the chip puts first: the slowest last time, never an Output (human checks SE-1 and SE-3).
@MainActor
struct SlowEvaluationNamesTests {
    private func node(_ title: String, _ id: String, output: Bool = false, took milliseconds: Int64 = 0) -> AppModel.EvaluatingNode {
        AppModel.EvaluatingNode(title: title, id: id, isOutput: output, lastDuration: .milliseconds(milliseconds))
    }

    @Test func theSlowestNodeLastTimeComesFirst() {
        let names = AppModel.chipNames(of: [node("All Edges", "1"), node("Fillet", "2", took: 400), node("Box", "3", took: 5)])
        #expect(names == ["Fillet", "Box", "All Edges"])
    }

    @Test func theChipReadsTheSlowNodeWithTheOthersCountedAndNoOutput() async {
        func text(_ nodes: [AppModel.EvaluatingNode]) async -> String? {
            let model = SlowEvaluationModel()
            let gate = WaitGate()
            model.wait = { try await gate.wait($0) }
            model.follow(running: true, names: AppModel.chipNames(of: nodes))
            gate.open()
            await model.waitForTimer()
            return model.text
        }
        let output = node("Output", "0", output: true, took: 900)
        #expect(await text([output, node("Fillet", "1", took: 400), node("All Edges", "2"), node("Box", "3", took: 2)])
                == "Building Fillet and 2 more…")
        #expect(await text([node("Fillet", "1", took: 400), output]) == "Building Fillet…")
        #expect(await text([output]) == "Building…")
    }

    @Test func aSlowNodeBesideFastNodesAndAnOutputReadsAsItAndTheOthersCounted() {
        let names = AppModel.chipNames(of: [node("Output", "0", output: true, took: 900), node("Fillet", "1", took: 400),
                                            node("All Edges", "2"), node("Box", "3", took: 2), node("Extrude", "4", took: 1),
        ])
        #expect(names == ["Fillet", "Box", "Extrude", "All Edges"])
        let model = SlowEvaluationModel()
        model.follow(running: true, names: names)
        #expect(model.running == names)
    }

    @Test func anOutputIsLeftOutOfTheNameAndTheCount() {
        #expect(AppModel.chipNames(of: [node("Fillet", "1", took: 3), node("Output", "2", output: true, took: 50)]) == ["Fillet"])
    }

    @Test func onlyAnOutputLeavesNoName() {
        #expect(AppModel.chipNames(of: [node("Output", "1", output: true)]).isEmpty)
    }

    @Test func equalTimesFallBackToNameThenID() {
        let names = AppModel.chipNames(of: [node("Box", "9"), node("Box", "2"), node("Arc", "5")])
        #expect(names.count == 3 && names[0] == "Arc")
        let again = AppModel.chipNames(of: [node("Arc", "5"), node("Box", "2"), node("Box", "9")])
        #expect(names == again)
    }

    // MARK: - From the document

    @Test func theDocumentRemembersEachNodesLastTimeAndTheChipNamesNoOutput() async throws {
        var builder = GraphBuilder()
        let (_, extrude, _) = builder.box()
        let app = try await AppWindow.open(builder.graph)
        let model = app.model
        #expect(model.document.lastDurations[extrude.id] != nil)
        try model.document.perform(.setInput(extrude.id, "distance", .number(12)), name: "Test")
        let names = model.evaluatingNodeNames()
        #expect(names.contains("Extrude") && !names.contains("Output"), "\(names)")
        await model.settle()
    }

    @Test func aReplacedDocumentForgetsTheTimes() async throws {
        var builder = GraphBuilder()
        let (_, extrude, _) = builder.box()
        let app = try await AppWindow.open(builder.graph)
        #expect(app.model.document.lastDurations[extrude.id] != nil)
        app.model.newDocument()
        #expect(app.model.document.lastDurations.isEmpty)
    }
}
