import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// What a preview asks of a field: equality (is it the same field as before?), its own plane, whether it needs the kernel,
/// whether it is a signed distance and its unit.
struct FieldPreviewPropertiesTests {
    func solid() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                       tag: NodeTag(node: NodeID(), item: 0))
    }

    // MARK: equality

    @Test func theSameRecipeOverTheSameSolidIsEqualAndAnotherSolidIsNot() async throws {
        let one = try await solid(), other = try await solid()
        let a = Field.multiply(.distance(.kernel(.solid(one)), signed: true), .noise(seed: 4, scale: 5, octaves: 2))
        let b = Field.multiply(.distance(.kernel(.solid(one)), signed: true), .noise(seed: 4, scale: 5, octaves: 2))
        let c = Field.multiply(.distance(.kernel(.solid(other)), signed: true), .noise(seed: 4, scale: 5, octaves: 2))
        #expect(a == b && a.hashValue == b.hashValue)
        #expect(a != c)
        #expect(a != .multiply(.distance(.kernel(.solid(one)), signed: false), .noise(seed: 4, scale: 5, octaves: 2)))
        #expect(a != .multiply(.distance(.kernel(.solid(one)), signed: true), .noise(seed: 5, scale: 5, octaves: 2)))
    }

    @Test func edgeSetsAreEqualByTheirSolidAndEdges() async throws {
        let part = try await solid()
        let a = Field.distance(.kernel(.edges(EdgeSet(solid: part, edges: [EdgeID(0), EdgeID(1)]))), signed: false)
        let b = Field.distance(.kernel(.edges(EdgeSet(solid: part, edges: [EdgeID(1), EdgeID(0)]))), signed: false)
        #expect(a == b)
        #expect(a != .distance(.kernel(.edges(EdgeSet(solid: part, edges: [EdgeID(0)]))), signed: false))
        #expect(Field.distance(.point(.zero), signed: false) == .distance(.point(.zero), signed: false))
        #expect(Field.distance(.point(.zero), signed: false) != .distance(.point(.unitX), signed: false))
        #expect(Field.constant(1) != .constant(2) && Field.constant(1) != .radialGradient(center: .zero, radius: 1))
    }

    // MARK: own plane

    @Test func aGradientsPlaneIsTheFieldsOwnAndMathsKeepTheFirstOne() {
        let plane = Plane(origin: Vector3(1, 2, 3), normal: .unitX, xAxis: .unitY)
        let gradient = Field.linearGradient(plane: plane, length: 10)
        #expect(gradient.ownPlane == plane)
        #expect(Field.remap(gradient, fromLow: 0, fromHigh: 1, toLow: 0, toHigh: 5, clamped: true).ownPlane == plane)
        #expect(Field.add(.noise(seed: 1, scale: 5, octaves: 1), gradient).ownPlane == plane)
        let second = Plane(origin: .zero, normal: .unitZ, xAxis: .unitX)
        #expect(Field.add(gradient, .linearGradient(plane: second, length: 1)).ownPlane == plane, "the first")
        #expect(Field.radialGradient(center: .zero, radius: 5).ownPlane == nil)
        #expect(Field.constant(3).ownPlane == nil && Field.noise(seed: 1, scale: 5, octaves: 1).ownPlane == nil)
    }

    // MARK: kernel

    @Test func onlyADistanceToTheKernelNeedsTheKernel() async throws {
        let part = try await solid()
        let kernel = Field.distance(.kernel(.solid(part)), signed: true)
        #expect(kernel.measuresWithKernel)
        #expect(Field.clamp(.multiply(.constant(2), kernel), low: 0, high: 1).measuresWithKernel)
        #expect(!Field.distance(.point(.zero), signed: false).measuresWithKernel)
        #expect(!Field.distance(.profile(.rectangle(width: 4, height: 4, plane: .xy)), signed: false).measuresWithKernel)
        #expect(!Field.add(.noise(seed: 1, scale: 5, octaves: 1), .radialGradient(center: .zero, radius: 5)).measuresWithKernel)
    }

    // MARK: signed distance and unit

    @Test func aSignedDistanceToASolidCentresOnZeroAndSoDoesTheMinimumOfTwo() async throws {
        let part = try await solid()
        let signed = Field.distance(.kernel(.solid(part)), signed: true)
        let unsigned = Field.distance(.kernel(.solid(part)), signed: false)
        #expect(signed.isSignedDistance && !unsigned.isSignedDistance)
        #expect(!Field.distance(.kernel(.faces(FaceSet(solid: part, faces: [FaceID(0)]))), signed: true).isSignedDistance)
        #expect(Field.minimum(signed, signed).isSignedDistance && Field.clamp(signed, low: -2, high: 2).isSignedDistance)
        #expect(!Field.minimum(signed, unsigned).isSignedDistance && !Field.add(signed, signed).isSignedDistance)
        #expect(!Field.constant(0).isSignedDistance && !Field.noise(seed: 1, scale: 5, octaves: 1).isSignedDistance)
    }

    @Test func aDistanceIsInMillimetresAndSoIsWhatKeepsItsUnit() async throws {
        let distance = Field.distance(.point(.zero), signed: false)
        #expect(distance.unit == .millimetres)
        #expect(Field.clamp(distance, low: 0, high: 20).unit == .millimetres)
        #expect(Field.add(distance, .constant(5)).unit == .millimetres && Field.add(.constant(5), distance).unit == .millimetres)
        #expect(Field.minimum(distance, .distance(.point(.unitX), signed: false)).unit == .millimetres)
        #expect(Field.smoothMinimum(distance, distance, width: 2).unit == .millimetres)
        #expect(Field.add(distance, .noise(seed: 1, scale: 5, octaves: 1)).unit == .none, "a mixture has no unit")
        #expect(Field.multiply(distance, distance).unit == .none)
        #expect(Field.remap(distance, fromLow: 0, fromHigh: 20, toLow: 0, toHigh: 1, clamped: true).unit == .none)
        #expect(Field.radialGradient(center: .zero, radius: 5).unit == .none && Field.constant(1).unit == .none)
    }
}
