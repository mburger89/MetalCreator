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

    static func revolve(_ profile: Profile2D, axis: Axis, angle: Angle) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let origin = [axis.origin.x, axis.origin.y, axis.origin.z]
        let direction = [axis.direction.x, axis.direction.y, axis.direction.z]
        return try OCCTProfile.with(profile) { cProfile throws(OCCTError) in
            try building { history, status in occt_revolve(cProfile, origin, direction, angle.radians, history, status) }
        }
    }

    static func loft(_ sections: [Profile2D], ruled: Bool) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        try OCCTProfile.withAll(sections) { profiles, count throws(OCCTError) in
            try building { history, status in occt_loft(profiles, Int32(count), ruled ? 1 : 0, history, status) }
        }
    }
}
