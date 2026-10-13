import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import CreatorViewport
import Testing
@testable import CreatorApp

/// Holds the preview's mesh lookup back until a test opens the gate, so a test can look at the model while it samples.
actor SamplingGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}

/// The gate a test's meshes wait at, and how many meshes were asked for.
@MainActor
final class PreviewHarness {
    var gate: SamplingGate?
    private(set) var asked = 0
    var meshes: [ObjectIdentifier: DisplayMesh] = [:]

    @discardableResult
    func part(width: Double = 20, depth: Double = 10, height: Double = 6) async throws -> Solid {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height, mode: .oneSided,
                                             tag: NodeTag(node: NodeID(), item: 0))
        meshes[ObjectIdentifier(solid)] = try await kernel.tessellate(solid, tolerance: 0.05)
        return solid
    }

    func model(limit: Int = CoarseSampling.vertexLimit) -> FieldPreviewModel {
        FieldPreviewModel(kernel: FakeKernel(), distances: FieldDistanceCache(), vertexLimit: limit) { [self] solid in
            asked += 1
            if let gate { await gate.wait() }
            return meshes[ObjectIdentifier(solid)]
        }
    }

    func request(_ node: NodeID, _ field: Field, _ solids: [Solid], toEye: Vector3 = .unitZ) -> FieldPreviewRequest {
        FieldPreviewRequest(node: node, field: field, solids: solids, toEye: toEye)
    }
}

/// Following a field, sampling it for the tint and the slice, and what the model hands the scene (fields spec §6).
@MainActor
struct FieldPreviewModelTests {
    let radial = Field.radialGradient(center: .zero, radius: 10)
    let node = NodeID()

    @Test func aRequestSamplesEachSolidAtItsVerticesAndPublishesTheTint() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        #expect(model.node == node && model.field == radial)
        await model.waitForSampling()
        let mesh = try #require(harness.meshes[ObjectIdentifier(part)])
        let tint = try #require(model.tints[ObjectIdentifier(part)]?.tint)
        #expect(tint.values.count == mesh.positions.count && !tint.isCoarse && !model.isSampling)
        #expect(tint.values[0] == Float(mesh.positions[0].length / 10))
        #expect(model.range == FieldPreviewRange.make(extent: model.extent, centredOnZero: false, fixedToUnit: false))
        #expect(model.legend?.unit == FieldUnit.none && model.legend?.failure == nil && model.legend?.isCoarse == false)
    }

    @Test func aRepeatedRequestChangesNothingAndSamplesNothing() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        let (revision, asked) = (model.revision, harness.asked)
        model.follow(harness.request(node, radial, [part], toEye: .unitX))
        await model.waitForSampling()
        #expect(model.revision == revision && harness.asked == asked, "the camera moving is not a new request")
    }

    @Test func anEditedFieldKeepsTheOldTintUntilTheNewOneIsReady() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        let before = try #require(model.tints[ObjectIdentifier(part)]?.tint.values)

        let gate = SamplingGate()
        harness.gate = gate
        model.follow(harness.request(node, .radialGradient(center: .zero, radius: 20), [part]))
        #expect(model.isSampling)
        #expect(model.tints[ObjectIdentifier(part)]?.tint.values == before, "the old tint stays: no grey flash")
        await gate.open()
        await model.waitForSampling()
        let after = try #require(model.tints[ObjectIdentifier(part)]?.tint.values)
        #expect(after != before && after[1] == before[1] / 2, "the new tint: twice the radius, half the value")
    }

    @Test func aNewerRequestSupersedesAnOlderOneWhichPublishesNothing() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        let gate = SamplingGate()
        harness.gate = gate
        model.follow(harness.request(node, radial, [part]))
        model.follow(harness.request(node, .radialGradient(center: .zero, radius: 40), [part]))
        await gate.open()
        await model.waitForSampling()
        let mesh = try #require(harness.meshes[ObjectIdentifier(part)])
        let values = try #require(model.tints[ObjectIdentifier(part)]?.tint.values)
        #expect(values[0] == Float(mesh.positions[0].length / 40), "the second request's field, never the first's")
    }

    @Test func noRequestStopsEverythingAndIsQuietWhenThereWasNothing() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        let idle = model.revision
        model.follow(nil)
        #expect(model.revision == idle, "nothing shown, nothing changed")
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        model.follow(nil)
        #expect(model.node == nil && model.tints.isEmpty && model.grid == nil && model.legend == nil && model.choice == .hidden)
        #expect(model.sliceHandle == nil && !model.isSampling && model.revision > idle)
    }

    @Test func aBigMeshIsSampledCoarselyAndTheLegendSaysSo() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model(limit: 4)
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        #expect(model.tints[ObjectIdentifier(part)]?.tint.isCoarse == true && model.legend?.isCoarse == true)
    }

    @Test func aFailedSamplingSaysSoInTheKernelsWordsAndKeepsNoTint() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        let bad = Field.distance(.kernel(.faces(FaceSet(solid: part, faces: [FaceID(99)]))), signed: false)
        model.follow(harness.request(node, bad, [part]))
        await model.waitForSampling()
        #expect(model.failure == "A selected face doesn't exist on the solid." && model.tints.isEmpty && model.grid == nil)
        #expect(model.legend?.failure == model.failure && model.legend?.range == nil)
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        #expect(model.failure == nil && model.tints.count == 1, "and the next field samples again")
    }

    @Test func aSliceThatSamplesFineDoesNotHideTheTintsFailureNorTheOtherWayRound() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        // The tint's batch (the part's few vertices) fails; the slice's grid is bigger and succeeds.
        let model = FieldPreviewModel(kernel: SmallBatchFailingKernel(minimum: 50), distances: nil) { solid in
            harness.meshes[ObjectIdentifier(solid)]
        }
        model.follow(harness.request(node, .distance(.kernel(.solid(part)), signed: true), [part]))
        await model.waitForSampling()
        let words = "The batch is too small."
        #expect(model.tintFailure == words && model.sliceFailure == nil && model.grid != nil, "the slice sampled fine")
        #expect(model.failure == words && model.legend?.failure == words, "the explanation stays while the slice succeeds")
        // Ruling: a failure does not clear the other half (the slice stays drawn); moving the slice keeps the words.
        model.moveSlice(to: 1)
        await model.waitForSampling()
        #expect(model.failure == words && model.grid != nil)
        // A tint that samples again clears its own words.
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        #expect(model.failure == nil)
    }

    @Test func aDistanceFieldIsSampledThroughTheEvaluatorsCacheInMillimetres() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let cache = FieldDistanceCache()
        let model = FieldPreviewModel(kernel: FakeKernel(), distances: cache) { solid in harness.meshes[ObjectIdentifier(solid)] }
        model.follow(harness.request(node, .distance(.kernel(.solid(part)), signed: true), [part]))
        await model.waitForSampling()
        #expect(await cache.misses >= 1)
        #expect(model.legend?.unit == .millimetres)
        let range = try #require(model.range)
        #expect(range.mid == 0 && range.low == -range.high, "a signed distance centres the middle on 0")
        let misses = await cache.misses
        model.setUnitRange(true)
        #expect(model.range == .unit && model.tints.count == 1, "the toggle changes the ramp, not the values")
        #expect(await cache.misses == misses)
    }

    // MARK: what the scene gets

    @Test func tintedGivesTheRampToTheSolidsItHasAndLeavesTheRestAlone() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let other = try await harness.part(width: 30)
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        let colors = ColorTheme.dracula.colors
        let items = [
            ViewportItem(solid: part), ViewportItem(solid: part, isGhost: true), ViewportItem(solid: part, isGuide: true),
            ViewportItem(solid: other),
        ]
        let tinted = model.tinted(items, colors: colors)
        #expect(tinted[0].fieldValues == model.tints[ObjectIdentifier(part)]?.tint.values)
        #expect(tinted[0].fieldRamp?.low == colors.fieldLow.rgba && tinted[0].fieldRamp?.high == colors.fieldHigh.rgba)
        #expect(tinted[1].fieldValues == nil && tinted[2].fieldValues == nil && tinted[3].fieldValues == nil)
        let unit = { () -> FieldRamp? in
            model.setUnitRange(true)
            return model.tinted(items, colors: colors)[0].fieldRamp
        }()
        #expect(unit?.lowValue == 0 && unit?.midValue == 0.5 && unit?.highValue == 1)
    }

    @Test func withNothingSampledTheItemsAreHandedBackAsTheyAre() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        #expect(model.tinted([ViewportItem(solid: part)], colors: ColorTheme.dracula.colors)[0].fieldValues == nil)
        #expect(model.viewportSlice(colors: ColorTheme.dracula.colors) == nil)
    }
}
