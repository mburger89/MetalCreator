import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The reference evaluation of an implicit solid, in `Double` (implicit spec §4.1): every node's distance, with fields sampled per
/// point. The Metal path must agree with it to 1e-4 mm. One instance keeps the noise generators and profile measures its fields
/// need, so it is made once per batch and used from one task only.
final class CPUEvaluation {
    private struct NoiseKey: Hashable {
        var seed: Int
        var scale: Double
        var octaves: Int
    }

    private var noises: [NoiseKey: FieldNoise] = [:]
    private var profiles: [Field.DistanceSource: ProfileDistance] = [:]

    // MARK: Solids

    // The value of `solid` at `p`. One branch per case, with no `default`, so a case added later is a compile error here.
    // swiftlint:disable:next cyclomatic_complexity
    func distance(_ solid: ImplicitSolid, at p: Vector3) -> Double {
        switch solid {
        case .sphere(let radius):
            return p.length - radius
        case .box(let half, let cornerRadius):
            let inner = Vector3(abs(p.x) - (half.x - cornerRadius), abs(p.y) - (half.y - cornerRadius),
                                abs(p.z) - (half.z - cornerRadius))
            let outside = Vector3(max(inner.x, 0), max(inner.y, 0), max(inner.z, 0)).length
            return outside + min(max(inner.x, inner.y, inner.z), 0) - cornerRadius
        case .cylinder(let radius, let halfHeight):
            let (across, along) = ((p.x * p.x + p.y * p.y).squareRoot() - radius, abs(p.z) - halfHeight)
            return min(max(across, along), 0) + (max(across, 0) * max(across, 0) + max(along, 0) * max(along, 0)).squareRoot()
        case .moved(let child, let move):
            return distance(child, at: move.toLocal(p))
        case .union(let children, let blend):
            let width = max(0, value(blend, at: p))
            return children.dropFirst().reduce(children.first.map { distance($0, at: p) } ?? .infinity) {
                Self.smoothMinimum($0, distance($1, at: p), width: width)
            }
        case .intersect(let children, let blend):
            let width = max(0, value(blend, at: p))
            return children.dropFirst().reduce(children.first.map { distance($0, at: p) } ?? -.infinity) {
                -Self.smoothMinimum(-$0, -distance($1, at: p), width: width)
            }
        case .subtract(let children, let blend):
            let width = max(0, value(blend, at: p))
            return children.dropFirst().reduce(children.first.map { distance($0, at: p) } ?? .infinity) {
                -Self.smoothMinimum(-$0, distance($1, at: p), width: width)
            }
        case .offset(let child, let amount):
            return distance(child, at: p) - value(amount, at: p)
        case .shell(let child, let thickness, let side):
            let wall = max(0, value(thickness, at: p))
            return abs(distance(child, at: p) - side.centreOffset(thickness: wall)) - wall / 2
        case .baked(let blocks, _):
            return blocks.value(at: p)
        case .isosurface(let grading, let level, let maxSlope, let region):
            return max((value(grading, at: p) - level) / maxSlope, Self.boxDistance(p, region))
        }
    }

    /// The polynomial smooth minimum of `a` and `b` over `width`; 0 is the plain minimum.
    static func smoothMinimum(_ a: Double, _ b: Double, width: Double) -> Double {
        guard width > 0 else { return min(a, b) }
        let blend = max(width - abs(a - b), 0) / width
        return min(a, b) - blend * blend * width / 4
    }

    /// The signed distance to the box: negative inside.
    static func boxDistance(_ p: Vector3, _ box: BoundingBox) -> Double {
        let centre = box.center, half = box.size * 0.5
        let inner = Vector3(abs(p.x - centre.x) - half.x, abs(p.y - centre.y) - half.y, abs(p.z - centre.z) - half.z)
        return Vector3(max(inner.x, 0), max(inner.y, 0), max(inner.z, 0)).length + min(max(inner.x, inner.y, inner.z), 0)
    }

    // MARK: Fields

    /// A graded setting at `p`.
    func value(_ grading: Grading, at p: Vector3) -> Double {
        if let constant = grading.constantValue { return constant }
        return value(grading.field, at: p, in: grading)
    }

    // One branch per field case, with no `default`.
    // swiftlint:disable:next cyclomatic_complexity
    private func value(_ field: Field, at p: Vector3, in grading: Grading) -> Double {
        switch field {
        case .constant(let value):
            return value
        case .distance(let source, let signed):
            switch source {
            case .point(let target):
                return (p - target).length
            case .profile:
                if profiles[source] == nil, case .profile(let profile) = source { profiles[source] = ProfileDistance(profile) }
                return profiles[source]?.distance(from: p) ?? .infinity
            case .kernel(let target):
                return grading.blocks(for: target.identity, signed: signed)?.value(at: p) ?? .nan
            }
        case .linearGradient(let plane, let length):
            return (p - plane.origin).dot(plane.normal.normalized ?? .zero) / length
        case .radialGradient(let center, let radius):
            return (p - center).length / radius
        case .noise(let seed, let scale, let octaves):
            let key = NoiseKey(seed: seed, scale: scale, octaves: octaves)
            if noises[key] == nil { noises[key] = FieldNoise(seed: seed, scale: scale, octaves: octaves) }
            return noises[key]?.value(at: p) ?? 0.5
        case .image(let image, let plane, let width, let height, let edges):
            let across = plane.xAxis.normalized ?? .zero, up = plane.yAxis.normalized ?? .zero
            let offset = p - plane.origin
            return image.value(u: offset.dot(across) / width + 0.5, v: 0.5 - offset.dot(up) / height, edges: edges)
        case .implicit(let reference):
            return reference.solid.map { distance($0, at: p) } ?? reference.payload.signedDistance(at: p)
        case .add(let a, let b):
            return value(a, at: p, in: grading) + value(b, at: p, in: grading)
        case .multiply(let a, let b):
            return value(a, at: p, in: grading) * value(b, at: p, in: grading)
        case .minimum(let a, let b):
            return FieldMath.minimum(value(a, at: p, in: grading), value(b, at: p, in: grading))
        case .maximum(let a, let b):
            return FieldMath.maximum(value(a, at: p, in: grading), value(b, at: p, in: grading))
        case .remap(let inner, let fromLow, let fromHigh, let toLow, let toHigh, let clamped):
            return FieldMath.remap(value(inner, at: p, in: grading), fromLow: fromLow, fromHigh: fromHigh, toLow: toLow,
                                   toHigh: toHigh, clamped: clamped)
        case .clamp(let inner, let low, let high):
            return FieldMath.clamp(value(inner, at: p, in: grading), low: low, high: high)
        case .smoothMinimum(let a, let b, let width):
            return FieldMath.smoothMinimum(value(a, at: p, in: grading), value(b, at: p, in: grading), width: width)
        }
    }
}
