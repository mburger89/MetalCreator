import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing
@testable import CreatorApp

/// The field benchmarks' inputs are what `FieldBench` says: a plain `swift test` checks them, since the benchmark itself runs only in
/// a release build when asked.
struct FieldBenchFixturesTests {
    @Test func rowOneIsAFiveNodeFieldWithNoKernelDistance() async throws {
        #expect(FieldBenchFixtures.fiveNodeField.nodeCount == 5)
        let points = FieldBenchFixtures.points(10_000)
        let values = try await FieldSampler.sample(FieldBenchFixtures.fiveNodeField, at: points, kernel: FakeKernel())
        #expect(values.count == 10_000 && values.allSatisfy { (0.0...1.0).contains($0) })
        #expect(Set(values).count > 1_000, "a real field, not a constant")
    }

    @Test func thePointsAreTheSameEveryTimeAndFillTheRegion() {
        let points = FieldBenchFixtures.points(10_000)
        #expect(points == FieldBenchFixtures.points(10_000))
        #expect(points.allSatisfy { abs($0.x) <= 50 && abs($0.y) <= 40 && $0.z >= -5 && $0.z <= 15 })
    }

    @Test func rowTwoIsTheSignedDistanceToAPlateOnOCCT() async throws {
        let kernel = OCCTKernel()
        let plate = try await FieldBenchFixtures.plate(kernel)
        let points = [Vector3(0, 0, 3), Vector3(40, 0, 3), Vector3(0, 0, 8)]
        let found = try await kernel.distances(from: points, to: .solid(plate), signed: true)
        #expect(abs(found[0] + 3) < 1e-7, "3 mm inside the 6 mm plate's mid-plane is 3 from either face")
        #expect(abs(found[1] - 10) < 1e-7 && abs(found[2] - 2) < 1e-7)
    }

    @Test func rowTwoBIsASmoothLoftWithSignedDistancesOnOCCT() async throws {
        let kernel = OCCTKernel()
        let loft = try await FieldBenchFixtures.loft(kernel)
        let found = try await kernel.distances(from: [Vector3(0, 0, 10), Vector3(20, 0, 10), Vector3(0, 0, 30)], to: .solid(loft),
                                               signed: true)
        #expect(found[0] < 0 && found[0] > -6, "inside the waist, a little under 3 mm from the wall: \(found)")
        #expect(abs(found[1] - 17) < 0.5 && abs(found[2] - 10) < 1e-6, "outside, beside the waist and above the top: \(found)")
    }

    @Test func rowThreeIsAFaceThatFieldScatterFillsWithAboutTwoThousandPoints() async throws {
        let (solid, pick) = try await FieldBenchFixtures.scatterPlate(OCCTKernel())
        let placed = try await FieldScatterNode.evaluate(FieldBenchFixtures.scatterInputs(solid), kernel: FakeKernel(),
                                                         context: FieldBenchFixtures.scatterContext(pick: pick))
        let planes = (placed.trees["placements"]?.items ?? []).compactMap { scalar -> Plane? in
            if case .plane(let plane) = scalar { plane } else { nil }
        }
        #expect(planes.count > 1_500 && planes.count <= 2_000, "\(planes.count) points")
        #expect(planes.allSatisfy { abs($0.origin.z) < 1e-9 && abs($0.origin.x) <= 57 + 1e-6 && abs($0.origin.y) <= 57 + 1e-6 })
        let denser = planes.filter { $0.origin.length < 20 }.count
        #expect(Double(denser) / (Double.pi * 400) > Double(planes.count - denser) / (114 * 114 - Double.pi * 400),
                "closer together near the middle, where the field is low")
    }

    @Test func rowThreeBIsTwoThousandPlacementsInFortyBranches() {
        let tree = FieldBenchFixtures.placements(rows: 40, columns: 50)
        #expect(tree.itemCount == 2000 && tree.depth == 2 && tree.leaves.count == 40)
    }
}
