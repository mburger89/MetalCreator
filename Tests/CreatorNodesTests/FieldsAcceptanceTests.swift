import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

/// Fields spec §8, "Acceptance (headless, OCCT)": a vented plate. Field Scatter on its top face with a distance field (denser
/// near the edges), Remap → Sample Field → Hole Pattern sizes (larger towards the centre), Cull by Field (Probability, noise)
/// thinning the points. It asserts the instance count, the sizes increasing towards the centre, and identical results on a
/// second run.
@MainActor
struct FieldsAcceptanceTests {
    /// The 60 × 40 plate's half sizes, and how far from the outline the distance field's ramps end.
    static let halfWidth = 30.0
    static let halfDepth = 20.0
    static let ramp = 14.0

    struct Part {
        var h = Harness()
        let plate: Node, scatter: Node, cull: Node, sample: Node, holes: Node
    }

    /// Plate → Hole Pattern at the surviving scatter points. The scatter's field is the distance to the plate's outline
    /// remapped 0…14 mm → 0…1 (spacing 4.5 mm at the edge, 9 mm from 14 mm in); the hole sizes are the same distance remapped
    /// 0…14 mm → Ø2…Ø4.
    static func makePart(kernel: any Kernel) async throws -> Part {
        var h = Harness()
        let plate = h.box(60, 40, 6, at: Vector3(0, 0, -6))
        let outline = h.add(RectangleNode.self, ["width": .number(60), "height": .number(40), "plane": .plane(.xy)])
        let distance = h.add(DistanceFieldNode.self)
        let density = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(ramp), "toLow": .number(0), "toHigh": .number(1),
        ])
        let sizes = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(ramp), "toLow": .number(2), "toHigh": .number(4),
        ])
        let scatter = h.add(FieldScatterNode.self, [
            "minSpacing": .number(4.5), "maxSpacing": .number(9), "margin": .number(3), "seed": .integer(5),
        ])
        let noise = h.add(NoiseFieldNode.self, ["seed": .integer(4), "scale": .number(12)])
        let cull = h.add(CullByFieldNode.self, ["mode": .integer(1), "seed": .integer(7)])
        let sample = h.add(SampleFieldNode.self)
        let holes = h.add(HolePatternNode.self, ["depth": .number(6)])
        h.wire(outline, "profile", to: distance, "target")
        h.wire(distance, "field", to: density, "field")
        h.wire(distance, "field", to: sizes, "field")
        h.wire(plate, "solid", to: scatter, "solid")
        h.wire(density, "field", to: scatter, "field")
        h.wire(scatter, "placements", to: cull, "placements")
        h.wire(noise, "field", to: cull, "field")
        h.wire(sizes, "field", to: sample, "field")
        h.wire(cull, "placements", to: sample, "at")
        h.wire(plate, "solid", to: holes, "part")
        h.wire(cull, "placements", to: holes, "placements")
        h.wire(sample, "values", to: holes, "diameter")

        // The face pick, made the way the app makes it: the plate's top face.
        let solid = try onlySolid(try await h.run([plate], kernel: kernel), plate)
        let top = try #require(solid.topology.faces.filter { $0.kind == .plane && $0.normal == .unitZ }
            .max { $0.centroid.z < $1.centroid.z })
        h.set(scatter, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: top.id))))
        return Part(h: h, plate: plate, scatter: scatter, cull: cull, sample: sample, holes: holes)
    }

    /// Everything one run of the part gives that the assertions look at.
    struct Result: Equatable {
        var scattered: [Vector3]
        var kept: [Vector3]
        var sizes: [Double]
        var volume: Double
    }

    static func run(_ part: Part, kernel: any Kernel) async throws -> (result: Result, solid: Solid) {
        let report = try await part.h.run([part.holes], kernel: kernel)
        for node in [part.scatter, part.cull, part.sample, part.holes] {
            #expect(report.isOK(node), "\(node.name): \(String(describing: report.state(node)))")
        }
        let solid = try onlySolid(report, part.holes)
        let result = Result(
            scattered: try #require(report.value(part.scatter, "placements")?.planes).map(\.origin),
            kept: try #require(report.value(part.cull, "placements")?.planes).map(\.origin),
            sizes: try #require(report.value(part.sample, "values")?.numbers),
            volume: try await volume(solid, kernel))
        return (result, solid)
    }

    /// A point's distance to the plate's outline.
    static func edgeDistance(_ point: Vector3) -> Double { min(halfWidth - abs(point.x), halfDepth - abs(point.y)) }

    #if canImport(CreatorOCCT)
    @Test func aVentedPlateGetsGradedHolesAtThinnedScatteredPoints() async throws {
        let kernel = OCCTKernel()
        let (result, solid) = try await Self.run(try await Self.makePart(kernel: kernel), kernel: kernel)

        // The instance count: pinned, with the scatter and the thinning visible in it.
        #expect(result.scattered.count == 29, "scattered points: \(result.scattered.count)")
        #expect(result.kept.count == 13, "points kept by the noise: \(result.kept.count)")
        #expect(result.kept.count < result.scattered.count && result.kept.count >= 10)
        #expect(result.sizes.count == result.kept.count)
        #expect(Set(result.kept).isSubset(of: Set(result.scattered)), "Cull by Field only takes points away")

        // Every hole is the size its distance from the plate's edge gives: Ø2 at the edge to Ø4 from 14 mm in, so the holes
        // grow towards the centre.
        for (point, size) in zip(result.kept, result.sizes) {
            let expected = 2 + 2 * min(Self.edgeDistance(point) / Self.ramp, 1)
            #expect(abs(size - expected) < 1e-9, "at \(point): Ø\(size), wanted Ø\(expected)")
        }
        let byDistance = zip(result.kept, result.sizes).sorted { Self.edgeDistance($0.0) < Self.edgeDistance($1.0) }.map(\.1)
        #expect(zip(byDistance, byDistance.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 }, "nearer the centre, never smaller")
        #expect((result.sizes.min() ?? 0) < 3 && (result.sizes.max() ?? 0) > 3, "a real range of sizes: \(result.sizes)")

        // The holes were cut at those sizes.
        let removed = PatternPlate.plateVolume - result.volume
        let wanted = result.sizes.reduce(0) { $0 + PatternPlate.cylinderVolume($1, 6) }
        #expect(abs(removed - wanted) < 1e-3 * wanted, "removed \(removed) mm³, wanted \(wanted)")

        // Denser near the edges: the scatter's points per area in the 7 mm band along the edge (inside the 3 mm margin) against the middle.
        let band = result.scattered.filter { Self.edgeDistance($0) < 7 }.count
        let middle = result.scattered.count - band
        let bandArea = 54.0 * 34 - 46 * 26, middleArea = 46.0 * 26
        #expect(Double(band) / bandArea > 1.3 * Double(middle) / middleArea, "band \(band), middle \(middle)")

        // Exact B-rep: the part exports.
        let url = temporaryURL("vented-plate.step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([solid], format: .step, to: url)
        #expect(((try? Data(contentsOf: url))?.count ?? 0) > 1_000)
    }

    @Test func aSecondRunFromAFreshKernelAndFreshNodesGivesTheSamePointsSizesAndVolume() async throws {
        let first = try await Self.run(try await Self.makePart(kernel: OCCTKernel()), kernel: OCCTKernel()).result
        let second = try await Self.run(try await Self.makePart(kernel: OCCTKernel()), kernel: OCCTKernel()).result
        #expect(first == second)
        #expect(!first.kept.isEmpty)
    }
    #endif
}

/// A fresh path in the temporary directory.
private func temporaryURL(_ name: String) -> URL {
    URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
}
