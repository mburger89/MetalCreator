import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// The graded-sizes path (fields spec §3.3) in the one order that wires: a field → Remap → Sample Field → a shortcut's size
/// socket. Remap takes and returns a field, so a Remap after the sampling would put a field into a number socket.
struct GradedHolesTests {
    #if canImport(CreatorOCCT)
    /// A Radial Gradient of radius 40 centred on one hole of the plate's 2 × 2 grid (at (±20, ±10)), remapped 0…1 → Ø3…Ø5 and
    /// held there, sampled at the four placements into a Hole Pattern's `diameter`. The holes are 0, 0.5, 1 and 1.118 radii
    /// from the centre: Ø3, Ø4, Ø5 and (clamped) Ø5.
    @Test func gradedHolesFollowTheFieldAcrossThePlate() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate()
        let centre = plate.h.add(VectorNode.self, ["x": .number(-20), "y": .number(-10)])
        let radial = plate.h.add(RadialGradientNode.self, ["radius": .number(40)])
        let remap = plate.h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(1), "toLow": .number(3), "toHigh": .number(5),
        ])
        let sample = plate.h.add(SampleFieldNode.self)
        let holes = plate.h.add(HolePatternNode.self, ["depth": .number(6)])
        plate.h.wire(centre, "vector", to: radial, "center")
        plate.h.wire(radial, "field", to: remap, "field")
        plate.h.wire(remap, "field", to: sample, "field")
        plate.h.wire(plate.placements, "placements", to: sample, "at")
        plate.h.wire(sample, "values", to: holes, "diameter")
        plate.h.wire(plate.plate, "solid", to: holes, "part")
        plate.h.wire(plate.placements, "placements", to: holes, "placements")
        let report = try await plate.h.run([holes], kernel: kernel)
        #expect(report.isOK(sample) && report.isOK(holes), "\(String(describing: report.state(holes)))")

        // The numbers are the field at each placement, in the placements' order.
        let origins = (report.value(plate.placements, "placements")?.items ?? []).compactMap { item -> Vector3? in
            if case .plane(let plane) = item { plane.origin } else { nil }
        }
        let sizes = try #require(report.value(sample, "values")?.numbers)
        #expect(origins.count == 4 && sizes.count == 4)
        let expected = origins.map { min(5, 3 + 2 * ($0 - Vector3(-20, -10, 0)).length / 40) }
        #expect(zip(sizes, expected).allSatisfy { abs($0 - $1) < 1e-9 }, "got \(sizes), wanted \(expected)")
        #expect(sizes.sorted().map { ($0 * 1000).rounded() / 1000 } == [3, 4, 5, 5])

        // And the holes cut are those sizes, paired with the placements by InstanceGrid: the plate loses Ø3 + Ø4 + Ø5 + Ø5.
        let want = [3.0, 4, 5, 5].reduce(0) { $0 + PatternPlate.cylinderVolume($1, 6) }
        let removed = PatternPlate.plateVolume - (try await volume(try onlySolid(report, holes), kernel))
        #expect(isClose(removed, want), "removed \(removed), wanted \(want)")
    }
    #endif
}
