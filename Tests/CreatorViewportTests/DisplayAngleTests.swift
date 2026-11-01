import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The display mesh's angular deflection (zebra needs a finer one): it reaches the kernel, the shown meshes stay up
/// until the finer ones land, and the last request wins.
@MainActor
struct DisplayAngleTests {
    func model(_ kernel: StubMeshKernel) -> ViewportModel {
        let model = ViewportModel(kernel: kernel, pose: nil)
        model.viewSize = ViewportSize(width: 400, height: 300)
        return model
    }

    @Test func theAngleReachesTheKernel() async throws {
        let kernel = StubMeshKernel()
        let model = model(kernel)
        let part = try await fakeBox()
        model.show([ViewportItem(solid: part)])
        await model.waitForMeshes()
        model.displayAngle = DisplayAngle.zebra
        model.show([ViewportItem(solid: part)])
        await model.waitForMeshes()
        #expect(await kernel.angles == [DisplayAngle.standard, DisplayAngle.zebra])
    }

    @Test func aChangeAppliesAtTheNextShowOnly() async throws {
        let kernel = StubMeshKernel()
        let model = model(kernel)
        let part = try await fakeBox()
        model.show([ViewportItem(solid: part)])
        await model.waitForMeshes()
        model.displayAngle = DisplayAngle.zebra
        #expect(await kernel.tessellations == 1)
    }

    @Test func aSolidKeepsItsMeshUntilTheFinerOneLands() async throws {
        let kernel = StubMeshKernel()
        await kernel.setFineDelay(milliseconds: 200)
        let model = model(kernel)
        let part = try await fakeBox()
        model.show([ViewportItem(solid: part)])
        await model.waitForMeshes()
        let coarse = try #require(model.displayMesh(of: part))
        model.displayAngle = DisplayAngle.zebra
        model.show([ViewportItem(solid: part)])
        #expect(model.displayMesh(of: part)?.positions == coarse.positions, "while the finer mesh is being made")
        await model.waitForMeshes()
        let fine = try #require(model.displayMesh(of: part))
        #expect(fine.positions != coarse.positions)
    }

    @Test func theLastToggleWins() async throws {
        let kernel = StubMeshKernel()
        await kernel.setFineDelay(milliseconds: 30)
        let model = model(kernel)
        let part = try await fakeBox()
        model.show([ViewportItem(solid: part)])
        await model.waitForMeshes()
        let coarse = try #require(model.displayMesh(of: part))
        for angle in [DisplayAngle.zebra, DisplayAngle.standard, DisplayAngle.zebra] {
            model.displayAngle = angle
            model.show([ViewportItem(solid: part)])
        }
        await model.waitForMeshes()
        let settled = try #require(model.displayMesh(of: part))
        #expect(settled.positions != coarse.positions, "the settled mesh is the fine one")
        #expect(await kernel.angles.last == DisplayAngle.zebra)
    }
}
