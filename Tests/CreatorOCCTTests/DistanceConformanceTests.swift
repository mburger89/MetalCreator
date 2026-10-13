import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Fields spec §3.1 and §8 on OCCT: a 10 mm cube standing on z = 0, centred on x and y.
struct DistanceConformanceTests {
    func near(_ a: Double, _ b: Double, tolerance: Double = 1e-7) -> Bool { abs(a - b) <= tolerance }

    func cube(_ kernel: any Kernel, tag: NodeTag = newTag()) async throws -> Solid {
        try await box(kernel, 10, 10, 10, tag: tag)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aCubesSignedDistanceIsMinusFiveAtItsCentreAndZeroOnAFace(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await cube(kernel)
        let found = try await kernel.distances(from: [Vector3(0, 0, 5), Vector3(5, 0, 5), Vector3(0, 0, 10), Vector3(8, 0, 5)],
                                               to: .solid(solid), signed: true)
        #expect(near(found[0], -5) && near(found[1], 0) && near(found[2], 0) && near(found[3], 3), "got \(found)")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func unsignedIsTheDistanceToTheSurfaceFromEitherSide(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await cube(kernel)
        let found = try await kernel.distances(from: [Vector3(0, 0, 5), Vector3(1, 0, 5), Vector3(8, 0, 5)], to: .solid(solid),
                                               signed: false)
        #expect(near(found[0], 5) && near(found[1], 4) && near(found[2], 3), "got \(found)")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aCylindersDistanceIsExactOnACurvedSurface(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(.circle(radius: 3, center: .zero, plane: .xy), distance: 10, mode: .oneSided, tag: newTag())
        let found = try await kernel.distances(from: [Vector3(0, 0, 5), Vector3(5, 0, 5), Vector3(0, 4, 5)], to: .solid(solid),
                                               signed: true)
        #expect(near(found[0], -3) && near(found[1], 2) && near(found[2], 1), "got \(found)")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aBatchAcrossSeveralChunksAgreesWithTheFakesBoxMaths(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await cube(kernel)
        var points: [Vector3] = []
        for x in -6...6 {
            for y in -6...6 {
                for z in -3...9 { points.append(Vector3(Double(x) * 1.3, Double(y) * 1.1, Double(z) * 1.7)) }
            }
        }
        #expect(points.count > 2 * 1024, "the batch spans three chunks")
        let found = try await kernel.distances(from: points, to: .solid(solid), signed: true)
        #expect(found.count == points.count)
        var worst = 0.0
        for (point, distance) in zip(points, found) {
            worst = max(worst, abs(distance - FakeKernel.boxDistance(point, solid.bounds, signed: true)))
        }
        #expect(worst < 1e-7, "OCCT and the box formula differ by \(worst)")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aBatchGivesWhatEachPointGivesOnItsOwn(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await cube(kernel)
        // 200 points: three blocks of 64 and a part, which the shim's threads share out.
        let points = (0..<200).map { Vector3(Double($0) * 0.13 - 14, Double($0 % 7) - 3, Double($0 % 11) * 1.3 - 1) }
        let batch = try await kernel.distances(from: points, to: .solid(solid), signed: true)
        for (index, point) in points.enumerated() {
            let single = try await kernel.distances(from: [point], to: .solid(solid), signed: true)
            #expect(near(single[0], batch[index], tolerance: 1e-12))
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aPointInTheBoundsButOutsideTheShapeIsStillOutside(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        // R4 corners: the corner arc is centred on (26, 16), so (29, 19) is inside the bounding box but 0.243 outside the plate,
        // and (28, 18) is 1.172 inside it.
        let plate = try await kernel.extrude(.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy), distance: 6,
                                             mode: .oneSided, tag: newTag())
        let found = try await kernel.distances(from: [Vector3(29, 19, 3), Vector3(28, 18, 3)], to: .solid(plate), signed: true)
        #expect(near(found[0], 4.242640687119285 - 4) && near(found[1], 2.8284271247461903 - 4), "got \(found)")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func anEdgesDistanceAtAKnownPoint(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await cube(kernel)
        // The cube's bottom edge along x at y = -5, z = 0.
        let edge = try #require(solid.topology.edges.first { edge in
            guard case .line(let start, let end)? = edge.curve else { return false }
            return abs(start.y + 5) < 1e-9 && abs(start.z) < 1e-9 && abs(end.y + 5) < 1e-9 && abs(end.z) < 1e-9
        })
        let found = try await kernel.distances(from: [Vector3(0, -8, 4), Vector3(9, -5, 0), Vector3(0, -5, 0)],
                                               to: .edges(EdgeSet(solid: solid, edges: [edge.id])), signed: true)
        #expect(near(found[0], 5) && near(found[1], 4) && near(found[2], 0), "got \(found)")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aFacesDistanceIsToTheBoundedFace(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await cube(kernel, tag: tag)
        let top = try #require(faces(solid, role: .endCap, of: tag).first)
        let target = DistanceTarget.faces(FaceSet(solid: solid, faces: [top.id]))
        let found = try await kernel.distances(from: [Vector3(1, 2, 3), Vector3(20, 0, 10)], to: target, signed: true)
        #expect(near(found[0], 7), "straight down onto the face")
        #expect(near(found[1], 15), "beside the face it is the distance to its nearest edge, 15 mm, not to its plane")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func severalFacesGiveTheNearest(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await cube(kernel, tag: tag)
        let both = faces(solid, role: .startCap, of: tag) + faces(solid, role: .endCap, of: tag)
        let found = try await kernel.distances(from: [Vector3(0, 0, 3), Vector3(0, 0, 8)],
                                               to: .faces(FaceSet(solid: solid, faces: both.map(\.id))), signed: false)
        #expect(near(found[0], 3) && near(found[1], 2), "got \(found)")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func refusalsAreKernelErrors(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await cube(kernel)
        await #expect(throws: KernelError.invalidInput("No faces are selected to measure to.")) {
            try await kernel.distances(from: [.zero], to: .faces(FaceSet(solid: solid, faces: [])), signed: false)
        }
        await #expect(throws: KernelError.invalidInput("A selected edge doesn't exist on the solid.")) {
            try await kernel.distances(from: [.zero], to: .edges(EdgeSet(solid: solid, edges: [EdgeID(999)])), signed: false)
        }
        await #expect(throws: KernelError.invalidInput("A point to measure from is not a finite position.")) {
            try await kernel.distances(from: [Vector3(.nan, 0, 0)], to: .solid(solid), signed: true)
        }
        let foreign = try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided,
                                                     tag: newTag())
        await #expect(throws: KernelError.invalidInput("This solid was made by a different kernel.")) {
            try await kernel.distances(from: [.zero], to: .solid(foreign), signed: true)
        }
        #expect(try await kernel.distances(from: [], to: .solid(solid), signed: true).isEmpty)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aCancelledCallIsSkipped(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await cube(kernel)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.distances(from: [.zero], to: .solid(solid), signed: true)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Cancelled from a hook after the first of three chunks: the loop's own check, not the one on entry, stops it.
    @Test func aBatchCancelledBetweenChunksStopsThere() async throws {
        let kernel = OCCTKernel()
        let solid = try await cube(kernel)
        let points = (0..<(3 * OCCTKernel.distanceChunk)).map { Vector3(Double($0 % 17) - 8, 0, 5) }
        let task = Task {
            try await kernel.distances(from: points, to: .solid(solid), signed: true, afterChunk: {
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let whole = try await kernel.distances(from: points, to: .solid(solid), signed: true)
        #expect(whole.count == points.count, "the same batch without the cancel runs to the end")
    }

    /// A smooth loft through three circles has B-spline faces, not the planes and cylinders of the other fixtures: the shim's
    /// threads read a different kind of geometry, and a batch must still equal each point on its own, exactly.
    @Test func aBatchOnALoftGivesWhatEachPointGivesOnItsOwn() async throws {
        let kernel = OCCTKernel()
        let sections = [(0.0, 5.0), (10, 3), (20, 6)].map { height, radius in
            Profile2D.circle(radius: radius, center: .zero, plane: Plane.xy.offset(by: height))
        }
        let solid = try await kernel.loft(sections, ruled: false, tag: newTag())
        // 300 points in and around the loft: four blocks of 64 and a part for the threads to share out.
        let points = (0..<300).map { Vector3(Double($0 % 13) - 6, Double($0 % 7) * 1.5 - 4.5, Double($0) * 0.08 - 1) }
        let batch = try await kernel.distances(from: points, to: .solid(solid), signed: true)
        #expect(batch.contains { $0 < 0 } && batch.contains { $0 > 0 }, "points on both sides of the surface")
        for (index, point) in points.enumerated() {
            let single = try await kernel.distances(from: [point], to: .solid(solid), signed: true)
            #expect(near(single[0], batch[index], tolerance: 1e-12), "point \(index)")
        }
        #expect(try await kernel.distances(from: points, to: .solid(solid), signed: true) == batch, "a second run gives the same numbers")
    }

    /// The shim itself, below the Swift checks: a face index it doesn't have is a status, never an exception out of C++.
    @Test func aBadIndexInTheShimIsAnErrorNotACrash() async throws {
        let kernel = OCCTKernel()
        let shape = try await kernel.shape(of: try await cube(kernel))
        #expect(throws: OCCTError(message: "face index out of range")) {
            _ = try shape.distances(from: [Vector3.zero][...], kind: .faces, indices: [99], signed: false)
        }
        #expect(throws: OCCTError(message: "edge index out of range")) {
            _ = try shape.distances(from: [Vector3.zero][...], kind: .edges, indices: [0], signed: false)
        }
        #expect(throws: OCCTError(message: "nothing to measure to")) {
            _ = try shape.distances(from: [Vector3.zero][...], kind: .edges, indices: [], signed: false)
        }
    }

    @Test func manyCallsKeepWorking() async throws {
        let kernel = OCCTKernel()
        let solid = try await cube(kernel)
        for round in 0..<200 {
            let found = try await kernel.distances(from: [Vector3(0, 0, Double(round % 10))], to: .solid(solid), signed: true)
            #expect(found.count == 1)
        }
    }
}
