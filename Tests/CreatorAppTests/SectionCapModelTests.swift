import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Foundation
import Testing
@testable import CreatorApp

/// The section's cap in the app (section spec §3.3 to §3.5): computed off the main actor, shown on the viewport, no edit.
@MainActor
struct SectionCapModelTests {
    func boxApp(kernel: FakeKernel = FakeKernel()) async -> AppModel {
        var builder = GraphBuilder()
        _ = builder.box()
        return await makeApp(builder.graph, kernel: kernel)
    }

    @Test func turningTheSectionOnShowsACap() async throws {
        let app = await boxApp()
        app.setSection(true)
        await app.settle()
        let section = try #require(app.viewport.section)
        #expect(section.caps.count == 1 && !section.caps[0].triangles.isEmpty && !section.caps[0].outlines.isEmpty)
        #expect(!app.isEdited && !app.document.canUndo)
    }

    @Test func turningItOffClearsTheCap() async {
        let app = await boxApp()
        app.setSection(true)
        await app.settle()
        #expect(app.viewport.section != nil)
        app.setSection(false)
        await app.settle()
        #expect(app.viewport.section == nil && app.sectionCaps.section == nil)
    }

    @Test func sketchModeClearsTheCap() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.setSection(true)
        await app.settle()
        #expect(app.viewport.section != nil)
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        #expect(app.sketch != nil && app.viewport.section == nil)
    }

    @Test func aPlaneBesideThePartShowsNoCapAndNoProblem() async {
        let app = await boxApp()
        app.setSection(true)
        await app.settle()
        app.setSectionOffset(1000)
        await app.settle()
        #expect(app.viewport.section == nil && app.sectionCaps.problem == nil)
    }

    @Test func aBurstOfMovesPublishesOnlyTheLast() async throws {
        let app = await boxApp()
        app.setSection(true)
        await app.settle()
        let before = app.sectionCaps.revision
        for step in 1...20 { app.setSectionOffset(Double(step) * 0.1) }
        await app.settle()
        let clip = try #require(app.viewport.clip)
        let section = try #require(app.viewport.section)
        let expected = SectionCaps.plane(for: clip)
        #expect(section.plane == expected)
        for position in section.caps.flatMap(\.positions) {
            #expect(abs((position - expected.origin).dot(expected.normal)) < 1e-9)
        }
        #expect(app.sectionCaps.revision - before < 20)
    }

    @Test func aRefusedSectionLeavesNoCapAndSaysSo() async throws {
        let kernel = FakeKernel()
        let app = await boxApp(kernel: kernel)
        await kernel.setSectionHook { throw KernelError.unsupported("section") }
        app.setSection(true)
        await app.settle()
        #expect(app.viewport.section == nil)
        #expect(app.sectionCaps.problem == SectionCapModel.capProblem)
    }

    @Test func theRefusalShowsInThePanel() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let kernel = FakeKernel()
        let window = try await AppWindow.open(builder.graph, kernel: kernel)
        await kernel.setSectionHook { throw KernelError.unsupported("section") }
        window.model.setSection(true)
        await window.model.settle()
        try await window.window.runUntilIdle()
        #expect(window.model.sectionCaps.problem == SectionCapModel.capProblem)
        let text = SectionCapModel.capProblem
        let lines = try window.window.elements { $0.label == text || $0.value == text }
        #expect(!lines.isEmpty)
    }

    @Test func ghostItemsAreNotCapped() async throws {
        let app = await boxApp()
        let solid = try #require(app.viewport.items.first).solid
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        let clip = ViewportClip(origin: solid.bounds.center, normal: .unitZ)
        model.follow(clip: clip, items: [ViewportItem(solid: solid, isGhost: true)])
        await model.waitForCaps()
        #expect(model.section == nil)
        model.follow(clip: clip, items: [ViewportItem(solid: solid, isGuide: true)])
        await model.waitForCaps()
        #expect(model.section == nil && model.problem == nil)
        model.follow(clip: clip, items: [ViewportItem(solid: solid), ViewportItem(solid: solid, isGhost: true)])
        await model.waitForCaps()
        #expect(model.section?.caps.count == 1)
    }

    @Test func theOldCapStaysUntilTheNewOneLands() async throws {
        let kernel = FakeKernel()
        let app = await boxApp(kernel: kernel)
        app.setSection(true)
        await app.settle()
        let old = try #require(app.viewport.section)
        let gate = DispatchSemaphore(value: 0)
        let (entered, signal) = AsyncStream<Void>.makeStream()
        await kernel.setSectionHook {
            signal.yield()
            _ = gate.wait(timeout: .now() + 60)
        }
        app.setSectionOffset(1)
        let reached = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in entered { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(60)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        try #require(reached, "the section hook was never reached")
        #expect(app.sectionCaps.isComputing, "the new section is under way")
        let clip = try #require(app.viewport.clip)
        #expect(abs((clip.origin - old.plane.origin).length - 1) < 1e-3, "the viewport is clipped at the new offset")
        #expect(app.viewport.section == old, "the previous cap is still shown")
        gate.signal()
        await app.settle()
        let new = try #require(app.viewport.section)
        #expect(new.generation != old.generation)
    }

    @Test func planeForAClipIsInsetTowardsTheKeptSide() throws {
        let clip = ViewportClip(origin: Vector3(1, 2, 3), normal: Vector3(0, 0, 1))
        let plane = SectionCaps.plane(for: clip)
        #expect(plane.normal == clip.normal)
        #expect((plane.origin - (clip.origin - clip.normal * SectionCaps.inset)).length < 1e-12)
        #expect(abs(plane.xAxis.length - 1) < 1e-12 && abs(plane.xAxis.dot(plane.normal)) < 1e-12)
        let tilted = SectionCaps.plane(for: ViewportClip(origin: .zero, normal: Vector3(1, 1, 1)))
        #expect(abs(tilted.xAxis.length - 1) < 1e-12 && abs(tilted.xAxis.dot(Vector3(1, 1, 1).normalized ?? .zero)) < 1e-12)
    }

    /// A closed box mesh from 0 to `size` on every axis, as a display-only solid.
    private func meshSolid(size: Double) -> Solid {
        let corners = (0..<8).map { Vector3(($0 & 1) == 0 ? 0 : size, ($0 & 2) == 0 ? 0 : size, ($0 & 4) == 0 ? 0 : size) }
        let indices: [UInt32] = [0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6, 0, 1, 4, 1, 5, 4, 2, 6, 3, 3, 6, 7, 0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5]
        return Solid(displaying: DisplayMesh(positions: corners, normals: corners.map { _ in .unitZ }, indices: indices,
                                             triangleFaces: Array(repeating: FaceID(0), count: 12), edgePolylines: [:]))
    }

    @Test func aReplacedMeshIsCutAgain() async throws {
        let (first, second) = (meshSolid(size: 10), meshSolid(size: 20))
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        let clip = ViewportClip(origin: Vector3(0, 0, 5), normal: .unitZ)
        model.follow(clip: clip, items: [ViewportItem(solid: first)])
        await model.waitForCaps()
        let before = try #require(model.section)
        model.follow(clip: clip, items: [ViewportItem(solid: second)])
        await model.waitForCaps()
        let after = try #require(model.section)
        #expect(after.generation != before.generation)
        let mesh = try #require(second.displayedMesh)
        let direct = MeshSlicer.slice(positions: mesh.positions, triangles: mesh.indices, plane: SectionCaps.plane(for: clip))
        let expected = try #require(SectionCaps.cap(from: direct, hatchAngle: ViewportSection.hatchAngle(forCap: 0)))
        #expect(after.caps[0].positions == expected.positions && after.caps[0].triangles == expected.triangles)
        #expect(after.caps[0].positions != before.caps[0].positions)
    }

    @Test func aBurstOfMovesOnAMeshPartStartsAtMostTwoSlices() async throws {
        let solid = meshSolid(size: 10)
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        var last = ViewportClip(origin: .zero, normal: .unitZ)
        for step in 1...20 {
            last = ViewportClip(origin: Vector3(0, 0, Double(step) * 0.4), normal: .unitZ)
            model.follow(clip: last, items: [ViewportItem(solid: solid)])
        }
        await model.waitForCaps()
        #expect(model.slicesStarted <= 2 && !model.isComputing)
        let section = try #require(model.section)
        #expect(section.plane == SectionCaps.plane(for: last))
    }

    @Test func aBodyWithNoCutDoesNotShiftTheOthersHatchAngle() async throws {
        let (far, near) = (meshSolid(size: 10), meshSolid(size: 10))
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        let moved = Solid(displaying: DisplayMesh(
            positions: try #require(far.displayedMesh).positions.map { $0 + Vector3(0, 0, 100) }, normals: [],
            indices: try #require(far.displayedMesh).indices, triangleFaces: try #require(far.displayedMesh).triangleFaces,
            edgePolylines: [:]))
        let clip = ViewportClip(origin: Vector3(0, 0, 5), normal: .unitZ)
        model.follow(clip: clip, items: [ViewportItem(solid: moved), ViewportItem(solid: near)])
        await model.waitForCaps()
        let caps = try #require(model.section).caps
        #expect(caps.count == 1 && caps[0].hatchAngle == ViewportSection.hatchAngle(forCap: 1))
    }

    @Test func aRegionWithOutlinesAndNoTrianglesIsAProblem() {
        let loop = [Vector3.zero, Vector3(1, 0, 0), Vector3(1, 1, 0), .zero]
        let piece = SectionPiece(curve: nil, polyline: loop, sourceFace: nil)
        let unfilled = PlaneSection(regions: [SectionRegion(positions: [], triangles: [], boundary: [piece])])
        let corners = [Vector3.zero, Vector3(1, 0, 0), Vector3(1, 1, 0)]
        let filled = PlaneSection(regions: [SectionRegion(positions: corners, triangles: [0, 1, 2], boundary: [piece])])
        #expect(SectionCaps.isUnfilled(unfilled) && !SectionCaps.isUnfilled(filled) && !SectionCaps.isUnfilled(PlaneSection()))
    }

    @Test func nilClearsOnce() {
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        model.follow(clip: nil, items: [])
        #expect(model.revision == 0)
    }

    @Test func twoNilFollowsAfterACapBumpTheRevisionOnce() async throws {
        let app = await boxApp()
        let solid = try #require(app.viewport.items.first).solid
        let model = SectionCapModel(kernel: FakeKernel(), tolerance: 0.05)
        model.follow(clip: ViewportClip(origin: solid.bounds.center, normal: .unitZ), items: [ViewportItem(solid: solid)])
        await model.waitForCaps()
        #expect(model.section != nil)
        let before = model.revision
        model.follow(clip: nil, items: [])
        model.follow(clip: nil, items: [])
        #expect(model.revision == before + 1 && model.section == nil)
    }
}
