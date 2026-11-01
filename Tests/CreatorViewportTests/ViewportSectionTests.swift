import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The section's cap in the viewport model (section spec part B): stored and cleared by `showSection`, part of the render key by
/// its generation, hatched at angles that cycle by the cap's order.
@MainActor
struct ViewportSectionTests {
    func section(generation: Int) -> ViewportSection {
        let cap = ViewportSection.Cap(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], triangles: [0, 1, 2],
                                      outlines: [], hatchAngle: 0)
        return ViewportSection(caps: [cap], plane: .xz, generation: generation)
    }

    @Test func showSectionStoresAndClears() {
        let model = ViewportModel(kernel: FakeKernel())
        #expect(model.section == nil)
        model.showSection(section(generation: 1))
        #expect(model.section?.generation == 1)
        model.showSection(nil)
        #expect(model.section == nil)
    }

    @Test func aNewGenerationChangesTheRenderKey() {
        let model = ViewportModel(kernel: FakeKernel())
        let none = model.renderKey
        model.showSection(section(generation: 1))
        let first = model.renderKey
        model.showSection(section(generation: 1))
        #expect(model.renderKey == first, "an equal generation changes nothing")
        model.showSection(section(generation: 2))
        #expect(model.renderKey != first && first != none)
    }

    @Test func theHatchAnglesCycle() {
        let degrees = (0...6).map { ViewportSection.hatchAngle(forCap: $0) * 180 / .pi }
        for (got, want) in zip(degrees, [45.0, 135, 15, 105, 75, 165, 45]) { #expect(abs(got - want) < 1e-9) }
    }
}
