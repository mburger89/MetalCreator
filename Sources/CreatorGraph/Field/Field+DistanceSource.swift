import CreatorKernel

/// Equality for fields (the previews ask "is this the field I last sampled?"): a distance to a solid, faces or edges is the
/// same distance when its target is, by `DistanceTarget.identity` (the solid object and the selected IDs), since a `Solid`
/// has no value equality. Everything else a field holds is plain values.
extension Field.DistanceSource: Hashable {
    public static func == (lhs: Field.DistanceSource, rhs: Field.DistanceSource) -> Bool {
        switch (lhs, rhs) {
        case (.point(let a), .point(let b)): a == b
        case (.profile(let a), .profile(let b)): a == b
        case (.kernel(let a), .kernel(let b)): a.identity == b.identity
        case (.point, _), (.profile, _), (.kernel, _): false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .point(let point):
            hasher.combine(0)
            hasher.combine(point)
        case .profile(let profile):
            hasher.combine(1)
            hasher.combine(profile)
        case .kernel(let target):
            hasher.combine(2)
            hasher.combine(target.identity)
        }
    }
}
