import CoreGraphics
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The chip's feed from the document (`AppModel.followEvaluation()`) and its drawing in the app's real window. How it looks is a
/// human check (group SE).
@MainActor
struct SlowEvaluationAppTests {
    func yield() async { for _ in 0..<10 { await Task.yield() } }

    @Test func anEditMarksTheNodeAndTheChipFollowsIt() async throws {
        var builder = GraphBuilder()
        let (_, extrude, _) = builder.box()
        let app = try await AppWindow.open(builder.graph)
        let gate = WaitGate()
        app.model.slowEvaluation.wait = { try await gate.wait($0) }
        #expect(app.model.slowEvaluation.running.isEmpty)

        try app.model.document.perform(.setInput(extrude.id, "distance", .number(12)), name: "Test")
        app.model.followEvaluation()  // the nodes are marked now; observation would deliver this on the next turn
        #expect(app.model.slowEvaluation.running.contains("Extrude"))
        #expect(app.model.slowEvaluation.text == nil, "not before 0.5 s")
        gate.open()
        await app.model.slowEvaluation.waitForTimer()
        #expect(app.model.slowEvaluation.text != nil)

        await app.model.settle()
        await yield()
        #expect(app.model.slowEvaluation.running.isEmpty && app.model.slowEvaluation.text == nil, "gone when the evaluation ends")
    }

    @Test func aNodeThatFailsOrNeverRunsLeavesNoChip() async throws {
        var builder = GraphBuilder()
        let extrude = builder.add(ExtrudeNode.self)  // no profile: it can't build
        let output = builder.add(OutputNode.self)
        builder.wire(extrude, "solid", to: output, "solid")
        let app = try await AppWindow.open(builder.graph)
        try app.model.document.perform(.setInput(extrude.id, "distance", .number(3)), name: "Test")
        await app.model.settle()
        await yield()
        #expect(app.model.slowEvaluation.running.isEmpty && app.model.slowEvaluation.text == nil)
    }

    func rect(_ element: TestElement) -> CGRect {
        let frame = element.frame
        return CGRect(x: Double(frame.origin.x.value), y: Double(frame.origin.y.value),
                      width: Double(frame.size.width.value), height: Double(frame.size.height.value))
    }

    @Test func theChipIsDrawnAndDoesNotOverlapTheMeshBadge() async throws {
        var builder = GraphBuilder()
        let sphere = builder.add(ImplicitSphereNode.self, ["radius": .number(6)])
        let mesh = builder.add(MeshNode.self, ["preview resolution": .number(1)])
        let output = builder.add(OutputNode.self)
        builder.wire(sphere, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        let app = try await AppWindow.open(builder.graph)
        try await app.window.runUntilIdle()
        let gate = WaitGate()
        gate.open()
        app.model.slowEvaluation.wait = { try await gate.wait($0) }
        #expect(try app.window.elements { $0.label == "Building Fillet…" }.isEmpty)

        app.model.slowEvaluation.follow(["Fillet"])
        await app.model.slowEvaluation.waitForTimer()
        try await app.window.runUntilIdle()
        let chips = try app.window.elements { $0.label == "Building Fillet…" || $0.value == "Building Fillet…" }
        let badges = try app.window.elements { $0.label == "Preview 1 mm" || $0.value == "Preview 1 mm" }
        let chip = try #require(chips.first)
        let badge = try #require(badges.first)
        #expect(!rect(chip).intersects(rect(badge)), "chip \(rect(chip)) badge \(rect(badge))")
        #expect(rect(chip).maxY <= rect(badge).minY, "the chip stands above the badge")

        app.model.slowEvaluation.follow([])
        try await app.window.runUntilIdle()
        #expect(try app.window.elements { $0.label == "Building Fillet…" || $0.value == "Building Fillet…" }.isEmpty)
    }
}
