import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Generates Metal for an `ImplicitSolid` (implicit spec §4.1): one statement per node of the tree, in evaluation order, each a port of
/// the matching branch of `CPUEvaluation`. Numbers go to the parameter buffers and the source names their slots, so the source is the
/// same for every solid of one shape.
public enum ImplicitCompiler {
    public static func compile(_ solid: ImplicitSolid) throws(ImplicitCompileError) -> CompiledImplicit {
        var generator = Generator()
        let result = try generator.solid(solid, at: "p")
        let source = ImplicitShaderLibrary.source + """


        inline float sdf(const thread Env& e, float3 p) {
        \(generator.lines.joined(separator: "\n"))
            return \(result);
        }

        kernel void \(CompiledImplicit.kernelName)(device const packed_float3* points [[buffer(0)]], device float* out [[buffer(1)]],
                                                   device const float* P [[buffer(2)]], device const int* I [[buffer(3)]],
                                                   device const int* tables [[buffer(4)]], device const float* pool [[buffer(5)]],
                                                   device const float* images [[buffer(6)]], constant uint& count [[buffer(7)]],
                                                   uint gid [[thread_position_in_grid]]) {
            if (gid >= count) { return; }
            Env e = { P, I, tables, pool, images };
            out[gid] = sdf(e, float3(points[gid]));
        }
        """
        return CompiledImplicit(source: source, parameters: generator.parameters, integers: generator.integers,
                                tables: generator.tables, pool: generator.pool, images: generator.images)
    }

    /// The generator's state: statements so far and the buffers they read.
    private struct Generator {
        var lines: [String] = []
        var parameters: [Float] = []
        var integers: [Int32] = []
        var tables: [Int32] = []
        var pool: [Float] = []
        var images: [Float] = []
        var variables = 0
        var registered: [ObjectIdentifier: (integers: Int, parameters: Int)] = [:]

        // MARK: Pieces

        mutating func declare(_ expression: String) -> String {
            variables += 1
            lines.append("    float v\(variables) = \(expression);")
            return "v\(variables)"
        }

        mutating func declareVector(_ expression: String) -> String {
            variables += 1
            lines.append("    float3 v\(variables) = \(expression);")
            return "v\(variables)"
        }

        /// A float parameter's name in the shader.
        mutating func number(_ value: Double) -> String {
            parameters.append(Float(value))
            return "e.P[\(parameters.count - 1)]"
        }

        /// An integer parameter's name in the shader.
        mutating func integer(_ value: Int) -> String {
            integers.append(Int32(truncatingIfNeeded: value))
            return "e.I[\(integers.count - 1)]"
        }

        mutating func vector(_ value: Vector3) -> String {
            "float3(\(number(value.x)), \(number(value.y)), \(number(value.z)))"
        }

        /// Stores baked distance blocks (once, however often they are used) and returns where their parameters are.
        mutating func register(_ blocks: DistanceBlocks) -> (integers: Int, parameters: Int) {
            if let known = registered[ObjectIdentifier(blocks)] { return known }
            let slot = (integers: integers.count, parameters: parameters.count)
            integers += [Int32(tables.count), Int32(pool.count), Int32(pool.count + blocks.pool.count),
                         Int32(blocks.blockCounts[0]), Int32(blocks.blockCounts[1]), Int32(blocks.blockCounts[2]),
            ]
            tables += blocks.table
            pool += blocks.pool
            pool += blocks.coarse
            parameters += [Float(blocks.origin.x), Float(blocks.origin.y), Float(blocks.origin.z), Float(blocks.spacing)]
            registered[ObjectIdentifier(blocks)] = slot
            return slot
        }

        // MARK: Solids

        // One branch per case, with no `default`, so a case added later is a compile error here.
        // swiftlint:disable:next cyclomatic_complexity
        mutating func solid(_ solid: ImplicitSolid, at p: String) throws(ImplicitCompileError) -> String {
            switch solid {
            case .sphere(let radius):
                return declare("length(\(p)) - \(number(radius))")
            case .box(let half, let cornerRadius):
                return declare("sdBox(\(p), \(vector(half)), \(number(cornerRadius)))")
            case .cylinder(let radius, let halfHeight):
                return declare("sdCylinder(\(p), \(number(radius)), \(number(halfHeight)))")
            case .moved(let child, let move):
                let (origin, x, y, z) = (vector(move.origin), vector(move.xAxis), vector(move.yAxis), vector(move.zAxis))
                let local = declareVector("float3(dot(\(p) - \(origin), \(x)), dot(\(p) - \(origin), \(y)), dot(\(p) - \(origin), \(z)))")
                return try self.solid(child, at: local)
            case .union(let children, let blend):
                return try combine(children, blend, at: p, empty: "1e30", join: { "smoothMin(\($0), \($1), \($2))" })
            case .intersect(let children, let blend):
                return try combine(children, blend, at: p, empty: "-1e30", join: { "-smoothMin(-\($0), -\($1), \($2))" })
            case .subtract(let children, let blend):
                return try combine(children, blend, at: p, empty: "1e30", join: { "-smoothMin(-\($0), \($1), \($2))" })
            case .offset(let child, let distance):
                let inner = try self.solid(child, at: p)
                return declare("\(inner) - \(try grading(distance, at: p))")
            case .shell(let child, let thickness, let side):
                let inner = try self.solid(child, at: p)
                let wall = declare("max(0.0, \(try grading(thickness, at: p)))")
                let side = integer(side.rawValue)
                let centre = declare("(\(side) == 0 ? -\(wall) / 2.0 : (\(side) == 1 ? \(wall) / 2.0 : 0.0))")
                return declare("abs(\(inner) - \(centre)) - \(wall) / 2.0")
            case .baked(let blocks, _):
                let slot = register(blocks)
                return declare("bakedValue(e, \(slot.integers), \(slot.parameters), \(p))")
            case .isosurface(let graded, let level, let maxSlope, let region):
                let value = try grading(graded, at: p)
                let (levelName, slopeName) = (number(level), number(maxSlope))
                let (centre, half) = (vector(region.center), vector(region.size * 0.5))
                return declare("max((\(value) - \(levelName)) / \(slopeName), regionDistance(\(p), \(centre), \(half)))")
            case .tpms(let lattice):
                return try tpms(lattice, at: p)
            case .struts(let lattice):
                return try struts(lattice, at: p)
            case .voronoi(let lattice):
                return try voronoi(lattice, at: p)
            }
        }

        /// A TPMS lattice: `tpmsLattice` of the cell size, the stretch and the thickness at `p`, its type and form as integers.
        mutating func tpms(_ lattice: TPMSLattice, at p: String) throws(ImplicitCompileError) -> String {
            let cell = try grading(lattice.cells.size, at: p)
            let wall = try grading(lattice.thickness, at: p)
            let stretch = vector(lattice.cells.stretch)
            let (type, form) = (integer(lattice.type.rawValue), integer(lattice.form.rawValue))
            let scale = number(lattice.type.wallScale)
            let (centre, half) = (vector(lattice.region.center), vector(lattice.region.size * 0.5))
            return declare("tpmsLattice(\(p), \(cell), \(stretch), \(wall), \(type), \(form), \(scale), \(centre), \(half))")
        }

        /// A strut lattice: the cell's struts go to the `pool` buffer (six floats each), their place and number to the integers.
        mutating func struts(_ lattice: StrutLattice, at p: String) throws(ImplicitCompileError) -> String {
            let cell = try grading(lattice.cells.size, at: p)
            let radius = try grading(lattice.radius, at: p)
            let stretch = vector(lattice.cells.stretch)
            let (offset, count) = (integer(pool.count), integer(lattice.cell.struts.count))
            for strut in lattice.cell.struts {
                pool += [strut.start, strut.end].flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
            }
            let blend = number(lattice.blend)
            let (centre, half) = (vector(lattice.region.center), vector(lattice.region.size * 0.5))
            return declare("strutLattice(e, \(offset), \(count), \(p), \(cell), \(stretch), \(radius), \(blend), \(centre), \(half))")
        }

        /// A Voronoi lattice: the seeds go to the `pool` buffer (three floats each), the grid to the `tables` buffer (cell starts, then
        /// seed numbers), where they are and how big the grid is to the integers, the grid's corner and cell size to the floats.
        mutating func voronoi(_ lattice: VoronoiLattice, at p: String) throws(ImplicitCompileError) -> String {
            let seeds = lattice.seeds
            let wall = try grading(lattice.thickness, at: p)
            let slot = (integers: integers.count, parameters: parameters.count)
            integers += [Int32(pool.count), Int32(tables.count), Int32(tables.count + seeds.starts.count)]
            integers += seeds.counts.map { Int32($0) }
            pool += seeds.points.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
            tables += seeds.starts
            tables += seeds.entries
            parameters += [Float(seeds.origin.x), Float(seeds.origin.y), Float(seeds.origin.z), Float(seeds.radius)]
            let form = integer(lattice.form.rawValue)
            let scale = number(VoronoiLattice.strutScale)
            let (centre, half) = (vector(lattice.region.center), vector(lattice.region.size * 0.5))
            return declare("voronoiLattice(e, \(slot.integers), \(slot.parameters), \(p), \(wall), \(form), \(scale), \(centre), \(half))")
        }

        /// Union, intersect and subtract: the children folded left to right with `join(result, next, width)`; `empty` is the value
        /// with no children (the same as `CPUEvaluation.emptySentinel`).
        mutating func combine(_ children: [ImplicitSolid], _ blend: Grading, at p: String, empty: String,
                              join: (String, String, String) -> String) throws(ImplicitCompileError) -> String {
            let width = declare("max(0.0, \(try grading(blend, at: p)))")
            var names: [String] = []
            for child in children { names.append(try solid(child, at: p)) }
            guard var result = names.first else { return declare(empty) }
            for name in names.dropFirst() { result = declare(join(result, name, width)) }
            return result
        }

        // MARK: Fields

        mutating func grading(_ grading: Grading, at p: String) throws(ImplicitCompileError) -> String {
            if let constant = grading.constantValue { return number(constant) }
            return try field(grading.field, at: p, in: grading)
        }

        // One branch per field case, with no `default`.
        // swiftlint:disable:next cyclomatic_complexity function_body_length
        mutating func field(_ field: Field, at p: String, in grading: Grading) throws(ImplicitCompileError) -> String {
            switch field {
            case .constant(let value):
                return number(value)
            case .distance(let source, let signed):
                switch source {
                case .point(let target):
                    return declare("length(\(p) - \(vector(target)))")
                case .profile:
                    throw .unsupported("a distance to a profile")
                case .kernel(let target):
                    guard let blocks = grading.blocks(for: target.identity, signed: signed) else {
                        throw .unsupported("a distance to a solid that was not baked")
                    }
                    let slot = register(blocks)
                    return declare("bakedValue(e, \(slot.integers), \(slot.parameters), \(p))")
                }
            case .linearGradient(let plane, let length):
                let (origin, normal) = (vector(plane.origin), vector(plane.normal.normalized ?? .zero))
                return declare("dot(\(p) - \(origin), \(normal)) / \(number(length))")
            case .radialGradient(let center, let radius):
                return declare("length(\(p) - \(vector(center))) / \(number(radius))")
            case .noise(let seed, let scale, let octaves):
                let seeds = tables.count
                for octave in 0..<octaves {
                    let start = SeededRandom(seed: seed, stream: octave, purpose: .fieldNoise).streamStart
                    tables += [Int32(truncatingIfNeeded: start & 0xFFFF_FFFF), Int32(truncatingIfNeeded: start >> 32)]
                }
                let (scaleName, octavesName, seedsName) = (number(scale), integer(octaves), integer(seeds))
                return declare("fieldNoise(e, \(p), \(scaleName), \(octavesName), \(seedsName))")
            case .image(let image, let plane, let width, let height, let edges):
                let slot = (integers: integers.count, parameters: parameters.count)
                integers += [Int32(images.count), Int32(image.width), Int32(image.height), Int32(edges.rawValue)]
                images += image.pixels.map(Float.init)
                let (origin, across, up) = (vector(plane.origin), vector(plane.xAxis.normalized ?? .zero),
                                            vector(plane.yAxis.normalized ?? .zero))
                let (widthName, heightName) = (number(width), number(height))
                let offset = declareVector("\(p) - \(origin)")
                return declare("imageValue(e, \(slot.integers), dot(\(offset), \(across)) / \(widthName) + 0.5, "
                    + "0.5 - dot(\(offset), \(up)) / \(heightName))")
            case .implicit(let reference):
                guard let solid = reference.solid else { throw .unsupported("an implicit that is not an ImplicitSolid") }
                return try self.solid(solid, at: p)
            case .add(let a, let b):
                return declare("\(try self.field(a, at: p, in: grading)) + \(try self.field(b, at: p, in: grading))")
            case .multiply(let a, let b):
                return declare("\(try self.field(a, at: p, in: grading)) * \(try self.field(b, at: p, in: grading))")
            case .minimum(let a, let b):
                return declare("min(\(try self.field(a, at: p, in: grading)), \(try self.field(b, at: p, in: grading)))")
            case .maximum(let a, let b):
                return declare("max(\(try self.field(a, at: p, in: grading)), \(try self.field(b, at: p, in: grading)))")
            case .remap(let inner, let fromLow, let fromHigh, let toLow, let toHigh, let clamped):
                let value = try self.field(inner, at: p, in: grading)
                let numbers = [fromLow, fromHigh, toLow, toHigh].map { number($0) }
                return declare("remapField(\(value), \(numbers.joined(separator: ", ")), \(integer(clamped ? 1 : 0)))")
            case .clamp(let inner, let low, let high):
                let value = try self.field(inner, at: p, in: grading)
                return declare("min(max(\(value), \(number(low))), \(number(high)))")
            case .smoothMinimum(let a, let b, let width):
                let (x, y) = (try self.field(a, at: p, in: grading), try self.field(b, at: p, in: grading))
                return declare("smoothMin(\(x), \(y), \(number(width)))")
            }
        }
    }
}
