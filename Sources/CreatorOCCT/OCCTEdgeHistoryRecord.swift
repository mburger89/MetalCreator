import COCCT

/// One shim edge record (NS-5, R5): output edge `outEdge` was made from edge `index` of input `operand`, every index 0-based.
struct OCCTEdgeHistoryRecord: Hashable, Sendable {
    var outEdge: Int
    var operand: Int
    var index: Int

    /// Reads the shim's records, whose edge indices arrive 1-based.
    static func read(_ history: occt_edge_history) -> [OCCTEdgeHistoryRecord] {
        UnsafeBufferPointer(start: history.records, count: Int(history.count)).map {
            OCCTEdgeHistoryRecord(outEdge: Int($0.out_edge) - 1, operand: Int($0.operand), index: Int($0.index) - 1)
        }
    }
}
