// Test fixture file: builders and a text outline for data trees, shared by the tree tests.
@testable import CreatorGraph

func ints(_ values: Int...) -> [Scalar] { values.map { .integer($0) } }

func ints(_ range: Range<Int>) -> [Scalar] { range.map { .integer($0) } }

/// A tree of depth 2 whose branches hold the given integers.
func rows(_ branches: [Int]...) -> DataTree {
    DataTree(depth: 2, branches: branches.map { .list($0.map { .integer($0) }) }) ?? .empty(depth: 2)
}

extension Scalar {
    /// "3" for an integer or a whole number, "1.5" otherwise, "true" for a bool, the type name for anything else.
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
    /// "[[0,1],[2,3]]": the nesting and the items, for assertions.
    var outline: String {
        depth == 1 ? "[" + items.map(\.outlineText).joined(separator: ",") + "]"
            : "[" + branches.map(\.outline).joined(separator: ",") + "]"
    }
}

extension Value {
    /// The outline of a tree or list value, "3" for one item.
    var outline: String {
        switch self {
        case .one(let scalar): scalar.outlineText
        case .list(let scalars): DataTree.list(scalars).outline
        case .tree(let tree): tree.outline
        }
    }
}
