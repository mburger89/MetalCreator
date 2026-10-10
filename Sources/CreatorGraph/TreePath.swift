import Foundation

/// An item's address in a data tree: its index at each level, written `{0;3}` (branch 0, item 3) or `{1;0;4}`.
///
/// Paths are derived from the data and never stored, so they cannot drift from it. A branch's path is the item
/// path without its last index. This is the one path type: later work (instance names for placed copies, picks on
/// instances) adopts it as it is; a flat list's item `i` is `{i}`.
public struct TreePath: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var indices: [Int]

    public init(_ indices: [Int] = []) {
        self.indices = indices
    }

    /// How many levels the path has.
    public var count: Int { indices.count }

    /// `{0;3}`. The empty path is `{}`.
    public var description: String {
        "{" + indices.map { String($0) }.joined(separator: ";") + "}"
    }

    public func appending(_ index: Int) -> TreePath {
        TreePath(indices + [index])
    }

    /// Paths order level by level, so a branch's items sort in index order.
    public static func < (lhs: TreePath, rhs: TreePath) -> Bool {
        lhs.indices.lexicographicallyPrecedes(rhs.indices)
    }

    /// Reads `{0;3}` (spaces allowed, `{}` is the empty path); `nil` for anything else, including a negative or
    /// missing index.
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        let inner = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        if inner.isEmpty {
            self.init()
            return
        }
        var indices: [Int] = []
        for part in inner.split(separator: ";", omittingEmptySubsequences: false) {
            guard let index = Int(part.trimmingCharacters(in: .whitespaces)), index >= 0 else { return nil }
            indices.append(index)
        }
        self.init(indices)
    }
}
