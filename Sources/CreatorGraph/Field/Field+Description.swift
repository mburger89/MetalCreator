import CreatorKernel
import Foundation

extension Field: CustomStringConvertible {
    /// A one-line readable recipe, such as `remap(distance(edges), 0…20 → 1…0) × noise(seed 4, scale 5, octaves 3)`
    /// (fields spec §2.1). Numbers are written in `Locale.messages`. The inspector shows it; a socket's tooltip shows
    /// `description(limit: 80)`.
    public var description: String { recipe(inside: .top) }

    /// The recipe cut to `limit` characters, ending in "…" when it was cut.
    public func description(limit: Int) -> String {
        let text = description
        guard text.count > limit else { return text }
        return String(text.prefix(max(limit - 1, 0))) + "…"
    }

    /// Where a recipe sits, which decides whether an addition needs brackets.
    private enum Context { case top, factor }

    // One branch per case, so the compiler checks that each has a recipe: that is over the complexity limit.
    // swiftlint:disable:next cyclomatic_complexity
    private func recipe(inside context: Context) -> String {
        switch self {
        case .constant(let value):
            return Self.number(value)
        case .distance(let source, let signed):
            switch source {
            case .point: return "distance(point)"
            case .profile: return "distance(profile)"
            case .kernel(.edges): return "distance(edges)"
            case .kernel(.faces): return "distance(faces)"
            case .kernel(.solid): return signed ? "distance(solid)" : "distance(solid, unsigned)"
            }
        case .linearGradient(_, let length):
            return "linear(length \(Self.number(length)))"
        case .radialGradient(_, let radius):
            return "radial(radius \(Self.number(radius)))"
        case .noise(let seed, let scale, let octaves):
            return "noise(seed \(seed.formatted(.number.locale(.messages))), scale \(Self.number(scale)), octaves \(octaves))"
        case .image(let image, _, let width, let height, let edges):
            let pixels = "\(image.width.formatted(.number.locale(.messages))) × \(image.height.formatted(.number.locale(.messages)))"
            return "image(\(pixels) px over \(Self.number(width)) × \(Self.number(height)) mm, \(edges.name))"
        case .add(let a, let b):
            let text = "\(a.recipe(inside: .top)) + \(b.recipe(inside: .top))"
            return context == .factor ? "(\(text))" : text
        case .multiply(let a, let b):
            return "\(a.recipe(inside: .factor)) × \(b.recipe(inside: .factor))"
        case .minimum(let a, let b):
            return "min(\(a.recipe(inside: .top)), \(b.recipe(inside: .top)))"
        case .maximum(let a, let b):
            return "max(\(a.recipe(inside: .top)), \(b.recipe(inside: .top)))"
        case .remap(let field, let fromLow, let fromHigh, let toLow, let toHigh, let clamped):
            let ranges = "\(Self.number(fromLow))…\(Self.number(fromHigh)) → \(Self.number(toLow))…\(Self.number(toHigh))"
            return "remap(\(field.recipe(inside: .top)), \(ranges)\(clamped ? "" : ", unclamped"))"
        case .clamp(let field, let low, let high):
            return "clamp(\(field.recipe(inside: .top)), \(Self.number(low))…\(Self.number(high)))"
        case .smoothMinimum(let a, let b, let width):
            return "smoothMin(\(a.recipe(inside: .top)), \(b.recipe(inside: .top)), width \(Self.number(width)))"
        }
    }

    /// A number as messages write it: up to two decimals, grouped, never "-0".
    private static func number(_ value: Double) -> String {
        (value == 0 ? 0 : value).millimetreText(locale: .messages)
    }
}
