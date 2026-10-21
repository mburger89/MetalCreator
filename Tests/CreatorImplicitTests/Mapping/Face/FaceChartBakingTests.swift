import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorImplicit

/// Measuring a face with a kernel and keeping the chart (implicit spec §3.5: "baked once per face and tolerance"), on the Fake's planar
/// faces; a curved face of a real OpenCascade solid is in `FaceMappingOCCTTests`.
struct FaceChartBakingTests {
    let kernel = FakeKernel()

    /// A solid with a top face at height 5 looking up, written by hand: a Fake prism's faces carry no positions.
    func part(topAt height: Double = 5) -> Solid {
        let faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: Vector3(2, 3, height), tags: []),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitZ, area: 1, centroid: Vector3(2, 3, 0), tags: []),
        ]
        return Solid(topology: Topology(faces: faces, edges: []), bounds: BoundingBox(min: .zero, max: Vector3(4, 6, height)),
                     storage: StandInStorage())
    }

    /// Distance blocks standing for the baked solid: only their box and their source matter.
    func blocks(of solid: Solid, tolerance: Double = 0.01) -> DistanceBlocks {
        BlocksFixture.make(origin: Vector3(-12, -12, -12), spacing: 1, blocks: 4) { $0.length }
            .timed(0.1, source: BakeSource(solid: solid, tolerance: tolerance))
    }

    @Test func aPlanarFaceIsChartedAsItsPlane() async throws {
        let solid = part()
        let source = blocks(of: solid)
        let chart = try await FaceChartBaker.bake(bounds: source.bounds, solid: solid, face: FaceID(0), tolerance: 0.01, kernel: kernel)
        let map = FaceMap(chart: chart, firstCell: nil, secondCell: nil)
        // u along world X from the centroid (2, 3, 5), v along Y, depth along Z.
        let c = map.coordinates(at: Vector3(5, 1, 7.5))
        #expect(abs(c.x - 3) < 1e-4 && abs(c.y + 2) < 1e-4 && abs(c.z - 2.5) < 1e-4, "\(c)")
        #expect(!chart.hasSingular && chart.kind == .plane)
        #expect(chart.bounds.min == source.bounds.min && chart.bounds.max.x >= source.bounds.max.x - 1e-9)
    }

    @Test func theChartIsMeasuredOncePerFaceAndTolerance() async throws {
        let cache = FaceChartCache()
        let solid = part()
        let source = blocks(of: solid)
        let first = try await cache.chart(for: source, face: FaceID(0), kernel: kernel)
        let second = try await cache.chart(for: source, face: FaceID(0), kernel: kernel)
        #expect(first === second)
        #expect(await cache.bakeCount == 1)
        let other = try await cache.chart(for: source, face: FaceID(1), kernel: kernel)
        #expect(other !== first)
        #expect(await cache.bakeCount == 2)
        _ = try await cache.chart(for: blocks(of: solid, tolerance: 0.02), face: FaceID(0), kernel: kernel)
        _ = try await cache.chart(for: blocks(of: part()), face: FaceID(0), kernel: kernel)
        let (measured, kept) = (await cache.bakeCount, await cache.entryCount)
        #expect(measured == 4 && kept == 4, "another tolerance and another solid are other charts")
        #expect(await cache.totalBytes > 0)
    }

    @Test func callersAskingTogetherShareOneMeasurement() async throws {
        let cache = FaceChartCache()
        let source = blocks(of: part())
        let kernel = kernel
        let charts = try await withThrowingTaskGroup(of: FaceChart.self) { group in
            for _ in 0..<4 { group.addTask { try await cache.chart(for: source, face: FaceID(0), kernel: kernel) } }
            var found: [FaceChart] = []
            for try await chart in group { found.append(chart) }
            return found
        }
        #expect(charts.count == 4 && charts.allSatisfy { $0 === charts[0] })
        #expect(await cache.bakeCount == 1)
    }

    @Test func theLeastRecentlyUsedChartsGoWhenTheCacheIsFull() async throws {
        let cache = FaceChartCache(capacity: 1)
        let source = blocks(of: part())
        let first = try await cache.chart(for: source, face: FaceID(0), kernel: kernel)
        _ = try await cache.chart(for: source, face: FaceID(1), kernel: kernel)
        #expect(await cache.entryCount == 1, "the newest is kept")
        let again = try await cache.chart(for: source, face: FaceID(0), kernel: kernel)
        #expect(again !== first)
        #expect(await cache.bakeCount == 3)
    }

    @Test func distancesThatWereNotBakedFromASolidAreRefused() async throws {
        let plain = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        await #expect(throws: KernelError.invalidInput("These distances were not baked from a solid.")) {
            _ = try await FaceChartCache().chart(for: plain, face: FaceID(0), kernel: kernel)
        }
    }

    @Test func aFaceTheKernelCannotChartIsItsError() async throws {
        let source = blocks(of: part())
        await #expect(throws: KernelError.invalidInput("The face doesn't exist on the solid.")) {
            _ = try await FaceChartCache().chart(for: source, face: FaceID(9), kernel: kernel)
        }
        let sphere = FaceInfo(id: FaceID(0), kind: .sphere, normal: nil, area: 1, centroid: .zero, tags: [])
        let curved = Solid(topology: Topology(faces: [sphere], edges: []), bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)),
                           storage: StandInStorage())
        await #expect(throws: KernelError.unsupported("face mapping on a curved face")) {
            _ = try await FaceChartCache().chart(for: self.blocks(of: curved), face: FaceID(0), kernel: kernel)
        }
    }

    @Test func aCancelledMeasurementStopsAndDoesNotPoisonTheCache() async throws {
        let cache = FaceChartCache()
        let source = blocks(of: part())
        let kernel = kernel
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.chart(for: source, face: FaceID(0), kernel: kernel)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let later = try await cache.chart(for: source, face: FaceID(0), kernel: kernel)
        #expect(!later.hasSingular)
    }

    // MARK: Which solid a region came from

    @Test func aBakedSolidKnowsWhereItCameFrom() {
        let solid = part()
        let baked = blocks(of: solid)
        #expect(baked.source?.solid === solid && baked.source?.tolerance == 0.01)
        #expect(baked.timed(2).source === baked.source, "a new bake time keeps the source")
        let tree = ImplicitSolid.union([.sphere(radius: 3), .baked(baked, label: "Bracket")], blend: .constant(0))
        #expect(tree.sourceBlocks == [baked] && !tree.holdsMovedSource)
        let plain = ImplicitSolid.baked(BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }, label: "a")
        #expect(plain.sourceBlocks.isEmpty && ImplicitSolid.sphere(radius: 1).sourceBlocks.isEmpty)
    }

    @Test func aMovedCopyOfASolidIsNotWhereItWasBaked() {
        let baked = blocks(of: part())
        let move = RigidMove(origin: Vector3(5, 0, 0), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let moved = ImplicitSolid.moved(.baked(baked, label: "Bracket"), move)
        #expect(moved.sourceBlocks.isEmpty && moved.holdsMovedSource)
        let both = ImplicitSolid.union([moved, .baked(baked, label: "Bracket")], blend: .constant(0))
        #expect(both.sourceBlocks == [baked] && both.holdsMovedSource, "the unmoved copy still counts")
    }
}
