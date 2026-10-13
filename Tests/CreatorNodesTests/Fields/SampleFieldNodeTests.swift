import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Sample Field (fields spec §3.3): numbers in exactly the shape of `at`, paths and culled gaps included.
struct SampleFieldNodeTests {
    /// Four placements along +X, 10 mm apart from the origin, then (in this order) a Partition into rows of `rows` and a Cull
    /// Pattern `mask`, into the `at` of a Sample Field whose field is x ÷ 10 (so the placements sample 0, 1, 2, 3), unless
    /// `xField` is false and the test wires its own.
    struct Rig {
        var h = Harness()
        let placements: Node, sample: Node

        init(rows: Int? = nil, mask: String? = nil, xField: Bool = true) {
            let grid = h.add(GridPointsNode.self, [
                "countX": .integer(4), "countY": .integer(1), "spacingX": .number(10), "centred": .bool(false),
            ])
            placements = h.add(PointsToPlacementsNode.self)
            sample = h.add(SampleFieldNode.self)
            h.wire(grid, "points", to: placements, "points")
            var (source, socket): (Node, SocketName) = (placements, "placements")
            if let rows {
                let partition = h.add(PartitionNode.self, ["size": .integer(rows)])
                h.wire(source, socket, to: partition, "tree")
                (source, socket) = (partition, "tree")
            }
            if let mask {
                let before = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text(mask)])
                h.wire(source, socket, to: before, "tree")
                (source, socket) = (before, "tree")
            }
            h.wire(source, socket, to: sample, "at")
            if xField {
                let plane = h.add(PlaneNode.self, ["orientation": .integer(2)])  // YZ: its normal is +X
                let field = h.add(LinearGradientNode.self, ["length": .number(10)])
                h.wire(plane, "plane", to: field, "plane")
                h.wire(field, "field", to: sample, "field")
            }
        }
    }

    func numbers(_ report: EvaluationReport, _ node: Node) -> [[Double]] {
        (report.value(node, "values")?.asTree?.leaves ?? []).map { leaf in
            leaf.items.compactMap { if case .number(let value) = $0 { value } else { nil } }
        }
    }

    // MARK: shape

    @Test func aFlatListGivesAFlatListOfNumbers() async throws {
        let rig = Rig()
        let report = try await rig.h.run([rig.sample])
        #expect(report.value(rig.sample, "values")?.numbers == [0, 1, 2, 3])
        #expect(report.value(rig.sample, "values")?.isList == true)
        #expect(report.isOK(rig.sample))
    }

    @Test func aTreeKeepsItsBranchesAndPaths() async throws {
        let rig = Rig(rows: 2)
        let report = try await rig.h.run([rig.sample])
        #expect(numbers(report, rig.sample) == [[0, 1], [2, 3]])
        #expect(report.positions(rig.sample, "values") == [[0, 1], [0, 1]])
        #expect(report.tree(rig.sample, "values")?.depth == 2)
    }

    @Test func culledGapsStayAndTheNumbersBelongToTheSurvivors() async throws {
        let rig = Rig(mask: "1 0")  // keeps {0} and {2}
        let report = try await rig.h.run([rig.sample])
        #expect(report.positions(rig.sample, "values") == [[0, 2]], "the numbers keep the places of the placements")
        #expect(numbers(report, rig.sample) == [[0, 2]], "the field at x = 0 and x = 20, not at the culled ones")
        #expect(report.tree(rig.sample, "values")?.isCulled == true)
    }

    @Test func aSinglePlaneGivesAListOfOneNumber() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["offset": .number(5)])
        let gradient = h.add(LinearGradientNode.self)  // z ÷ 10
        let sample = h.add(SampleFieldNode.self)
        h.wire(plane, "plane", to: sample, "at")
        h.wire(gradient, "field", to: sample, "field")
        let report = try await h.run([sample])
        #expect(report.value(sample, "values")?.numbers == [0.5])
    }

    @Test func aVectorWiredIntoAtIsAPlaneThroughIt() async throws {
        var h = Harness()
        let point = h.add(VectorNode.self, ["x": .number(0), "y": .number(0), "z": .number(20)])
        let gradient = h.add(LinearGradientNode.self)
        let sample = h.add(SampleFieldNode.self)
        h.wire(point, "vector", to: sample, "at")
        h.wire(gradient, "field", to: sample, "field")
        #expect(try await h.run([sample]).value(sample, "values")?.numbers == [2])
    }

    @Test func aNumberTypedIntoFieldSamplesAsThatConstant() async throws {
        var rig = Rig(xField: false)
        let typed = rig.h.add(SampleFieldNode.self, ["field": .number(7)])
        rig.h.wire(rig.placements, "placements", to: typed, "at")
        let report = try await rig.h.run([typed])
        #expect(report.value(typed, "values")?.numbers == [7, 7, 7, 7])
    }

    // MARK: kernel use and the cache

    @Test func aSolidDistanceIsOneKernelCallForTheWholeTreeAndIsRememberedAcrossEdits() async throws {
        var rig = Rig(xField: false)
        let box = rig.h.box(10, 10, 10)
        let distance = rig.h.add(DistanceFieldNode.self)
        let remap = rig.h.add(FieldRemapNode.self, [
            "fromLow": .number(-5), "fromHigh": .number(30), "toLow": .number(0), "toHigh": .number(1),
        ])
        rig.h.wire(box, "solid", to: distance, "target")
        rig.h.wire(distance, "field", to: remap, "field")
        rig.h.wire(remap, "field", to: rig.sample, "field")
        let kernel = FakeKernel()
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        let demand: Set<NodeID> = [rig.sample.id]
        let first = try await evaluator.evaluate(rig.h.graph, demand: demand)
        #expect(first.isOK(rig.sample))
        #expect(await kernel.operationLog.filter { $0 == "distances" }.count == 1, "one call for the four placements")
        // Edit the remap: a new field over the same distance source and points, so the kernel is not asked again.
        rig.h.set(remap, "toHigh", .number(2))
        let second = try await evaluator.evaluate(rig.h.graph, demand: demand)
        #expect(second.isOK(rig.sample))
        #expect(await kernel.operationLog.filter { $0 == "distances" }.count == 1, "the cache answered")
        let before = try #require(first.value(rig.sample, "values")?.numbers)
        let after = try #require(second.value(rig.sample, "values")?.numbers)
        #expect(zip(before, after).allSatisfy { abs($0 * 2 - $1) < 1e-12 }, "toHigh 1 → 2 doubled every number")
    }

    @Test func aKernelLimitIsTheSamplingNodesError() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                                   tag: NodeTag(node: NodeID(), item: 0))
        let curved = FaceInfo(id: FaceID(0), kind: .cylinder, normal: .unitZ, area: 1, centroid: .zero, tags: [])
        let round = Solid(topology: Topology(faces: [curved], edges: []), bounds: solid.bounds, storage: BareStorage())
        let node = BuiltInNodes.registry.makeNode(SampleFieldNode.typeID)
        let field = Field.distance(.kernel(.faces(FaceSet(solid: round, faces: [FaceID(0)]))), signed: false)
        let inputs = NodeInputs(item: 0, slots: ["field": .item(.field(field)), "at": .tree(.list([.plane(.xy)]))])
        do {
            _ = try await SampleFieldNode.evaluate(inputs, kernel: FakeKernel(), context: EvalContext(node: node, item: 0, parameters: [:]))
            Issue.record("expected the kernel's refusal")
        } catch {
            #expect(Evaluator.message(for: error) == "Distance to a curved face isn't supported by this kernel yet.")
        }
    }

    // MARK: refusals

    @Test func withoutAFieldTheNodeWaits() async throws {
        var h = Harness()
        let plane = h.add(PlaneNode.self)
        let sample = h.add(SampleFieldNode.self)
        h.wire(plane, "plane", to: sample, "at")
        let report = try await h.run([sample])
        #expect(report.state(sample) == .idle("Connect or set “field”."))
    }

    @Test func aListOfFieldsIsRefusedInWords() async throws {
        var rig = Rig(xField: false)
        let series = rig.h.add(SeriesNode.self, ["count": .integer(3)])
        rig.h.wire(series, "values", to: rig.sample, "field")
        let report = try await rig.h.run([rig.sample])
        #expect(report.error(rig.sample) == "Sample Field takes single values, not lists: wire one value into each input, "
                + "or pick one out of the list first with List Item.")
    }

    @Test func aTreeOfNothingGivesNothing() async throws {
        let rig = Rig(mask: "0")
        let report = try await rig.h.run([rig.sample])
        #expect(report.isOK(rig.sample))
        #expect(report.tree(rig.sample, "values")?.itemCount == 0)
    }
}

/// Storage for a hand-built solid.
private final class BareStorage: SolidStorage {
    var estimatedBytes: Int { 0 }
}
