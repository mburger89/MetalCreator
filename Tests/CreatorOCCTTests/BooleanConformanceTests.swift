import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct BooleanConformanceTests {
    /// A 60 × 40 × 6 plate (centred on XY, z 0…6) and four Ø5 through-tools at (±20, ±10),
    /// each tool tagged as its own broadcast item and running from z = −1 to 7.
    func plateAndHoles(_ kernel: any Kernel, plate plateTag: NodeTag, holes holeNode: NodeID)
        async throws -> (Solid, [Solid]) {
        let plate = try await box(kernel, 60, 40, 6, tag: plateTag)
        var tools: [Solid] = []
        for (item, center) in [Vector2(-20, -10), Vector2(20, -10), Vector2(-20, 10), Vector2(20, 10)].enumerated() {
            tools.append(try await kernel.extrude(.circle(radius: 2.5, center: center, plane: Plane.xy.offset(by: -1)),
                                                  distance: 8, mode: .oneSided, tag: NodeTag(node: holeNode, item: item)))
        }
        return (plate, tools)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func subtractingHolesKeepsPlateTagsAndNamesHoleWalls(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let plateTag = newTag()
        let holeNode = NodeID()
        let (plate, tools) = try await plateAndHoles(kernel, plate: plateTag, holes: holeNode)
        let result = try await kernel.boolean(.subtract, plate, tools, tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 14400 - 4 * Double.pi * 6.25 * 6))
        #expect(result.topology.faces.count == 10)
        #expect(faces(result, role: .endCap, of: plateTag).count == 1)
        #expect(faces(result, role: .startCap, of: plateTag).count == 1)
        for k in 0..<4 {
            #expect(faces(result, role: .side(segment: k), of: plateTag).count == 1)
            #expect(faces(result, role: .side(segment: 0), of: NodeTag(node: holeNode, item: k)).count == 1)
        }
        #expect(result.topology.faces.allSatisfy { face in !face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func subtractingAMissingToolKeepsThePlate(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let plateTag = newTag()
        let plate = try await box(kernel, 10, 10, 2, tag: plateTag)
        let far = try await kernel.extrude(.rectangle(width: 1, height: 1, plane: Plane.xy.offset(by: 100)), distance: 1,
                                           mode: .oneSided, tag: newTag())
        let result = try await kernel.boolean(.subtract, plate, [far], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 200))
        #expect(faces(result, role: .endCap, of: plateTag).count == 1)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func unionOfOverlappingBoxesMergesTags(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 10, 10, 10)
        let b = try await kernel.transform(try await box(kernel, 10, 10, 10), by: Transform(translation: Vector3(5, 0, 0)), tag: newTag())
        let result = try await kernel.boolean(.union, a, [b], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 1500))
        // SimplifyResult merges the coplanar top faces into one face carrying both tags.
        #expect(result.topology.faces.contains { $0.tags.count >= 2 })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func steppedUnionHasConcaveEdges(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 10, 10, 10)
        let b = try await kernel.transform(try await box(kernel, 10, 10, 10), by: Transform(translation: Vector3(5, 0, 5)), tag: newTag())
        let result = try await kernel.boolean(.union, a, [b], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 1750))
        #expect(result.topology.edges.contains { $0.convexity == .concave })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func intersectKeepsTheOverlap(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 10, 10, 10)
        let b = try await kernel.transform(try await box(kernel, 10, 10, 10), by: Transform(translation: Vector3(5, 0, 0)), tag: newTag())
        let result = try await kernel.boolean(.intersect, a, [b], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 500))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func emptyIntersectionIsAPlainError(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 1, 1, 1)
        let b = try await kernel.transform(try await box(kernel, 1, 1, 1), by: Transform(translation: Vector3(50, 0, 0)), tag: newTag())
        let error = await #expect(throws: KernelError.self) { try await kernel.boolean(.intersect, a, [b], tag: newTag()) }
        guard case .operationFailed(let operation, let reason)? = error else { Issue.record("expected operationFailed"); return }
        #expect(operation == "intersect")
        #expect(reason.contains("empty"))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func booleanWithNoToolsIsRejected(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 1, 1, 1)
        await #expect(throws: KernelError.invalidInput("Connect at least one tool solid.")) {
            try await kernel.boolean(.subtract, a, [], tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func translateMovesBoundsAndKeepsTags(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let original = try await box(kernel, 2, 2, 2, tag: tag)
        let moved = try await kernel.transform(original, by: Transform(translation: Vector3(5, 0, 0)), tag: newTag())
        #expect(isClose(moved.bounds.min.x, 4, relative: 1e-4) && isClose(moved.bounds.max.x, 6, relative: 1e-4))
        #expect(isClose(try await kernel.properties(of: moved).volume, 8))
        #expect(Set(moved.topology.faces.flatMap(\.tags)) == Set(original.topology.faces.flatMap(\.tags)))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func rotateTurnsTheBounds(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let slab = try await box(kernel, 10, 2, 2)
        let turned = try await kernel.transform(slab, by: Transform(rotationAxis: .z, rotation: .degrees(90)), tag: newTag())
        #expect(isClose(turned.bounds.size.y, 10, relative: 1e-3))
        #expect(isClose(turned.bounds.size.x, 2, relative: 1e-3))
    }
}
