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
    func subtractLeavesItsInputsUntouched(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let (plate, tools) = try await plateAndHoles(kernel, plate: newTag(), holes: NodeID())
        let before = try await kernel.properties(of: plate)
        let beforeMesh = try await kernel.tessellate(plate, tolerance: 0.1)
        let first = try await kernel.boolean(.subtract, plate, tools, tag: newTag())
        let after = try await kernel.properties(of: plate)
        #expect(isClose(after.volume, before.volume) && isClose(after.surfaceArea, before.surfaceArea))
        let afterMesh = try await kernel.tessellate(plate, tolerance: 0.1)
        #expect(Set(afterMesh.triangleFaces) == Set(beforeMesh.triangleFaces))
        #expect(Set(afterMesh.triangleFaces).count == 6)
        #expect(afterMesh.edgePolylines.count == beforeMesh.edgePolylines.count)
        let second = try await kernel.boolean(.subtract, plate, tools, tag: newTag())
        #expect(isClose(try await kernel.properties(of: second).volume, try await kernel.properties(of: first).volume))
        #expect(second.topology.faces.count == first.topology.faces.count)
        #expect(second.topology.edges.count == first.topology.edges.count)
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
        let aTag = newTag()
        let bTag = newTag()
        let a = try await box(kernel, 10, 10, 10, tag: aTag)
        let b = try await kernel.transform(try await box(kernel, 10, 10, 10, tag: bTag),
                                           by: Transform(translation: Vector3(5, 0, 0)), tag: newTag())
        let result = try await kernel.boolean(.union, a, [b], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 1500))
        // SimplifyResult merges the coplanar top faces into one face carrying both operands' end caps.
        let tops = result.topology.faces.filter { hasTag($0, .endCap, of: aTag) && hasTag($0, .endCap, of: bTag) }
        #expect(tops.count == 1)
        #expect(tops.first.map { isClose($0.area, 150) } == true)
        let bottoms = result.topology.faces.filter { hasTag($0, .startCap, of: aTag) && hasTag($0, .startCap, of: bTag) }
        #expect(bottoms.count == 1)
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
    @Test(arguments: KernelUnderTest.allCases)
    func rotationWithoutAnAxisIsRejected(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let slab = try await box(kernel, 10, 2, 2)
        await #expect(throws: KernelError.invalidInput("A rotation needs an axis.")) {
            try await kernel.transform(slab, by: Transform(rotation: .degrees(90)), tag: newTag())
        }
    }
    @Test(arguments: KernelUnderTest.allCases)
    func rotationHappensBeforeTranslation(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let slab = try await box(kernel, 10, 2, 2)
        let moved = try await kernel.transform(slab, by: Transform(translation: Vector3(5, 0, 0), rotationAxis: .z, rotation: .degrees(90)),
                                               tag: newTag())
        #expect(abs(moved.bounds.min.x - 4) < 1e-3 && abs(moved.bounds.max.x - 6) < 1e-3)
        #expect(abs(moved.bounds.min.y + 5) < 1e-3 && abs(moved.bounds.max.y - 5) < 1e-3)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func rotationAboutAnOffOriginAxis(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let cube = try await box(kernel, 2, 2, 2)
        let axis = Axis(origin: Vector3(10, 0, 0), direction: .unitZ)
        let turned = try await kernel.transform(cube, by: Transform(rotationAxis: axis, rotation: .degrees(180)), tag: newTag())
        #expect(abs(turned.bounds.center.x - 20) < 1e-3)
        #expect(abs(turned.bounds.center.y) < 1e-3)
        #expect(abs(turned.bounds.size.x - 2) < 1e-3)
    }
}
