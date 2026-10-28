import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// The pattern features and the layouts declare their dimensions (spec §3.1, DIM-3 Task 8).
struct PatternDimensionTests {
    #if canImport(CreatorOCCT)
    /// A pattern feature on the 2 × 2 `PatternPlate`, with `settings` and any list inputs.
    func feature(_ definition: any NodeDefinition.Type,
                 _ settings: [SocketName: ConstantValue] = [:]) async throws ->
        (specs: [DimensionSpec], report: EvaluationReport, node: Node) {
        var plate = PatternPlate(columns: 2, rows: 1)
        let node = plate.h.add(definition, settings)
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        let report = try await plate.h.run([node], kernel: OCCTKernel())
        return (report.results[node.id]?.dimensions ?? [], report, node)
    }

    #endif

    func linear(_ spec: DimensionSpec) throws -> (from: Vector3, to: Vector3, direction: Vector3, side: Vector3) {
        guard case let .linear(from, to, direction, side, _) = spec.geometry else {
            Issue.record("expected a linear dimension, got \(spec.geometry)")
            throw CancellationError()
        }
        return (from, to, direction, side)
    }

    func layout(_ definition: any NodeDefinition.Type, _ settings: [SocketName: ConstantValue]) async throws -> [DimensionSpec] {
        var h = Harness()
        let node = h.add(definition, settings)
        let report = try await h.run([node])
        #expect(report.error(node) == nil)
        return report.results[node.id]?.dimensions ?? []
    }

    #if canImport(CreatorOCCT)
    @Test func equalHoleDiametersAreOneSpecWithACount() async throws {
        let (specs, report, node) = try await feature(HolePatternNode.self, ["diameter": .number(8), "depth": .number(3)])
        #expect(report.error(node) == nil)
        let diameters = specs.filter { $0.target == .input("diameter") }
        let spec = try #require(diameters.first)
        #expect(diameters.count == 1 && spec.quantity == .diameter && spec.value == 8 && spec.count == 2)
        guard case let .radial(center, radius, normal, toward, _) = spec.geometry else {
            Issue.record("expected a radial dimension")
            return
        }
        #expect(isClose(radius, 4) && isClose(normal, .unitZ) && isClose(toward, .unitX))
        #expect(isClose(center, Vector3(-20, 0, 0)))
        let depth = try #require(specs.first { $0.target == .input("depth") })
        #expect(depth.quantity == .length && depth.value == 3 && depth.count == 2)
        let line = try linear(depth)
        #expect(isClose(line.from, Vector3(-20, 0, 0)) && isClose(line.to, Vector3(-20, 0, -3)))
        #expect(isClose(line.direction, -.unitZ) && isClose(line.side, .unitX))
    }

    @Test func varyingDiametersGiveOneSpecPerHole() async throws {
        var plate = PatternPlate(columns: 2, rows: 1)
        let list = plate.h.add(SeriesNode.self, ["start": .number(6), "step": .number(2), "count": .integer(2)])
        let node = plate.h.add(HolePatternNode.self, ["depth": .number(3)])
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        plate.h.wire(list, "values", to: node, "diameter")
        let report = try await plate.h.run([node], kernel: OCCTKernel())
        let diameters = (report.results[node.id]?.dimensions ?? []).filter { $0.target == .input("diameter") }
        #expect(diameters.map(\.value) == [6, 8])
        #expect(diameters.allSatisfy { $0.count == nil })
    }

    @Test func throughAllHolesHaveNoDepth() async throws {
        let (specs, _, _) = try await feature(HolePatternNode.self, ["diameter": .number(5), "throughAll": .bool(true)])
        #expect(specs.contains { $0.target == .input("diameter") })
        #expect(!specs.contains { $0.target == .input("depth") })
    }

    @Test func perInstanceSpecsStopAtTheLimit() async throws {
        var plate = PatternPlate(columns: 30, rows: 1, spacingX: 1)
        let list = plate.h.add(SeriesNode.self, ["start": .number(2), "step": .number(1), "count": .integer(30)])
        let node = plate.h.add(HolePatternNode.self, ["depth": .number(3)])
        plate.h.wire(plate.plate, "solid", to: node, "part")
        plate.h.wire(plate.placements, "placements", to: node, "placements")
        plate.h.wire(list, "values", to: node, "diameter")
        let report = try await plate.h.run([node], kernel: OCCTKernel())
        let diameters = (report.results[node.id]?.dimensions ?? []).filter { $0.target == .input("diameter") }
        #expect(diameters.count == 24)
    }

    @Test func bossAndSlotPatternsDimensionTheirSizes() async throws {
        let boss = try await feature(BossPatternNode.self, ["diameter": .number(6), "height": .number(4)]).specs
        #expect(boss.first { $0.target == .input("diameter") }?.value == 6)
        let height = try #require(boss.first { $0.target == .input("height") })
        let up = try linear(height)
        #expect(height.value == 4 && isClose(up.from, Vector3(-20, 0, 0)) && isClose(up.to, Vector3(-20, 0, 4)))
        let slot = try await feature(SlotPatternNode.self, ["length": .number(20), "width": .number(6), "depth": .number(2)]).specs
        let length = try linear(try #require(slot.first { $0.target == .input("length") }))
        #expect(isClose(length.from, Vector3(-30, 0, 0)) && isClose(length.to, Vector3(-10, 0, 0)))
        #expect(isClose(length.direction, .unitX) && isClose(length.side, .unitY))
        let width = try linear(try #require(slot.first { $0.target == .input("width") }))
        #expect(isClose(width.from, Vector3(-20, -3, 0)) && isClose(width.to, Vector3(-20, 3, 0)))
        #expect(isClose(width.direction, .unitY) && isClose(width.side, .unitX))
        #expect(slot.contains { $0.target == .input("depth") && $0.value == 2 })
    }

    #endif

    @Test func aLinearPatternDimensionsSpacingAndCount() async throws {
        let specs = try await layout(LinearPatternNode.self, ["count": .integer(4), "spacing": .number(20)])
        let spacing = try #require(specs.first { $0.target == .input("spacing") })
        let line = try linear(spacing)
        #expect(spacing.value == 20 && isClose(line.from, .zero) && isClose(line.to, Vector3(20, 0, 0)))
        let count = try #require(specs.first { $0.target == .input("count") })
        let across = try linear(count)
        #expect(count.quantity == .count && count.value == 4)
        #expect(isClose(across.from, .zero) && isClose(across.to, Vector3(60, 0, 0)))
        #expect(isClose(across.side, line.side * -1))
    }

    @Test func aLinearPatternWithALengthDimensionsTheLength() async throws {
        let specs = try await layout(LinearPatternNode.self, ["count": .integer(4), "length": .number(30)])
        #expect(!specs.contains { $0.target == .input("spacing") })
        let length = try #require(specs.first { $0.target == .input("length") })
        let line = try linear(length)
        #expect(length.value == 30 && isClose(line.to, Vector3(30, 0, 0)))
    }

    @Test func aGridPatternDimensionsBothSpacingsAndCounts() async throws {
        let specs = try await layout(GridPatternNode.self, ["countX": .integer(3), "countY": .integer(2), "spacingX": .number(10),
                                                            "spacingY": .number(20), "centred": .bool(false),
        ])
        let sx = try linear(try #require(specs.first { $0.target == .input("spacingX") }))
        #expect(isClose(sx.from, .zero) && isClose(sx.to, Vector3(10, 0, 0)))
        let sy = try linear(try #require(specs.first { $0.target == .input("spacingY") }))
        #expect(isClose(sy.to, Vector3(0, 20, 0)))
        let cx = try #require(specs.first { $0.target == .input("countX") })
        let cxLine = try linear(cx)
        #expect(cx.quantity == .count && cx.value == 3 && isClose(cxLine.to, Vector3(20, 0, 0)))
        let cy = try #require(specs.first { $0.target == .input("countY") })
        let cyLine = try linear(cy)
        #expect(cy.value == 2 && isClose(cyLine.to, Vector3(0, 20, 0)))
    }

    @Test func aCircularPatternDimensionsRadiusCountAndAPartSweep() async throws {
        let full = try await layout(CircularPatternNode.self, ["radius": .number(20), "count": .integer(6)])
        let radius = try #require(full.first { $0.target == .input("radius") })
        #expect(radius.quantity == .radius && radius.value == 20)
        guard case let .radial(center, r, normal, toward, _) = radius.geometry else {
            Issue.record("expected a radial dimension")
            return
        }
        #expect(isClose(center, .zero) && isClose(r, 20) && isClose(normal, .unitZ) && isClose(toward, .unitX))
        #expect(full.first { $0.target == .input("count") }?.value == 6)
        #expect(!full.contains { $0.target == .input("sweep") })
        let part = try await layout(CircularPatternNode.self, ["radius": .number(20), "count": .integer(3), "sweep": .number(180)])
        let sweep = try #require(part.first { $0.target == .input("sweep") })
        #expect(sweep.quantity == .angle && sweep.value == 180)
        guard case let .angular(vertex, first, second, _, _) = sweep.geometry else {
            Issue.record("expected an angular dimension")
            return
        }
        #expect(isClose(vertex, .zero) && isClose(first, Vector3(20, 0, 0)) && isClose(second, Vector3(-20, 0, 0), tolerance: 1e-9))
    }

    @Test func aSingleInstanceLayoutHasNoSpacing() async throws {
        let linear = try await layout(LinearPatternNode.self, ["count": .integer(1)])
        #expect(linear.isEmpty)
        let grid = try await layout(GridPatternNode.self, ["countX": .integer(1), "countY": .integer(1)])
        #expect(grid.isEmpty)
        let circle = try await layout(CircularPatternNode.self, ["count": .integer(1)])
        #expect(circle.map(\.target) == [.input("radius")])
    }
}
