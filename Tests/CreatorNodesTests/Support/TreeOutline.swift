// Test fixture file: a text outline of list and tree values, for assertions.
import CreatorGraph

extension Scalar {
    var outlineText: String {
        switch self {
        case .integer(let value): "\(value)"
        case .number(let value): value == value.rounded() ? "\(Int(value))" : "\(value)"
        case .bool(let value): "\(value)"
        default: "\(type)"
        }
    }
}

extension DataTree {
    /// "[[0,1],[2,3]]": the nesting and the items.
    var outline: String {
        depth == 1 ? "[" + items.map(\.outlineText).joined(separator: ",") + "]"
            : "[" + branches.map(\.outline).joined(separator: ",") + "]"
    }
}

extension Value {
    /// The outline of a list or tree, "3" for one item.
    var outline: String {
        switch self {
        case .one(let scalar): scalar.outlineText
        case .list(let scalars): DataTree.list(scalars).outline
        case .tree(let tree): tree.outline
        }
    }
}
