import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The tint's GPU data: the uniform's layout and one value per de-indexed corner, in the order `meshVertices` makes them.
struct FieldTintDataTests {
    let mesh = TestMeshes.box(BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30)))
    let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)

    @Test func theRampUniformHasTheShaderLayout() {
        #expect(MemoryLayout<FieldRampUniforms>.stride == 64)
        #expect(MemoryLayout<FieldRampUniforms>.offset(of: \FieldRampUniforms.range) == 48)
        let uniforms = FieldRampUniforms(ramp)
        #expect(uniforms.low == ramp.low && uniforms.high == ramp.high)
        #expect(uniforms.range == SIMD4<Float>(-5, 0, 5, 0))
    }

    @Test func eachCornerCarriesItsVerticesValue() throws {
        let values = mesh.positions.map { Float($0.x) }
        let corners = try #require(GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp))
        let vertices = GPUGeometry.meshVertices(mesh)
        #expect(corners.count == vertices.count && corners.count == mesh.indices.count)
        #expect(zip(corners, vertices).allSatisfy { $0 == $1.position.x })
    }

    @Test func aTriangleThatMeshVerticesSkipsIsSkippedHereToo() throws {
        var broken = mesh
        broken.indices[0] = 999
        let corners = try #require(GPUGeometry.fieldCorners(broken, values: broken.positions.map { Float($0.x) }, ramp: ramp))
        #expect(corners.count == GPUGeometry.meshVertices(broken).count && corners.count == mesh.indices.count - 3)
    }

    @Test func valuesOfTheWrongCountMakeNoBuffer() {
        #expect(GPUGeometry.fieldCorners(mesh, values: [], ramp: ramp) == nil)
        #expect(GPUGeometry.fieldCorners(mesh, values: [Float](repeating: 1, count: mesh.positions.count + 1), ramp: ramp) == nil)
    }

    @Test func aValueThatIsNotANumberBecomesTheRampsMiddle() throws {
        var values = mesh.positions.map { Float($0.x) }
        values[0] = .nan
        values[1] = .infinity
        let corners = try #require(GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp))
        #expect(corners.allSatisfy { $0.isFinite })
        #expect(corners[0] == ramp.midValue, "the first corner is vertex 0")
    }
}
