import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import CreatorViewport
import Testing
@testable import CreatorApp

/// The slice plane's state in the preview model (fields spec §6, "Slice plane"): its start, its toggles and its handle.
@MainActor
struct FieldPreviewSliceTests {
    let node = NodeID()
    let noise = Field.noise(seed: 3, scale: 6, octaves: 1)
    let colors = ColorTheme.dracula.colors

    func following(_ field: Field, toEye: Vector3 = .unitZ) async throws -> (FieldPreviewModel, PreviewHarness, Solid) {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, field, [part], toEye: toEye))
        await model.waitForSampling()
        return (model, harness, part)
    }

    @Test func aNewNodeStartsWithTheSliceShownThroughThePartOnTheAxisPlaneNearestTheCamera() async throws {
        let (model, _, part) = try await following(noise)
        #expect(model.choice == .axis(.xy) && model.offset == 0)
        let slice = try #require(model.viewportSlice(colors: colors))
        #expect(slice.columns == 256 && slice.rows == 256 && slice.isValid)
        #expect(slice.origin == part.bounds.center && slice.opacity == 0.85)
        #expect(model.legend?.choice == .axis(.xy) && !(model.legend?.hasOwnPlane ?? true))
        let side = try await following(noise, toEye: .unitX).0
        #expect(side.choice == .axis(.yz))
    }

    @Test func aFieldThatMeasuresWithTheKernelGetsTheCoarserGrid() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, .distance(.kernel(.solid(part)), signed: false), [part]))
        await model.waitForSampling()
        let slice = try #require(model.viewportSlice(colors: colors))
        #expect(slice.columns == 64 && slice.rows == 64 && slice.values.count == 4_096)
    }

    @Test func aGradientsPlaneIsWhereItStartsAndTheLegendCanGoBackToIt() async throws {
        let plane = Plane(origin: Vector3(-10, 0, 0), normal: .unitX, xAxis: .unitY)
        let (model, _, _) = try await following(.linearGradient(plane: plane, length: 20))
        #expect(model.choice == .own && model.hasOwnPlane)
        #expect(model.viewportSlice(colors: colors)?.origin.x == -10, "on the gradient's own plane")
        model.chooseSlice(.axis(.yz))
        await model.waitForSampling()
        #expect(model.choice == .axis(.yz) && model.viewportSlice(colors: colors)?.origin.x == 0)
        model.chooseSlice(.own)
        await model.waitForSampling()
        #expect(model.viewportSlice(colors: colors)?.origin.x == -10)
    }

    @Test func theAxisButtonsResampleOnThePlaneAndHidingTakesTheSliceAndItsHandleAway() async throws {
        let (model, _, part) = try await following(noise)
        let first = try #require(model.viewportSlice(colors: colors))
        model.chooseSlice(.axis(.xz))
        #expect(model.viewportSlice(colors: colors) == nil, "the old quad is for another plane: gone until the new one is ready")
        await model.waitForSampling()
        let second = try #require(model.viewportSlice(colors: colors))
        #expect(abs(second.yAxis.z) == 1 && second.generation != first.generation && second.origin == part.bounds.center)
        model.chooseSlice(.hidden)
        #expect(model.viewportSlice(colors: colors) == nil && model.sliceHandle == nil && model.pose == nil)
        #expect(model.legend?.choice == .hidden)
        await model.waitForSampling()
        #expect(model.viewportSlice(colors: colors) == nil, "and it stays hidden when a sampling finishes")
    }

    @Test func theHandleSitsOnThePlaneAndMovingItMovesAndResamplesTheSlice() async throws {
        let (model, _, _) = try await following(noise)
        let handle = try #require(model.sliceHandle)
        #expect(handle.id == FieldPreviewModel.sliceHandleID && handle.value == 0 && handle.direction == .unitZ)
        #expect(handle.anchor == model.pose?.plane.origin && handle.style == .linear)
        let generation = model.viewportSlice(colors: colors)?.generation
        model.moveSlice(to: 2)
        #expect(model.offset == 2 && model.sliceHandle?.value == 2)
        #expect(model.viewportSlice(colors: colors)?.generation == generation, "the old grid stays until the new one is ready")
        await model.waitForSampling()
        let moved = try #require(model.viewportSlice(colors: colors))
        #expect(moved.generation != generation && abs(moved.origin.z - (model.bounds?.center.z ?? 0) - 2) < 1e-9)
    }

    @Test func movingIsHeldToTheLimitAndIgnoresWhatIsNotANumber() async throws {
        let (model, _, _) = try await following(noise)
        let limit = try #require(model.pose?.offsetLimit)
        model.moveSlice(to: 1_000)
        #expect(model.offset == limit)
        model.moveSlice(to: .nan)
        #expect(model.offset == limit)
        model.moveSlice(to: -1_000)
        #expect(model.offset == -limit)
        await model.waitForSampling()
    }

    @Test func choosingAnAxisPutsTheOffsetBackToZero() async throws {
        let (model, _, _) = try await following(noise)
        model.moveSlice(to: 2)
        model.chooseSlice(.axis(.yz))
        #expect(model.offset == 0)
        model.chooseSlice(.axis(.yz))
        await model.waitForSampling()
    }

    @Test func aBiggerPartRefitsTheSliceKeepingItsChoiceAndOffset() async throws {
        let harness = PreviewHarness()
        let small = try await harness.part()
        let big = try await harness.part(width: 60, depth: 40)
        let model = harness.model()
        model.follow(harness.request(node, noise, [small]))
        await model.waitForSampling()
        model.chooseSlice(.axis(.yz))
        model.moveSlice(to: 1)
        await model.waitForSampling()
        let before = try #require(model.pose)
        model.follow(harness.request(node, noise, [big]))
        await model.waitForSampling()
        let after = try #require(model.pose)
        #expect(after.choice == .axis(.yz) && after.offset == 1 && after.halfWidth > before.halfWidth)
    }

    @Test func aFieldThatLosesItsPlaneLeavesTheOwnChoice() async throws {
        let plane = Plane(origin: .zero, normal: .unitX, xAxis: .unitY)
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, .linearGradient(plane: plane, length: 20), [part]))
        await model.waitForSampling()
        #expect(model.choice == .own)
        model.follow(harness.request(node, noise, [part], toEye: .unitZ))
        await model.waitForSampling()
        #expect(model.choice == .axis(.xy), "the same node, but its field has no plane now")
    }

    @Test func aHiddenSliceStaysHiddenWhileTheFieldIsEdited() async throws {
        let (model, harness, part) = try await following(noise)
        model.chooseSlice(.hidden)
        model.follow(harness.request(node, .noise(seed: 4, scale: 6, octaves: 1), [part]))
        await model.waitForSampling()
        #expect(model.choice == .hidden && model.viewportSlice(colors: colors) == nil)
    }

    @Test func anotherNodeStartsOverShownAgain() async throws {
        let (model, harness, part) = try await following(noise)
        model.chooseSlice(.hidden)
        model.follow(harness.request(NodeID(), noise, [part]))
        await model.waitForSampling()
        #expect(model.choice == .axis(.xy))
    }

    @Test func thePartsSliceIsAbsentWithNoPart() async throws {
        let harness = PreviewHarness()
        let model = harness.model()
        model.follow(harness.request(node, noise, []))
        await model.waitForSampling()
        #expect(model.pose == nil && model.sliceHandle == nil && model.viewportSlice(colors: colors) == nil && model.legend == nil)
    }
}
