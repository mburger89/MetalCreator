import CreatorGeometry
import CreatorKernel

/// One runtime value flowing along a wire.
public enum Scalar: Sendable {
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case vector(Vector3)
    case plane(Plane)
    case profile(Profile2D)
    case solid(Solid)
    case edgeSet(EdgeSet)
    case faceSet(FaceSet)
    /// A value that varies over space (fields spec §2.1). Never saved.
    case field(Field)

    public var type: SocketType {
        switch self {
        case .number: .number
        case .integer: .integer
        case .bool: .bool
        case .vector: .vector
        case .plane: .plane
        case .profile: .profile
        case .solid: .solid
        case .edgeSet: .edgeSet
        case .faceSet: .faceSet
        case .field: .field
        }
    }

    /// The runtime form of a stored constant. `text`, `edgePicks`, `sketch` and `facePick` settings have none.
    public init?(_ constant: ConstantValue) {
        switch constant {
        case .number(let value): self = .number(value)
        case .integer(let value): self = .integer(value)
        case .bool(let value): self = .bool(value)
        case .vector(let value): self = .vector(value)
        case .plane(let value): self = .plane(value)
        case .text, .edgePicks, .sketch, .facePick: return nil
        }
    }

    /// This value as `target`, applying the implicit conversions, or `nil` if impossible.
    public func converted(to target: SocketType) -> Scalar? {
        if type == target || target == .any { return self }
        switch (self, target) {
        case (.integer(let value), .number): return .number(Double(value))
        case (.vector(let value), .plane): return .plane(.through(value))
        // A number is a constant field (fields spec D4). Nothing converts back: a sampling node turns a field into numbers.
        case (.number(let value), .field): return .field(.constant(value))
        case (.integer(let value), .field): return .field(.constant(Double(value)))
        default: return nil
        }
    }

    public var estimatedBytes: Int {
        switch self {
        case .solid(let solid): solid.estimatedBytes
        case .profile(let profile): 64 + profile.segmentCount * 48
        case .edgeSet(let set): 32 + set.edges.count * 8
        case .faceSet(let set): 32 + set.faces.count * 8
        case .field(let field): field.estimatedBytes
        case .number, .integer, .bool, .vector, .plane: 32
        }
    }
}
