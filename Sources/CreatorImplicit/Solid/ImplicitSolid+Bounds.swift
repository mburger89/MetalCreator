import CreatorGeometry

extension ImplicitSolid {
    /// A box that contains the surface (implicit spec §2.1). A smooth union may bulge a quarter of its blend radius past its
    /// children, an offset or a shell grows by its largest distance, and an intersection can be empty (then a zero-size box at the
    /// first child's centre).
    public var bounds: BoundingBox {
        switch self {
        case .sphere(let radius):
            return Self.box(Vector3(radius, radius, radius))
        case .box(let half, _):
            return Self.box(half)
        case .cylinder(let radius, let halfHeight):
            return Self.box(Vector3(radius, radius, halfHeight))
        case .moved(let child, let move):
            return move.bounds(of: child.bounds)
        case .union(let children, let blend):
            let all = children.map(\.bounds)
            let joined = all.dropFirst().reduce(all.first ?? Self.box(.zero)) { $0.union($1) }
            return Self.grown(joined, by: max(0, blend.range.upperBound) / 4)
        case .intersect(let children, _):
            let all = children.map(\.bounds)
            guard let first = all.first else { return Self.box(.zero) }
            let overlap = all.dropFirst().reduce(Optional(first)) { box, next in box.flatMap { next.intersection($0) } }
            return overlap ?? BoundingBox(min: first.center, max: first.center)
        case .subtract(let children, _):
            return children.first?.bounds ?? Self.box(.zero)
        case .offset(let child, let distance):
            return Self.grown(child.bounds, by: max(0, distance.range.upperBound))
        case .shell(let child, let thickness, let side):
            let largest = max(0, thickness.range.upperBound)
            switch side {
            case .inward: return child.bounds
            case .outward: return Self.grown(child.bounds, by: largest)
            case .centred: return Self.grown(child.bounds, by: largest / 2)
            }
        case .baked(let blocks, _):
            return blocks.bounds
        case .isosurface(_, _, _, let region):
            return region
        case .tpms(let lattice):
            return lattice.region
        }
    }

    private static func box(_ half: Vector3) -> BoundingBox { BoundingBox(min: -half, max: half) }

    public static func grown(_ box: BoundingBox, by amount: Double) -> BoundingBox {
        let pad = Vector3(amount, amount, amount)
        return BoundingBox(min: box.min - pad, max: box.max + pad)
    }
}
