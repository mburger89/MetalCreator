import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The kernel recognises the shim's refusals by their wording (`OCCTKernel.weightMessage`, `cornerMessage`); a drift
/// between `cocct_g2_blend.cpp` and Swift turns them into a generic failure and fails here.
struct G2FilletRefusalWordingTests {
    func edges(of solid: Solid, where keep: (Vector3) -> Bool) -> [EdgeID] {
        solid.topology.edges.filter { keep($0.midpoint) }.map(\.id)
    }

    @Test func aWeightOfTwoIsRefusedInTheShimsWords() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let (low, high) = (solid.bounds.min, solid.bounds.max)
        let top = edges(of: solid) { isClose($0.y, low.y) && isClose($0.z, high.z) }
        #expect(top.count == 1)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(solid, edges: top, radius: 2, profile: .curvatureContinuous(weight: 2), tag: newTag())
        }
        #expect(error == .invalidInput("The tangency weight is too large for this fillet."))
        #expect(error?.userMessage == "The tangency weight is too large for this fillet.")
    }

    /// A light weight (0.1) at the box's three-edge corner leaves the corner patch nothing to fill smoothly.
    @Test func aCornerThatCannotBeFilledIsRefusedInTheShimsWords() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 20, 20, 10)
        let (low, high) = (solid.bounds.min, solid.bounds.max)
        let corner = edges(of: solid) {
            (isClose($0.y, low.y) && isClose($0.z, high.z)) || (isClose($0.x, low.x) && isClose($0.z, high.z))
                || (isClose($0.x, low.x) && isClose($0.y, low.y))
        }
        #expect(corner.count == 3)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(solid, edges: corner, radius: 1, profile: .curvatureContinuous(weight: 0.1), tag: newTag())
        }
        #expect(error == .invalidInput("The fillet's corners can't be made smooth at this radius."))
    }
}
