import COCCT
import CreatorGeometry

extension OCCTShape {
    /// Runs a shim builder that returns a shape and fills a history; frees the history.
    static func building(_ body: (UnsafeMutablePointer<occt_history>, UnsafeMutablePointer<occt_status>) -> OpaquePointer?)
        throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        var history = occt_history()
        defer { occt_history_free(&history) }
        let shape = try make { status in body(&history, status) }
        return (shape, OCCTHistoryRecord.read(history))
    }

    static func extrude(_ profile: Profile2D, distance: Double) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        try OCCTProfile.with(profile) { cProfile throws(OCCTError) in
            try building { history, status in occt_extrude(cProfile, distance, history, status) }
        }
    }
}
