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
        case .face:
            throw .unsupported("a lattice mapped to a face")
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
}
