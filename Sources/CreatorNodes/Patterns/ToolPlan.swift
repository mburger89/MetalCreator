/// Which tool each instance uses: one per distinct size, in the order the sizes first appear, shared by every instance
/// of that size (patterns spec §7). The tool for instance `i` is `distinct[toolIndex[i]]`.
struct ToolPlan<Size: Hashable> {
    let distinct: [Size]
    let toolIndex: [Int]

    init(sizes: [Size]) {
        var distinct: [Size] = []
        var indices: [Size: Int] = [:]
        var toolIndex: [Int] = []
        for size in sizes {
            if let known = indices[size] {
                toolIndex.append(known)
            } else {
                indices[size] = distinct.count
                toolIndex.append(distinct.count)
                distinct.append(size)
            }
        }
        self.distinct = distinct
        self.toolIndex = toolIndex
    }
}
