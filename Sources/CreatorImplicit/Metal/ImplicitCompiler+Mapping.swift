import CreatorGeometry

/// The Metal for the lattices' mappings (implicit spec §3.5): the lattice coordinates of a point, the distance to the singular set, and
/// the join that leaves the singular set solid.
extension ImplicitCompiler.Generator {
    /// The lattice coordinates of `p` under `mapping`, and the name of the distance to its singular set (`nil` for Straight, whose
    /// coordinates are `p` itself).
    mutating func mapped(_ mapping: LatticeMapping, at p: String) throws(ImplicitCompileError) -> (coordinates: String, singular: String?) {
        switch mapping {
        case .straight:
            return (p, nil)
        case .cylindrical(let map):
            let (origin, reference, side) = (vector(map.origin), vector(map.reference), vector(map.side))
            let (axis, radius) = (vector(map.axis), number(map.radius))
            let coordinates = declareVector("mapCylindrical(\(p), \(origin), \(reference), \(side), \(axis), \(radius))")
            return (coordinates, declare("singularCylindrical(\(p), \(origin), \(reference), \(side))"))
        case .spherical(let map):
            let (centre, radius) = (vector(map.centre), number(map.radius))
            return (declareVector("mapSpherical(\(p), \(centre), \(radius))"), declare("singularSpherical(\(p), \(centre))"))
        case .face(let map):
            return face(map, at: p)
        }
    }

    /// A lattice's `body`, left solid at the mapping's singular set (`singular`, from `mapped`) and cut to the region at `p`.
    mutating func cut(_ body: String, singular: String?, at p: String, region: BoundingBox) -> String {
        var joined = body
        if let singular {
            let (exclusion, fade) = (number(LatticeMapping.exclusion), number(LatticeMapping.fadeWidth))
            joined = declare("mappingJoin(\(body), \(singular), \(exclusion), \(fade))")
        }
        let (centre, half) = (vector(region.center), vector(region.size * 0.5))
        return declare("max(\(joined), regionDistance(\(p), \(centre), \(half)))")
    }

    /// A face chart: its blocks go where every baked distance goes, and its header (flags, then the slots of the five channels) to the
    /// integers; the lengths of a radian of the periodic coordinates to the floats. The singular distance, if the chart has one, is a
    /// sixth channel.
    mutating func face(_ map: FaceMap, at p: String) -> (coordinates: String, singular: String?) {
        let chart = map.chart
        let slots = [chart.first, chart.firstSine ?? chart.first, chart.second, chart.secondSine ?? chart.second, chart.depth]
            .map { register($0) }
        let header = integers.count
        let flags = (chart.firstSine == nil ? 0 : 1) | (chart.secondSine == nil ? 0 : 2)
        integers += [Int32(flags)] + slots.flatMap { [Int32($0.integers), Int32($0.parameters)] }
        let (first, second) = (number(map.firstRadius ?? 1), number(map.secondRadius ?? 1))
        let coordinates = declareVector("mapFace(\(dialect.environment)\(header), \(p), \(first), \(second))")
        guard let blocks = chart.singular else { return (coordinates, nil) }
        let slot = register(blocks)
        return (coordinates, declare("bakedChannel(\(dialect.environment)\(slot.integers), \(slot.parameters), \(p))"))
    }
}
