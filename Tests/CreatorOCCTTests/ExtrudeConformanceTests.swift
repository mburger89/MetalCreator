import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct ExtrudeConformanceTests {
    @Test(arguments: KernelUnderTest.allCases)
    func boxExtrudeIsAnalytic(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await box(kernel, 10, 20, 30, tag: tag)
        let properties = try await kernel.properties(of: solid)
        #expect(isClose(properties.volume, 6000))
        #expect(solid.topology.faces.count == 6)
        #expect(solid.topology.edges.count == 12)
        #expect(isClose(solid.bounds.min.z, 0, relative: 1e-4) && isClose(solid.bounds.max.z, 30, relative: 1e-4))
        let top = try #require(faces(solid, role: .endCap, of: tag).first)
        let bottom = try #require(faces(solid, role: .startCap, of: tag).first)
        #expect((top.normal ?? .zero).dot(.unitZ) > 0.999)
        #expect((bottom.normal ?? .zero).dot(.unitZ) < -0.999)
        for k in 0..<4 {
            #expect(faces(solid, role: .side(segment: k), of: tag).count == 1)
        }
        #expect(solid.topology.faces.allSatisfy { $0.tags.count == 1 })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func symmetricExtrudeStraddlesThePlane(_ under: KernelUnderTest) async throws {
        let solid = try await under.make().extrude(.rectangle(width: 2, height: 2, plane: .xy), distance: 6, mode: .symmetric, tag: newTag())
        #expect(isClose(solid.bounds.min.z, -3, relative: 1e-4))
        #expect(isClose(solid.bounds.max.z, 3, relative: 1e-4))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func circleExtrudeHasASeamAndACylinder(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await kernel.extrude(.circle(radius: 2.5, center: .zero, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        #expect(isClose(try await kernel.properties(of: solid).volume, Double.pi * 6.25 * 6))
        #expect(solid.topology.faces.count == 3)
        let wall = try #require(faces(solid, role: .side(segment: 0), of: tag).first)
        #expect(wall.kind == .cylinder)
        #expect(solid.topology.edges.contains { $0.isSeam })
        let rims = solid.topology.edges.filter { $0.kind == .circle }
        #expect(rims.count == 2)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func profileOnTheFrontPlaneExtrudesTowardMinusY(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(.rectangle(width: 10, height: 4, plane: .xz), distance: 2, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 80))
        #expect(isClose(solid.bounds.min.y, -2, relative: 1e-4) && isClose(solid.bounds.max.y, 0, relative: 1e-3))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func clockwiseProfileStillGivesAPositiveSolid(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let ccw = Profile2D.rectangle(width: 4, height: 4, plane: .xy)
        let cw = Profile2D(plane: .xy, segments: ccw.segments.reversed().map { segment in
            guard case .line(let a, let b) = segment else { return segment }
            return .line(b, a)
        })
        let solid = try await kernel.extrude(cw, distance: 1, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 16))
    }

    /// Exactly one start cap and one end cap, with the end cap facing +Z (the XY plane's normal)
    /// and the start cap facing −Z.
    func expectOneCapEach(_ solid: Solid, tag: NodeTag) throws {
        let starts = faces(solid, role: .startCap, of: tag)
        let ends = faces(solid, role: .endCap, of: tag)
        #expect(starts.count == 1)
        #expect(ends.count == 1)
        let endNormal = try #require(ends.first?.normal)
        let startNormal = try #require(starts.first?.normal)
        #expect(endNormal.dot(.unitZ) > 0.999, "end cap normal \(endNormal) should be +Z")
        #expect(startNormal.dot(.unitZ) < -0.999, "start cap normal \(startNormal) should be −Z")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func clockwiseAndSymmetricExtrudesHaveOneCapEach(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let ccw = Profile2D.rectangle(width: 4, height: 4, plane: .xy)
        let cw = Profile2D(plane: .xy, segments: ccw.segments.reversed().map { segment in
            guard case .line(let a, let b) = segment else { return segment }
            return .line(b, a)
        })
        let cwTag = newTag()
        try expectOneCapEach(try await kernel.extrude(cw, distance: 1, mode: .oneSided, tag: cwTag), tag: cwTag)
        let symmetricTag = newTag()
        try expectOneCapEach(try await kernel.extrude(ccw, distance: 6, mode: .symmetric, tag: symmetricTag), tag: symmetricTag)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func openProfileIsRejected(_ under: KernelUnderTest) async {
        let open = Profile2D(plane: .xy, segments: [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))])
        await #expect(throws: KernelError.invalidInput("The profile is not a closed loop.")) {
            try await under.make().extrude(open, distance: 1, mode: .oneSided, tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func zeroLengthLineIsAPlainError(_ under: KernelUnderTest) async {
        let degenerate = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(0, 0)), .line(Vector2(0, 0), Vector2(1, 0)),
            .line(Vector2(1, 0), Vector2(1, 1)), .line(Vector2(1, 1), Vector2(0, 0)),
        ])
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(degenerate, distance: 1, mode: .oneSided, tag: newTag())
        }
        guard case .operationFailed(let operation, let reason)? = error else { Issue.record("expected operationFailed"); return }
        #expect(operation == "extrude")
        #expect(reason == "a line in the profile has zero length.")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func invalidPlaneIsRejected(_ under: KernelUnderTest) async {
        let plane = Plane(origin: .zero, normal: .unitZ, xAxis: .unitZ)
        let profile = Profile2D(plane: plane, segments: Profile2D.rectangle(width: 1, height: 1, plane: .xy).segments)
        await #expect(throws: KernelError.invalidInput("The profile's plane is not valid.")) {
            try await under.make().extrude(profile, distance: 1, mode: .oneSided, tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func halfDiscArcRunsCounterClockwiseFromXAxis(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let profile = Profile2D(plane: .xy, segments: [
            .arc(center: Vector2(0, 0), radius: 2, start: Angle(radians: 0), end: Angle(radians: .pi)),
            .line(Vector2(-2, 0), Vector2(2, 0)),
        ])
        let solid = try await kernel.extrude(profile, distance: 1, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 2 * Double.pi))
        #expect(isClose(solid.bounds.min.y, 0, relative: 1e-4) && isClose(solid.bounds.max.y, 2, relative: 1e-4))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func sideFacesFollowSegmentOrder(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let solid = try await under.make().extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 1, mode: .oneSided, tag: tag)
        let first = try #require(faces(solid, role: .side(segment: 0), of: tag).first?.normal)
        let second = try #require(faces(solid, role: .side(segment: 1), of: tag).first?.normal)
        #expect(first.dot(Vector3(0, -1, 0)) > 0.999)
        #expect(second.dot(.unitX) > 0.999)
    }

    @Test func concurrentKernelsDoNotInterfere() async throws {
        let kernels = (0..<4).map { _ in OCCTKernel() }
        try await withThrowingTaskGroup(of: Double.self) { group in
            for index in 0..<8 {
                let kernel = kernels[index % 4]
                group.addTask {
                    let solid = try await box(kernel, 2, 3, 4)
                    return try await kernel.properties(of: solid).volume
                }
            }
            for try await volume in group { #expect(isClose(volume, 24)) }
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func nonPositiveDistanceIsRejected(_ under: KernelUnderTest) async {
        await #expect(throws: KernelError.invalidInput("Extrude distance must be greater than 0 mm.")) {
            try await under.make().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 0, mode: .oneSided, tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func cancelledCallIsSkipped(_ under: KernelUnderTest) async {
        let kernel = under.make()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided, tag: newTag())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func solidsFromAnotherKernelAreRejected() async throws {
        let fake = try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided, tag: newTag())
        await #expect(throws: KernelError.invalidInput("This solid was made by a different kernel.")) {
            try await OCCTKernel().properties(of: fake)
        }
    }
}
