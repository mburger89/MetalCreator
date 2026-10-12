/// How a placed copy's position in its pattern is named: in messages (`{3}`, `{0;3}`, patterns spec §2 and §6) and in
/// the `item` of its faces' tags (`TopoTag.item`), which is one `Int`.
///
/// A flat list's instance `i` has the path `{i}` and the item `i`, exactly as before trees, so a pick saved then still
/// names the same instance. A deeper path (`{0;3}`: 2 to 4 indices, each at most `maximumIndex`) is packed into one
/// negative `Int`: the depth in the bits from 60 up, then the indices 15 bits each, the whole negated. No path equals
/// another's, and no deeper path equals a flat one. This is the one place that writes and reads both forms.
public enum InstancePath {
    /// The most indices a path can have and still be named in a tag.
    public static let maximumDepth = 4
    /// The largest index of a path with two or more indices.
    public static let maximumIndex = (1 << indexBits) - 1

    private static let indexBits = 15
    private static let depthShift = 60

    /// The tag item that names the instance at `indices`. `nil` when the path is empty, has a negative index, is deeper
    /// than `maximumDepth`, or (when it has two or more indices) has an index above `maximumIndex`.
    public static func item(for indices: [Int]) -> Int? {
        guard indices.allSatisfy({ $0 >= 0 }) else { return nil }
        if indices.count == 1 { return indices[0] }
        guard (2...maximumDepth).contains(indices.count), indices.allSatisfy({ $0 <= maximumIndex }) else { return nil }
        var packed = indices.count << depthShift
        for (position, index) in indices.enumerated() {
            packed |= index << (indexBits * (indices.count - 1 - position))
        }
        return -packed
    }

    /// The indices a tag item names: `[item]` for a flat instance, the packed path for a negative one, and `nil` for
    /// a negative number that `item(for:)` never made.
    public static func indices(ofItem item: Int) -> [Int]? {
        if item >= 0 { return [item] }
        guard item != Int.min else { return nil }
        let packed = -item
        let depth = packed >> depthShift
        guard (2...maximumDepth).contains(depth) else { return nil }
        let indices = (0..<depth).map { position in (packed >> (indexBits * (depth - 1 - position))) & maximumIndex }
        // Reject a number with stray bits between the indices and the depth.
        return self.item(for: indices) == item ? indices : nil
    }

    /// `{3}` or `{0;3}`: the path of `indices`.
    public static func text(indices: [Int]) -> String {
        "{" + indices.map { String($0) }.joined(separator: ";") + "}"
    }

    /// The path a tag item names, written as in messages. A number that is no path is written as it is.
    public static func text(_ item: Int) -> String {
        text(indices: indices(ofItem: item) ?? [item])
    }
}
