import CreatorGeometry

extension VoronoiSeeds {
    /// The seeds of a Voronoi lattice under `mapping` (implicit spec §3.5): each world point put through the mapping. Across a
    /// coordinate that closes on itself (`LatticeMapping.periods`, whose cut is at ± half a period), every seed within the search radius
    /// of the cut is copied to the far side, shifted by a period, so the cells meet there.
    ///
    /// The search radius is twice the mean spacing the seeds would have in the lattice coordinates of `region`.
    /// - Parameters:
    ///   - points: the seeds in world space.
    ///   - region: the box the lattice fills.
    public static func mapped(points: [Vector3], mapping: LatticeMapping, region: BoundingBox) -> VoronoiSeeds {
        guard case .straight = mapping else {
            let moved = points.map(mapping.coordinates(at:))
            let radius = searchRadius(count: points.count, in: mapping.coordinateBounds(of: region))
            var ghosts: [Vector3] = []
            let periods = mapping.periods
            for point in moved {
                if let period = periods.first {
                    if point.x > period / 2 - radius { ghosts.append(point - Vector3(period, 0, 0)) }
                    if point.x < -period / 2 + radius { ghosts.append(point + Vector3(period, 0, 0)) }
                }
                if let period = periods.second {
                    if point.y > period / 2 - radius { ghosts.append(point - Vector3(0, period, 0)) }
                    if point.y < -period / 2 + radius { ghosts.append(point + Vector3(0, period, 0)) }
                }
            }
            return VoronoiSeeds(points: moved + ghosts, radius: radius, ghostCount: ghosts.count)
        }
        return VoronoiSeeds(points: points, radius: searchRadius(count: points.count, in: region))
    }
}

extension LatticeMapping {
    /// The box that contains the lattice coordinates of `region`, found on a grid of 9 × 9 × 9 points and widened by a tenth: a
    /// Voronoi lattice spreads its search radius over it.
    public func coordinateBounds(of region: BoundingBox) -> BoundingBox {
        guard case .straight = self else {
            let steps = 8
            var points: [Vector3] = []
            for k in 0...steps {
                for j in 0...steps {
                    for i in 0...steps {
                        let fraction = Vector3(Double(i), Double(j), Double(k)) * (1 / Double(steps))
                        points.append(coordinates(at: region.min + Vector3(region.size.x * fraction.x, region.size.y * fraction.y,
                                                                          region.size.z * fraction.z)))
                    }
                }
            }
            guard let box = BoundingBox(points: points) else { return region }
            return ImplicitSolid.grown(box, by: max(box.size.x, box.size.y, box.size.z) / 10)
        }
        return region
    }
}
