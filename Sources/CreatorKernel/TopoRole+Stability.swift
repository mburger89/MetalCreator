extension TopoRole {
    /// True for the `.unnamed` fallback, and for a blend whose source edge borders such a face: names
    /// that may move to a different face when the model is rebuilt.
    public var isUnstable: Bool {
        switch self {
        case .unnamed: true
        case .blend(let source): source.first.union(source.second).contains { $0.role.isUnstable }
        case .startCap, .endCap, .side: false
        }
    }
}
