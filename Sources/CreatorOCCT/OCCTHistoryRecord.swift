import COCCT

/// One shim history record, with every index made 0-based.
struct OCCTHistoryRecord: Hashable, Sendable {
    enum Kind: Sendable {
        case startCap, endCap, segment, face, edge
    }

    var outFace: Int
    var kind: Kind
    var operand: Int
    var index: Int

    /// Reads the shim's records. Out/face/edge indices arrive 1-based; segment indices 0-based.
    static func read(_ history: occt_history) -> [OCCTHistoryRecord] {
        UnsafeBufferPointer(start: history.records, count: Int(history.count)).compactMap { record in
            let kind: Kind
            switch record.kind {
            case Int32(OCCT_FROM_START_CAP.rawValue): kind = .startCap
            case Int32(OCCT_FROM_END_CAP.rawValue): kind = .endCap
            case Int32(OCCT_FROM_SEGMENT.rawValue): kind = .segment
            case Int32(OCCT_FROM_FACE.rawValue): kind = .face
            case Int32(OCCT_FROM_EDGE.rawValue): kind = .edge
            default: return nil
            }
            let index = (kind == .face || kind == .edge) ? Int(record.index) - 1 : Int(record.index)
            return OCCTHistoryRecord(outFace: Int(record.out_face) - 1, kind: kind, operand: Int(record.operand), index: index)
        }
    }
}
