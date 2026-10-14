import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorImplicit

/// What the compiler generates, without a GPU (implicit spec §4.1): the source depends on the shape of the tree and never on its numbers.
struct ImplicitCompilerTests {
    func source(_ solid: ImplicitSolid) throws -> String { try ImplicitCompiler.compile(solid).source }

    @Test func editingANumberDoesNotChangeTheSource() throws {
        #expect(try source(.sphere(radius: 5)) == source(.sphere(radius: 50)))
        let a = ImplicitSolid.shell(.box(halfSize: Vector3(1, 2, 3), cornerRadius: 0), thickness: .constant(1), side: .inward)
        let b = ImplicitSolid.shell(.box(halfSize: Vector3(9, 8, 7), cornerRadius: 2), thickness: .constant(4), side: .outward)
        #expect(try source(a) == source(b), "the side is a parameter too")
        #expect(try source(.union([.sphere(radius: 1), .sphere(radius: 2)], blend: .constant(0)))
            == source(.union([.sphere(radius: 3), .sphere(radius: 4)], blend: .constant(5))))
    }

    @Test func aFieldSettingsNumbersAreNotInTheSourceEither() throws {
        func graded(_ seed: Int, _ octaves: Int, _ level: Double) -> ImplicitSolid {
            let noise = Field.noise(seed: seed, scale: 4 + level, octaves: octaves)
            let field = Field.remap(noise, fromLow: 0, fromHigh: level + 1, toLow: 0, toHigh: 1, clamped: octaves.isMultiple(of: 2))
            return .offset(.sphere(radius: 3), distance: Grading(field: field, range: 0...1, slope: 1))
        }
        #expect(try source(graded(1, 1, 0.5)) == source(graded(77, 4, 3)))
    }

    @Test func aDifferentShapeIsADifferentSource() throws {
        let sphere = ImplicitSolid.sphere(radius: 5)
        #expect(try source(sphere) != source(.box(halfSize: Vector3(1, 1, 1), cornerRadius: 0)))
        #expect(try source(.union([sphere, sphere], blend: .constant(0))) != source(.union([sphere, sphere, sphere], blend: .constant(0))))
        #expect(try source(.union([sphere, sphere], blend: .constant(0))) != source(.intersect([sphere, sphere], blend: .constant(0))))
        let graded = Grading(field: .linearGradient(plane: .xy, length: 3), range: 0...1, slope: 0.3)
        #expect(try source(.offset(sphere, distance: .constant(1))) != source(.offset(sphere, distance: graded)),
                "a field-valued setting is another shape from a constant")
    }

    @Test func theSourceHasTheKernelAndTheLibrary() throws {
        let text = try source(.sphere(radius: 5))
        #expect(text.contains("kernel void \(CompiledImplicit.kernelName)"))
        #expect(text.contains("inline float sdf(const thread Env& e, float3 p)"))
        #expect(text.contains("inline float smoothMin") && text.contains("inline float bakedValue"))
        #expect(text.contains("length(p) - e.P[0]"), "the radius is a slot, not a number")
    }

    @Test func parametersAreInTheBuffers() throws {
        let program = try ImplicitCompiler.compile(.sphere(radius: 5))
        #expect(program.parameters == [5])
        let shell = try ImplicitCompiler.compile(.shell(.sphere(radius: 5), thickness: .constant(2), side: .centred))
        #expect(shell.parameters == [5, 2] && shell.integers == [Int32(ShellSide.centred.rawValue)])
    }

    @Test func bakedBlocksAreUploadedOnceHoweverOftenTheyAreUsed() throws {
        let blocks = BlocksFixture.make(origin: .zero, spacing: 1, blocks: 1) { $0.x }
        let baked = ImplicitSolid.baked(blocks, label: "a")
        let program = try ImplicitCompiler.compile(.union([baked, baked, baked], blend: .constant(0)))
        #expect(program.tables.count == 1 && program.pool.count == 512 + 1)
        #expect(program.integers.count == 6)
        // 6 integers [table, pool, coarse, nx, ny, nz] and 4 floats [origin, spacing] per distinct block set, plus the blend (1).
        #expect(program.parameters.count == 4 + 1)
    }

    @Test func noiseSeedsAreInTheTablesAndPicturesInTheirOwnBuffer() throws {
        let noisy = ImplicitSolid.offset(.sphere(radius: 3), distance: GPUFixtures.graded(.noise(seed: 3, scale: 5, octaves: 3)))
        let noise = try ImplicitCompiler.compile(noisy)
        #expect(noise.tables.count == 6, "a pair of words for each octave")
        let start = SeededRandom(seed: 3, stream: 0, purpose: .fieldNoise).streamStart
        #expect(UInt32(bitPattern: noise.tables[0]) == UInt32(start & 0xFFFF_FFFF))
        #expect(UInt32(bitPattern: noise.tables[1]) == UInt32(start >> 32))
        let image = try #require(GPUFixtures.picture)
        let picture = try ImplicitCompiler.compile(.offset(.sphere(radius: 3), distance: GPUFixtures.graded(
            .image(image, plane: .xy, width: 10, height: 10, edges: .clamp))))
        #expect(picture.images.count == 30 && picture.images == image.pixels.map(Float.init))
    }

    @Test func aDistanceToAProfileIsLeftToTheCPU() {
        let profile = Profile2D.rectangle(width: 4, height: 4, plane: .xy)
        let graded = Grading(field: .distance(.profile(profile), signed: false), range: 0...10, slope: 1)
        #expect(throws: ImplicitCompileError.unsupported("a distance to a profile")) {
            try ImplicitCompiler.compile(.offset(.sphere(radius: 3), distance: graded))
        }
    }

    @Test func aKernelDistanceThatWasNotBakedIsLeftToTheCPU() {
        let graded = Grading(field: .distance(.kernel(.solid(GPUFixtures.stand)), signed: true), range: 0...10, slope: 1)
        #expect(throws: ImplicitCompileError.unsupported("a distance to a solid that was not baked")) {
            try ImplicitCompiler.compile(.offset(.sphere(radius: 3), distance: graded))
        }
    }

    @Test(arguments: GPUFixtures.all.map(\.name))
    func everyFixtureCompiles(_ name: String) throws {
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let program = try ImplicitCompiler.compile(solid)
        #expect(program.source.contains("return v"))
    }
}
